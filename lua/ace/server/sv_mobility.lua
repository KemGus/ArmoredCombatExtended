--[[
	Server side of the drivetrain: turns linked engines, gearboxes and wheel props into a
	drivetrain description (lua/ace/shared/mobility/drivetrain.lua), steps it once per tick and
	hands the resulting impulses back to VPhysics.

	One solve covers every engine that shares a gearbox with another, so twin-engine builds are
	solved together. The first engine of a group to think in a tick runs the solve; the others see
	the group's stamp and skip.
]]

local M = ACE.Mobility
local Units = M.Units

local Drivetrain = M.Drivetrain
local EngineModel = M.Engine
local Vehicle = M.Vehicle

local abs = math.abs
local max = math.max

local DegToRad = Units.DegToRad
local InchToMeter = Units.InchToMeter
local Gravity = Units.Gravity

local AssistedConVar = CreateConVar("ace_mobility_assisted", "0", FCVAR_ARCHIVE + FCVAR_NOTIFY,
	"1 = assisted driving for every gearbox: automatic clutch on launch and shifts, rev matching, no stalling. 0 = realistic, gearboxes can opt in with their Assisted input.", 0, 1)
local AllowAssistedConVar = CreateConVar("ace_mobility_allow_assisted", "1", FCVAR_ARCHIVE + FCVAR_NOTIFY,
	"Whether gearboxes may switch themselves to assisted driving with their Assisted input.", 0, 1)
local SubstepsConVar = CreateConVar("ace_mobility_substeps", "8", FCVAR_ARCHIVE,
	"Drivetrain solver substeps per tick. More is smoother for very light, fast-revving engines.", 2, 32)

--- Whether a gearbox should drive in assisted mode.
-- @param Box acf_gearbox entity.
function M.IsAssisted(Box)
	if AssistedConVar:GetBool() then return true end
	return AllowAssistedConVar:GetBool() and Box.AssistedInput == true
end

------------------------------------------------------------------------ engines

--- Builds (or returns the cached) physical spec for an engine entity.
-- Rebuilt when the fuel in use changes, because fuel reshapes the torque curve.
-- @param Engine acf_engine entity.
-- @param FuelType Fuel currently being burned.
function M.EngineSpec(Engine, FuelType)
	local Key = FuelType or Engine.FuelType
	if Engine.MobSpec and Engine.MobSpecKey == Key then return Engine.MobSpec end

	local Def = ACE.Weapons.Engines[Engine.Id]
	local Curve = table.Copy(Engine.TorqueCurve)
	local Mul = ACE.PerFuelTorqueCurveMul and ACE.PerFuelTorqueCurveMul[Key == "Multifuel" and "Diesel" or Key]
	if Mul then ACE.ApplyEngineFuelModifierToCurve(Curve, Mul) end

	local Spec = EngineModel.Build(Def or {
		torque = Engine.BaseTorque, idlerpm = Engine.IdleRPM, limitrpm = Engine.LimitRPM,
		fuel = Engine.FuelType, enginetype = Engine.EngineType,
	}, Curve)

	Engine.MobSpec, Engine.MobSpecKey = Spec, Key
	Engine.Inertia = Spec.Inertia -- read by E2/Starfall as flywheel inertia, kg·m²
	if Engine.MobState then
		Engine.MobState.Spec = Spec
	else
		Engine.MobState = EngineModel.NewState(Spec)
	end
	return Spec
end

------------------------------------------------------------------------ wheels

-- Rolling radius of a wheel prop: half its largest extent perpendicular to the axle.
local function wheelRadius(Wheel, LocalAxis)
	local Mins, Maxs = Wheel:OBBMins(), Wheel:OBBMaxs()
	local Size = Maxs - Mins
	local A = Vector(abs(LocalAxis.x), abs(LocalAxis.y), abs(LocalAxis.z))
	-- Project the box extents onto the plane of rotation and take the largest.
	local R = 0
	if A.x < 0.7 then R = max(R, Size.x) end
	if A.y < 0.7 then R = max(R, Size.y) end
	if A.z < 0.7 then R = max(R, Size.z) end
	return R * 0.5 * InchToMeter
end

local function surfaceFriction(Index)
	local Data = Index and util.GetSurfaceData(Index)
	return Data and Data.friction or 0.8
end

--[[
	Contact friction VPhysics will actually apply between a wheel and the ground.
	Source combines the two surfaces' friction values multiplicatively. Using the same number
	keeps the solver from predicting traction VPhysics will not deliver.
]]
local function contactMu(WheelPhys, GroundSurface)
	local Own = surfaceFriction(util.GetSurfaceIndex(WheelPhys:GetMaterial()))
	return Own * surfaceFriction(GroundSurface)
end

-- Refreshes one wheel description from VPhysics. Link is the gearbox's WheelLink entry.
local function readWheel(Box, Link, BoxAngVel, Ctx)
	local Ent = Link.Ent
	local Phys = Ent:GetPhysicsObject()
	if not IsValid(Phys) then return nil end

	local Desc = Link.Mob
	if not Desc then
		Desc = { Key = Ent }
		Link.Mob = Desc
	end
	Desc.Ent, Desc.Phys, Desc.Box, Desc.Link = Ent, Phys, Box, Link

	local AxisWorld = Phys:LocalToWorldVector(Link.Axis)
	Desc.AxisWorld = AxisWorld
	Desc.Radius = Desc.Radius or wheelRadius(Ent, Link.Axis)

	-- Forward rotation is about -axis (the convention the old drivetrain used).
	local AngVel = Phys:LocalToWorldVector(Phys:GetAngleVelocity()) - BoxAngVel
	Desc.W = -AngVel:Dot(AxisWorld) * DegToRad

	-- Own inertia about the axle.
	Desc.J = max((Link.Axis * Phys:GetInertia()):Length() * Units.SourceInertiaToSI, 1e-3)

	-- Ground contact under the wheel.
	local R = Desc.Radius
	local Center = Phys:GetPos()
	local Down = Vector(0, 0, -1)
	local Tr = util.TraceLine({
		start = Center,
		endpos = Center + Down * (R / InchToMeter + 4),
		filter = Ctx.Filter,
	})
	Desc.Grounded = Tr.Hit
	Desc.Mu = Tr.Hit and contactMu(Phys, Tr.SurfaceProps) or 0

	-- Rolling direction and contact ground speed.
	local Fwd = (-AxisWorld):Cross(Vector(0, 0, 1))
	if Fwd:LengthSqr() > 1e-6 then
		Fwd:Normalize()
		Desc.GroundSpeed = Phys:GetVelocity():Dot(Fwd) * InchToMeter
	else
		Desc.GroundSpeed = Desc.W * R
	end

	return Desc
end

------------------------------------------------------------------------ gearboxes

-- Reduction ratio (input speed / output speed) from the legacy gear table, which stores
-- output/input.
local function reduction(Box)
	local R = Box.GearRatio or 0
	if abs(R) < 1e-6 then return 0 end
	return 1 / R
end
M.Reduction = reduction

local buildGearbox

-- Builds the description for one gearbox and everything below it.
buildGearbox = function(Box, Ctx)
	if Ctx.Boxes[Box] then return Ctx.Boxes[Box] end

	local Desc = Box.Mob
	if not Desc then
		Desc = { Key = Box }
		Box.Mob = Desc
	end
	Ctx.Boxes[Box] = Desc
	Ctx.BoxList[#Ctx.BoxList + 1] = Box

	Box:MobilityControl(Ctx.Dt)

	local Max = Box.MaxTorque or 0
	Desc.Ratio = Box.MobRatio or reduction(Box)
	Desc.InputJ = Box.InputJ or 0.02 + 0.00002 * Max
	Desc.Efficiency = Box.MobEfficiency or 0.97
	Desc.SpinLoss = 0.002 * Max
	Desc.Dual = Box.Dual
	Desc.ClutchCap = Box.MobClutchCap
	local SideScale = Box.MobSideScale or 1
	Desc.SideCap = { [0] = (Box.LClutch or Max) * SideScale, [1] = (Box.RClutch or Max) * SideScale }
	Desc.DriveCap = Box.MobDriveCap
	Desc.Diff = Box.MobDiff
	Desc.LSDPreload, Desc.LSDRamp = Box.LSDPreload, Box.LSDRamp
	Desc.Converter = Box.MobConverter
	Desc.LockupCap = Box.MobLockupCap
	if Box.DoubleDiff then
		Desc.Steer = Box.SteerRate or 0
		Desc.SteerRatio = Box.MobSteerRatio or 2
		Desc.SteerCap = Max
	else
		Desc.Steer, Desc.SteerRatio, Desc.SteerCap = nil, nil, nil
	end

	local Phys = Box:GetPhysicsObject()
	local BoxAngVel = IsValid(Phys) and Phys:LocalToWorldVector(Phys:GetAngleVelocity()) or vector_origin

	Desc.Outputs = {}
	Desc.Brake = { [0] = 0, [1] = 0 }
	Desc.WheelDescs = {}

	for _, Link in pairs(Box.WheelLink) do
		local Ent = Link.Ent
		if not IsValid(Ent) or Link.Notvalid then continue end

		if Ent.IsGeartrain then
			if Ent.Legal then
				Desc.Outputs[#Desc.Outputs + 1] = { Side = Link.Side, Gearbox = buildGearbox(Ent, Ctx) }
			end
		else
			local Wheel = readWheel(Box, Link, BoxAngVel, Ctx)
			if Wheel then
				Desc.Outputs[#Desc.Outputs + 1] = { Side = Link.Side, Wheel = Wheel }
				Desc.WheelDescs[#Desc.WheelDescs + 1] = Wheel
				if not Ctx.Wheels[Wheel.Key] then
					Ctx.Wheels[Wheel.Key] = Wheel
					Ctx.WheelList[#Ctx.WheelList + 1] = Wheel
				end
			end
		end
	end

	return Desc
end

--- Builds the drivetrain description for a gearbox and everything below it.
-- @param Box acf_gearbox entity.
-- @param Ctx Solve context from M.Tick.
M.GearboxDesc = function(Box, Ctx) return buildGearbox(Box, Ctx) end

------------------------------------------------------------------------ groups

-- Every engine connected to Engine through shared gearboxes.
local function collectGroup(Engine)
	local Engines, Seen, Stack = {}, {}, { Engine }
	while #Stack > 0 do
		local E = table.remove(Stack)
		if IsValid(E) and not Seen[E] then
			Seen[E] = true
			if E:GetClass() == "acf_engine" then
				Engines[#Engines + 1] = E
				for _, Link in pairs(E.GearLink) do Stack[#Stack + 1] = Link.Ent end
			else
				for _, Master in pairs(E.Master or {}) do Stack[#Stack + 1] = Master end
				for _, Link in pairs(E.WheelLink or {}) do
					if IsValid(Link.Ent) and Link.Ent.IsGeartrain then Stack[#Stack + 1] = Link.Ent end
				end
			end
		end
	end
	return Engines
end

local function contraptionFilter(Engine)
	local Con = Engine.CFW_GetContraption and Engine:CFW_GetContraption()
	if not Con then return { Engine } end
	return function(Ent)
		return not (Ent.CFW_GetContraption and Ent:CFW_GetContraption() == Con)
	end
end

--- Solves the drivetrain group that Engine belongs to for this tick.
-- Safe to call from every engine's Think; the group is only solved once per tick.
-- @param Engine acf_engine entity.
-- @param Dt Tick length.
function M.Tick(Engine, Dt)
	local Now = CurTime()
	if Engine.MobSolvedAt == Now then return end

	local Group = collectGroup(Engine)
	for _, E in ipairs(Group) do E.MobSolvedAt = Now end

	local Ctx = {
		Dt = Dt,
		Boxes = {}, BoxList = {},
		Wheels = {}, WheelList = {},
		Filter = contraptionFilter(Engine),
	}

	local EngineDescs = {}
	local PhysMass = 0
	for _, E in ipairs(Group) do
		local Desc = E:MobilityDesc(Ctx)
		if Desc then
			EngineDescs[#EngineDescs + 1] = Desc
			PhysMass = max(PhysMass, E.PhysMass or 0)
		end
	end
	if #EngineDescs == 0 then return end

	-- Every grounded driven wheel propels an equal share of the vehicle. Normal load is
	-- deliberately generous (all weight on the driven wheels) so the solver never predicts less
	-- traction than VPhysics has; any excess simply shows up as wheelspin next tick.
	local Grounded = 0
	for _, W in ipairs(Ctx.WheelList) do
		if W.Grounded then Grounded = Grounded + 1 end
	end
	local Share = Grounded > 0 and PhysMass / Grounded or 0
	for _, W in ipairs(Ctx.WheelList) do
		W.Ground = Vehicle.Ground(Share, W.Radius, W.GroundSpeed, W.Mu, Share * Gravity, W.Grounded)
		W.RollDrag = W.Grounded and (ACE.MobilityRollingResistance or 0.012) * Share * Gravity * W.Radius or 0
		-- Brakes are sized to lock the wheel with some margin, like real brake systems.
		W.BrakeMax = 1.5 * max(W.Mu, 0.5) * Share * Gravity * W.Radius + 10 * W.J
	end

	for _, Box in ipairs(Ctx.BoxList) do
		local Desc = Box.Mob
		local BrakeL, BrakeR = (Box.LBrake or 0) / 100, (Box.RBrake or 0) / 100
		-- Brake torque is per side; use the strongest wheel on that side as the reference.
		local MaxL, MaxR = 0, 0
		for _, Out in ipairs(Desc.Outputs) do
			if Out.Wheel then
				if Out.Side == 0 then MaxL = max(MaxL, Out.Wheel.BrakeMax) else MaxR = max(MaxR, Out.Wheel.BrakeMax) end
			end
		end
		Desc.Brake[0] = BrakeL * MaxL
		Desc.Brake[1] = BrakeR * MaxR
	end

	local Sys = Drivetrain.Build({ Engines = EngineDescs })
	Drivetrain.Step(Sys, Dt, SubstepsConVar:GetInt())

	-- Hand the impulses to VPhysics: the wheel gets the drivetrain's angular impulse, the chassis
	-- the reaction through the gearbox mounts.
	for _, W in ipairs(Ctx.WheelList) do
		local Imp = W.Impulse or 0
		if Imp ~= 0 and IsValid(W.Phys) then
			local Src = Units.ToSourceAngularImpulse(Imp)
			W.Phys:ApplyTorqueCenter(W.AxisWorld * -Src)
			local Root = ACE.GetPhysicalParent(W.Box)
			local RootPhys = IsValid(Root) and Root:GetPhysicsObject()
			if IsValid(RootPhys) then RootPhys:ApplyTorqueCenter(W.AxisWorld * Src) end
		end
	end

	for _, E in ipairs(Group) do E:MobilityApply() end
	for _, Box in ipairs(Ctx.BoxList) do Box:MobilityApply() end
end

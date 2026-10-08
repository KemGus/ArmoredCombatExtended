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
local min = math.min

local DegToRad = Units.DegToRad
local InchToMeter = Units.InchToMeter
local Gravity = Units.Gravity

local AssistedConVar = CreateConVar("ace_mobility_assisted", "0", FCVAR_ARCHIVE + FCVAR_NOTIFY,
	"1 = assisted driving for every gearbox: automatic clutch on launch and shifts, rev matching, no stalling. 0 = realistic, gearboxes can opt in with their Assisted input.", 0, 1)
local AllowAssistedConVar = CreateConVar("ace_mobility_allow_assisted", "1", FCVAR_ARCHIVE + FCVAR_NOTIFY,
	"Whether gearboxes may switch themselves to assisted driving with their Assisted input.", 0, 1)
local SubstepsConVar = CreateConVar("ace_mobility_substeps", "8", FCVAR_ARCHIVE,
	"Drivetrain solver substeps per tick. More is smoother for very light, fast-revving engines.", 2, 32)
local DebugConVar = CreateConVar("ace_mobility_debug", "0", 0,
	"Drivetrain debug output. 1 = console summary twice a second and warnings on suspicious impulses, 2 = also a per-tick CSV in data/ace_mobility_debug.csv.", 0, 2)
local TyreGripConVar = CreateConVar("ace_mobility_tyre_grip", "1", FCVAR_ARCHIVE,
	"Tyre grip the drivetrain assumes. 1 = what VPhysics really transmits (product of the tyre's and the ground's surface friction), so the drivetrain never spins a wheel the ground could still hold. 0 = real-world tyre friction by surface (the tyres will spin earlier than VPhysics would let them slide).", 0, 1)
local BrakeOnlyConVar = CreateConVar("ace_mobility_brakeonly_boxes", "1", FCVAR_ARCHIVE,
	"1 = a linked gearbox whose every ratio is zero only brakes its wheels and is left out of the parent gearbox's differential (the usual way to give an undriven axle brakes). 0 = it is a real output that spins freely.", 0, 1)
local ApplyConVar = CreateConVar("ace_mobility_apply", "1", 0,
	"0 = solve the drivetrain but do not push the wheels or chassis. For telling drivetrain problems apart from physics problems.", 0, 1)
local InStepConVar = CreateConVar("ace_mobility_instep", "1", FCVAR_ARCHIVE,
	"1 = the drivetrain runs inside every physics step (the physics engine steps every 15 ms whatever the tickrate), so it behaves the same at any tickrate. 0 = once per server tick.", 0, 1)

--- Whether a gearbox should drive in assisted mode.
-- @param Box acf_gearbox entity.
function M.IsAssisted(Box)
	if AssistedConVar:GetBool() then return true end
	return AllowAssistedConVar:GetBool() and (Box.AssistedInput == true or Box.AssistedSetup == true)
end

------------------------------------------------------------------------ engines

--- Builds (or returns the cached) physical spec for an engine entity.
-- Rebuilt when the fuel in use changes (the fallback definition below records it).
-- @param Engine acf_engine entity.
-- @param FuelType Fuel currently being burned.
function M.EngineSpec(Engine, FuelType)
	local Key = (FuelType or Engine.FuelType or "") .. "|" .. (Engine.CoolingChoice or "")
	if Engine.MobSpec and Engine.MobSpecKey == Key then return Engine.MobSpec end

	local Def = ACE.Weapons.Engines[Engine.Id]
	-- The engine menu's cooling choice (ENT:SetStarterSetup) stands in for the definition's.
	if Def and Engine.CoolingChoice then
		Def = setmetatable({ cooling = Engine.CoolingChoice }, { __index = Def })
	end
	local Curve = Engine.TorqueCurve

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

-- Rolling radius of a wheel prop: half its largest extent perpendicular to the axle, from the
-- collision hull (the visual model is often larger than what touches the ground).
local function wheelRadius(Wheel, LocalAxis)
	-- Wheels made spherical (github.com/daveth/makespherical) roll on a sphere whose radius the
	-- visual model says nothing about. The tool stores the applied radius for the duplicator
	-- (its "noradius" is the model's original size, not the sphere) and also sets the collision
	-- bounds to the sphere, which the OBB fallback below picks up; GetAABB has no answer for
	-- sphere physics.
	local Mods = Wheel.EntityMods and Wheel.EntityMods.MakeSphericalCollisions
	local SphereRadius = Mods and Mods.enabled and tonumber(Mods.radius)
	if SphereRadius and SphereRadius > 0 then return math.Clamp(SphereRadius, 1, 200) * InchToMeter end

	local Phys = Wheel:GetPhysicsObject()
	local Mins, Maxs
	if IsValid(Phys) then
		local Ok, A, B = pcall(Phys.GetAABB, Phys)
		if Ok and A and B then Mins, Maxs = A, B end
	end
	if not Mins then Mins, Maxs = Wheel:OBBMins(), Wheel:OBBMaxs() end
	local Size = Maxs - Mins
	local A = Vector(abs(LocalAxis.x), abs(LocalAxis.y), abs(LocalAxis.z))
	-- Project the box extents onto the plane of rotation and take the largest.
	local R = 0
	if A.x < 0.7 then R = max(R, Size.x) end
	if A.y < 0.7 then R = max(R, Size.y) end
	if A.z < 0.7 then R = max(R, Size.z) end
	return R * 0.5 * InchToMeter
end

--[[
	Peak tyre-road friction coefficients for a rubber tyre on dry surfaces, by the ground's
	surface material. Source's own friction values are game tuning (their product reaches 2-3),
	not real coefficients, so they are not used here.
	Sources: Wong, Theory of Ground Vehicles, 4th ed., Table 1.3 (asphalt/concrete 0.8-0.9,
	earth road 0.68, gravel 0.6, snow 0.2, ice 0.1); Gillespie, Fundamentals of Vehicle
	Dynamics, Table 10.1; loose sand and grass from off-road tractive data (Wong ch. 2, 0.3-0.5).
]]
local TyreMu = {}
for Name, Mu in pairs({
	MAT_CONCRETE = 0.85, MAT_TILE = 0.7, MAT_DIRT = 0.68, MAT_GRASS = 0.45,
	MAT_SAND = 0.4, MAT_SNOW = 0.2, MAT_GLASS = 0.6, MAT_METAL = 0.6,
	MAT_VENT = 0.6, MAT_GRATE = 0.6, MAT_WOOD = 0.6, MAT_PLASTIC = 0.6,
	MAT_FOLIAGE = 0.45, MAT_SLOSH = 0.3, MAT_COMPUTER = 0.6, MAT_FLESH = 0.4,
}) do
	-- Looked up by name so a material enum missing from this game build cannot break loading.
	local Id = _G[Name]
	if Id then TyreMu[Id] = Mu end
end
local DefaultTyreMu = 0.8

-- Steel (tracks, metal wheels) on the ground grips less than rubber on hard ground: about
-- 0.4-0.6 dry (Wong Table 1.3, steel wheel on rail 0.25-0.4; tracked vehicles on soil rely on
-- shear, not friction, which the contact solve handles).
local SteelMuCap = 0.6

local function isRubber(Name)
	Name = string.lower(Name or "")
	return string.find(Name, "tire", 1, true) or string.find(Name, "rubber", 1, true)
end

--[[
	Tyre-road friction coefficient for the drivetrain's traction estimate. VPhysics resolves the
	real contact; this only tells the solver how much torque the tyre can pass before it spins.
]]
local SurfaceFriction = {} -- [physics material name] = VPhysics friction

local function contactMu(WheelPhys, GroundSurface)
	local Data = GroundSurface and util.GetSurfaceData(GroundSurface)

	if TyreGripConVar:GetBool() then
		-- VPhysics' contact friction is the product of both surfaces' friction values. Capping
		-- the drivetrain lower than that makes it spin wheels whose contact still holds, and a
		-- spinning wheel in VPhysics loses its side grip too (spin-outs under power).
		local Material = WheelPhys:GetMaterial()
		local WheelFriction = SurfaceFriction[Material]

		if not WheelFriction then
			local Wheel = util.GetSurfaceData(util.GetSurfaceIndex(Material))
			WheelFriction = Wheel and Wheel.friction or 0.8
			SurfaceFriction[Material] = WheelFriction
		end

		return WheelFriction * (Data and Data.friction or 0.8)
	end

	local Mu = Data and TyreMu[Data.material] or DefaultTyreMu
	if not isRubber(WheelPhys:GetMaterial()) then Mu = math.min(Mu, SteelMuCap) end
	return Mu
end

--[[
	Static brake hold. The drivetrain acts on the wheels once per tick, but VPhysics resolves
	contact inside its step, where a braked wheel is free to turn: on a slope the tyre spins it
	up a few rad/s every step and the brake can only undo that at the next tick, so the wheels
	creep and chatter although the brake is far stronger than the load. A real brake at a
	standstill is static friction, so once the vehicle has stopped with the pedal down the
	wheel's rotation is locked to its hub with a rotation-only constraint that VPhysics enforces
	inside the step, and released as soon as the pedal lifts or the drivetrain overpowers the
	brake. The constraint is never saved into dupes.
]]
local BrakeFullConVar = CreateConVar("ace_mobility_brake_full", "1", FCVAR_ARCHIVE,
	"Brake input value that means full pedal (full braking locks the wheels). 1 = brakes take 0-1; 5 = the old drivetrain's scale.", 0.01, 100)

--- Brake pedal fraction (0-1) from a gearbox brake input value.
-- @param Value Brake input value.
function M.BrakePedal(Value)
	return math.min((Value or 0) / BrakeFullConVar:GetFloat(), 1)
end

local MeasuredGripConVar = CreateConVar("ace_mobility_measured_grip", "1", FCVAR_ARCHIVE,
	"1 = a sliding tyre is limited to the grip the physics engine actually gave it last tick. 0 = use the friction product (overestimates sliding grip).", 0, 1)

local LockPedal = 0.3          -- brake fraction from which a stopped wheel is held statically
local PedalRestSpeed = 0.05    -- m/s below which the pedal takes the static hold (see solveGroup)
local BrakeLocks = {}          -- [constraint] = wheel description, for cleanup

-- Moment of inertia of a physics object about a world direction through its centre, kg·m².
local function inertiaAbout(Phys, AxisWorld)
	local A = Phys:WorldToLocalVector(AxisWorld)
	local I = Phys:GetInertia()
	return A.x * A.x * I.x + A.y * A.y * I.y + A.z * A.z * I.z
end

--[[
	A body with far less inertia about the axle than the wheel cannot hold the wheel's spin:
	a constraint between them gives way, and a brake lock to it only spins it. The buggy's
	rear wheels turn on a 25 kg axle rod with a hundredth of a wheel's inertia about its
	length; locked to it, the rear axle and both wheels wound up to 9,000 deg/s. That rod is
	itself held to the chassis about the axle, so the chassis stands in for it.
]]
local function canHoldSpin(Hub, Wheel, AxisWorld)
	local HubPhys, WheelPhys = Hub:GetPhysicsObject(), Wheel:GetPhysicsObject()
	if not IsValid(HubPhys) or not IsValid(WheelPhys) or not AxisWorld then return true end
	return inertiaAbout(HubPhys, AxisWorld) >= 0.25 * inertiaAbout(WheelPhys, AxisWorld)
end

--[[
	The body a wheel turns against: its Axis constraint's other end, else the gearbox's
	mounting, else (when that cannot hold the wheel's spin) the chassis. A parented entity's
	physics object is not simulated, so a constraint to it would hold nothing: its physical
	parent is used.
]]
local function wheelHub(W, Chassis)
	local WheelPhys = W.Ent:GetPhysicsObject()
	local WheelMass = IsValid(WheelPhys) and WheelPhys:GetMass() or 0
	for _, C in ipairs(constraint.FindConstraints(W.Ent, "Axis")) do
		local Other = C.Ent1 == W.Ent and C.Ent2 or C.Ent1
		if IsValid(Other) and Other ~= W.Ent then
			Other = ACE.GetPhysicalParent(Other) or Other
			--[[
				A prop much lighter than the wheel on an axis is a decoration turning with or
				around it (a brake caliper, a hubcap), not what the wheel turns against: a brake
				lock to it held nothing, as constraints give way between very different masses,
				and the Taycan crawled on at 5 km/h with full brakes against a 1 kg caliper.
			]]
			local OtherPhys = Other:GetPhysicsObject()
			if not IsValid(OtherPhys) or OtherPhys:GetMass() >= 0.5 * WheelMass then
				if IsValid(Chassis) and not canHoldSpin(Other, W.Ent, W.AxisWorld) then return Chassis end
				return Other
			end
		end
	end
	local Mount = ACE.GetPhysicalParent(W.Box)
	if IsValid(Mount) and IsValid(Chassis) and Mount ~= Chassis and not canHoldSpin(Mount, W.Ent, W.AxisWorld) then return Chassis end
	return Mount
end

--[[
	Spin groups. A common way to build tank running gear is to tie every road wheel to the
	sprocket with a rotation-only AdvBallsocket whose limits are a fraction of a degree, so all
	of them turn as one: the sprocket is linked to the gearbox, the road wheels carry the tank.
	Read and driven alone, the sprocket looked like a light wheel in the air; the drivetrain
	gave it impulses sized for its own inertia, which the ballsockets then fought every tick.
	The sprocket swung between -100 and +140 rad/s and the T-64 crawled at 13 km/h in second,
	the engine on its limiter. The wheels locked to the driven one are one rotating body: their
	inertias add, their speed is read together, and the group rolls on whichever member touches
	the ground.
]]
local SpinLockDeg = 5 -- an AdvBallsocket whose every limit is within this many degrees locks rotation
local SpinGroupMax = 32
local LimitKeys = { "xmin", "xmax", "ymin", "ymax", "zmin", "zmax" }

local function locksSpin(C)
	if C.Type == "Weld" then return true end
	if C.Type ~= "AdvBallsocket" then return false end
	for _, K in ipairs(LimitKeys) do
		local V = tonumber(C[K])
		if not V or math.abs(V) > SpinLockDeg then return false end
	end
	return true
end

-- Props whose spin is locked to the wheel, not counting the wheel, its hub, the chassis or
-- the gearbox mounting. Each entry: { Ent, Phys, LocalAxis, Radius }.
local function spinGroup(W, Ctx)
	local Skip = { [W.Ent] = true }
	if IsValid(Ctx.Chassis) then Skip[Ctx.Chassis] = true end
	if IsValid(W.Hub) then Skip[W.Hub] = true end
	local Mount = ACE.GetPhysicalParent(W.Box)
	if IsValid(Mount) then Skip[Mount] = true end
	local Members, Queue = {}, { W.Ent }
	while #Queue > 0 and #Members < SpinGroupMax do
		local E = table.remove(Queue)
		for _, C in pairs(constraint.GetTable(E) or {}) do
			local Other = C.Ent1 == E and C.Ent2 or C.Ent1
			if IsValid(Other) and not Skip[Other] and locksSpin(C) then
				Skip[Other] = true
				local P = Other:GetPhysicsObject()
				-- Another driven wheel is read and driven on its own.
				if IsValid(P) and Other:GetClass() == "prop_physics" and not IsValid(Other:GetParent()) and Other.ACEWheelW == nil then
					local LocalAxis = P:WorldToLocalVector(W.AxisWorld)
					Members[#Members + 1] = { Ent = Other, Phys = P, LocalAxis = LocalAxis, Radius = wheelRadius(Other, LocalAxis) }
					Queue[#Queue + 1] = Other
				end
			end
		end
	end
	return Members
end

--[[
	Only the spin about the axle is locked; the other two rotations stay free, so a wheel hung
	on ballsockets (steering knuckles, suspension arms) keeps steering and travelling while it
	is held. A ragdoll constraint's limits are about the axes of its own frame, which is the
	constraint entity's angles when it spawns; constraint.AdvBallsocket leaves those at zero,
	so its limits are world axes, and a lock made that way held a wheel only while the car
	faced along a world axis that matched the axle. On a car facing 90 degrees off, it locked
	a direction the wheel's own axle already holds and left the spin free: the brake did
	nothing and the car rolled and swung on with the pedal down (measured: 0 vs 568 deg/s).
	So the frame is built with its x axis along the axle and only x is limited.
]]
local function axleLock(Wheel, Hub, AxisWorld)
	local WheelPhys, HubPhys = Wheel:GetPhysicsObject(), Hub:GetPhysicsObject()
	if not IsValid(WheelPhys) or not IsValid(HubPhys) or not AxisWorld then return nil end
	local Lock = ents.Create("phys_ragdollconstraint")
	if not IsValid(Lock) then return nil end
	Lock:SetPos(WheelPhys:GetPos())
	Lock:SetAngles(AxisWorld:Angle())
	Lock:SetKeyValue("xmin", -0.01)
	Lock:SetKeyValue("xmax", 0.01)
	Lock:SetKeyValue("ymin", -180)
	Lock:SetKeyValue("ymax", 180)
	Lock:SetKeyValue("zmin", -180)
	Lock:SetKeyValue("zmax", 180)
	Lock:SetKeyValue("spawnflags", 2) -- rotation only
	Lock:SetPhysConstraintObjects(WheelPhys, HubPhys)
	Lock:Spawn()
	Lock:Activate()
	Lock:SetTable({ Type = "AdvBallsocket", Ent1 = Wheel, Ent2 = Hub, Bone1 = 0, Bone2 = 0, onlyrotation = 1 })
	constraint.AddConstraintTable(Wheel, Lock, Hub)
	return Lock
end

local function applyBrakeLock(W, Want)
	local Lock = W.BrakeLock
	if Want then
		W.BrakeLockSeen = CurTime()
		if IsValid(Lock) then return end
		local Hub = IsValid(W.Ent) and (IsValid(W.Hub) and W.Hub or wheelHub(W))
		if not IsValid(Hub) or Hub == W.Ent then return end
		Lock = axleLock(W.Ent, Hub, W.AxisWorld)
		if not IsValid(Lock) then return end
		Lock.DoNotDuplicate = true
		Lock.ACE_BrakeLock = true
		W.BrakeLock = Lock
		BrakeLocks[Lock] = W
		if M.Log then M.Log.Event(W.Ent, "lock_on", (W.LockWhy or "?") .. " hub " .. tostring(Hub)) end
	elseif Lock then
		if M.Log then M.Log.Event(W.Ent, "lock_off", W.BrakeSlipped and "brake overpowered" or "no longer wanted") end
		if IsValid(Lock) then Lock:Remove() end
		BrakeLocks[Lock] = nil
		W.BrakeLock = nil
	end
end

--[[
	The locks are constraints, which must not be made or removed while the physics engine is
	stepping (the drivetrain can run inside the step), so the solve only records what it wants
	and the locks are set from the entity side of the tick.
]]
local function brakeLock(W, Want)
	W.LockWant = Want
end

local function applyBrakeLocks(WheelList)
	for _, W in ipairs(WheelList) do
		if W.LockWant ~= nil then applyBrakeLock(W, W.LockWant) end
	end
end

-- Drops locks whose drivetrain stopped updating them (engine removed or unlinked).
timer.Create("ACE_Mobility_BrakeLocks", 0.5, 0, function()
	local Now = CurTime()
	for Lock, W in pairs(BrakeLocks) do
		if not IsValid(Lock) or Now - (W.BrakeLockSeen or 0) > 0.5 then
			if M.Log then M.Log.Event(W.Ent, "lock_off", IsValid(Lock) and "stale: drivetrain stopped updating it" or "constraint removed elsewhere") end
			if IsValid(Lock) then Lock:Remove() end
			BrakeLocks[Lock] = nil
			if W.BrakeLock == Lock then W.BrakeLock = nil end
		end
	end
end)

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
	Desc.OwnRadius = Desc.OwnRadius or wheelRadius(Ent, Link.Axis)
	Desc.Radius = Desc.OwnRadius

	-- Forward rotation is about -axis (the convention the old drivetrain used).
	--[[
		Spin is measured against what the wheel turns on (its axis constraint's other end, else
		the chassis), not against the gearbox: a parented gearbox's physics object does not
		move, so its angular velocity is zero and chassis pitch would read as wheel spin. The
		drivetrain's own reaction torque pitches the chassis, so that error fed back on itself
		and kept wheels turning and chassis rocking on a standing vehicle.
	]]
	local Now = CurTime()
	if not IsValid(Desc.Hub) or Now > (Desc.HubAt or 0) then
		local Hub = wheelHub(Desc, Ctx.Chassis)
		Desc.Hub = IsValid(Hub) and ACE.GetPhysicalParent(Hub) or nil
		Desc.HubAt = Now + 2
		Desc.Group = spinGroup(Desc, Ctx)
	end
	local HubPhys = IsValid(Desc.Hub) and Desc.Hub:GetPhysicsObject()
	local RefAngVel = IsValid(HubPhys) and HubPhys:LocalToWorldVector(HubPhys:GetAngleVelocity()) or BoxAngVel
	--[[
		A hub that turns about the wheel's own axle is not something the wheel turns against: a
		solid axle prop between two wheels, ballsocketed to the chassis, is free to spin about
		its length. Measured against it, its spin read as wheel spin, the drivetrain fought that
		with impulses the axle picked up, and the axle ran away until the physics engine deleted
		it with its constraints (buggy: 93,000 deg/s). A hub spinning about the axle more than
		10 rad/s faster than the chassis (no suspension arm swings that fast) gives way to the
		chassis.
	]]
	local Root = ACE.GetPhysicalParent(Box)
	local RootPhys = IsValid(Root) and Root:GetPhysicsObject()
	if IsValid(HubPhys) and IsValid(RootPhys) and RootPhys ~= HubPhys then
		local RootAngVel = RootPhys:LocalToWorldVector(RootPhys:GetAngleVelocity())
		if math.abs((RefAngVel - RootAngVel):Dot(AxisWorld)) * DegToRad > 10 then RefAngVel = RootAngVel end
	end
	local AngVel = Phys:LocalToWorldVector(Phys:GetAngleVelocity()) - RefAngVel
	local PrevW, PrevOut, Applied = Desc.W, Desc.WOut, Desc.AppliedDW
	Desc.W = -AngVel:Dot(AxisWorld) * DegToRad
	-- A spin group turns as one body: its speed is the inertia-weighted mean of its members,
	-- which the ground-rolling road wheels keep steady while the sprocket alone jitters.
	local Group = Desc.Group
	if Group and #Group > 0 then
		local OwnJ = max(inertiaAbout(Phys, AxisWorld) * Units.SourceInertiaToSI, 1e-3)
		local SumJ, SumJW = OwnJ, OwnJ * Desc.W
		for I = #Group, 1, -1 do
			local G = Group[I]
			if not IsValid(G.Phys) then
				table.remove(Group, I)
			else
				G.J = max(inertiaAbout(G.Phys, AxisWorld) * Units.SourceInertiaToSI, 1e-3)
				local GW = -(G.Phys:LocalToWorldVector(G.Phys:GetAngleVelocity()) - RefAngVel):Dot(AxisWorld) * DegToRad
				SumJ, SumJW = SumJ + G.J, SumJW + G.J * GW
			end
		end
		Desc.OwnJ, Desc.GroupJ = OwnJ, SumJ
		Desc.W = SumJW / SumJ
	else
		Desc.OwnJ, Desc.GroupJ = nil, nil
	end
	Ent.ACEWheelW = Desc.W -- for the acfWheelRPM accessors
	-- What the road (and anything else) did to the wheel's spin since last tick, beyond the
	-- impulse the drivetrain applied: the tyre's actual pass-through, N*m*s.
	Desc.TyreImp = PrevW and Applied and Desc.J and Desc.J * (Desc.W - PrevW - Applied) or nil
	-- While the tyre slides, that is its real (kinetic) grip: remember it, smoothed over a few
	-- ticks. It is forgotten once the tyre has been rolling for half a second.
	if Desc.WasSliding and Desc.TyreImp then
		local Cap = math.abs(Desc.TyreImp) / Ctx.Dt
		Desc.SlideCap = Desc.SlideCap and Desc.SlideCap * 0.6 + Cap * 0.4 or Cap
		Desc.SlideSeen = Now
	elseif Desc.SlideCap and Now - (Desc.SlideSeen or 0) > 0.5 then
		Desc.SlideCap = nil
	end

	-- Ground contact under the wheel, or under any member of its spin group (which then sets
	-- the rolling radius: every member turns at the same speed).
	local R = Desc.Radius
	local Center = Phys:GetPos()
	local ContactPhys = Phys
	local Tr = util.TraceLine({
		start = Center,
		endpos = Center + Vector(0, 0, -1) * (R / InchToMeter + 4),
		filter = Ctx.Filter,
	})
	if not Tr.Hit and Group then
		for _, G in ipairs(Group) do
			local GC = G.Phys:GetPos()
			local GTr = util.TraceLine({
				start = GC,
				endpos = GC + Vector(0, 0, -1) * (G.Radius / InchToMeter + 4),
				filter = Ctx.Filter,
			})
			if GTr.Hit then
				Tr, Center, ContactPhys = GTr, GC, G.Phys
				R = G.Radius
				Desc.Radius = R
				break
			end
		end
	end

	--[[
		Load detection for wheels the ground trace cannot see: tank sprockets and idlers ride
		above the ground and drive through the track, so they are loaded by the whole vehicle
		although nothing is under them. Compare what VPhysics did to the wheel with what the
		drivetrain asked for last tick: a wheel that keeps less than 40 % of the commanded speed
		change is held by something (track, ground, other props) and is coupled to the vehicle;
		a coupled wheel that runs far past the coupled prediction is really spinning free.
	]]
	-- A wheel spinning about a near-vertical axle (a rotor, a turret ring) cannot roll on the
	-- ground, so whatever resists it is not the vehicle's weight.
	local Upright = math.abs(AxisWorld.z) > 0.7
	--[[
		Nor is a wheel a player holds (physics gun, gravity gun, use key): the hold, not a track,
		is what keeps it from following the drivetrain. Turning one wheel of a car frozen in the
		air latched it as a sprocket in a few ticks, which also made it grounded, and a car in
		gear with the engine off then locked it to its hub, so the other wheel never answered
		through the differential.
	]]
	Desc.Held = Ent:IsPlayerHolding() or nil
	if M.Log and Desc.Held and Desc.Loaded then M.Log.Event(Ent, "unloaded", "held by a player") end
	if Upright or Desc.Held then
		Desc.Loaded = false
		Desc.LoadEMA = 1
		Desc.FreeTicks = 0
	elseif PrevW and PrevOut and Applied then
		if not Desc.Loaded then
			--[[
				Only a wheel with nothing under it is tested: one standing on the ground is loaded
				by it anyway, and a latch made there outlived the ground. Lifted and frozen in the
				air after a drive, every wheel still counted as a sprocket driving the vehicle
				through a track, so the parking hold locked them all and turning one wheel moved
				nothing else (Volvo and Sputnik, engine off in gear).
			]]
			if not Tr.Hit and math.abs(Applied) > 0.3 then
				local Kept = (Desc.W - PrevW) / Applied
				Desc.LoadEMA = (Desc.LoadEMA or 1) * 0.7 + Kept * 0.3
				if Desc.LoadEMA < 0.4 then
					Desc.Loaded = true
					if M.Log then M.Log.Event(Ent, "loaded", string.format("kept %.2f of the drivetrain's impulse", Desc.LoadEMA)) end
				end
			end
		else
			--[[
				Only a wheel that keeps running past the prediction is spinning free. A sprocket
				jumps a tooth of its track now and then, and one such tick used to drop it to a
				free wheel that got only its own inertia's worth of torque, so a tank's tracks
				rattled at a fraction of their drive (T-14 pivot turned 0 degrees).
			]]
			local Excess = Desc.W - PrevOut
			if math.abs(Excess) > max(2, 3 * math.abs(PrevOut - PrevW)) and Excess * Applied > 0 then
				Desc.FreeTicks = (Desc.FreeTicks or 0) + 1
			else
				Desc.FreeTicks = 0
			end
			if Desc.FreeTicks >= 10 then
				if M.Log then M.Log.Event(Ent, "unloaded", "ran past the prediction for 10 ticks") end
				Desc.Loaded = false
				Desc.LoadEMA = 1
				Desc.FreeTicks = 0
			end
		end
	end

	-- Own inertia about the axle.
	Desc.J = max((Link.Axis * Phys:GetInertia()):Length() * Units.SourceInertiaToSI, 1e-3)
	if Desc.GroupJ then Desc.J = Desc.J + Desc.GroupJ - Desc.OwnJ end

	Desc.Grounded = not Upright and (Tr.Hit or Desc.Loaded == true)
	Desc.Meshed = not Tr.Hit and Desc.Loaded == true
	Desc.GroundNormal = Tr.Hit and Tr.HitNormal or nil
	if Tr.Hit then
		Desc.Mu = contactMu(ContactPhys, Tr.SurfaceProps)
	elseif Desc.Grounded then
		-- Driving through a track: steel on the ground.
		Desc.Mu = SteelMuCap
	else
		Desc.Mu = 0
	end

	-- Rolling direction and contact ground speed. Measured on the chassis at the wheel centre:
	-- the wheel prop's own velocity carries its suspension and contact jitter.
	local Fwd = (-AxisWorld):Cross(Vector(0, 0, 1))
	if Fwd:LengthSqr() > 1e-6 then
		Fwd:Normalize()
		local Root = ACE.GetPhysicalParent(Box)
		local RootPhys = IsValid(Root) and Root:GetPhysicsObject()
		local Vel = IsValid(RootPhys) and RootPhys:GetVelocityAtPoint(Center) or Phys:GetVelocity()
		Desc.GroundSpeed = Vel:Dot(Fwd) * InchToMeter
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
	-- A box whose every gear (or final drive) is zero can never transmit; builders use one to
	-- give an undriven axle brakes.
	local Final = Box.GearTable and Box.GearTable.Final or 0
	local AnyGear = false
	-- A standalone clutch has no gears: it always runs on its gear 0 (a fixed 1:1 before the final drive).
	for I = (Box.Gears or 0) == 0 and 0 or 1, Box.Gears or 0 do
		if abs((Box.GearTable[I] or 0) * Final) > 1e-6 then AnyGear = true break end
	end
	Desc.BrakeOnly = not AnyGear and not Box.CVT and BrakeOnlyConVar:GetBool()
	Desc.InputJ = (Box.InputJ or 0.02 + 0.00002 * Max) + (Box.MobClutchJ or 0)
	Desc.Efficiency = Box.MobEfficiency or 0.97
	Desc.SpinLoss = 0.002 * Max
	Desc.Dual = Box.Dual
	Desc.ClutchCap = Box.MobClutchCap
	Desc.ClutchFree = not Box.MobCapFull
	local SideScale = Box.MobSideScale or 1
	Desc.SideCap = { [0] = (Box.LClutch or Max) * SideScale, [1] = (Box.RClutch or Max) * SideScale }
	Desc.DriveCap = Box.MobDriveCap
	Desc.Diff = Box.MobDiff
	Desc.Steering = Box.MobSteering
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

------------------------------------------------------------------------ debug

local NextDebugPrint = 0
local CsvHeaderWritten = false
local CsvPath = "ace_mobility_debug.csv"

local function fmt(V) return string.format("%.2f", V or 0) end

-- Prints the state of one solved group. Detail matters more than looks here: the output is
-- meant to be pasted back when a vehicle misbehaves.
local function debugReport(Group, Ctx, Dt)
	local Level = DebugConVar:GetInt()
	if Level <= 0 then return end

	local Now = CurTime()
	local Chassis = ACE.GetPhysicalParent(Group[1])
	local CPhys = IsValid(Chassis) and Chassis:GetPhysicsObject()
	local CVel = IsValid(CPhys) and CPhys:GetVelocity() or vector_origin
	local CAng = IsValid(CPhys) and CPhys:GetAngleVelocity() or vector_origin

	-- Suspicious impulses are reported every tick: one tick is enough to launch a car.
	for _, W in ipairs(Ctx.WheelList) do
		local DW = (W.Impulse or 0) / max(W.J or 1, 1e-3)
		if abs(DW) > 60 or W.W ~= W.W or (W.Impulse or 0) ~= (W.Impulse or 0) then
			MsgN(string.format("[ACE mobility] WARNING t=%.3f wheel %s impulse %.1f N*m*s would change its spin by %.0f rad/s in one tick (J=%.2f, w=%.1f, ground=%.1f, grounded=%s)",
				Now, tostring(W.Ent), W.Impulse or 0, DW, W.J or 0, W.W or 0, W.Ground and W.Ground.W or 0, tostring(W.Grounded)))
		end
	end

	if Level >= 2 then
		if not CsvHeaderWritten then
			file.Write(CsvPath, "t,dt,engine,rpm,throttle,torque,chassis_speed,chassis_vz,chassis_angvel,wheel,side,grounded,mu,radius,J,w_in,w_out,ground_w,ground_J,cap,impulse,ground_impulse,brake_max,ground_speed,loaded,locked\n")
			CsvHeaderWritten = true
		end
		local E = Group[1]
		local Head = string.format("%.4f,%.4f,%s,%.1f,%.3f,%.1f,%.3f,%.3f,%.2f", Now, Dt, E:EntIndex(), E.FlyRPM or 0, E.Throttle or 0,
			E.Torque or 0, CVel:Length() * InchToMeter, CVel.z * InchToMeter, CAng:Length())
		local Rows = {}
		for _, W in ipairs(Ctx.WheelList) do
			local G = W.Ground
			Rows[#Rows + 1] = string.format("%s,%s,%s,%d,%.3f,%.3f,%.3f,%.3f,%.3f,%.3f,%.2f,%.1f,%.3f,%.3f,%.1f,%.3f,%d,%d\n", Head,
				W.Ent:EntIndex(), W.Link and W.Link.Side or -1, W.Grounded and 1 or 0, W.Mu or 0, W.Radius or 0, W.J or 0,
				W.W or 0, W.WOut or 0, G and G.W or 0, G and G.J or 0, G and G.Cap or 0, W.Impulse or 0, W.GroundImpulse or 0, W.BrakeMax or 0,
				W.GroundSpeed or 0, W.Loaded and 1 or 0, IsValid(W.BrakeLock) and 1 or 0)
		end
		file.Append(CsvPath, table.concat(Rows))
	end

	if Now < NextDebugPrint then return end
	NextDebugPrint = Now + 0.5

	MsgN(string.format("[ACE mobility build 4] t=%.2f dt=%.4f chassis %s speed %.1f km/h vz %.2f m/s angvel %.0f deg/s mass phys %.0f / total %.0f kg",
		Now, Dt, tostring(Chassis), CVel:Length() * InchToMeter * 3.6, CVel.z * InchToMeter, CAng:Length(), Group[1].PhysMass or 0, Group[1].TotalMass or 0))
	for _, E in ipairs(Group) do
		local St = E.MobState
		MsgN(string.format("  engine %s active=%s rpm=%.0f throttle=%.2f torque=%.0f stalled=%s",
			tostring(E), tostring(E.Active), E.FlyRPM or 0, E.Throttle or 0, E.Torque or 0, tostring(St and St.Stalled)))
	end
	for _, Box in ipairs(Ctx.BoxList) do
		local D = Box.Mob or {}
		MsgN(string.format("  gearbox %s gear=%s ratio=%s clutchCap=%s driveCap=%s diff=%s inRPM=%.0f brakeL=%s brakeR=%s assisted=%s",
			tostring(Box), tostring(Box.Gear), fmt(D.Ratio), fmt(D.ClutchCap), tostring(D.DriveCap and fmt(D.DriveCap)), tostring(D.Diff),
			(D.InputW or 0) * 30 / math.pi, fmt(D.Brake and D.Brake[0]), fmt(D.Brake and D.Brake[1]), tostring(M.IsAssisted(Box))))
	end
	for _, W in ipairs(Ctx.WheelList) do
		local G = W.Ground
		MsgN(string.format("  wheel %s side=%s grounded=%s mu=%.2f r=%.3f J=%.2f w=%.1f->%.1f rad/s ground_w=%s cap=%s impulse=%.2f (road %.2f) dw=%.1f",
			tostring(W.Ent), tostring(W.Link and W.Link.Side), tostring(W.Grounded), W.Mu or 0, W.Radius or 0, W.J or 0,
			W.W or 0, W.WOut or 0, G and fmt(G.W) or "-", G and fmt(G.Cap) or "-", W.Impulse or 0, W.GroundImpulse or 0,
			(W.Impulse or 0) / max(W.J or 1, 1e-3)))
	end
end

-- Sizes wheel loads and brakes, solves one drivetrain and hands the impulses to VPhysics.
--[[
	Wheels held by a stopped engine: in gear with every clutch on the way engaged, a car whose
	engine is off is held by the engine's compression, like leaving a manual in gear to park.
	That hold has the same problem as a brake at a standstill (the drivetrain acts once per
	tick, the ground spins the wheel inside the physics step, so the car jitters on the spot),
	so it uses the same static lock. Returns a set of wheel descriptions, or nil.
]]
local function engineHeldWheels(EngineDescs)
	if not EngineDescs then return nil end
	-- An engine that is off (and not cranking) holds the wheels whatever its crank speed reads:
	-- on a standing vehicle that speed only comes from the wheels jiggling through the clutch,
	-- and waiting for it to reach zero kept the jiggle going. Each wheel is still only held
	-- once its own ground speed is near zero.
	for _, E in ipairs(EngineDescs) do
		local State = E.State
		if not State or State.Running or (State.Cranking or 0) > 0 then return nil end
	end

	local Held = {}
	local function walk(Desc, Depth)
		if not Desc or Depth > 8 or Desc.BrakeOnly or Desc.Converter then return end
		if (Desc.Ratio or 0) == 0 then return end
		if Desc.ClutchCap and Desc.ClutchCap < 1 then return end
		for _, Out in ipairs(Desc.Outputs or {}) do
			local SideCap = Desc.Dual and Desc.SideCap and Desc.SideCap[Out.Side == 0 and 0 or 1]
			if not SideCap or SideCap >= 1 then
				if Out.Wheel then Held[Out.Wheel] = true else walk(Out.Gearbox, Depth + 1) end
			end
		end
	end
	for _, E in ipairs(EngineDescs) do
		for _, Box in ipairs(E.Gearboxes or {}) do walk(Box, 0) end
	end
	return next(Held) and Held or nil
end

-- EngineDescs and Roots (gearbox trees no engine drives) are what Drivetrain.Build takes.
-- The physics engine's spin cap in rad/s, with a margin for the chassis' own rotation (the cap
-- applies to the wheel's total angular velocity, spin is measured against the hub).
local MaxSpin, MaxSpinAt = nil, 0
local function MaxWheelSpin()
	local Now = CurTime()
	if not MaxSpin or Now > MaxSpinAt then
		local Settings = physenv.GetPerformanceSettings()
		MaxSpin = 0.95 * (Settings and Settings.MaxAngularVelocity or 7272) * DegToRad
		MaxSpinAt = Now + 5
	end
	return MaxSpin
end

--[[
	Whether the holds can really take the load: a static friction contact sticks only while
	what pulls it stays below what holds it (Karnopp). A lock is a fixed point for the physics
	engine and would hold the vehicle on any slope, so this is solved instead: the whole
	drivetrain from rest for one tick, every wheel free, each grounded wheel carrying its share
	of the vehicle with the slope pulling, and the brakes, the engine (a stopped one through its
	friction and pumping, a running one through the clutch) and everything geared to them
	resisting. A wheel that stays put can be held; one that turns cannot. Sets W.HoldSlips.
	It is solved apart from the real step so moving wheels do not drag held ones through the
	differentials. A buggy parked in first with the engine off held on a 49 degree slope its
	engine could hold a seventh of; tested inside the real step, the hold was taken and lost
	every other tick and the buggy crept down instead of rolling.
]]
local HoldTolerance = 0.005 -- rad/s after one tick from rest: numerical noise, not motion

local function staticHold(Ctx, EngineDescs, Roots, Dt)
	local Any = false
	for _, W in ipairs(Ctx.WheelList) do
		W.HoldSlips = nil
		if W.WantLock or IsValid(W.BrakeLock) then Any = true end
	end
	if not Any then return end

	local SavedWheels, SavedStates, SavedInputs = {}, {}, {}
	for _, W in ipairs(Ctx.WheelList) do
		SavedWheels[W] = { W.Ground, W.Anchored }
		W.Ground, W.Anchored, W.ParkProbe = W.RestGround, nil, true
	end
	for _, E in ipairs(EngineDescs) do
		local Copy = {}
		for K, V in pairs(E.State) do Copy[K] = V end
		-- The cylinders' trapped air changes in place during the trial.
		if E.State.Charge then Copy.Charge = table.Copy(E.State.Charge) end
		SavedStates[E] = Copy
	end
	for _, Box in ipairs(Ctx.BoxList) do
		local D = Box.Mob
		if D then
			SavedInputs[D] = D.InputW or false
			D.InputW = 0
		end
	end

	local Sys = Drivetrain.Build({ Engines = EngineDescs, Roots = Roots })
	Drivetrain.Step(Sys, Dt, SubstepsConVar:GetInt())
	for _, W in ipairs(Ctx.WheelList) do
		W.HoldSlips = abs(W.WOut or 0) > HoldTolerance or nil
	end

	for W, S in pairs(SavedWheels) do W.Ground, W.Anchored, W.ParkProbe = S[1], S[2], nil end
	for E, Copy in pairs(SavedStates) do
		for K in pairs(E.State) do E.State[K] = nil end
		for K, V in pairs(Copy) do E.State[K] = V end
	end
	for D, V in pairs(SavedInputs) do D.InputW = V or nil end
end

local function solveGroup(Ctx, EngineDescs, Roots, PhysMass, TotalMass, Dt)
	TotalMass = max(TotalMass, PhysMass)
	local RoadScale = TotalMass > 0 and PhysMass / TotalMass or 1

	-- Every grounded driven wheel propels an equal share of the vehicle. Normal load is
	-- deliberately generous (all weight on the driven wheels) so the solver never predicts less
	-- traction than VPhysics has; any excess simply shows up as wheelspin next tick.
	local Grounded = 0
	for _, W in ipairs(Ctx.WheelList) do
		if W.Grounded then Grounded = Grounded + 1 end
	end
	local Share = Grounded > 0 and TotalMass / Grounded or 0
	-- Brakes are sized to lock the wheel under its share of the whole vehicle with some margin,
	-- like real brake systems, whether or not this wheel is touching the ground right now
	-- (tank sprockets often ride above it and drive through the track).
	local BrakeShare = TotalMass / max(#Ctx.WheelList, 1)
	local ChassisPhys = IsValid(Ctx.Chassis) and Ctx.Chassis:GetPhysicsObject()
	local ChassisFrozen = IsValid(ChassisPhys) and not ChassisPhys:IsMotionEnabled()
	local EngineHeld = engineHeldWheels(EngineDescs)

	--[[
		Brake bias. A stop moves load onto the wheels ahead of the centre of mass (in the
		direction of travel) and off those behind it, and brake systems are proportioned to
		match (about 60-70 % front on road vehicles, Gillespie ch. 3): the trailing wheels get
		less torque so they are not the first to lock, which would swing the vehicle round.
	]]
	local Root = Ctx.WheelList[1] and ACE.GetPhysicalParent(Ctx.WheelList[1].Box)
	local RootPhys = IsValid(Root) and Root:GetPhysicsObject()
	local MassCenter, TravelDir
	if IsValid(RootPhys) then
		local Vel = RootPhys:GetVelocity()
		if Vel:Length() * InchToMeter > 1 then
			TravelDir = Vel:GetNormalized()
			MassCenter = RootPhys:LocalToWorld(RootPhys:GetMassCenter())
		end
	end
	for _, W in ipairs(Ctx.WheelList) do
		--[[
			A braked wheel on a standing vehicle is in static adhesion: VPhysics' own contact holds
			the car, and the brake only has to keep the wheel still against its hub. Coupling it to
			the vehicle's inertia here would treat the chassis' suspension rocking (seen as a few
			cm/s at the wheel centre) as vehicle motion and brake it through the tyre every tick,
			which keeps the car rocking and the wheels creeping.
		]]
		local Box, Side = W.Box, W.Link and W.Link.Side
		local Pedal = IsValid(Box) and (Side == 0 and Box.LBrake or Box.RBrake) or 0
		--[[
			A hold engages below 0.25 m/s but, once on, lets go only past 1.5 m/s: the chassis
			rocking on its suspension reads up to about 0.6 m/s at the wheel centres, and a lock
			that let go on that was made and removed every few ticks, each time kicking the car
			and keeping it rocking (measured on the Volvo parked in gear).
		]]
		local Speed = abs(W.GroundSpeed or 0)
		local Stopped = Speed < (IsValid(W.BrakeLock) and 1.5 or 0.25)
		local Parked = EngineHeld and EngineHeld[W] and (W.Grounded or IsValid(W.BrakeLock))
		--[[
			A lock does not take the vehicle's momentum the way a brake does. It stops the wheel
			dead, and the tyre goes from rolling to stuck in one step; the physics engine holds a
			stuck contact with a spring that does not slip at tyre grip, so the vehicle's motion
			winds that spring up and it throws the vehicle back with most of it. Locked at 0.85
			m/s, the buggy stopped in 0.06 s and bounced back at 0.47 m/s with the pedal down (the
			wheels stayed locked to the chassis; it was the tyres that slid back), then rocked to
			and fro; locked at 0.24 m/s it came back at 0.21, at 0.05 m/s at 0.04. A brake is
			friction: it takes the motion out and cannot give any back. So the pedal brakes
			through the drivetrain's brake torque, which can only stop the wheel, and the lock is
			only taken once the vehicle is at rest (below 0.05 m/s), to hold it there.
		]]
		local AtRest = Speed < (IsValid(W.BrakeLock) and 1.5 or PedalRestSpeed)
		--[[
			Except where the brake torque cannot get it there: braked by impulses, a car sliding
			slowly down a slope never came to rest: each step the brake knocked the wheel back,
			the tyre spun it forward again inside the physics step, the contact never gripped
			and the car slid on at 2 km/h (Volvo, engine off, full brake). A firm pedal that has
			not slowed a vehicle at walking pace (below 3 m/s) by StallDecel for StallTime is not
			going to stop it, so the wheel is locked there and the tyre then grips or slides, as a
			real locked wheel does. Track sprockets keep impulse braking: locking one mid-turn
			would snap a brake-steered tank round.
		]]
		--[[
			A held lock does not let go because the ground trace missed for a tick: a wheel
			bouncing on its suspension lost and found the ground every other tick, and its lock
			was made and removed each time (buggy rear axle, 30 times in half a second).
		]]
		local Crawling = Speed < (IsValid(W.BrakeLock) and 4 or 3) and (W.Grounded or IsValid(W.BrakeLock)) and not W.Meshed
		local Firm = M.BrakePedal(Pedal) >= LockPedal
		local Stalled = Drivetrain.BrakeStalled(W, Firm and Crawling and not IsValid(W.BrakeLock), Speed, Dt)
		local PedalLock = Firm and (AtRest or Crawling and (IsValid(W.BrakeLock) or Stalled))
		-- Strictly true or false: nil means "leave the lock as it is", and a nil here (no engine
		-- hold) left a released brake locked until the stale-lock timer dropped it 0.5 s later,
		-- long enough to stall a truck pulling away.
		-- Whether the hold can really be taken is decided by staticHold below.
		W.WantLock = PedalLock or Parked and Stopped or false
		W.LockWhy = PedalLock and (AtRest and "pedal at standstill" or "pedal not slowing a crawling vehicle") or Parked and Stopped and "parked in gear with the engine off" or nil
		local Held = IsValid(W.BrakeLock) or (Pedal or 0) > 0 and AtRest and abs(W.W * W.Radius) < 0.5
		--[[
			A wheel locked to its hub is a fixed point for the drivetrain and gets no impulse.
			Solved as a free wheel, the solver pushed it every tick against the lock and the lock
			pushed back, so a held car vibrated in place (a parked Volvo, and one on the brake
			pedal: 4 m of jitter in 10 s). The torque the drivetrain puts through it is still
			measured (AnchorTorque), so a pedal hold lets go once the engine overpowers the brake.
		]]
		W.HeldStill = Held or nil
		W.Anchored = IsValid(W.BrakeLock) or nil
		W.Braking = (Pedal or 0) > 0
		W.Ground = not Held and Vehicle.Ground(Share, W.Radius, W.GroundSpeed, W.Mu, Share * Gravity, W.Grounded, W.W, W.Meshed) or nil
		-- The wheel's share of the vehicle standing on it with the slope pulling, for staticHold.
		W.RestGround = nil
		if W.Grounded and not W.Meshed and W.Radius > 0 then
			local Rest = Vehicle.Ground(Share, W.Radius, 0, W.Mu, Share * Gravity, true, 0, false)
			local Downhill = (-W.AxisWorld):Cross(W.GroundNormal or Vector(0, 0, 1))
			if Rest and Downhill:LengthSqr() > 1e-6 then
				Downhill:Normalize()
				-- Along the physics engine's own gravity, which maps and addons can tilt. A frozen
				-- chassis cannot roll anywhere, so then only the drivetrain pushes.
				local Pull = ChassisFrozen and 0 or physenv.GetGravity():GetNormalized():Dot(Downhill)
				Rest.Torque = Share * Gravity * Pull * W.Radius
			end
			W.RestGround = Rest
		end
		--[[
			The friction product (and the generous load above) overestimate what a sliding tyre
			passes: measured, the physics engine gives a spinning or locked wheel about 40-60 % of
			it. A sliding tyre is limited to what it really got last tick, so the solver sends a
			spinning wheel no more torque than it can use and an open differential splits torque
			by the grip the wheels really have. A rolling tyre keeps the generous limit.
		]]
		local Sliding = W.Ground ~= nil and not W.Meshed and W.Ground.W ~= W.W
		if Sliding and W.SlideCap and MeasuredGripConVar:GetBool() then
			W.Ground.Cap = min(W.Ground.Cap, max(W.SlideCap * 1.1, 0.05 * W.Ground.Cap))
		end
		W.WasSliding = Sliding
		--[[
			Rolling resistance: about 0.012 of the load for tyres on a hard road (Gillespie ch. 4).
			A track adds its internal losses (pin joints, road wheels and idlers flexing the
			track), about 0.03-0.05 of vehicle weight on hard ground (Wong, Theory of Ground
			Vehicles, 4th ed., ch. 2), so sprockets driving through a track use 0.04.
		]]
		local Crr = W.Meshed and (ACE.MobilityTrackResistance or 0.04) or (ACE.MobilityRollingResistance or 0.012)
		W.RollDrag = W.Grounded and Crr * Share * Gravity * W.Radius or 0
		--[[
			Full pedal is 2.5 times the torque that locks the wheel under an equal share of the
			weight (1.0 behind the centre of mass, see the brake bias above). Braking moves load
			forward (the front axle of a high vehicle carries up to about 70 % of the weight in a
			hard stop, Gillespie, Fundamentals of Vehicle Dynamics, ch. 3), so locking a front wheel
			takes about 1.4 times its equal share; brake systems are sized to lock the wheels part
			way down the pedal with reserve left for fade, so full pedal always locks.
		]]
		local BrakeFactor = 2.5
		if TravelDir and not W.Meshed and IsValid(W.Phys) and (W.Phys:GetPos() - MassCenter):Dot(TravelDir) < 0 then
			BrakeFactor = 1.0
		end
		W.BrakeMax = BrakeFactor * max(W.Mu, DefaultTyreMu) * max(Share, BrakeShare) * Gravity * W.Radius + 10 * W.J
	end

	for _, Box in ipairs(Ctx.BoxList) do
		local Desc = Box.Mob
		local BrakeL, BrakeR = M.BrakePedal(Box.LBrake), M.BrakePedal(Box.RBrake)
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

	staticHold(Ctx, EngineDescs, Roots, Dt)
	for _, W in ipairs(Ctx.WheelList) do
		brakeLock(W, W.WantLock and not W.HoldSlips or false)
	end

	local Sys = Drivetrain.Build({ Engines = EngineDescs, Roots = Roots })
	Drivetrain.Step(Sys, Dt, SubstepsConVar:GetInt())

	-- A brake that ran at its full torque this tick was overpowered (engine through a locked
	-- clutch, a steep slope with a light pedal): it slips, so the static lock must let go.
	for _, Gearbox in ipairs(Sys.Gearboxes) do
		for _, C in ipairs(Gearbox.Brakes or {}) do
			local W = C.Wheel
			if W and W.Anchored then
				-- A held wheel lets go when the static check says the hold cannot carry the load.
				W.BrakeSlipped = W.HoldSlips or false
			elseif W then
				W.BrakeSlipped = C.Max and C.Max > 0 and C.Max < math.huge and abs(C.Acc) >= 0.98 * C.Max or false
			end
		end
	end

	-- Hand the impulses to VPhysics: the wheel gets the drivetrain's angular impulse, the chassis
	-- the reaction through the gearbox mounts.
	for _, W in ipairs(Ctx.WheelList) do
		--[[
			Only the part of the drivetrain's impulse that went on into the road is scaled, so the
			correction can shrink the impulse but never add one: a ground reaction larger than
			what the drivetrain delivered (the solver pulling a wheel back up to ground speed)
			would otherwise come out as a push that grows with speed.
		]]
		local Imp = W.Anchored and 0 or W.Impulse or 0
		local Road = W.GroundImpulse or 0
		Road = Road * Imp > 0 and (Road > 0 and min(Road, Imp) or max(Road, Imp)) or 0
		Imp = Imp - Road * (1 - RoadScale)
		if W.Braking and W.Ground and not W.Meshed and W.TyreImp and W.Radius > 0 then
			--[[
				A brake can only stop the wheel. The solver brakes wheel and road together, but the
				road's share has to pass through the tyre inside the physics step, and the tyre
				passes what the physics engine's contact gives, not what the solver assumed. Any
				impulse past bringing the wheel to rest against that spins it backwards, so a
				braked wheel gets at most the impulse that stops it, given the tyre impulse the
				physics engine actually delivered last tick.
			]]
			local Toward = (W.GroundSpeed or 0) / W.Radius - W.W
			local Pass = abs(W.TyreImp)
			local TyreOnWheel = Toward > 0 and Pass or Toward < 0 and -Pass or 0
			local Target = -(W.J or 0) * W.W - TyreOnWheel
			if Imp * Target <= 0 then
				Imp = 0
			elseif abs(Imp) > abs(Target) then
				Imp = Target
			end
		end
		--[[
			The physics engine caps every object's spin (MaxAngularVelocity, default 7272 deg/s)
			and throws away anything past it. A wheel pushed further past the cap would keep its
			speed while the chassis still took the reaction torque, which spins and rolls the
			vehicle. So the wheel gets at most what brings it to the cap.
		]]
		local MaxW = MaxWheelSpin()
		if Imp * (W.W or 0) > 0 then
			local Room = max(MaxW - abs(W.W), 0) * (W.J or 0)
			if abs(Imp) > Room then Imp = Imp > 0 and Room or -Room end
		end
		--[[
			Nor may one step change its spin by more than the cap the other way. A driven prop can
			be far lighter than what it moves (a thin solid-axle cylinder with the wheels
			ballsocketed to it): the vehicle's share of road impulse went into its own inertia,
			spun it to 187,000 deg/s, and the physics engine deleted it with its constraints.
		]]
		local Lim = MaxW * (W.J or 0)
		if abs(Imp) > Lim then Imp = Imp > 0 and Lim or -Lim end
		W.AppliedDW = 0
		W.ImpOut = 0
		if Imp ~= 0 and Imp == Imp and ApplyConVar:GetBool() and IsValid(W.Phys) then
			W.AppliedDW = Imp / max(W.J or 1, 1e-3)
			W.ImpOut = Imp
			local Src = Units.ToSourceAngularImpulse(Imp)
			if W.GroupJ and W.Group and #W.Group > 0 then
				-- Each member of a spin group takes its share by inertia, so the constraints that
				-- tie them carry no extra load from the drive.
				W.Phys:ApplyTorqueCenter(W.AxisWorld * (-Src * W.OwnJ / W.GroupJ))
				for _, G in ipairs(W.Group) do
					if IsValid(G.Phys) and G.J then G.Phys:ApplyTorqueCenter(W.AxisWorld * (-Src * G.J / W.GroupJ)) end
				end
			else
				W.Phys:ApplyTorqueCenter(W.AxisWorld * -Src)
			end
			--[[
				The reaction goes through the gearbox mounts, except when the gearbox rides on the
				very body its wheels turn on and that body is not the engine's chassis: a solid axle
				prop ballsocketed to the chassis cannot pass torque about its own length, so the
				reaction only spun the axle, until the physics engine deleted it (buggy: its rear
				differential is parented to the axle). A real axle housing hands it to the chassis
				through its suspension links. The same goes for any mounting too light about the
				axle to hold the wheel's spin.
			]]
			local Root = ACE.GetPhysicalParent(W.Box)
			if IsValid(Ctx.Chassis) and IsValid(Root) and Root ~= Ctx.Chassis and (Root == W.Hub or W.Hub == Ctx.Chassis) then
				Root = Ctx.Chassis
			end
			local RootPhys = IsValid(Root) and Root:GetPhysicsObject()
			if IsValid(RootPhys) then RootPhys:ApplyTorqueCenter(W.AxisWorld * Src) end
		end
	end
end

--[[
	The entity side of a solve: brake locks, wire outputs, sounds, fuel, heat and damage. These
	can set off other addons' code (wire outputs run E2 chips), which must not run inside the
	physics engine's step, so with the in-step drivetrain they run from Think with everything
	the physics steps since the last Think added up.
]]
local function finishGroup(Group, Ctx, Dt)
	applyBrakeLocks(Ctx.WheelList)
	for _, Box in ipairs(Ctx.BoxList) do
		if IsValid(Box) then
			Box.MobDt = Dt
			Box:MobilityApply()
		end
	end
	for _, E in ipairs(Group) do
		if IsValid(E) then
			E.MobDt = Dt
			E:MobilityApply()
		end
	end
	debugReport(Group, Ctx, Dt)
end


--[[
	A physics gun makes what it holds far heavier while it holds it, for a steady grip (the
	buggy's 250 kg chassis weighed about 45,700 kg). Weighed then, the vehicle came to 46 t, its
	tyres were sized for 46 t, and the drivetrain spun its wheels at 40 rad/s while the gun held
	it just off the ground. A held body counts with the mass it had before it was picked up.
]]
local function bodyMass(Ent, Phys)
	if Ent:IsPlayerHolding() then return Ent.MobOwnMass or Phys:GetMass() end
	Ent.MobOwnMass = Phys:GetMass()
	return Ent.MobOwnMass
end

local function isFrozen(Ent)
	local P = Ent:GetPhysicsObject()
	return IsValid(P) and not P:IsMotionEnabled()
end

--[[
	Bodies that move with the vehicle: everything constrained to the starting entities, without
	going through frozen props. A frozen prop is part of the world, not the vehicle, and chip
	steering often hangs the wheels on one (a frozen Starfall prop the chip turns), and anything
	else constrained to that prop is another vehicle.
]]
local function movingBodies(Starts)
	local Seen, Stack = {}, {}
	for _, Ent in ipairs(Starts) do
		if IsValid(Ent) and not Seen[Ent] then
			Seen[Ent] = true
			Stack[#Stack + 1] = Ent
		end
	end
	while #Stack > 0 do
		local Ent = table.remove(Stack)
		for _, Con in ipairs(constraint.GetTable(Ent)) do
			if Con.Type ~= "NoCollide" then
				for _, E in pairs(Con.Entity) do
					local Other = E.Entity
					if IsValid(Other) and not Seen[Other] and not isFrozen(Other) then
						Seen[Other] = true
						Stack[#Stack + 1] = Other
					end
				end
			end
		end
	end
	return Seen
end

-- Mass of the bodies moving with Starts[1] (see movingBodies), and of those plus their parented
-- props. Cached on Starts[1] for a few seconds.
local function contraptionMass(Starts)
	local Ent = Starts[1]
	if Ent.MobMassAt and CurTime() < Ent.MobMassAt then return Ent.MobPhysMass, Ent.MobTotalMass end
	local Bodies = movingBodies(Starts)
	local All = {}
	for V in pairs(Bodies) do
		All[V] = true
		for _, C in pairs(ACE.GetAllChildren(V)) do All[C] = true end
	end
	local Phys, Total = 0, 0
	for V in pairs(All) do
		local P = IsValid(V) and V:GetPhysicsObject()
		if IsValid(P) then
			local Mass = bodyMass(V, P)
			Total = Total + Mass
			if not IsValid(V:GetParent()) then Phys = Phys + Mass end
		end
	end
	if Phys > 0 then Ent.MobPhysMass, Ent.MobTotalMass, Ent.MobMassAt = Phys, Total, CurTime() + 5 end
	return Phys, Total
end

-- Builds and solves one group's physics and pushes the wheels. Returns the solve context, or
-- nil when no engine of the group is ready.
local function solvePhysics(Engine, Group, Dt)
	local Ctx = {
		Dt = Dt,
		Boxes = {}, BoxList = {},
		Wheels = {}, WheelList = {},
		Filter = contraptionFilter(Engine),
		Chassis = ACE.GetPhysicalParent(Engine),
	}

	local EngineDescs = {}
	local PhysMass, TotalMass = 0, 0
	for _, E in ipairs(Group) do
		local Desc = E:MobilityDesc(Ctx)
		-- The engine measures its vehicle when switched on and at its legality checks; one never
		-- switched on had no mass yet, which sized its brakes for an empty vehicle (31 N·m
		-- instead of 9,300 on the Volvo) until the first check.
		if Desc then EngineDescs[#EngineDescs + 1] = Desc end
	end
	-- The vehicle is what the engine sits on plus everything moving with its wheels (an engine
	-- on its own contraption still drives, and is weighed with, the wheels' vehicle).
	if #EngineDescs > 0 and IsValid(Ctx.Chassis) then
		local Starts = { Ctx.Chassis }
		for _, W in ipairs(Ctx.WheelList) do Starts[#Starts + 1] = W.Ent end
		PhysMass, TotalMass = contraptionMass(Starts)
	end
	--[[
		Parented props have no mass in Source's physics, so the physical chassis is lighter than
		the vehicle. The drivetrain works with the whole vehicle (what the engine drags, what the
		tyres carry), and the part of each impulse that moves the vehicle is scaled by
		physical / total mass before it reaches VPhysics, so the light physical body accelerates
		as the full-weight vehicle would. This keeps the old drivetrain's balance rule (torque
		scaled by MassRatio) without starving the engine, starter or clutch of torque.
	]]
	if #EngineDescs == 0 then return nil end
	solveGroup(Ctx, EngineDescs, nil, PhysMass, TotalMass, Dt)
	if M.Log then M.Log.Frame(M.InStep and "step" or "tick", Group, Ctx, Dt) end
	return Ctx
end

--[[
	In-step drivetrain. The physics engine does not step once per server tick: it steps every
	15 ms whatever the tickrate (measured: one step per tick at 66, two at 33, four at 16, and
	at 128 about every other tick has none). A drivetrain that acts once per tick is therefore
	out of step with the tyres everywhere except 66 tick: at 33 it pushes once for two steps of
	road, at 128 it pushes on ticks where the road has not acted at all and reads that as a
	tyre that grips nothing. So the group's lead engine registers the wheels with its motion
	controller, which the physics engine calls inside every step, and the drivetrain is solved
	there, at the step's own 15 ms. Fuel, heat, clutch heat and torque are added up over the
	steps and handed to the entity side of the tick from Think.
]]

-- The engine of a group that owns the motion controller: the lowest entity index.
local function groupLeader(Group)
	local Lead
	for _, E in ipairs(Group) do
		if IsValid(E) and (not Lead or E:EntIndex() < Lead:EntIndex()) then Lead = E end
	end
	return Lead
end

-- Adds this solve's step to what the entity side of the tick will read.
local function accumulate(Group, Ctx, Dt)
	for _, E in ipairs(Group) do
		local Desc = E.MobDesc
		if Desc then
			local Acc = E.MobAcc or { Dt = 0, FuelKg = 0, HeatJ = 0, TorqueDt = 0 }
			E.MobAcc = Acc
			Acc.Dt = Acc.Dt + Dt
			Acc.FuelKg = Acc.FuelKg + (Desc.FuelKg or 0)
			Acc.HeatJ = Acc.HeatJ + (Desc.HeatJ or 0)
			Acc.TorqueDt = Acc.TorqueDt + (Desc.AvgTorque or 0) * Dt
		end
	end
	for _, Box in ipairs(Ctx.BoxList) do
		local Mob = Box.Mob
		if Mob then Box.MobAccHeatJ = (Box.MobAccHeatJ or 0) + (Mob.ClutchHeatJ or 0) end
	end
end

-- Moves the added-up steps into the descriptions MobilityApply reads. Returns their time.
local function takeAccumulated(Group, Ctx)
	local Dt = 0
	for _, E in ipairs(Group) do
		local Acc, Desc = E.MobAcc, E.MobDesc
		if Acc and Desc and Acc.Dt > 0 then
			Desc.FuelKg, Desc.HeatJ = Acc.FuelKg, Acc.HeatJ
			Desc.AvgTorque = Acc.TorqueDt / Acc.Dt
			Dt = max(Dt, Acc.Dt)
		end
		E.MobAcc = nil
	end
	for _, Box in ipairs(Ctx.BoxList) do
		if Box.Mob then Box.Mob.ClutchHeatJ = Box.MobAccHeatJ or 0 end
		Box.MobAccHeatJ = nil
	end
	return Dt
end

-- Keeps the lead engine's motion controller holding exactly the group's wheels.
local function syncController(Lead, Ctx)
	-- Keyed by wheel entity: physics object userdata are not unique per object.
	local Want = {}
	for _, W in ipairs(Ctx.WheelList) do
		if IsValid(W.Phys) then Want[W.Ent] = W.Phys end
	end
	local Have = Lead.MobCtrlPhys or {}
	if not Lead.MobCtrlStarted then
		Lead:StartMotionController()
		Lead.MobCtrlStarted = true
	end
	for Ent, Phys in pairs(Have) do
		if not Want[Ent] or not IsValid(Phys) then
			if IsValid(Phys) then Lead:RemoveFromMotionController(Phys) end
			Have[Ent] = nil
		end
	end
	for Ent, Phys in pairs(Want) do
		if not Have[Ent] then
			Lead:AddToMotionController(Phys)
			Have[Ent] = Phys
		end
	end
	Lead.MobCtrlPhys = Have
end

local function stopController(Engine)
	if not Engine.MobCtrlStarted then return end
	for _, Phys in pairs(Engine.MobCtrlPhys or {}) do
		if IsValid(Phys) then Engine:RemoveFromMotionController(Phys) end
	end
	Engine.MobCtrlPhys = nil
	Engine:StopMotionController()
	Engine.MobCtrlStarted = nil
end

--- Called from the lead engine's PhysicsSimulate for every physics object on its controller.
-- The first call of each physics step solves the group at the step's length.
-- @param Engine acf_engine entity that owns the controller.
-- @param Phys The physics object being simulated.
-- @param Dt Physics step length.
function M.PhysicsStep(Engine, Phys, Dt)
	if not InStepConVar:GetBool() or Engine.MobLeader ~= Engine or not next(Engine.GearLink or {}) then return end
	-- Every object is called once per step: seeing one again means a new step began. Physics
	-- objects come as a new userdata on every call, so they are told apart by their entity.
	local Key = Phys:GetEntity()
	local Seen = Engine.MobStepSeen
	if Seen and not Seen[Key] then
		Seen[Key] = true
		return
	end
	Engine.MobStepSeen = { [Key] = true }

	local Group = Engine.MobGroup
	if not Group then return end
	M.InStep = true
	local Ok, Ctx = pcall(solvePhysics, Engine, Group, Dt)
	M.InStep = false
	if not Ok then
		ErrorNoHalt("[ACE mobility] " .. tostring(Ctx) .. "\n")
		return
	end
	if Ctx then
		accumulate(Group, Ctx, Dt)
		Engine.MobStepCtx = Ctx
		Engine.MobStepTick = engine.TickCount()
	end
end

--- Whether the drivetrain is running inside a physics step, where side effects that can reach
-- other addons' code (wire outputs, gear changes) must wait for Think.
function M.Deferring()
	return M.InStep == true
end

--- Runs the drivetrain group that Engine belongs to for this tick.
-- Safe to call from every engine's Think; the group is only handled once per tick.
-- @param Engine acf_engine entity.
-- @param Dt Tick length.
function M.Tick(Engine, Dt)
	local Now = CurTime()
	if Engine.MobSolvedAt == Now then return end

	local Group = collectGroup(Engine)
	for _, E in ipairs(Group) do E.MobSolvedAt = Now end

	local Lead = groupLeader(Group)
	if not Lead then return end
	for _, E in ipairs(Group) do
		E.MobLeader = Lead
		if E ~= Lead then stopController(E) end
	end
	Lead.MobGroup = Group

	if InStepConVar:GetBool() then
		--[[
			The steps ran inside the physics engine since the last Think; only the entity side
			is left. Sleeping wheels are not stepped, so a vehicle at rest (an engine idling in
			neutral) is solved here instead until its wheels wake.
		]]
		-- Counted in ticks: at 16 tick the physics steps can fall in the tick before this Think.
		local Ctx = Lead.MobStepCtx
		local Stepping = Ctx and engine.TickCount() - (Lead.MobStepTick or -10) <= 2 or false
		if M.Log and Lead.MobLogStepping ~= Stepping then
			M.Log.Event(Lead, Stepping and "instep" or "per_tick", Stepping and "solving inside the physics steps" or "no physics step ran (wheels asleep?), solving once per tick")
		end
		Lead.MobLogStepping = Stepping
		if Stepping then
			local StepDt = takeAccumulated(Group, Ctx)
			if StepDt > 0 then finishGroup(Group, Ctx, StepDt) end
			syncController(Lead, Ctx)
			return
		end
		for _, E in ipairs(Group) do E.MobAcc = nil end
	elseif Lead.MobCtrlStarted then
		stopController(Lead)
	end

	local Ctx = solvePhysics(Lead, Group, Dt)
	if not Ctx then return end
	finishGroup(Group, Ctx, Dt)
	if InStepConVar:GetBool() then
		Lead.MobStepCtx = nil
		syncController(Lead, Ctx)
	end
end

--- Releases an engine's motion controller (on removal).
-- @param Engine acf_engine entity.
function M.StopController(Engine)
	stopController(Engine)
end

------------------------------------------------------------------------ gearboxes without an engine

--[[
	A gearbox tree that no engine drives (a trailer axle, or an undriven axle that only needs
	its brakes) is solved on its own, so its brakes work without linking it to a powered
	gearbox. It only needs solving while a brake is applied or a brake hold is still set.
]]
local StandaloneRoots, NextRootScan = {}, 0

local function treeNeedsSolve(Box, Depth)
	if Depth > 8 then return false end
	if (Box.LBrake or 0) > 0 or (Box.RBrake or 0) > 0 then return true end
	for _, Link in pairs(Box.WheelLink or {}) do
		local Ent = Link.Ent
		if IsValid(Ent) then
			if Ent.IsGeartrain then
				if treeNeedsSolve(Ent, Depth + 1) then return true end
			elseif Link.Mob and IsValid(Link.Mob.BrakeLock) then
				return true
			end
		end
	end
	return false
end


--- Solves a gearbox tree that has no engine: brakes, brake holds and differentials only.
-- @param Box The root acf_gearbox (one with no linked engine or gearbox above it).
-- @param Dt Tick length.
function M.TickStandalone(Box, Dt)
	local Ctx = {
		Dt = Dt,
		Boxes = {}, BoxList = {},
		Wheels = {}, WheelList = {},
		Filter = contraptionFilter(Box),
		Chassis = ACE.GetPhysicalParent(Box),
	}
	local Desc = buildGearbox(Box, Ctx)
	local PhysMass, TotalMass = contraptionMass({ ACE.GetPhysicalParent(Box) or Box })
	solveGroup(Ctx, {}, { Desc }, PhysMass, TotalMass, Dt)
	if M.Log then M.Log.Frame("standalone", nil, Ctx, Dt) end
	applyBrakeLocks(Ctx.WheelList)
	for _, B in ipairs(Ctx.BoxList) do
		B.MobDt = Dt
		B:MobilityApply()
	end
end

hook.Add("Think", "ACE_Mobility_StandaloneGearboxes", function()
	local Now = CurTime()
	if Now >= NextRootScan then
		NextRootScan = Now + 1
		StandaloneRoots = {}
		-- Engines register themselves in a gearbox's Master list; gearboxes linked below another
		-- gearbox only appear in that gearbox's WheelLink.
		local Boxes = ents.FindByClass("acf_gearbox")
		local Child = {}
		for _, Box in ipairs(Boxes) do
			for _, Link in pairs(Box.WheelLink or {}) do
				if IsValid(Link.Ent) and Link.Ent.IsGeartrain then Child[Link.Ent] = true end
			end
		end
		for _, Box in ipairs(Boxes) do
			local HasEngine = false
			for _, Master in pairs(Box.Master or {}) do
				if IsValid(Master) then HasEngine = true break end
			end
			if not HasEngine and not Child[Box] and next(Box.WheelLink or {}) then
				StandaloneRoots[#StandaloneRoots + 1] = Box
			end
		end
	end
	local Dt = engine.TickInterval()
	for _, Box in ipairs(StandaloneRoots) do
		if IsValid(Box) and Box.Legal ~= false and treeNeedsSolve(Box, 0) then M.TickStandalone(Box, Dt) end
	end
end)

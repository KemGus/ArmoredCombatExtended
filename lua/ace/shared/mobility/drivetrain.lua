--[[
	Builds a solver system from a drivetrain description and steps it through one tick.
	GMod-free: the entity adapters and the offline rig both describe the drivetrain with
	plain tables.

	Description:
	  Engine  = { Spec, State, Throttle, NoStall, HasFuel, TorqueMul, AccessoryTorque,
	              Gearboxes = { Gearbox... } }
	  Gearbox = {
	    Key,                -- unique per gearbox
	    Ratio,              -- signed reduction (input/output speed); 0 = neutral
	    InputJ,             -- input shaft + clutch disc inertia, kg·m²
	    ClutchCap,          -- main clutch capacity N·m (nil = rigid, used by dual-clutch boxes)
	    ClutchFree,         -- the main clutch is not fully engaged (it can slip)
	    Converter,          -- torque converter (from TorqueConverter.New) or nil
	    LockupCap,          -- converter lock-up clutch capacity when engaged, N·m
	    Dual,               -- per-side clutches instead of a main clutch
	    SideCap = {[0]=, [1]=},  -- dual clutch capacities (input-side N·m)
	    Diff,               -- "open" | "lsd" | "locked"
	    LSDPreload, LSDRamp,-- Salisbury limited-slip: bias = preload + ramp·|input torque|
	    Steer, SteerRatio,  -- double differential steering input (-1..1) and ratio
	    Steering,           -- a dual box whose sides are commanded differently (clutch-brake steering)
	    DriveCap,           -- torque the engaged gear's clutch pack can carry while shifting (nil = rigid)
	    Efficiency,         -- mesh efficiency of the engaged path (0..1)
	    SpinLoss,           -- churning/bearing drag at the input at running speed, N·m
	    Brake = {[0]=, [1]=},    -- brake torque per side at the wheels, N·m
	    BrakeOnly,          -- can never transmit (every ratio is zero): brakes only, no drive
	    Outputs = { {Side = 0|1, Wheel = Wheel} | {Side = 0|1, Gearbox = Gearbox} ... },
	  }
	  Wheel   = { Key, J, W, RollDrag, Ground, Anchored, ParkProbe, Held }
	    J is the wheel's own inertia; Ground = { J, W, Cap, Torque } from Vehicle.Ground couples it
	    to its share of the vehicle through tyre friction (nil when airborne), Torque being an
	    outside torque on that share (the slope pulling it). Anchored = locked to its hub (fixed at
	    rest), unless ParkProbe asks to solve whether that lock really holds; Held = turned by
	    something outside the drivetrain (a player's physics gun), so it keeps its measured speed.

	After Step, every Wheel has .Impulse (total angular impulse to apply to the wheel, N·m·s),
	.GroundImpulse (the part passed to the road, N·m·s) and .WOut,
	every Gearbox has .InputW/.OutputTorque/.ClutchSlip, and Engine.State is advanced.
]]

ACE = ACE or {}
ACE.Mobility = ACE.Mobility or {}

local Drivetrain = {}
ACE.Mobility.Drivetrain = Drivetrain

local Solver = ACE.Mobility.Solver
local EngineModel = ACE.Mobility.Engine
local TC = ACE.Mobility.TorqueConverter

local abs = math.abs
local min = math.min
local max = math.max

--[[
	Drag that only exists while something turns fades in from standstill instead of acting at
	full strength on the slightest motion. Gearbox no-load losses (oil churning, bearings) grow
	with shaft speed (estimated), and rolling resistance gets a smooth onset near zero speed, so
	it stays well behaved at standstill (estimated). Applied as full Coulomb
	friction to a standing vehicle, the solver's drag on a shaft geared to the wheels went
	through the wheels into the road, the tyre handed it back reversed, and the wheels turned
	back and forth on their own (buggy, clutch pressed: 85 N·m of churning on each axle box
	kept all four wheels creeping at 0.4 rad/s).
]]
local SpinLossFullW = 100 -- rad/s (about 950 rpm): churning reaches its rated value
local RollFullSpeed = 0.5 -- m/s: rolling resistance is fully built up

local function fadeIn(W, Full)
	return min(abs(W) / Full, 1)
end

local function addConstraint(Sys, Bodies, Coefs, Cap, Target, Tag)
	local C = Solver.Constraint(Bodies, Coefs, Cap, Target)
	C.Tag = Tag
	Sys.Constraints[#Sys.Constraints + 1] = C
	return C
end

local function wheelBody(Sys, Wheel)
	local B = Sys.WheelBodies[Wheel.Key]
	if B then return B end
	-- An anchored wheel (held to its hub by a parking lock) is fixed: infinite inertia, no spin.
	if Wheel.Anchored and not Wheel.ParkProbe then
		B = Solver.Body(math.huge, 0)
	elseif Wheel.Held then
		--[[
			A wheel a player turns with the physics gun goes at the speed the player gives it
			whatever the drivetrain does, so the rest of the drivetrain has to follow it: as a
			light free wheel the solver slowed it instead (the gun undid that at once) and the
			engine and the other wheels barely moved (Volvo, locked differentials, engine off in
			gear: the other wheels turned at 162 deg/s against the held wheel's 360).
		]]
		B = Solver.Body(math.huge, Wheel.W)
	else
		B = Solver.Body(Wheel.J, Wheel.ParkProbe and 0 or Wheel.W)
	end
	B.Wheel = Wheel
	B.W0 = B.W
	Wheel.AnchorTorque = nil
	Wheel.Impulse = 0
	Wheel.GroundImpulse = 0
	Sys.WheelBodies[Wheel.Key] = B
	Sys.Bodies[#Sys.Bodies + 1] = B
	Sys.Wheels[#Sys.Wheels + 1] = B

	local Ground = Wheel.Ground
	if Ground then
		local GB = Solver.Body(Ground.J, Ground.W)
		GB.W0 = Ground.W
		B.GroundBody = GB
		Sys.Bodies[#Sys.Bodies + 1] = GB
		B.TyreC = addConstraint(Sys, { B, GB }, { 1, -1 }, Ground.Cap, 0, "tyre")
	end
	return B
end

-- Returns the body that an output drives.
local function outputBody(Sys, Out)
	if Out.Wheel then return wheelBody(Sys, Out.Wheel) end
	return Sys.GearboxBodies[Out.Gearbox.Key]
end

local buildGearbox
local shareRoad

--[[
	Input shaft speed that a gearbox's wheels dictate this tick, or nil when its outputs can
	slip (a dual box's side clutches, a capped drive during a shift) or it is in neutral. The
	wheels are re-read from the physics engine every tick, so a shaft geared rigidly to them
	must start from their speed too: carrying last tick's speed over would kick the wheels back
	towards it whenever the physics engine moved them (a standing vehicle rocking on its
	suspension through a high ratio kept rocking).
]]
local function kinematicInputW(Gearbox)
	local R = Gearbox.Ratio or 0
	if R == 0 or Gearbox.Dual or Gearbox.DriveCap then return nil end
	local Sum, N = { [0] = 0, [1] = 0 }, { [0] = 0, [1] = 0 }
	for _, Out in ipairs(Gearbox.Outputs or {}) do
		if not (Out.Gearbox and Out.Gearbox.BrakeOnly) then
			local W
			-- A chained box is geared rigidly only through a fully engaged clutch. Behind an open one
			-- (a rotor clutch the pilot's controller has released), starting from the stopped
			-- rotor's speed dragged the engines to it every tick (turbines held at 323 rpm on full
			-- throttle).
			if Out.Gearbox and Out.Gearbox.ClutchFree then return nil end
			if Out.Wheel then W = Out.Wheel.Anchored and 0 or Out.Wheel.W elseif Out.Gearbox then W = kinematicInputW(Out.Gearbox) end
			if W == nil then return nil end
			local S = Out.Side == 0 and 0 or 1
			Sum[S], N[S] = Sum[S] + W, N[S] + 1
		end
	end
	local Total, Sides = 0, 0
	for S = 0, 1 do
		if N[S] > 0 then Total, Sides = Total + Sum[S] / N[S], Sides + 1 end
	end
	if Sides == 0 then return nil end
	return R * Total / Sides
end

--[[
	Inertia the gearbox's input shaft carries through its engaged gears: the wheels and the
	share of the vehicle each one moves, reflected through the ratio (J / R²). Open
	differentials and slipping tyres make this an upper bound.
]]
local function reflectedJ(Gearbox, Depth)
	local R = Gearbox.Ratio or 0
	if R == 0 or Depth > 8 then return 0 end
	local Out = 0
	for _, O in ipairs(Gearbox.Outputs or {}) do
		if O.Wheel then
			Out = Out + (O.Wheel.J or 0) + (O.Wheel.Ground and O.Wheel.Ground.J or 0)
		elseif O.Gearbox and not O.Gearbox.BrakeOnly then
			Out = Out + (O.Gearbox.InputJ or 0.02) + reflectedJ(O.Gearbox, Depth + 1)
		end
	end
	return Out / (R * R)
end

-- Couples a crank to a gearbox's input body through the gearbox's clutch or converter.
-- A gearbox driven by several engines gets one coupling per engine.
local function couple(Sys, Crank, Gearbox)
	local In = Sys.GearboxBodies[Gearbox.Key]
	local Fresh = not In
	if Fresh then
		In = Solver.Body(max(Gearbox.InputJ or 0.02, 1e-4), kinematicInputW(Gearbox) or Gearbox.InputW or Crank.W)
		In.Gearbox = Gearbox
		Sys.Bodies[#Sys.Bodies + 1] = In
		Sys.GearboxBodies[Gearbox.Key] = In
		Gearbox.Body = In
		Gearbox.Inputs = {}
	end

	local C
	if Gearbox.Converter then
		-- The converter is a torque source between crank and turbine; only its lock-up clutch is
		-- a constraint.
		C = addConstraint(Sys, { Crank, In }, { 1, -1 }, Gearbox.LockupCap or 0, 0, "lockup")
		Sys.Converters[#Sys.Converters + 1] = { Gearbox = Gearbox, Crank = Crank }
		Gearbox.TurbineJ = In.J + reflectedJ(Gearbox, 0)
	else
		C = addConstraint(Sys, { Crank, In }, { 1, -1 }, (not Gearbox.Dual) and Gearbox.ClutchCap or nil, 0, "clutch")
	end
	Gearbox.Inputs[#Gearbox.Inputs + 1] = C
	Gearbox.Input = Gearbox.Inputs[1]

	if Fresh then buildGearbox(Sys, Gearbox) end
end

buildGearbox = function(Sys, Gearbox)
	local In = Gearbox.Body
	local R = Gearbox.Ratio or 0

	-- Chained gearboxes need their input body before we can constrain to them.
	for _, Out in ipairs(Gearbox.Outputs or {}) do
		if Out.Gearbox and not Sys.GearboxBodies[Out.Gearbox.Key] then
			local Child = Out.Gearbox
			local Body = Solver.Body(max(Child.InputJ or 0.02, 1e-4), kinematicInputW(Child) or Child.InputW or (R ~= 0 and In.W / R or 0))
			Body.Gearbox = Child
			Sys.Bodies[#Sys.Bodies + 1] = Body
			Sys.GearboxBodies[Child.Key] = Body
			Child.Body = Body
			Child.Inputs = Child.Inputs or {}
			buildGearbox(Sys, Child)
		end
	end

	--[[
		Group outputs by side. A chained box that can never transmit (all ratios zero) is how
		builders give an undriven axle its brakes; it is not a drive output. Left in, its free
		input shaft would sit on one side of an open differential and take all the speed while
		the driven side got no torque.
	]]
	local Sides = { [0] = {}, [1] = {} }
	for _, Out in ipairs(Gearbox.Outputs or {}) do
		if not (Out.Gearbox and Out.Gearbox.BrakeOnly) then
			local List = Sides[Out.Side == 0 and 0 or 1]
			List[#List + 1] = Out
		end
	end

	Gearbox.Drive = {}
	-- Friction elements that slip instead of the main clutch (a dual box's side clutches), with
	-- the factor that turns their slip into input-shaft speed.
	Gearbox.SideClutches = {}
	local HasL, HasR = #Sides[0] > 0, #Sides[1] > 0

	if R ~= 0 then
		if not (HasL and HasR) or Gearbox.Diff == "locked" then
			-- Each output rigidly geared (through its side clutch on dual boxes). A locked dual box is
			-- a clutch-brake steering cross-shaft.
			for S = 0, 1 do
				local Cap = Gearbox.Dual and Gearbox.SideCap and Gearbox.SideCap[S] or nil
				for _, Out in ipairs(Sides[S]) do
					local OutCap = Cap
					if Out.Gearbox and Out.Gearbox.ClutchCap then
						OutCap = OutCap and min(OutCap, Out.Gearbox.ClutchCap) or Out.Gearbox.ClutchCap
					end
					if Gearbox.DriveCap then OutCap = OutCap and min(OutCap, Gearbox.DriveCap) or Gearbox.DriveCap end
					local C = addConstraint(Sys, { In, outputBody(Sys, Out) }, { 1, -R }, OutCap, 0, "gear")
					Gearbox.Drive[#Gearbox.Drive + 1] = C
					if Gearbox.Dual then Gearbox.SideClutches[#Gearbox.SideClutches + 1] = { C = C, Scale = 1 } end
				end
			end
		elseif Gearbox.Dual then
			-- Open differential with a clutch on each output (a controlled differential): the side
			-- gears are small bodies of their own, each clutched to that side's outputs.
			local SideJ = max((Gearbox.InputJ or 0.02) * 0.5, 1e-4)
			local SideBodies = {}
			for S = 0, 1 do
				local First = outputBody(Sys, Sides[S][1])
				local SB = Solver.Body(SideJ, First.W)
				Sys.Bodies[#Sys.Bodies + 1] = SB
				SideBodies[S] = SB
				-- Side clutch ratings are input-shaft torque (as on locked dual boxes); the clutch sits
				-- on the output side of the ratio, where the same clutch carries |R| times as much.
				local Cap = Gearbox.SideCap and Gearbox.SideCap[S]
				if Cap then Cap = Cap * abs(R) end
				for _, Out in ipairs(Sides[S]) do
					local OutCap = Cap
					if Out.Gearbox and Out.Gearbox.ClutchCap then
						OutCap = OutCap and min(OutCap, Out.Gearbox.ClutchCap) or Out.Gearbox.ClutchCap
					end
					local C = addConstraint(Sys, { SB, outputBody(Sys, Out) }, { 1, -1 }, OutCap, 0, "side clutch")
					Gearbox.SideClutches[#Gearbox.SideClutches + 1] = { C = C, Scale = abs(R) }
				end
			end
			Gearbox.Drive[1] = addConstraint(Sys, { In, SideBodies[0], SideBodies[1] }, { 1, -R / 2, -R / 2 }, Gearbox.DriveCap, 0, "diff")
			if Gearbox.Diff == "lsd" then
				Gearbox.LSD = addConstraint(Sys, { SideBodies[0], SideBodies[1] }, { 1, -1 }, 0, 0, "lsd")
			end
		else
			-- Differential between the first output on each side; extra outputs on a side
			-- are rigidly tied to that side's first output.
			local L, Rt = outputBody(Sys, Sides[0][1]), outputBody(Sys, Sides[1][1])
			Gearbox.Drive[1] = addConstraint(Sys, { In, L, Rt }, { 1, -R / 2, -R / 2 }, Gearbox.DriveCap, 0, "diff")
			for S = 0, 1 do
				local First = outputBody(Sys, Sides[S][1])
				for I = 2, #Sides[S] do
					addConstraint(Sys, { First, outputBody(Sys, Sides[S][I]) }, { 1, -1 }, nil, 0, "side")
				end
			end
			if Gearbox.Diff == "lsd" then
				Gearbox.LSD = addConstraint(Sys, { L, Rt }, { 1, -1 }, 0, 0, "lsd")
			end
		end
	end

	-- Double differential steering path, driven from the input shaft regardless of gear, so a
	-- tank can pivot in neutral (Merritt-Brown principle).
	if Gearbox.SteerRatio and HasL and HasR then
		local L, Rt = outputBody(Sys, Sides[0][1]), outputBody(Sys, Sides[1][1])
		Gearbox.SteerC = addConstraint(Sys, { L, Rt, In }, { 0.5, -0.5, 0 }, Gearbox.SteerCap, 0, "steer")
	end

	-- Brakes act between each driven wheel and the chassis.
	Gearbox.Brakes = {}
	for S = 0, 1 do
		local Tq = Gearbox.Brake and Gearbox.Brake[S] or 0
		for _, Out in ipairs(Sides[S]) do
			if Out.Wheel then
				local C = addConstraint(Sys, { outputBody(Sys, Out) }, { 1 }, Tq, 0, "brake")
				C.Wheel = Out.Wheel
				Gearbox.Brakes[#Gearbox.Brakes + 1] = C
			end
		end
	end

	Sys.Gearboxes[#Sys.Gearboxes + 1] = Gearbox
end

--- Builds a solver system for one or more engines and everything downstream of them.
-- @param Group An engine description, or { Engines = { engine descriptions } } when engines
-- share gearboxes, optionally with Roots = { gearbox descriptions } for trees no engine drives.
-- @return System table for Drivetrain.Step.
function Drivetrain.Build(Group)
	local Engines = Group.Engines or (Group.Roots and {}) or { Group }
	local Sys = {
		Engines = Engines,
		Engine = Engines[1],
		Bodies = {},
		Constraints = {},
		Wheels = {},
		WheelBodies = {},
		GearboxBodies = {},
		Gearboxes = {},
		Converters = {},
		Cranks = {},
	}
	for I, Engine in ipairs(Engines) do
		local Crank = Solver.Body(Engine.Spec.Inertia, Engine.State.W)
		Crank.Engine = Engine
		Sys.Cranks[I] = Crank
		Sys.Bodies[#Sys.Bodies + 1] = Crank
		for _, Gearbox in ipairs(Engine.Gearboxes or {}) do
			couple(Sys, Crank, Gearbox)
		end
	end
	-- Gearbox trees with no engine (a trailer, a braked axle): their input shaft turns freely.
	local Roots = Group.Roots or {}
	for _, Gearbox in ipairs(Roots) do
		if not Sys.GearboxBodies[Gearbox.Key] then
			local In = Solver.Body(max(Gearbox.InputJ or 0.02, 1e-4), kinematicInputW(Gearbox) or Gearbox.InputW or 0)
			In.Gearbox = Gearbox
			Sys.Bodies[#Sys.Bodies + 1] = In
			Sys.GearboxBodies[Gearbox.Key] = In
			Gearbox.Body = In
			Gearbox.Inputs = {}
			buildGearbox(Sys, Gearbox)
		end
	end
	for _, Gearbox in ipairs(Sys.Gearboxes) do
		-- Not while a dual box steers: its two sides are meant to run at different speeds.
		if false then shareRoad(Sys, Gearbox) end
	end
	--[[
		Engine friction and gearbox losses are friction constraints on their shafts, solved with
		everything geared to them. Applied as a drag on the shaft alone, each substep could only
		stop the shaft's own inertia: the vehicle's weight, coupled through the gears, turned it
		straight back, so a stopped engine left in gear could not hold even a gentle slope.
	]]
	for _, Crank in ipairs(Sys.Cranks) do
		Crank.FrictionC = addConstraint(Sys, { Crank }, { 1 }, 0, 0, "engine friction")
	end
	for _, Gearbox in ipairs(Sys.Gearboxes) do
		Gearbox.LossC = addConstraint(Sys, { Gearbox.Body }, { 1 }, 0, 0, "gearbox loss")
	end
	Sys.Crank = Sys.Cranks[1]
	return Sys
end

local function converterStep(Gearbox, Crank, H)
	local Conv = Gearbox.Converter
	local In = Gearbox.Body
	local Tp, Tt = TC.Torques(Conv, Crank.W, In.W)
	--[[
		Bound the exchange so one substep cannot drive the turbine past the pump (the
		converter can only ever pull the two speeds together in drive). The turbine drives the
		whole vehicle through the gears, so that is the inertia the bound uses: the input shaft
		alone would clip the converter's torque, harder the longer the substep, which made an
		automatic pull less at low tickrates.
	]]
	local Rel = Crank.W - In.W
	local Meff = 1 / (Crank.InvJ + 1 / (Gearbox.TurbineJ or In.J))
	local Limit = abs(Rel) * Meff / H
	if abs(Tt) > Limit and Rel * Tt > 0 then
		local Scale = Limit / abs(Tt)
		Tt = Tt * Scale
		Tp = Tp * Scale
	end
	Crank.Torque = Crank.Torque - Tp
	In.Torque = In.Torque + Tt
	Gearbox.ConverterTp, Gearbox.ConverterTt = Tp, Tt
end

--[[
	The wheels of a locked axle stand on one road. A locked axle turns both wheels at one speed,
	so whatever their contact patches would do differently (one side scrubbing round a turn, or
	the car rocking in yaw on its suspension) is tyre slip, which the physics engine's own
	contact handles. Coupled each to a separate share of the vehicle, the solver also pushed the
	two wheels apart and together through their tyres to reconcile those shares, a second scrub
	torque on top of the contact's. Standing still, where the road takes none of it, the
	contact handed each push straight back, a little larger: a car in neutral with its diffs
	locked rocked its wheels at 3-5 rad/s and its body at 3 deg/s of yaw (Volvo, buggy, MRAP).
	So each locked axle's wheels share one road body, and the solver only carries the drive.
]]
shareRoad = function(Sys, Gearbox)
	local Wheels = {}
	for _, Out in ipairs(Gearbox.Outputs or {}) do
		local B = Out.Wheel and Sys.WheelBodies[Out.Wheel.Key]
		-- Track sprockets keep their own: a track's slip against the ground is left to the physics engine.
		if B and B.GroundBody and B.TyreC and not Out.Wheel.Meshed then Wheels[#Wheels + 1] = B end
	end
	if #Wheels < 2 then return end
	local J, Momentum = 0, 0
	for _, B in ipairs(Wheels) do
		J = J + B.GroundBody.J
		Momentum = Momentum + B.GroundBody.J * B.GroundBody.W
	end
	local Road = Solver.Body(J, Momentum / J)
	Road.W0 = Road.W
	local Gone = {}
	for _, B in ipairs(Wheels) do
		Gone[B.GroundBody] = true
		B.GroundBody = Road
		B.TyreC.Bodies[2] = Road
	end
	for I = #Sys.Bodies, 1, -1 do
		if Gone[Sys.Bodies[I]] then table.remove(Sys.Bodies, I) end
	end
	Sys.Bodies[#Sys.Bodies + 1] = Road
end

--- Advances the drivetrain by one tick.
-- @param Sys System from Drivetrain.Build.
-- @param Dt Tick length in seconds.
-- @param Substeps Number of substeps (default 8).
-- @param Iterations Constraint sweeps per substep (default 6).
function Drivetrain.Step(Sys, Dt, Substeps, Iterations)
	Substeps = Substeps or 8
	local H = Dt / Substeps

	Solver.Reset(Sys.Constraints)

	for _, Crank in ipairs(Sys.Cranks) do
		local Engine = Crank.Engine
		Engine.FuelKg, Engine.HeatJ, Engine.TorqueSum = 0, 0, 0
		Crank.Opts = { NoStall = Engine.NoStall, HasFuel = Engine.HasFuel }
	end
	for _, Gearbox in ipairs(Sys.Gearboxes) do Gearbox.ClutchHeatJ = 0 end
	for _, B in ipairs(Sys.Wheels) do B.TyreSum = 0 end

	for _ = 1, Substeps do
		for _, Crank in ipairs(Sys.Cranks) do
			local Engine = Crank.Engine
			local State = Engine.State
			State.W = Crank.W
			local Drive, Loss = EngineModel.Step(State, Engine.Throttle or 0, H, Crank.Opts)
			-- Damage and driver modifiers scale combustion, not the starter motor or the air
			-- trapped in the cylinders.
			local Unscaled = (State.StarterTorque or 0) + (State.GasTorque or 0)
			Crank.Torque = Crank.Torque + (Drive - Unscaled) * (Engine.TorqueMul or 1) + Unscaled
			Crank.FrictionC.Cap = Loss + (Engine.AccessoryTorque or 0)
			Engine.FuelKg = Engine.FuelKg + State.FuelRate * H
			Engine.HeatJ = Engine.HeatJ + State.HeatRate * H
			Engine.TorqueSum = Engine.TorqueSum + State.Torque
		end

		for _, Conv in ipairs(Sys.Converters) do converterStep(Conv.Gearbox, Conv.Crank, H) end

		for _, Gearbox in ipairs(Sys.Gearboxes) do
			-- Losses at the input shaft: churning plus mesh inefficiency on last substep's load.
			local Out = 0
			for _, C in ipairs(Gearbox.Drive) do Out = Out + abs(C.Acc) end
			local MeshLoss = (1 - (Gearbox.Efficiency or 0.97)) * Out / H
			Gearbox.LossC.Cap = (Gearbox.SpinLoss or 0) * fadeIn(Gearbox.Body.W, SpinLossFullW) + MeshLoss

			if Gearbox.LSD then
				-- Salisbury ramp: clamping force, and so locking torque, grows with input torque.
				Gearbox.LSD.Cap = (Gearbox.LSDPreload or 0) + (Gearbox.LSDRamp or 0) * Out / H * abs(Gearbox.Ratio or 0)
			end
			if Gearbox.SteerC then
				local S = Gearbox.Steer or 0
				Gearbox.SteerC.Coefs[3] = -S / (Gearbox.SteerRatio or 1)
			end
		end

		for _, B in ipairs(Sys.Wheels) do
			local Roll = B.Wheel.RollDrag or 0
			if Roll > 0 then Solver.Drag(B, Roll * fadeIn(B.W * (B.Wheel.Radius or 0.3), RollFullSpeed), H) end
		end

		for _, B in ipairs(Sys.Wheels) do
			local GB = B.GroundBody
			local Tq = GB and B.Wheel.Ground.Torque
			if Tq then GB.Torque = GB.Torque + Tq end
		end

		Solver.Step(Sys.Bodies, Sys.Constraints, H, Iterations or 6)
		for _, B in ipairs(Sys.Wheels) do
			if B.TyreC then B.TyreSum = B.TyreSum + B.TyreC.Acc end
		end

		for _, Gearbox in ipairs(Sys.Gearboxes) do
			for _, C in ipairs(Gearbox.Inputs or {}) do
				-- Clutch slip heat: transmitted torque × slip speed (power = torque × angular speed).
				local Slip = abs(C.Bodies[1].W * C.Coefs[1] + C.Bodies[2].W * C.Coefs[2])
				Gearbox.ClutchHeatJ = Gearbox.ClutchHeatJ + abs(C.Acc) * Slip
			end
			for _, E in ipairs(Gearbox.SideClutches or {}) do
				local C = E.C
				local Slip = abs(C.Bodies[1].W * C.Coefs[1] + C.Bodies[2].W * C.Coefs[2])
				Gearbox.ClutchHeatJ = Gearbox.ClutchHeatJ + abs(C.Acc) * Slip
			end
		end
	end

	for _, Crank in ipairs(Sys.Cranks) do
		local Engine = Crank.Engine
		Engine.State.W = Crank.W
		Engine.AvgTorque = Engine.TorqueSum / Substeps
	end

	-- Torque the drivetrain puts through each anchored wheel (last substep), for its hold to
	-- compare with the brake: brakes themselves are left out, they are what holds it.
	for _, C in ipairs(Sys.Constraints) do
		if C.Tag ~= "brake" and C.Acc ~= 0 then
			for I, B in ipairs(C.Bodies) do
				if B.Wheel and B.InvJ == 0 then
					B.Wheel.AnchorTorque = (B.Wheel.AnchorTorque or 0) + C.Coefs[I] * C.Acc / H
				end
			end
		end
	end

	for _, B in ipairs(Sys.Wheels) do
		local GB = B.GroundBody
		-- What this wheel's own tyre passed to the road (a locked axle's wheels share one road).
		local Ground = GB and -B.TyreSum or 0
		B.Wheel.GroundImpulse = Ground
		B.Wheel.Impulse = B.InvJ == 0 and 0 or B.J * (B.W - B.W0) + Ground
		B.Wheel.WOut = B.W
	end

	for _, Gearbox in ipairs(Sys.Gearboxes) do
		Gearbox.InputW = Gearbox.Body.W
		local Out = 0
		for _, C in ipairs(Gearbox.Drive) do Out = Out + C.Acc end
		Gearbox.OutputTorque = Out / H * (Gearbox.Ratio or 0)
		local C = Gearbox.Input
		if C then
			Gearbox.ClutchSlip = C.Bodies[1].W * C.Coefs[1] + Gearbox.Body.W * C.Coefs[2]
		end
		-- Dual boxes slip at their side clutches; report the worst one in input-shaft speed.
		for _, E in ipairs(Gearbox.SideClutches or {}) do
			local SC = E.C
			local Slip = (SC.Bodies[1].W * SC.Coefs[1] + SC.Bodies[2].W * SC.Coefs[2]) * E.Scale
			if abs(Slip) > abs(Gearbox.ClutchSlip or 0) then Gearbox.ClutchSlip = Slip end
		end
	end
end

Drivetrain.StallDecel = 0.2 -- m/s²: a firm pedal slowing a vehicle by less than this is not stopping it
Drivetrain.StallTime = 0.1  -- s the vehicle must go without slowing that much

--- Whether a firm brake pedal has stopped slowing a wheel's vehicle down.
-- Tracks the ground speed while Active: the reference speed is renewed whenever the vehicle has
-- slowed by StallDecel times the time since; once StallTime passes without that, the brake has
-- stalled. Resets while not Active.
-- @param State Per-wheel table that keeps the reference (StallRef, StallFor).
-- @param Active Whether the pedal is firm and the vehicle crawling (the check applies).
-- @param Speed Ground speed magnitude, m/s.
-- @param Dt Seconds since the last call.
-- @return true once the brake has stalled.
function Drivetrain.BrakeStalled(State, Active, Speed, Dt)
	if not Active then
		State.StallRef, State.StallFor = nil, nil
		return false
	end
	local For = (State.StallFor or 0) + Dt
	if not State.StallRef or Speed <= State.StallRef - Drivetrain.StallDecel * For then
		State.StallRef, State.StallFor = Speed, 0
		return false
	end
	State.StallFor = For
	return For >= Drivetrain.StallTime
end

return Drivetrain

--[[
	Builds a solver system from a drivetrain description and steps it through one tick.
	GMod-free: the entity adapters and the offline rig both describe the drivetrain with
	plain tables.

	Description:
	  Engine  = { Spec, State, Throttle, NoStall, HasFuel, Gearboxes = { Gearbox... } }
	  Gearbox = {
	    Key,                -- unique per gearbox
	    Ratio,              -- signed reduction (input/output speed); 0 = neutral
	    InputJ,             -- input shaft + clutch disc inertia, kg·m²
	    ClutchCap,          -- main clutch capacity N·m (nil = rigid, used by dual-clutch boxes)
	    Converter,          -- torque converter (from TorqueConverter.New) or nil
	    LockupCap,          -- converter lock-up clutch capacity when engaged, N·m
	    Dual,               -- per-side clutches instead of a main clutch
	    SideCap = {[0]=, [1]=},  -- dual clutch capacities (input-side N·m)
	    Diff,               -- "open" | "lsd" | "locked"
	    LSDPreload, LSDRamp,-- Salisbury limited-slip: bias = preload + ramp·|input torque|
	    Steer, SteerRatio,  -- double differential steering input (-1..1) and ratio
	    Efficiency,         -- mesh efficiency of the engaged path (0..1)
	    SpinLoss,           -- constant churning/bearing drag at the input, N·m
	    Brake = {[0]=, [1]=},    -- brake torque per side at the wheels, N·m
	    Outputs = { {Side = 0|1, Wheel = Wheel} | {Side = 0|1, Gearbox = Gearbox} ... },
	  }
	  Wheel   = { Key, J, W, RollDrag, Ground }
	    J is the wheel's own inertia; Ground = { J, W, Cap } from Vehicle.Ground couples it to
	    its share of the vehicle through tyre friction (nil when airborne).

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

local function addConstraint(Sys, Bodies, Coefs, Cap, Target, Tag)
	local C = Solver.Constraint(Bodies, Coefs, Cap, Target)
	C.Tag = Tag
	Sys.Constraints[#Sys.Constraints + 1] = C
	return C
end

local function wheelBody(Sys, Wheel)
	local B = Sys.WheelBodies[Wheel.Key]
	if B then return B end
	B = Solver.Body(Wheel.J, Wheel.W)
	B.Wheel = Wheel
	B.W0 = Wheel.W
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
		addConstraint(Sys, { B, GB }, { 1, -1 }, Ground.Cap, 0, "tyre")
	end
	return B
end

-- Returns the body that an output drives.
local function outputBody(Sys, Out)
	if Out.Wheel then return wheelBody(Sys, Out.Wheel) end
	return Sys.GearboxBodies[Out.Gearbox.Key]
end

local buildGearbox

-- Couples an upstream velocity (Body·1) to a gearbox's input body.
local function couple(Sys, Up, UpCoef, Gearbox, Cap)
	local In = Solver.Body(max(Gearbox.InputJ or 0.02, 1e-4), 0)
	In.W = Gearbox.InputW or Up.W * UpCoef
	In.Gearbox = Gearbox
	Sys.Bodies[#Sys.Bodies + 1] = In
	Sys.GearboxBodies[Gearbox.Key] = In
	Gearbox.Body = In
	Gearbox.Input = addConstraint(Sys, { Up, In }, { UpCoef, -1 }, Cap, 0, "clutch")
	buildGearbox(Sys, Gearbox)
	return In
end

buildGearbox = function(Sys, Gearbox)
	local In = Gearbox.Body
	local R = Gearbox.Ratio or 0

	-- Group outputs by side.
	local Sides = { [0] = {}, [1] = {} }
	for _, Out in ipairs(Gearbox.Outputs or {}) do
		local List = Sides[Out.Side == 0 and 0 or 1]
		List[#List + 1] = Out
	end

	-- Chained gearboxes need their input body before we can constrain to them.
	for S = 0, 1 do
		for _, Out in ipairs(Sides[S]) do
			if Out.Gearbox and not Sys.GearboxBodies[Out.Gearbox.Key] then
				local Child = Out.Gearbox
				local Body = Solver.Body(max(Child.InputJ or 0.02, 1e-4), Child.InputW or (R ~= 0 and In.W / R or 0))
				Body.Gearbox = Child
				Sys.Bodies[#Sys.Bodies + 1] = Body
				Sys.GearboxBodies[Child.Key] = Body
				Child.Body = Body
				buildGearbox(Sys, Child)
			end
		end
	end

	Gearbox.Drive = {}
	local HasL, HasR = #Sides[0] > 0, #Sides[1] > 0

	if R ~= 0 then
		if Gearbox.Dual or not (HasL and HasR) or Gearbox.Diff == "locked" then
			-- Each output rigidly geared (through its side clutch on dual boxes).
			for S = 0, 1 do
				local Cap = Gearbox.Dual and Gearbox.SideCap and Gearbox.SideCap[S] or nil
				for _, Out in ipairs(Sides[S]) do
					local OutCap = Cap
					if Out.Gearbox and Out.Gearbox.ClutchCap then
						OutCap = OutCap and min(OutCap, Out.Gearbox.ClutchCap) or Out.Gearbox.ClutchCap
					end
					Gearbox.Drive[#Gearbox.Drive + 1] = addConstraint(Sys, { In, outputBody(Sys, Out) }, { 1, -R }, OutCap, 0, "gear")
				end
			end
		else
			-- Differential between the first output on each side; extra outputs on a side
			-- are rigidly tied to that side's first output.
			local L, Rt = outputBody(Sys, Sides[0][1]), outputBody(Sys, Sides[1][1])
			Gearbox.Drive[1] = addConstraint(Sys, { In, L, Rt }, { 1, -R / 2, -R / 2 }, nil, 0, "diff")
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

--- Builds a solver system for one engine and everything downstream of it.
-- @param Engine Engine description (see file header).
-- @return System table for Drivetrain.Step.
function Drivetrain.Build(Engine)
	local Sys = {
		Engine = Engine,
		Bodies = {},
		Constraints = {},
		Wheels = {},
		WheelBodies = {},
		GearboxBodies = {},
		Gearboxes = {},
	}
	local Crank = Solver.Body(Engine.Spec.Inertia, Engine.State.W)
	Sys.Crank = Crank
	Sys.Bodies[1] = Crank

	for _, Gearbox in ipairs(Engine.Gearboxes or {}) do
		if Gearbox.Converter then
			-- The converter is a torque source between crank and input; only its lock-up
			-- clutch is a constraint.
			local In = Solver.Body(max(Gearbox.InputJ or 0.05, 1e-4), Gearbox.InputW or Crank.W)
			In.Gearbox = Gearbox
			Sys.Bodies[#Sys.Bodies + 1] = In
			Sys.GearboxBodies[Gearbox.Key] = In
			Gearbox.Body = In
			Gearbox.Input = addConstraint(Sys, { Crank, In }, { 1, -1 }, Gearbox.LockupCap or 0, 0, "lockup")
			buildGearbox(Sys, Gearbox)
		else
			couple(Sys, Crank, 1, Gearbox, Gearbox.Dual and nil or Gearbox.ClutchCap)
		end
	end

	return Sys
end

local function converterStep(Gearbox, Crank, H)
	local Conv = Gearbox.Converter
	local In = Gearbox.Body
	local Tp, Tt = TC.Torques(Conv, Crank.W, In.W)
	-- Bound the exchange so one substep cannot drive the turbine past the pump (the
	-- converter can only ever pull the two speeds together in drive).
	local Rel = Crank.W - In.W
	local Meff = 1 / (Crank.InvJ + In.InvJ)
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

--- Advances the drivetrain by one tick.
-- @param Sys System from Drivetrain.Build.
-- @param Dt Tick length in seconds.
-- @param Substeps Number of substeps (default 8).
-- @param Iterations Constraint sweeps per substep (default 6).
function Drivetrain.Step(Sys, Dt, Substeps, Iterations)
	Substeps = Substeps or 8
	local H = Dt / Substeps
	local Engine = Sys.Engine
	local State = Engine.State
	local Crank = Sys.Crank
	local Opts = { NoStall = Engine.NoStall, HasFuel = Engine.HasFuel }

	Solver.Reset(Sys.Constraints)

	local FuelKg, HeatJ, TorqueSum = 0, 0, 0
	local ClutchHeat = {}

	for _ = 1, Substeps do
		State.W = Crank.W
		local Drive, Loss = EngineModel.Step(State, Engine.Throttle or 0, H, Opts)
		Crank.Torque = Crank.Torque + Drive
		Solver.Drag(Crank, Loss, H)
		FuelKg = FuelKg + State.FuelRate * H
		HeatJ = HeatJ + State.HeatRate * H
		TorqueSum = TorqueSum + State.Torque

		for _, Gearbox in ipairs(Sys.Gearboxes) do
			if Gearbox.Converter then converterStep(Gearbox, Crank, H) end

			-- Losses at the input shaft: churning plus mesh inefficiency on last substep's load.
			local Out = 0
			for _, C in ipairs(Gearbox.Drive) do Out = Out + abs(C.Acc) end
			local MeshLoss = (1 - (Gearbox.Efficiency or 0.97)) * Out / H
			Solver.Drag(Gearbox.Body, (Gearbox.SpinLoss or 0) + MeshLoss, H)

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
			if Roll > 0 then Solver.Drag(B, Roll, H) end
		end

		Solver.Step(Sys.Bodies, Sys.Constraints, H, Iterations or 6)

		for _, Gearbox in ipairs(Sys.Gearboxes) do
			local C = Gearbox.Input
			if C then
				-- Clutch slip heat: transmitted torque × slip speed (Shigley §16-8).
				local Up, Down = C.Bodies[1], C.Bodies[2]
				local Slip = abs(Up.W * C.Coefs[1] + Down.W * C.Coefs[2])
				ClutchHeat[Gearbox] = (ClutchHeat[Gearbox] or 0) + abs(C.Acc) * Slip
			end
		end
	end

	State.W = Crank.W
	Engine.FuelKg = FuelKg
	Engine.HeatJ = HeatJ
	Engine.AvgTorque = TorqueSum / Substeps

	for _, B in ipairs(Sys.Wheels) do
		local GB = B.GroundBody
		local Ground = GB and GB.J * (GB.W - GB.W0) or 0
		B.Wheel.GroundImpulse = Ground
		B.Wheel.Impulse = B.J * (B.W - B.W0) + Ground
		B.Wheel.WOut = B.W
	end

	for _, Gearbox in ipairs(Sys.Gearboxes) do
		Gearbox.InputW = Gearbox.Body.W
		local Out = 0
		for _, C in ipairs(Gearbox.Drive) do Out = Out + C.Acc end
		Gearbox.OutputTorque = Out / H * (Gearbox.Ratio or 0)
		Gearbox.ClutchHeatJ = ClutchHeat[Gearbox] or 0
		local C = Gearbox.Input
		if C then
			local Up = C.Bodies[1]
			Gearbox.ClutchSlip = Up.W * C.Coefs[1] + Gearbox.Body.W * C.Coefs[2]
		end
	end
end

return Drivetrain

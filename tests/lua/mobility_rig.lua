--[[
	Offline drivetrain rig. Runs the real ACE mobility modules against a lumped vehicle whose
	tyre contact step imitates what VPhysics does after the drivetrain applies its impulses:
	the wheel and the chassis exchange a friction impulse that removes contact slip, capped
	at μ·N·dt. Used by the self-tests and for tickrate sweeps; no GMod needed.

	Usage from a test:  local Rig = dofile(root .. "/tests/lua/mobility_rig.lua")(root)
]]

return function(Root)
	ACE = ACE or {}
	ACE.Mobility = ACE.Mobility or {}

	local function load(Path)
		local F = assert(io.open(Root .. "/" .. Path, "rb"))
		local Src = F:read("*a")
		F:close()
		assert(loadstring(Src, Path))()
	end

	load("lua/ace/shared/mobility/units.lua")
	load("lua/ace/shared/mobility/engine_model.lua")
	load("lua/ace/shared/mobility/solver.lua")
	load("lua/ace/shared/mobility/torque_converter.lua")
	load("lua/ace/shared/mobility/drivetrain.lua")
	load("lua/ace/shared/mobility/vehicle.lua")
	if not ACE.GenericTorqueCurves then load("lua/ace/shared/engines/ace_engine_properties.lua") end

	local M = ACE.Mobility
	local Rig = {}

	local RPMToRad = math.pi / 30
	local G = 9.80665

	--- Makes a vehicle.
	-- Opts: EngineDef, Mass (kg), WheelRadius (m), WheelJ (kg·m² per wheel), Driven (count),
	-- Mu, Crr, CdA, Grade (rad), Ratios {..}, Final, ClutchCap, Diff, Converter (bool),
	-- Assisted (bool), Tick (s), Substeps.
	function Rig.New(Opts)
		local Def = Opts.EngineDef
		local Curve = Def.torquecurve or ACE.GenericTorqueCurves[Def.enginetype] or ACE.GenericTorqueCurves.GenericPetrol
		local Spec = M.Engine.Build(Def, Curve)
		local State = M.Engine.NewState(Spec)

		local V = {
			Opts = Opts,
			Spec = Spec,
			State = State,
			Mass = Opts.Mass or 1500,
			R = Opts.WheelRadius or 0.32,
			Jw = Opts.WheelJ or 1.2,
			Driven = Opts.Driven or 2,
			Mu = Opts.Mu or 0.9,
			Crr = Opts.Crr or 0.012,
			CdA = Opts.CdA or 0.65,
			Grade = Opts.Grade or 0,
			Tick = Opts.Tick or 1 / 66,
			Substeps = Opts.Substeps or 8,
			Time = 0,
			Speed = Opts.Speed or 0,  -- m/s
			Gear = 1,
			Throttle = 0,
			Clutch = 0,  -- pedal 0 = engaged, 1 = pressed (ACE convention)
			Brake = 0,   -- 0..1
			FuelKg = 0,
			Log = {},
		}

		V.Wheels = {}
		for I = 1, V.Driven do
			V.Wheels[I] = { Key = I, W = V.Speed / V.R, Side = (I % 2 == 1) and 0 or 1 }
		end

		V.Gearbox = {
			Key = "gb",
			InputJ = Opts.InputJ or 0.03,
			Diff = Opts.Diff or "open",
			Efficiency = Opts.Efficiency or 0.97,
			SpinLoss = Opts.SpinLoss or 2,
			Outputs = {},
			Brake = { [0] = 0, [1] = 0 },
		}
		for _, W in ipairs(V.Wheels) do
			V.Gearbox.Outputs[#V.Gearbox.Outputs + 1] = { Side = W.Side, Wheel = W }
		end
		if Opts.Converter then
			local StallRPM = Opts.StallRPM or math.max(Spec.IdleRPM * 2.2, 1800)
			V.Gearbox.Converter = M.TorqueConverter.New(StallRPM, Spec.BrakeWOT(StallRPM * RPMToRad), 2.0)
		end
		return V
	end

	--- One tick: drivetrain step, then the VPhysics-like contact step.
	function Rig.Tick(V)
		local O = V.Opts
		local Dt = V.Tick
		local Gb = V.Gearbox
		local Ratio = V.Gear == 0 and 0 or (O.Ratios[V.Gear] or 0) * (O.Final or 1)
		Gb.Ratio = Ratio

		local MaxClutch = O.ClutchCap or V.Spec.PeakTorque * 1.5
		if Gb.Converter then
			Gb.LockupCap = O.Lockup and MaxClutch or 0
		elseif O.Assisted then
			Gb.ClutchCap = M.Vehicle.AssistedClutch(V.State, V.Spec, MaxClutch, V.Clutch, V.Throttle)
		else
			Gb.ClutchCap = MaxClutch * (1 - V.Clutch)
		end
		local BrakeTq = (O.BrakeMax or 3000) * V.Brake
		Gb.Brake[0], Gb.Brake[1] = BrakeTq, BrakeTq

		-- Each driven wheel is coupled to its share of the vehicle through tyre friction.
		local N = V.Mass * G * math.cos(V.Grade) / V.Driven
		local MuEst = V.Mu * (O.MuEstimate or 1)
		for _, W in ipairs(V.Wheels) do
			W.J = V.Jw
			W.Ground = M.Vehicle.Ground(V.Mass / V.Driven, V.R, V.Speed, MuEst, N, true)
			W.RollDrag = V.Crr * N * V.R
		end

		local Eng = {
			Spec = V.Spec, State = V.State, Throttle = V.Throttle,
			NoStall = O.Assisted, HasFuel = true, Gearboxes = { Gb },
		}
		local Sys = M.Drivetrain.Build(Eng)
		M.Drivetrain.Step(Sys, Dt, V.Substeps)
		V.FuelKg = V.FuelKg + (Eng.FuelKg or 0)

		-- Apply the drivetrain impulse to the real (light) wheel, then let the contact settle.
		local Share = V.Mass / V.Driven
		local Fx = 0
		for _, W in ipairs(V.Wheels) do
			W.W = W.W + W.Impulse / V.Jw
			-- Contact: impulse P along the ground removes slip, limited by friction.
			local Slip = W.W * V.R - V.Speed
			local Meff = 1 / (V.R * V.R / V.Jw + 1 / Share)
			local P = Slip * Meff
			local Lim = V.Mu * N * Dt
			if P > Lim then P = Lim elseif P < -Lim then P = -Lim end
			W.W = W.W - P * V.R / V.Jw
			Fx = Fx + P
		end
		local Aero = 0.5 * 1.225 * V.CdA * V.Speed * math.abs(V.Speed)
		V.Speed = V.Speed + (Fx - (Aero + V.Mass * G * math.sin(V.Grade)) * Dt) / V.Mass
		V.Time = V.Time + Dt
		V.Sys = Sys
		return V
	end

	function Rig.RPM(V) return V.State.W * 30 / math.pi end
	function Rig.Kmh(V) return V.Speed * 3.6 end

	--- Runs until Fn(V) returns true or MaxTime passes. Control(V) sets inputs each tick.
	function Rig.Run(V, MaxTime, Control, Fn)
		while V.Time < MaxTime do
			if Control then Control(V) end
			Rig.Tick(V)
			if Fn and Fn(V) then return true end
		end
		return false
	end

	--- Starts the engine and waits until it idles.
	function Rig.StartEngine(V)
		M.Engine.Start(V.State)
		local Prev = V.Gear
		V.Gear = 0
		Rig.Run(V, V.Time + 4, nil, function(X) return X.State.Running and X.Time > 2.5 end)
		V.Gear = Prev
	end

	--- A simple driver: full throttle, clutch let out over ReleaseTime from a standstill, then
	-- shifts at ShiftRPM with a clutch dip. Purely time-based so it behaves the same at every
	-- tickrate.
	function Rig.LaunchDriver(ShiftRPM, ShiftTime, ReleaseTime)
		ShiftTime = ShiftTime or 0.35
		ReleaseTime = ReleaseTime or 1.2
		local ShiftUntil, Start = -1, nil
		return function(V)
			Start = Start or V.Time
			local RPM = Rig.RPM(V)
			V.Throttle = 1
			if V.Time < ShiftUntil then
				V.Clutch = 1
				V.Throttle = 0
				return
			end
			if V.Gear == 1 and not V.Opts.Converter and not V.Opts.Assisted then
				V.Clutch = math.max(0, 0.8 * (1 - (V.Time - Start) / ReleaseTime))
			else
				V.Clutch = 0
			end
			if RPM > ShiftRPM and V.Gear < #V.Opts.Ratios then
				V.Gear = V.Gear + 1
				ShiftUntil = V.Time + ShiftTime
			end
		end
	end

	return Rig
end

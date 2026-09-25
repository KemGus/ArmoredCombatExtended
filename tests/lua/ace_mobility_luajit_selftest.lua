-- Self-tests for the mobility modules, run offline against tests/lua/mobility_rig.lua.
local root = assert(arg[1], "usage: ace_mobility_luajit_selftest.lua <ACE repo>")
root = root:gsub("\\\\", "/"):gsub("/$", "")

local Rig = dofile(root .. "/tests/lua/mobility_rig.lua")(root)
local M = ACE.Mobility

local Passed = 0
local function check(Cond, Label, ...)
	if not Cond then error(("FAIL %s %s"):format(Label, table.concat({ ... }, " ")), 2) end
	Passed = Passed + 1
end
local function near(A, B, Tol, Label)
	check(math.abs(A - B) <= Tol, Label, ("got %.4g expected %.4g ±%.3g"):format(A, B, Tol))
end

local V8 = { id = "5.7-V8", name = "5.7L V8 Petrol", category = "V8", fuel = "Petrol", enginetype = "V8", torque = 480, idlerpm = 800, limitrpm = 6500 }
local Diesel = { id = "12.0-I6", name = "12.0L I6 Diesel", category = "I6", fuel = "Diesel", enginetype = "I6", torque = 2100, idlerpm = 600, limitrpm = 2100 }
local Single = { id = "0.25-I1", name = "250cc Single", category = "Single", fuel = "Petrol", enginetype = "Single", torque = 25, idlerpm = 1500, limitrpm = 14000, displacement = 0.25 }

local function car(Tick, Extra)
	local O = { EngineDef = V8, Mass = 1600, WheelRadius = 0.33, WheelJ = 1.2, Driven = 2,
		Ratios = { 2.97, 2.07, 1.43, 1.0, 0.84, 0.56 }, Final = 3.42, Tick = Tick }
	for K, V in pairs(Extra or {}) do O[K] = V end
	return Rig.New(O)
end

------------------------------------------------------------------ solver primitives
do
	-- A rigid 3:1 gear between two free bodies conserves r-weighted momentum.
	local A, B = M.Solver.Body(1, 30), M.Solver.Body(2, 0)
	local C = M.Solver.Constraint({ A, B }, { 1, -3 })
	M.Solver.Step({ A, B }, { C }, 0.01, 8)
	near(A.W - 3 * B.W, 0, 1e-9, "gear locks")
	-- Momentum through a gear: torque on A is λ, on B is -3λ, so J_A·ΔωA·3 + J_B·ΔωB = 0.
	near(1 * (A.W - 30) * 3 + 2 * (B.W - 0), 0, 1e-9, "gear conserves reflected momentum")

	-- A clutch never carries more than its capacity.
	local E, W = M.Solver.Body(0.3, 300), M.Solver.Body(5, 0)
	local Cl = M.Solver.Constraint({ E, W }, { 1, -1 }, 100)
	M.Solver.Step({ E, W }, { Cl }, 0.01, 8)
	near(math.abs(Cl.Acc), 100 * 0.01, 1e-9, "clutch impulse capped")
	check(E.W > W.W, "slipping clutch does not lock")

	-- Open differential: equal torque to both sides whatever their inertia.
	local Cr, L, R = M.Solver.Body(0.5, 10), M.Solver.Body(1, 0), M.Solver.Body(4, 0)
	local D = M.Solver.Constraint({ Cr, L, R }, { 1, -0.5, -0.5 })
	M.Solver.Step({ Cr, L, R }, { D }, 0.01, 8)
	near(L.W * 1, R.W * 4, 1e-9, "open diff splits torque equally")

	-- Drag stops a body but never reverses it.
	local S = M.Solver.Body(1, 0.5)
	M.Solver.Drag(S, 1000, 0.01)
	near(S.W, 0, 0, "drag does not reverse")
end

------------------------------------------------------------------ engine model
do
	local Spec = M.Engine.Build(V8, ACE.GenericTorqueCurves.V8)
	-- The dyno curve is brake torque: indicated minus losses at WOT must reproduce it.
	for _, RPM in ipairs({ 1500, 3000, 4500, 6000 }) do
		local W = RPM * math.pi / 30
		local Brake = M.Engine.IndicatedWOT(Spec, W) - M.Engine.FrictionTorque(Spec, W, 1) - M.Engine.PumpingTorque(Spec, 1)
		near(Brake, Spec.BrakeWOT(W), 1e-6, "WOT brake torque matches curve at " .. RPM)
	end
	-- Closed-throttle losses at 3000 RPM on a 5.7 L SI engine: Heywood fig. 13-12 puts total
	-- motoring mep (friction + pumping) around 1.5-2.5 bar, i.e. 70-110 N·m here.
	local W = 3000 * math.pi / 30
	local Motoring = M.Engine.FrictionTorque(Spec, W, 0) + M.Engine.PumpingTorque(Spec, 0)
	check(Motoring > 60 and Motoring < 120, "motoring torque plausible", Motoring)
	-- Diesel pumping is far smaller than SI at closed throttle.
	local DSpec = M.Engine.Build(Diesel, ACE.GenericTorqueCurves.GenericDiesel)
	check(M.Engine.PumpingTorque(DSpec, 0) / DSpec.Vd < M.Engine.PumpingTorque(Spec, 0) / Spec.Vd * 0.5, "diesel engine braking weaker than SI")
end

------------------------------------------------------------------ idle, free rev, stall
do
	local V = car(1 / 66)
	Rig.StartEngine(V)
	check(V.State.Running, "engine starts on the starter")
	local Lo, Hi = 1e9, 0
	Rig.Run(V, V.Time + 3, function(X) X.Gear = 0 end, function(X)
		local R = Rig.RPM(X) Lo = math.min(Lo, R) Hi = math.max(Hi, R)
	end)
	check(Lo > 760 and Hi < 860, "idle governor holds idle", Lo, Hi)
	local LPerH = V.State.FuelRate * 3600 / 0.745
	check(LPerH > 0.8 and LPerH < 3.0, "idle fuel flow plausible (L/h)", LPerH)

	-- Dropping the clutch at idle with no throttle: a big V8 can idle away in first, but it
	-- stalls in third, and a small I4 stalls even in first.
	V.Gear = 3
	Rig.Run(V, V.Time + 3, function(X) X.Clutch = 0 X.Throttle = 0 end)
	check(V.State.Stalled, "V8 clutch dump at idle in third stalls")

	local I4 = { id = "1.5-I4", name = "1.5L I4 Petrol", category = "I4", fuel = "Petrol", enginetype = "I4", torque = 135, idlerpm = 900, limitrpm = 7500 }
	local Small = Rig.New({ EngineDef = I4, Mass = 1100, WheelRadius = 0.3, WheelJ = 0.9, Driven = 2,
		Ratios = { 3.45, 1.94, 1.29, 0.97, 0.78 }, Final = 4.06 })
	Rig.StartEngine(Small)
	Small.Gear = 1
	Rig.Run(Small, Small.Time + 3, function(X) X.Clutch = 0 X.Throttle = 0 end)
	check(Small.State.Stalled, "I4 clutch dump at idle in first stalls")

	-- The same in Assisted mode does not.
	local A = car(1 / 66, { Assisted = true })
	Rig.StartEngine(A)
	A.Gear = 1
	Rig.Run(A, A.Time + 3, function(X) X.Clutch = 0 X.Throttle = 0 end)
	check(A.State.Running and not A.State.Stalled, "assisted mode does not stall")
	-- ...and it launches without any clutch work.
	local T0 = A.Time
	local Ok = Rig.Run(A, A.Time + 20, function(X) X.Throttle = 1 end, function(X) return Rig.Kmh(X) > 50 end)
	check(Ok, "assisted launches in first")
	check(A.Time - T0 < 6, "assisted 0-50 sane", A.Time - T0)
end

------------------------------------------------------------------ tickrate independence
do
	local Results = {}
	for _, Tick in ipairs({ 16, 33, 66, 100, 128 }) do
		local V = car(1 / Tick)
		Rig.StartEngine(V)
		V.Gear = 1
		local T0 = V.Time
		Rig.Run(V, V.Time + 30, Rig.LaunchDriver(6000), function(X) return Rig.Kmh(X) >= 100 end)
		local Accel = V.Time - T0

		local F = car(1 / Tick)
		Rig.StartEngine(F)
		F.Gear = 0
		local T1 = F.Time
		Rig.Run(F, F.Time + 5, function(X) X.Throttle = 1 end, function(X) return Rig.RPM(X) > 6000 end)
		Results[Tick] = { Accel = Accel, Rev = F.Time - T1 }
	end
	local Ref = Results[66]
	for Tick, R in pairs(Results) do
		-- A tick is 1/16 s at the slowest rate, so allow one tick of quantisation on top of 3%.
		near(R.Accel, Ref.Accel, Ref.Accel * 0.03 + 1 / Tick, "0-100 at " .. Tick .. " tick vs 66")
		near(R.Rev, Ref.Rev, Ref.Rev * 0.03 + 1 / Tick, "free rev at " .. Tick .. " tick vs 66")
	end
end

------------------------------------------------------------------ extreme envelope
do
	-- Rock crawler: 120:1 overall, 2.5 t, 45% grade start. Must climb without stalling and
	-- without NaN, at 16 and 66 tick.
	for _, Tick in ipairs({ 16, 66 }) do
		local V = car(1 / Tick, { Mass = 2500, WheelRadius = 0.45, WheelJ = 3, Driven = 4,
			Ratios = { 4.0 * 2.72 * 2.0 }, Final = 5.38, Grade = math.atan(0.45), Assisted = true })
		V.Brake = 1
		Rig.StartEngine(V)
		V.Gear = 1
		-- Driver holds the brake for a second while bringing the throttle in, then releases.
		local T0 = V.Time
		Rig.Run(V, V.Time + 10, function(X)
			X.Throttle = 0.6
			X.Brake = (X.Time - T0 < 1) and 1 or 0
		end)
		check(V.Speed > 0.1 and V.Speed == V.Speed, "crawler climbs 45% grade at " .. Tick, V.Speed)
		check(V.State.Running, "crawler keeps running at " .. Tick)
	end

	-- 40 t truck on a 12L diesel, 12-speed, pulling away on 8%.
	local T = Rig.New({ EngineDef = Diesel, Mass = 40000, WheelRadius = 0.52, WheelJ = 10, Driven = 4,
		Ratios = { 14.9, 11.7, 9.0, 7.1, 5.5, 4.4, 3.4, 2.7, 2.1, 1.6, 1.3, 1.0 }, Final = 3.4,
		Grade = math.atan(0.08), Mu = 0.8, Assisted = true, CdA = 6, BrakeMax = 40000 })
	T.Brake = 1
	Rig.StartEngine(T)
	T.Brake = 0
	T.Gear = 1
	Rig.Run(T, T.Time + 15, function(X) X.Throttle = 1 end)
	check(T.Speed > 0.5, "truck pulls away on 8%", T.Speed)

	-- Tiny high-revving single on a 100 kg bike: stable at 16 tick.
	local B = Rig.New({ EngineDef = Single, Mass = 180, WheelRadius = 0.3, WheelJ = 0.4, Driven = 1,
		Ratios = { 2.8, 2.0, 1.6, 1.3, 1.1, 0.95 }, Final = 2.9, Tick = 1 / 16, Assisted = true, CdA = 0.4 })
	Rig.StartEngine(B)
	check(B.State.Running, "single starts")
	B.Gear = 1
	Rig.Run(B, B.Time + 8, Rig.LaunchDriver(13000))
	check(B.Speed == B.Speed and B.Speed > 5 and Rig.RPM(B) < 16000, "single stable at 16 tick", Rig.Kmh(B), Rig.RPM(B))

	-- Absurd build: 20 kN·m into small wheels through 0.1:1. No NaN, no runaway.
	local Big = { id = "x", name = "Absurd", category = "V12", fuel = "Diesel", enginetype = "V12", torque = 20000, idlerpm = 500, limitrpm = 2500, displacement = 60 }
	local X = Rig.New({ EngineDef = Big, Mass = 800, WheelRadius = 0.2, WheelJ = 0.2, Driven = 2,
		Ratios = { 0.1 }, Final = 1, Tick = 1 / 33, Assisted = true })
	Rig.StartEngine(X)
	X.Gear = 1
	Rig.Run(X, X.Time + 5, function(V) V.Throttle = 1 end)
	check(X.Speed == X.Speed and Rig.RPM(X) < 2500 * 1.2, "absurd build stays finite", Rig.RPM(X))

	-- The same engine through a 50:1 crawl gear: huge wheel torque, still finite and grip-limited.
	local Y = Rig.New({ EngineDef = Big, Mass = 800, WheelRadius = 0.2, WheelJ = 0.2, Driven = 2,
		Ratios = { 50 }, Final = 1, Tick = 1 / 33, Assisted = true })
	Rig.StartEngine(Y)
	Y.Gear = 1
	Rig.Run(Y, Y.Time + 5, function(V) V.Throttle = 1 end)
	check(Y.Speed == Y.Speed and Y.Speed > 0 and Rig.RPM(Y) < 2500 * 1.2, "50:1 gear stays finite", Rig.Kmh(Y), Rig.RPM(Y))

	--[[
		62 t tank on the AGT1500 through a converter automatic, tracks (rolling resistance 0.04).
		M1A2: 0-32 km/h in about 7 s, 67 km/h governed (US Army fact files); ACE's AGT1500 has
		27 % more torque than the real one, so it may be a little quicker. Checked at 16, 66
		and 128 tick against each other.
	]]
	local Agt = { id = "agt", name = "AGT 1500", category = "Turbine", fuel = "Multifuel", enginetype = "GroundTurbine",
		torque = 6780, idlerpm = 830, limitrpm = 3000, inertia = 7.93,
		torquecurve = { 1.0, 0.974, 0.947, 0.921, 0.895, 0.868, 0.842, 0.815, 0.789, 0.763, 0.736, 0.71, 0.684 } }
	local T32 = {}
	for _, Tick in ipairs({ 16, 66, 128 }) do
		local K = Rig.New({ EngineDef = Agt, Mass = 62000, WheelRadius = 0.33, WheelJ = 40, Driven = 2,
			Ratios = { 4.0, 2.4, 1.5, 1.0 }, Final = 5.6, Converter = true, StallRPM = 1800, Crr = 0.04,
			CdA = 8, Mu = 0.9, BrakeMax = 200000, Tick = 1 / Tick })
		Rig.StartEngine(K)
		K.Gear = 1
		local T0 = K.Time
		-- The gearbox's own automatic logic: upshift at set road speeds, lock-up above 75 % speed ratio.
		local ShiftKmh = { 10, 22, 38 }
		local function Auto(V)
			V.Throttle = 1
			local Turbine = V.Gearbox.InputW or 0
			if ShiftKmh[V.Gear] and Rig.Kmh(V) > ShiftKmh[V.Gear] then V.Gear = V.Gear + 1 end
			V.Opts.Lockup = V.Gear >= 2 and (Turbine > 0.75 * V.State.W or V.Opts.Lockup and Turbine > 0.6 * V.State.W)
		end
		Rig.Run(K, K.Time + 40, Auto, function(V)
			if not T32[Tick] and V.Speed >= 32 / 3.6 then T32[Tick] = V.Time - T0 end
			return false
		end)
		check(K.Speed == K.Speed and T32[Tick] and T32[Tick] > 4 and T32[Tick] < 12, "tank 0-32 km/h plausible at " .. Tick, tostring(T32[Tick]))
		check(Rig.Kmh(K) > 55 and Rig.Kmh(K) < 75, "tank top speed near the governor at " .. Tick, Rig.Kmh(K))
	end
	near(T32[16], T32[66], 0.1 * T32[66], "tank 0-32 same at 16 and 66 tick")
	near(T32[128], T32[66], 0.1 * T32[66], "tank 0-32 same at 128 and 66 tick")

	-- Leopard 2 (62 t) on ACE's MB 873 definition as shipped: 1,500 PS at 2,600 rpm through a
	-- 4-speed converter automatic geared for about 70 km/h at 2,600 rpm (68 km/h governed).
	local Leo
	do
		local Saved = ACE.DefineEngine
		function ACE.DefineEngine(Id, Data) if Id == "47.6-V12" then Leo = Data end end
		local F = assert(io.open(root .. "/lua/ace/shared/engines/v12.lua", "rb"))
		assert(loadstring(F:read("*a"), "v12.lua"))()
		F:close()
		ACE.DefineEngine = Saved
	end
	check(Leo ~= nil, "MB 873 definition found")
	local LeoSpec = M.Engine.Build(Leo, ACE.GetEngineTorqueCurve(Leo))
	near(LeoSpec.RatedPower, 1103e3, 0.02 * 1103e3, "MB 873 rated power 1,103 kW")
	local L = Rig.New({ EngineDef = Leo, Mass = 62000, WheelRadius = 0.33, WheelJ = 40, Driven = 2,
		Ratios = { 4.0, 2.4, 1.5, 1.0 }, Final = 4.6, Converter = true, StallRPM = 1600, Crr = 0.04,
		CdA = 8, Mu = 0.9, BrakeMax = 200000, Tick = 1 / 66 })
	Rig.StartEngine(L)
	check(L.State.Running, "MB 873 starts")
	L.Gear = 1
	local L0, L32 = L.Time, nil
	local LeoShift = { 10, 22, 38 }
	Rig.Run(L, L.Time + 40, function(V)
		V.Throttle = 1
		local Turbine = V.Gearbox.InputW or 0
		if LeoShift[V.Gear] and Rig.Kmh(V) > LeoShift[V.Gear] then V.Gear = V.Gear + 1 end
		V.Opts.Lockup = V.Gear >= 2 and (Turbine > 0.75 * V.State.W or V.Opts.Lockup and Turbine > 0.6 * V.State.W)
	end, function(V)
		if not L32 and V.Speed >= 32 / 3.6 then L32 = V.Time - L0 end
		return false
	end)
	check(L32 and L32 > 3 and L32 < 10, "Leopard 2 0-32 km/h plausible", tostring(L32))
	check(Rig.Kmh(L) > 55 and Rig.Kmh(L) < 75 and Rig.RPM(L) < LeoSpec.LimitRPM * 1.07, "Leopard 2 top speed near 68 km/h", Rig.Kmh(L), Rig.RPM(L))

	-- Overdrive: a tall 0.56 top gear. Top speed must be set by drag, below the rev limit.
	local O = car(1 / 66, { CdA = 0.65 })
	Rig.StartEngine(O)
	O.Gear = 1
	Rig.Run(O, O.Time + 120, Rig.LaunchDriver(6000))
	local Before = O.Speed
	Rig.Run(O, O.Time + 5, Rig.LaunchDriver(6000))
	check(O.Gear == #O.Opts.Ratios, "overdrive reaches top gear", O.Gear)
	check(Rig.RPM(O) < O.Spec.LimitRPM * 0.98, "overdrive top speed is below the limiter", Rig.RPM(O))
	check(math.abs(O.Speed - Before) < 0.5 and Rig.Kmh(O) > 200 and Rig.Kmh(O) < 340, "overdrive settles at a drag-limited top speed", Rig.Kmh(O))

	-- High-revving single at 128 tick too.
	local B2 = Rig.New({ EngineDef = Single, Mass = 180, WheelRadius = 0.3, WheelJ = 0.4, Driven = 1,
		Ratios = { 2.8, 2.0, 1.6, 1.3, 1.1, 0.95 }, Final = 2.9, Tick = 1 / 128, Assisted = true, CdA = 0.4 })
	Rig.StartEngine(B2)
	B2.Gear = 1
	Rig.Run(B2, B2.Time + 8, Rig.LaunchDriver(13000))
	check(B2.Speed == B2.Speed and B2.Speed > 5 and Rig.RPM(B2) < 16000, "single stable at 128 tick", Rig.Kmh(B2), Rig.RPM(B2))
end

------------------------------------------------------------------ odd layouts
do
	local Spec = M.Engine.Build(V8, ACE.GenericTorqueCurves.V8)
	local function engine(W)
		local State = M.Engine.NewState(Spec)
		State.W, State.Running = W, true
		return { Spec = Spec, State = State, Throttle = 1, HasFuel = true }
	end
	local function wheel(Key)
		return { Key = Key, J = 1.2, W = 0, Ground = M.Vehicle.Ground(800, 0.33, 0, 0.9, 800 * 9.81, true) }
	end

	-- Ten gearboxes chained end to end (a 12:1 first box, then 1:1), the last on two wheels:
	-- finite, and the wheels turn.
	local Chain, Top = nil, nil
	local Wheels = { wheel("L"), wheel("R") }
	for I = 10, 1, -1 do
		local Box = { Key = "chain" .. I, Ratio = I == 1 and 12 or 1, InputJ = 0.03, ClutchCap = I == 1 and 2000 or nil, Diff = "open",
			Brake = { [0] = 0, [1] = 0 }, Outputs = {} }
		if Chain then
			Box.Outputs[1] = { Side = 0, Gearbox = Chain }
		else
			Box.Outputs[1] = { Side = 0, Wheel = Wheels[1] }
			Box.Outputs[2] = { Side = 1, Wheel = Wheels[2] }
		end
		Chain = Box
		Top = Box
	end
	local E = engine(300)
	E.NoStall = true
	E.Gearboxes = { Top }
	local Sys = M.Drivetrain.Build(E)
	for _ = 1, 66 do M.Drivetrain.Step(Sys, 1 / 66, 8) end
	check(Wheels[1].WOut == Wheels[1].WOut and Wheels[1].WOut > 0.5, "ten chained gearboxes drive the wheels", Wheels[1].WOut)

	-- Two engines on one gearbox: coupled through the same input, both finite, sharing the load.
	local E1, E2 = engine(300), engine(250)
	local Box = { Key = "twin", Ratio = 3, InputJ = 0.03, ClutchCap = 1e5, Diff = "open",
		Brake = { [0] = 0, [1] = 0 }, Outputs = { { Side = 0, Wheel = wheel("A") }, { Side = 1, Wheel = wheel("B") } } }
	E1.Gearboxes, E2.Gearboxes = { Box }, { Box }
	local Twin = M.Drivetrain.Build({ Engines = { E1, E2 } })
	for _ = 1, 66 do M.Drivetrain.Step(Twin, 1 / 66, 8) end
	check(E1.State.W == E1.State.W and E2.State.W == E2.State.W, "twin engines stay finite")
	near(E1.State.W, E2.State.W, 0.05 * E1.State.W, "twin engines turn together through a locked clutch")
end

------------------------------------------------------------------ automatic with converter
do
	local V = car(1 / 66, { Converter = true, StallRPM = 2200 })
	Rig.StartEngine(V)
	V.Gear = 1
	-- Converter creep: in gear at idle the car moves off the brakes, engine stays running.
	Rig.Run(V, V.Time + 3, function(X) X.Throttle = 0 end)
	check(V.State.Running and V.Speed > 0.2, "converter creeps at idle", V.Speed)
	-- Stall speed with the car held on the brakes at full throttle sits near the design point.
	local H = car(1 / 66, { Converter = true, StallRPM = 2200, BrakeMax = 50000 })
	Rig.StartEngine(H)
	H.Gear = 1
	Rig.Run(H, H.Time + 3, function(X) X.Throttle = 1 X.Brake = 1 end)
	near(Rig.RPM(H), 2200, 300, "converter stall speed")
end

------------------------------------------------------------------ dual-clutch box: open diff unless locked
do
	local function dual(Diff)
		local Spec = M.Engine.Build(V8, ACE.GenericTorqueCurves.GenericPetrol)
		local Box = {
			Key = "box", Ratio = 1, Dual = true, Diff = Diff, InputW = 11,
			SideCap = { [0] = 1e4, [1] = 1e4 }, Brake = { [0] = 0, [1] = 0 },
			Outputs = {
				{ Side = 0, Wheel = { Key = "L", J = 3, W = 10 } },
				{ Side = 1, Wheel = { Key = "R", J = 3, W = 12 } },
			},
		}
		local State = M.Engine.NewState(Spec)
		State.W = 11
		local Sys = M.Drivetrain.Build({ Spec = Spec, State = State, Throttle = 0, HasFuel = false, Gearboxes = { Box } })
		M.Drivetrain.Step(Sys, 1 / 66, 8)
		return Box.Outputs[1].Wheel.WOut, Box.Outputs[2].Wheel.WOut
	end
	local L, R = dual("open")
	near(R - L, 2, 0.2, "dual-clutch box differentiates by default")
	L, R = dual("locked")
	near(R - L, 0, 0.05, "dual-clutch box with diff lock is a solid axle")
end

print(("Mobility self-test: PASS (%d assertions)"):format(Passed))

-- Self-tests for electric motors (battery energy, regen) and free power turbines (spool, stall
-- torque, idle fuel) in the mobility engine model. Reference figures are in
-- docs/mobility-sources.md.
local root = assert(arg[1], "usage: ace_mobility_electric_turbine_luajit_selftest.lua <ACE repo>")
root = root:gsub("\\", "/"):gsub("/$", "")

local Rig = dofile(root .. "/tests/lua/mobility_rig.lua")(root)
local M = ACE.Mobility
local E = M.Engine

local RPMToRad = math.pi / 30
local G = 9.80665

local Passed = 0
local Verbose = os.getenv("ACE_TEST_VERBOSE")
local function check(Cond, Label, ...)
	if Verbose then print(Label, ...) end
	if not Cond then error(("FAIL %s %s"):format(Label, table.concat({ ... }, " ")), 2) end
	Passed = Passed + 1
end
local function near(A, B, Tol, Label)
	check(math.abs(A - B) <= Tol, Label, ("got %.4g expected %.4g ±%.3g"):format(A, B, Tol))
end

-- ACE's own definitions, through a stub DefineEngine.
local Defs = {}
function ACE.DefineEngine(Id, Data) Data.id = Id Defs[Id] = Data end
for _, Name in ipairs({ "electric.lua", "turbine.lua" }) do
	local F = assert(io.open(root .. "/lua/ace/shared/engines/" .. Name, "rb"))
	local Src = F:read("*a")
	F:close()
	assert(loadstring(Src, Name))()
end

-- 2012 Nissan LEAF EM61: 280 N·m to 2,730 rpm, 80 kW to 9,800 rpm, 10,390 rpm maximum.
local Leaf = { id = "leaf", name = "LEAF EM61", category = "Electric", fuel = "Electric", enginetype = "Electric",
	torque = 280, idlerpm = 0, limitrpm = 10390, inertia = 0.03 }

local function build(Def) return E.Build(Def, ACE.GetEngineTorqueCurve(Def)) end

-- Steps a lone engine at a fixed shaft speed and returns its state.
local function stepAt(State, RPM, Throttle, Dt, Opts)
	State.W = RPM * RPMToRad
	local Drive, Loss = E.Step(State, Throttle, Dt or 0.01, Opts)
	return Drive, Loss
end

------------------------------------------------------------------ motor torque envelope
do
	local Spec = build(Leaf)
	near(Spec.BrakeWOT(0), 280, 1e-6, "motor gives full torque at 0 rpm")
	near(Spec.BrakeWOT(2000 * RPMToRad), 280, 1, "constant torque below base speed")
	-- Constant power from base speed: 80 kW at 5,000 and 9,000 rpm.
	for _, RPM in ipairs({ 5000, 9000 }) do
		local W = RPM * RPMToRad
		near(Spec.BrakeWOT(W) * W / 1000, 80, 80 * 0.03, "80 kW at " .. RPM .. " rpm")
	end
	near(Spec.RatedPower / 1000, 80, 80 * 0.03, "rated power")
	-- The spline never pushes torque above the rated peak at the knee.
	local Top = 0
	for RPM = 0, 10390, 10 do Top = math.max(Top, Spec.BrakeWOT(RPM * RPMToRad)) end
	check(Top <= 280 + 1e-9, "no torque above peak", Top)
	-- The menu graph samples the same envelope, and shows nothing past the speed limit.
	near(M.EngineCurveSample(Leaf, 0), 280, 1e-6, "graph: full torque at 0 rpm")
	near(M.EngineCurveSample(Leaf, 11000), 0, 0, "graph: no torque past limit")
end

------------------------------------------------------------------ no idle, no stall, no starter
do
	local Spec = build(Leaf)
	local S = E.NewState(Spec)
	E.Start(S)
	check(S.Running and S.Cranking == 0, "motor is live at once, no cranking")
	local Drive = stepAt(S, 0, 0)
	near(Drive, 0, 0, "no idle torque at rest")
	near(S.FuelRate, 0, 1e-9, "no battery draw at rest with no pedal")
	Drive = stepAt(S, 0, 1)
	near(Drive, 280, 1e-6, "full torque from standstill")
	-- Held at 0 rpm under full torque it just stays live: no stall.
	for _ = 1, 100 do stepAt(S, 0, 1) end
	check(S.Running and not S.Stalled, "motor never stalls")
	-- Past the speed limit the inverter stops driving.
	Drive = stepAt(S, 11000, 1)
	near(Drive, 0, 0, "no drive past limit")
	-- Flat battery: no drive, no regen.
	local Drive2, Loss2 = stepAt(S, 5000, 1, 0.01, { HasFuel = false })
	near(Drive2, 0, 0, "flat battery: no drive")
	near(Loss2, E.FrictionTorque(Spec, 5000 * RPMToRad, 0), 1e-9, "flat battery: no regen")
end

------------------------------------------------------------------ motor efficiency and battery draw
do
	local Spec = build(Leaf)
	local S = E.NewState(Spec)
	E.Start(S)
	local function eta(RPM, Throttle)
		local Drive = stepAt(S, RPM, Throttle)
		local Loss = E.FrictionTorque(Spec, RPM * RPMToRad, 0)
		return (Drive - Loss) * RPM * RPMToRad / S.FuelRate
	end
	-- ORNL: combined motor+inverter peak above 96%, wide region above 90%.
	local E1 = eta(6000, 0.5)
	check(E1 > 0.93 and E1 < 0.97, "mid-map efficiency 93-97%", E1)
	local E2 = eta(2700, 1)
	check(E2 > 0.86 and E2 < 0.94, "peak-torque corner efficiency", E2)
	local E3 = eta(500, 0.1)
	check(E3 < E1, "low speed, low torque is less efficient", E3)
	-- Full power: about 85 kW from the battery for 80 kW at the shaft.
	stepAt(S, 6000, 1)
	local Kw = S.FuelRate / 1000
	check(Kw > 82 and Kw < 90, "battery draw at full power (kW)", Kw)
	-- A 24 kWh LEAF pack lasts ~17 minutes at full power.
	local Minutes = 24 * 3.6e6 / S.FuelRate / 60
	check(Minutes > 15 and Minutes < 19, "24 kWh pack at full power (min)", Minutes)
	-- Heat is the losses, not the input.
	check(S.HeatRate > 0 and S.HeatRate < S.FuelRate * 0.1, "motor heat is only the losses", S.HeatRate)
end

------------------------------------------------------------------ regenerative braking
do
	local Spec = build(Leaf)
	local S = E.NewState(Spec)
	E.Start(S)
	local _, Loss = stepAt(S, 4000, 0)
	local Friction = E.FrictionTorque(Spec, 4000 * RPMToRad, 0)
	check(Loss > Friction + 50, "lift-off regen brakes the motor", Loss)
	check(S.FuelRate < 0, "regen charges the battery", S.FuelRate)
	-- Charging power is below the mechanical power taken in (losses on the way back).
	check(-S.FuelRate < S.Regen * 4000 * RPMToRad, "regen loses energy on the way back")
	-- Regen fades out near standstill.
	stepAt(S, 100, 0)
	check(S.Regen < 0.4 * 280 * 0.3, "regen fades at crawl speed", S.Regen)
	stepAt(S, 0, 0)
	near(S.Regen, 0, 0, "no regen at rest")
	-- A full battery refuses charge.
	S.RegenLimitW = 0
	stepAt(S, 4000, 0)
	near(S.Regen, 0, 1e-9, "full battery: no regen")
	check(S.FuelRate >= 0, "full battery: no charging")
	S.RegenLimitW = 10000
	stepAt(S, 4000, 0)
	near(-S.FuelRate, 10000, 10000 * 0.1, "regen held to the battery's charge limit")
	-- Any pedal past the regen band drives instead.
	S.RegenLimitW = nil
	stepAt(S, 4000, 0.2)
	near(S.Regen, 0, 0, "no regen with the pedal pressed")
end

------------------------------------------------------------------ EV in a vehicle
local function leafCar(Tick)
	-- 2012 LEAF: ~1,600 kg with driver, 205/55R16 (0.316 m), 7.94 final drive (Burress 2013).
	return Rig.New({ EngineDef = Leaf, Mass = 1600, WheelRadius = 0.316, WheelJ = 0.9, Driven = 2,
		Ratios = { 1 }, Final = 7.94, Tick = Tick })
end
do
	local V = leafCar(1 / 66)
	M.Engine.Start(V.State)
	V.Gear = 1
	local T0 = V.Time
	local Ok = Rig.Run(V, 30, function(X) X.Throttle = 1 end, function(X) return Rig.Kmh(X) >= 100 end)
	local Launch = V.Time - T0
	-- Published 0-100 km/h for the 2012 LEAF is about 11.5 s.
	check(Ok and Launch > 8 and Launch < 14, "LEAF 0-100 km/h", Launch)
	-- Energy drawn exceeds the kinetic energy gained, but not by much at this power.
	local Ke = 0.5 * V.Mass * V.Speed ^ 2
	local Ratio = Ke / V.FuelKg
	check(Ratio > 0.6 and Ratio < 0.95, "kinetic energy / battery energy on launch", Ratio)

	-- Lift off: the car slows on regen and the battery gets energy back.
	local E0, S0 = V.FuelKg, V.Speed
	local Tl = V.Time
	Rig.Run(V, V.Time + 1, function(X) X.Throttle = 0 end)
	local Decel = (S0 - V.Speed) / (V.Time - Tl) / G
	check(Decel > 0.08 and Decel < 0.25, "lift-off regen deceleration (g)", Decel)
	Rig.Run(V, V.Time + 60, function(X) X.Throttle = 0 end, function(X) return Rig.Kmh(X) < 20 end)
	local Back = E0 - V.FuelKg
	local KeDrop = 0.5 * V.Mass * (S0 ^ 2 - V.Speed ^ 2)
	check(Back > 0.3 * KeDrop and Back < 0.9 * KeDrop, "regen recovers part of the kinetic energy", Back / KeDrop)

	-- Same launch at 16 and 128 tick.
	for _, Tick in ipairs({ 16, 128 }) do
		local W = leafCar(1 / Tick)
		M.Engine.Start(W.State)
		W.Gear = 1
		local Ta = W.Time
		Rig.Run(W, 30, function(X) X.Throttle = 1 end, function(X) return Rig.Kmh(X) >= 100 end)
		near(W.Time - Ta, Launch, Launch * 0.03 + 1 / Tick, "LEAF 0-100 at " .. Tick .. " tick")
	end
end

------------------------------------------------------------------ ACE's motors all behave
do
	for Id, Def in pairs(Defs) do
		if Def.fuel == "Electric" then
			local Spec = build(Def)
			near(Spec.BrakeWOT(0), Def.torque, 1e-6, Id .. " full torque at 0 rpm")
			check(Spec.RatedPower > 0, Id .. " has power")
		end
	end
end

------------------------------------------------------------------ free power turbine
local Agt = assert(Defs["AGT 1500 Large Turbine"], "AGT1500 definition")
do
	local Spec = build(Agt)
	-- Torque rises all the way down to output stall.
	local Prev = math.huge
	for RPM = 0, 3000, 100 do
		local T = Spec.BrakeWOT(RPM * RPMToRad)
		check(T < Prev, "turbine torque falls with output speed at " .. RPM)
		Prev = T
	end
	-- Published line: 5,355 N·m @ 1,000 and 3,754 N·m @ 3,000 rpm, so stall / 3,000 rpm = 1.64.
	local Stall = Spec.BrakeWOT(0)
	local Rated = Spec.BrakeWOT(3000 * RPMToRad)
	near(Stall / Rated, 6155 / 3754, 0.06, "stall torque ratio")
	near(Spec.BrakeWOT(1000 * RPMToRad) / Rated, 5355 / 3754, 0.03, "torque ratio 1,000 / 3,000 rpm")
	near(M.EngineCurveSample(Agt, 0), Stall, 1e-6, "graph shows stall torque")
	check(M.EngineCurveSample(Agt, 3100) == 0, "graph: no torque past limit")

	-- Aero and ground turbine families extrapolate the same way.
	for Id, Def in pairs(Defs) do
		if Def.category == "Turbine" then
			local S = build(Def)
			check(S.BrakeWOT(0) >= Def.torque, Id .. " stall torque at least idle torque")
		end
	end
end

do
	local Spec = build(Agt)
	-- Full power: SFC 0.30 kg/kWh (Forecast International).
	local Full = E.TurbineFuelRate(Spec, 1)
	near(Full * 3600 / (Spec.RatedPower / 1000), 0.30, 0.005, "full-power SFC (kg/kWh)")
	-- Idle: 10 US gal/h at basic idle for the real 1,119 kW engine (GlobalSecurity). ACE's
	-- AGT1500 is stronger than the real one, so scale by rated power.
	local S = E.NewState(Spec)
	E.Start(S)
	for _ = 1, 1000 do stepAt(S, 0, 0, 0.01) end
	local GalH = S.FuelRate * 3600 / 0.80 / 3.785 * (1119e3 / Spec.RatedPower)
	near(GalH, 10, 1, "idle fuel flow (US gal/h, scaled to 1,119 kW)")
	-- Output shaft stalled at full throttle: the gas generator still burns full-power fuel.
	for _ = 1, 1000 do stepAt(S, 0, 1, 0.01) end
	near(S.FuelRate, Full, Full * 0.01, "stalled output burns full-power fuel")
	check(S.Running and not S.Stalled, "free turbine cannot stall")
end

do
	-- Spool from idle to 95% power: first order with 1.2 s, about 3.5 s; within the 5 s of
	-- 14 CFR 33.73. The same at every tickrate and substep size.
	local Spec = build(Agt)
	local function spoolTime(Dt)
		local S = E.NewState(Spec)
		E.Start(S)
		for _ = 1, math.floor(20 / Dt) do stepAt(S, 1500, 0, Dt) end
		local T = 0
		while S.Spool < 0.95 and T < 20 do
			stepAt(S, 1500, 1, Dt)
			T = T + Dt
		end
		return T
	end
	local Ref = spoolTime(1 / 528)
	check(Ref > 2.5 and Ref < 5, "idle to 95% power time", Ref)
	for _, Tick in ipairs({ 16, 33, 66 }) do
		for _, Sub in ipairs({ 2, 8 }) do
			local Dt = 1 / Tick / Sub
			near(spoolTime(Dt), Ref, Dt + 1e-9, ("spool at %d tick x%d"):format(Tick, Sub))
		end
	end
end

do
	-- In a vehicle, held on the brakes in gear: the turbine idles and runs at full throttle with
	-- the output stalled, and never stalls.
	local V = Rig.New({ EngineDef = Agt, Mass = 60000, WheelRadius = 0.33, WheelJ = 20, Driven = 2,
		Ratios = { 4 }, Final = 5, BrakeMax = 1e6 })
	M.Engine.Start(V.State)
	V.Gear = 1
	Rig.Run(V, V.Time + 3, function(X) X.Throttle = 0 X.Brake = 1 end)
	check(V.State.Running and not V.State.Stalled, "turbine idles against the brakes")
	Rig.Run(V, V.Time + 5, function(X) X.Throttle = 1 X.Brake = 1 end)
	check(V.State.Running and not V.State.Stalled, "turbine at full throttle against the brakes")
	check(V.Speed < 0.1, "tank held on the brakes", V.Speed)
	-- Release: a 60 t tank pulls away.
	Rig.Run(V, V.Time + 5, function(X) X.Throttle = 1 X.Brake = 0 end)
	check(V.Speed > 1, "turbine pulls away", V.Speed)
end

print(("Mobility electric/turbine self-test: PASS (%d assertions)"):format(Passed))

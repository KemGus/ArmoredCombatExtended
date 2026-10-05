-- Self-tests for electric motors driving backwards (the Reverse input) and for the battery
-- model (lua/ace/shared/mobility/battery_model.lua): losses, heating and cooling, CC-CV charge
-- acceptance, temperature limits and wear. Reference figures are in docs/mobility-sources.md.
local root = assert(arg[1], "usage: ace_mobility_battery_reverse_luajit_selftest.lua <ACE repo>")
root = root:gsub("\\", "/"):gsub("/$", "")

local Rig = dofile(root .. "/tests/lua/mobility_rig.lua")(root)
do
	local F = assert(io.open(root .. "/lua/ace/shared/mobility/battery_model.lua", "rb"))
	assert(loadstring(F:read("*a"), "battery_model.lua"))()
	F:close()
end
local M = ACE.Mobility
local E = M.Engine
local B = M.Battery

local RPMToRad = math.pi / 30

local Passed = 0
local Verbose = os.getenv("ACE_TEST_VERBOSE")
local function check(Cond, Label, ...)
	if Verbose then print(Label, ...) end
	if not Cond then error(("FAIL %s %s"):format(Label, table.concat({ ... }, " ")), 2) end
	Passed = Passed + 1
end
local function near(A, Bv, Tol, Label)
	check(math.abs(A - Bv) <= Tol, Label, ("got %.4g expected %.4g ±%.3g"):format(A, Bv, Tol))
end

-- 2012 Nissan LEAF EM61, as in the electric/turbine self-test.
local Leaf = { id = "leaf", name = "LEAF EM61", category = "Electric", fuel = "Electric", enginetype = "Electric",
	torque = 280, idlerpm = 0, limitrpm = 10390, inertia = 0.03 }
local Diesel = { id = "5.9-I6", name = "5.9L I6 Diesel", category = "I6", fuel = "Diesel", enginetype = "I6",
	torque = 700, idlerpm = 700, limitrpm = 2600, displacement = 5.9 }

local function build(Def) return E.Build(Def, ACE.GetEngineTorqueCurve(Def)) end

------------------------------------------------------------------ motor direction, standalone
do
	local Spec = build(Leaf)
	local S = E.NewState(Spec)
	E.Start(S)
	check(S.Direction == 1, "motors start in forward")

	S.Direction = -1
	S.W = 0
	local Drive = E.Step(S, 1, 0.01)
	near(Drive, -280, 1, "reverse from standstill: full torque backwards")
	check(S.FuelRate >= 0, "driving backwards draws power", S.FuelRate)

	-- Reverse selected while spinning forwards at 3,000 rpm: the torque opposes rotation and the
	-- energy flows back into the battery.
	S.W = 3000 * RPMToRad
	Drive = E.Step(S, 1, 0.01)
	check(Drive < -200, "reverse selected at speed brakes the rotor", Drive)
	check(S.FuelRate < 0, "that braking charges the battery", S.FuelRate)

	-- With the battery full it can only brake as far as its losses absorb.
	S.RegenLimitW = 0
	local Limited = E.Step(S, 1, 0.01)
	check(math.abs(Limited) < math.abs(Drive) * 0.2, "a full battery limits reverse braking", Limited)
	check(S.FuelRate <= 1, "and takes no charge", S.FuelRate)
	S.RegenLimitW = nil

	-- Driving backwards the motor still stops at its rated top speed.
	S.W = -1.02 * Spec.LimitW
	check(E.Step(S, 1, 0.01) == 0, "no drive past top speed in reverse")

	-- Regen on a negative throttle works in reverse too, and opposes the (negative) rotation.
	S.W = -3000 * RPMToRad
	local D2, Loss = E.Step(S, -1, 0.01)
	check(D2 == 0 and Loss > 200, "regen in reverse brakes", Loss)
	check(S.Torque > 0, "regen torque opposes backward rotation", S.Torque)
	check(S.FuelRate < 0, "regen in reverse charges", S.FuelRate)

	-- Combustion engines ignore a direction.
	local DS = E.NewState(build(Diesel))
	DS.Direction = -1
	DS.Running, DS.Caught = true, true
	DS.W = 1500 * RPMToRad
	local DDrive = E.Step(DS, 1, 0.01)
	check(DDrive > 0, "a diesel still drives forwards", DDrive)
end

------------------------------------------------------------------ vehicle: reverse, then flip at speed
local function leafCar()
	return Rig.New({ EngineDef = Leaf, Mass = 1600, WheelRadius = 0.316, WheelJ = 0.9, Driven = 2,
		Ratios = { 1 }, Final = 7.94 })
end
do
	local V = leafCar()
	E.Start(V.State)
	V.Gear = 1
	V.State.Direction = -1
	Rig.Run(V, 5, function(X) X.Throttle = 0.5 end)
	check(V.Speed < -5, "reverse drives the car backwards without a reverse gear", Rig.Kmh(V))
	check(V.State.W < 0, "the motor turns backwards", Rig.RPM(V))

	-- Flip to forward at full throttle while rolling backwards: the car slows through zero
	-- and then accelerates forwards; the rotor never jumps.
	V.State.Direction = 1
	local MaxJump, Prev = 0, V.State.W
	local Stopped
	local T0 = V.Time
	Rig.Run(V, V.Time + 15, function(X) X.Throttle = 1 end, function(X)
		MaxJump = math.max(MaxJump, math.abs(X.State.W - Prev))
		Prev = X.State.W
		if not Stopped and X.Speed >= 0 then Stopped = X.Time - T0 end
		return X.Speed > 5
	end)
	check(Stopped and Stopped > 0.3, "flipping direction brakes to a stop first", Stopped)
	check(V.Speed > 5, "and then drives forwards", Rig.Kmh(V))
	-- 280 N·m on 0.03 kg·m² plus the car reflected: well under 100 rad/s per tick.
	check(MaxJump < 100, "no instant reversal of the rotor", MaxJump)
end

------------------------------------------------------------------ battery: losses and heat
-- A 16.7 kWh pack: a 20 in cube of ACE battery (docs/mobility-sources.md, Batteries).
local Wh = 16700
local CellKg = Wh / 1000 / 0.27 * 1.35
local Area = 6 * (20 * 0.0254) ^ 2
local Pack = B.Build(Wh, CellKg, 12, Area)
do
	local S = B.NewState(20)
	near(B.Loss1C, 0.0413, 0.001, "1C loss = LG M50 R·I/V")
	near(B.LossW(Pack, S, Wh), 0.0413 * Wh, 1, "loss at 1C")
	near(B.LossW(Pack, S, 2 * Wh) / B.LossW(Pack, S, Wh), 4, 1e-6, "loss grows with the square of power")

	-- Discharge 1 kWh at the terminals over 180 s (20 kW, 1.2C): the store gives more.
	local Stored = B.Transfer(Pack, S, -1000, 180)
	check(Stored < -1000 and Stored > -1060, "discharging takes the loss on top", Stored)
	-- Charging stores less than goes in.
	local In = B.Transfer(Pack, S, 1000, 180)
	check(In < 1000 and In > 940, "charging stores the input less the loss", In)

	-- Heating: 1C for an hour. Without cooling the rise would be the loss energy over C.
	local H = B.NewState(20)
	local Steps = 360
	for _ = 1, Steps do
		B.Transfer(Pack, H, -Wh / Steps, 3600 / Steps)
		B.ThermalStep(Pack, H, 3600 / Steps, 20, 1)
	end
	local Rise = H.T - 20
	local Adiabatic = 0.0413 * Wh * 3600 / Pack.C
	check(Rise > 0.5 * Adiabatic and Rise < Adiabatic, "1C for an hour warms the pack", Rise, Adiabatic)

	-- Cooling to ambient, and the heat time scale makes it faster.
	local C1, C2 = B.NewState(60), B.NewState(60)
	B.ThermalStep(Pack, C1, 600, 20, 1)
	B.ThermalStep(Pack, C2, 600, 20, 2)
	check(C1.T < 60 and C1.T > 20, "a hot pack cools towards ambient", C1.T)
	check(C2.T < C1.T, "ace_heat_timescale speeds cooling", C2.T, C1.T)
	-- Exact step: one long step equals many short ones.
	local L1, L2 = B.NewState(60), B.NewState(60)
	B.ThermalStep(Pack, L1, 100, 20, 2)
	for _ = 1, 100 do B.ThermalStep(Pack, L2, 1, 20, 2) end
	near(L1.T, L2.T, 1e-6, "cooling is step-size independent")
end

------------------------------------------------------------------ battery: CC-CV and temperature limits
do
	local S = B.NewState(25)
	near(B.ChargeAcceptW(Pack, S, 0.1), Wh, 1, "1C constant current when low")
	near(B.ChargeAcceptW(Pack, S, 0.85), Wh, 1, "still CC at the CV point")
	near(B.ChargeAcceptW(Pack, S, 0.95), Wh / 3, 1, "tapering in the CV stage")
	check(B.ChargeAcceptW(Pack, S, 0.999) == 0, "done below the 4 % cut-off current")
	near(B.FullSOC(), 0.994, 1e-3, "reads full at 99.4 %")

	-- Charging from empty to full with the acceptance as the limit: fast CC, slow CV tail.
	local SOC, T, T80 = 0, 0, nil
	while SOC < B.FullSOC() - 1e-4 and T < 5 * 3600 do
		local P = B.ChargeAcceptW(Pack, S, SOC)
		if P <= 0 then break end
		SOC = SOC + P * 10 / 3600 / Wh
		T = T + 10
		if not T80 and SOC >= 0.8 then T80 = T end
	end
	check(T80 and math.abs(T80 / 60 - 48) < 2, "0-80 % in about 48 min at 1C", T80 / 60)
	-- The CV tail: the last 20 % take over half as long again as the first 80 %.
	check(T / 60 > 70 and T / 60 < 100, "a full charge takes 70-100 min", T / 60)

	S.T = 47.5
	near(B.ChargeAcceptW(Pack, S, 0.2), Wh / 2, 1, "charging tapers near 50 °C")
	S.T = 50
	check(B.ChargeAcceptW(Pack, S, 0.2) == 0, "no charging at 50 °C")
	S.T = 55
	check(B.DischargeDerate(S) == 1, "full output to 55 °C")
	S.T = 60
	check(B.DischargeDerate(S) == 0, "no output at 60 °C")
end

------------------------------------------------------------------ battery: wear
do
	-- Calendar: a year at 25 °C, half charge vs full; and hot.
	local function year(SOC, Tc)
		local S = B.NewState(Tc)
		for _ = 1, 365 do B.CalendarAge(S, SOC, 1) end
		return 1 - B.Health(S), S
	end
	local Half = year(0.5, 25)
	local Full = year(1.0, 25)
	local Hot = year(1.0, 45)
	check(Half > 0.01 and Half < 0.06, "a year at 25 °C, 50 %: a few % fade", Half)
	check(Full > 1.5 * Half, "held full ages faster", Full, Half)
	check(Hot > 3 * Full, "held full at 45 °C ages much faster", Hot, Full)
	-- The t^0.75 law continued step by step matches one step.
	local One = B.NewState(25)
	B.CalendarAge(One, 1.0, 365)
	near(1 - B.Health(One), Full, 1e-9, "calendar wear is step-size independent")

	-- Cycling: 500 full cycles (discharge and charge, 1 → 0 → 1) near 3.7 V.
	local S = B.NewState(25)
	local SOC = 1
	local N = 50
	for _ = 1, 500 do
		for _ = 1, N do SOC = SOC - 1 / N B.AddThroughput(S, -1 / N, SOC) end
		for _ = 1, N do SOC = SOC + 1 / N B.AddThroughput(S, 1 / N, SOC) end
	end
	local Fade = 1 - B.Health(S)
	check(Fade > 0.15 and Fade < 0.35, "500 full cycles: 15-35 % fade", Fade)
	check(B.Resistance(S) > 1.2, "and resistance has grown", B.Resistance(S))

	-- The same throughput in shallow cycles wears less.
	local Sh = B.NewState(25)
	SOC = 0.6
	for _ = 1, 500 * 10 do
		for _ = 1, 5 do SOC = SOC - 0.02 B.AddThroughput(Sh, -0.02, SOC) end
		for _ = 1, 5 do SOC = SOC + 0.02 B.AddThroughput(Sh, 0.02, SOC) end
	end
	check(1 - B.Health(Sh) < 0.6 * Fade, "shallow cycling wears less than full cycles", 1 - B.Health(Sh), Fade)

	-- A worn pack loses more to its higher resistance.
	local New = B.NewState(25)
	check(B.LossW(Pack, S, Wh) > B.LossW(Pack, New, Wh), "a worn pack heats more")
end

print(("Mobility battery/reverse self-test: PASS (%d assertions)"):format(Passed))

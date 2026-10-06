-- Self-tests for the engine thermal model (lua/ace/shared/mobility/thermal_model.lua).
-- Prints the headline timings so they can be compared against real engines.
local root = assert(arg[1], "usage: ace_engine_thermal_luajit_selftest.lua <ACE repo>")
root = root:gsub("\\", "/"):gsub("/$", "")

local Rig = dofile(root .. "/tests/lua/mobility_rig.lua")(root)
do
	local F = assert(io.open(root .. "/lua/ace/shared/mobility/thermal_model.lua", "rb"))
	assert(loadstring(F:read("*a"), "thermal_model.lua"))()
	F:close()
end
local M = ACE.Mobility
local Th = M.Thermal

local Passed = 0
local function check(Cond, Label, ...)
	if not Cond then error(("FAIL %s %s"):format(Label, table.concat({ ... }, " ")), 2) end
	Passed = Passed + 1
end

-- The default of ace_heat_timescale and ace_engine_builtin_cooling.
local TimeScale, Builtin = 2, 0.5
local Ambient = 20

-- BMP-2 class: UTD-20, 15.8 L V6 diesel, ~220 kW at 2,600 rpm, 665 kg dry.
local UTD20 = { id = "15.8-V6", name = "15.8L V6 Diesel", category = "V6", fuel = "Diesel", enginetype = "V6",
	torque = 1000, idlerpm = 800, limitrpm = 2600, displacement = 15.8, weight = 665 }
local Spec = M.Engine.Build(UTD20, ACE.GetEngineTorqueCurve(UTD20))

-- A radiator sized for the rest of that heat: 0.6 m² face, 10 cm deep, fan on above 85 °C.
local Front, Depth = 0.6, 0.10
local function radiator(T, SpeedMS)
	local Fan = T.Tc > 85 and 1 or 0
	local UA, Cair = Th.RadiatorAir(Front, Depth, Th.FaceVelocity(Depth, SpeedMS or 0, Fan))
	return { { UA = UA, Cair = Cair } }
end

-- Runs Seconds of real time at a fixed heat input; Dt is the server tick.
local function run(TS, T, Seconds, Dt, HeatW, W, Opts)
	Opts = Opts or {}
	local N = math.floor(Seconds / Dt + 0.5)
	for _ = 1, N do
		Th.Step(T, TS, HeatW, W, Dt * (Opts.Scale or 1), {
			Ambient = Ambient, Running = Opts.Running ~= false,
			Exchangers = Opts.Rad and radiator(T, Opts.Speed) or nil,
			ExtraC = Opts.Rad and 5 * Th.CoolantCPerLitre or 0,
		})
		if Opts.Until and Opts.Until(T) then return true end
	end
	return false
end

-- Real seconds until the coolant reaches Target (Scale 1).
local function timeTo(TS, HeatW, W, Target, Opts)
	local T = Th.NewState(Ambient)
	local Dt, Time = 1 / 66, 0
	Opts = Opts or {}
	while Time < 7200 do
		Th.Step(T, TS, HeatW, W, Dt, { Ambient = Ambient, Running = true,
			Exchangers = Opts.Rad and radiator(T, Opts.Speed) or nil,
			ExtraC = Opts.Rad and 5 * Th.CoolantCPerLitre or 0 })
		Time = Time + Dt
		if T.Tc >= Target then return Time, T end
	end
	return math.huge, T
end

------------------------------------------------------------------ building blocks
do
	-- Cross-flow effectiveness: limits and monotonicity.
	local E0 = Th.CrossFlowEffectiveness(0, 100, 100)
	local E1 = Th.CrossFlowEffectiveness(100, 100, 100)
	local E2 = Th.CrossFlowEffectiveness(1000, 100, 100)
	local Einf = Th.CrossFlowEffectiveness(1e6, 100, 1e9)
	check(E0 == 0 and E1 > 0 and E2 > E1 and E2 < 1, "effectiveness grows with NTU", E1, E2)
	check(math.abs(Einf - 1) < 1e-6, "one side infinite: 1 - exp(-NTU)", Einf)
	-- Incropera table 11.3 check point: cross-flow unmixed, NTU 1, Cr 1 -> ε ≈ 0.48.
	check(math.abs(E1 - 0.48) < 0.02, "cross-flow NTU 1, Cr 1", E1)

	local Lo = Th.RadiatorRating(Front, Depth, Th.FaceVelocity(Depth, 0, 0), 80)
	local Fan = Th.RadiatorRating(Front, Depth, Th.FaceVelocity(Depth, 0, 1), 80)
	local Move = Th.RadiatorRating(Front, Depth, Th.FaceVelocity(Depth, 15, 1), 80)
	check(Lo < Fan and Fan < Move, "fan and ram air add cooling", Lo, Fan, Move)
	print(("radiator 0.6 m² x 10 cm at 80 K ITD: still %.0f kW, fan %.0f kW, fan + 54 km/h %.0f kW"):format(Lo / 1e3, Fan / 1e3, Move / 1e3))

	local TS = Th.Build(Spec, 665, Builtin)
	check(Th.Thermostat(TS, 80) == 0 and Th.Thermostat(TS, 95) == 1, "thermostat 82-95 °C")
	check(Th.Derate(TS, 120) == 1 and Th.Derate(TS, 250) < 0.7, "derate from hot metal")
	check(Th.DamageRate(TS, 190) == 0 and Th.DamageRate(TS, 250) > 0, "damage past 200 °C metal")
	print(("UTD-20 class: rated %.0f kW, coolant heat at rated %.0f kW, %.0f L coolant, metal %.0f kJ/K, coolant %.0f kJ/K"):format(
		Spec.RatedPower / 1e3, TS.RatedHeat / 1e3, TS.CoolantL, TS.Cb / 1e3, TS.Cc / 1e3))
end

------------------------------------------------------------------ coolant share of fuel energy
do
	-- Idle heat straight from the engine model running on the rig.
	local V = Rig.New({ EngineDef = UTD20, Mass = 14000, Ratios = { 5, 3, 2, 1.4, 1 }, Final = 6, WheelRadius = 0.35, Tick = 1 / 66 })
	Rig.StartEngine(V)
	V.Gear = 0
	Rig.Run(V, V.Time + 5)
	local TS = Th.Build(Spec, 665, Builtin)
	local Q, Fuel, Raw = 0, 0, 0
	for _ = 1, 660 do
		Rig.Tick(V)
		local E = V.Sys.Engine
		Q = Q + Th.CoolantHeat(TS, E.HeatJ, E.FuelKg, V.State.Load, V.State.W)
		Raw = Raw + E.HeatJ
		Fuel = Fuel + E.FuelKg * Spec.K.LHV
	end
	local Share = Q / Fuel
	-- Capped at 60% of fuel energy, unless the engine model's own figure (friction included)
	-- is already above that.
	check(Share > 0.3 and Share <= math.max(0.6, Raw / Fuel) + 1e-9, "idle coolant share 30-60% of fuel", Share)
	check(Q >= Raw * 0.8, "idle scaling does not lose heat", Q, Raw)
	print(("idle: fuel %.1f kW, to coolant %.1f kW (%.0f%%)"):format(Fuel / 10 / 1e3, Q / 10 / 1e3, Share * 100))

	-- Full load at rated speed: no scaling.
	local FuelKg = 1
	local HeatJ = FuelKg * Spec.K.LHV * Spec.K.CoolantFrac
	check(math.abs(Th.CoolantHeat(TS, HeatJ, FuelKg, 1, Spec.RatedW) - HeatJ) < 1e-6, "full load keeps the model's share")
	_G.IdleHeatW = Q / 10
end

------------------------------------------------------------------ headline timings
do
	local Rated = Th.Build(Spec, 665, 0).RatedHeat

	-- No radiator and no built-in cooling: pure heat soak.
	local TS0 = Th.Build(Spec, 665, 0)
	local T0 = timeTo(TS0, Rated, Spec.RatedW, 120)
	-- No radiator entity, default built-in cooling.
	local TSb = Th.Build(Spec, 665, Builtin)
	local Tb = timeTo(TSb, Rated, Spec.RatedW, 120)
	check(T0 > 60 and T0 < 600, "no cooling at all: minutes to boil", T0)
	check(Tb > T0 and Tb < 1800, "built-in cooling only delays it", Tb)
	print(("full load, no radiator: 120 °C after %.0f s real (%.0f s game at timescale %g); with no built-in cooling %.0f s real (%.0f s game)"):format(
		Tb, Tb / TimeScale, TimeScale, T0, T0 / TimeScale))

	-- Sustained boiling: the metal climbs until it derates and then damages the engine.
	local T = Th.NewState(Ambient)
	run(TSb, T, 1800, 1 / 33, Rated, Spec.RatedW)
	check(T.Boiling and T.Tc == 120, "coolant held at boiling", T.Tc)
	check(Th.Derate(TSb, T.Tb) < 0.8 and Th.DamageRate(TSb, T.Tb) > 0, "boiling engine derates and wears", T.Tb)
	print(("after 30 min boiling at full load: metal %.0f °C, torque x%.2f, health -%.2f%%/s"):format(T.Tb, Th.Derate(TSb, T.Tb), Th.DamageRate(TSb, T.Tb) * 100))

	-- With a proper radiator: regulated at 90-100 °C.
	local Tr = Th.NewState(Ambient)
	run(TSb, Tr, 3600, 1 / 33, Rated, Spec.RatedW, { Rad = true })
	check(Tr.Tc > 85 and Tr.Tc < 105 and not Tr.Boiling, "radiator holds full load standing", Tr.Tc)
	check(Th.Derate(TSb, Tr.Tb) == 1, "no derate with a radiator", Tr.Tb)
	local Tm = Th.NewState(Ambient)
	run(TSb, Tm, 3600, 1 / 33, Rated, Spec.RatedW, { Rad = true, Speed = 40 / 3.6 })
	check(Tm.Tc <= Tr.Tc + 1e-6 and Tm.Tc > 80, "moving cools better, thermostat still regulates", Tm.Tc)
	print(("full load with radiator: standing %.1f °C coolant / %.0f °C metal, 40 km/h %.1f °C"):format(Tr.Tc, Tr.Tb, Tm.Tc))

	-- Idle warm-up from cold.
	local Tw = timeTo(TSb, _G.IdleHeatW, Spec.IdleW, 82)
	check(Tw > 300 and Tw < 3600, "idle warm-up takes minutes", Tw)
	local Tr2 = Th.NewState(Ambient)
	run(TSb, Tr2, 7200, 1 / 33, _G.IdleHeatW, Spec.IdleW, { Rad = true })
	check(Tr2.Tc > 80 and Tr2.Tc < 95, "idle held at the thermostat", Tr2.Tc)
	print(("idle warm-up to 82 °C: %.1f min real (%.1f min game); settles at %.1f °C"):format(Tw / 60, Tw / 60 / TimeScale, Tr2.Tc))

	-- Engine off after a hard run: no pump, only the skin cools it; slow.
	local Toff = Th.NewState(Ambient)
	run(TSb, Toff, 600, 1 / 33, Rated, Spec.RatedW, { Rad = true })
	local HotMetal = Toff.Tb
	run(TSb, Toff, 600, 1 / 33, 0, 0, { Rad = true })
	-- Heat soak: with the pump stopped the metal's heat moves into the coolant, which warms up
	-- before the whole engine slowly cools through its skin.
	check(Toff.Tb < HotMetal and Toff.Tc > 60, "switched-off engine cools slowly", HotMetal, Toff.Tb, Toff.Tc)
	print(("10 min after switching off from full load: metal %.0f -> %.0f °C, coolant %.0f °C"):format(HotMetal, Toff.Tb, Toff.Tc))
end

------------------------------------------------------------------ tickrate independence
do
	local TS = Th.Build(Spec, 665, Builtin)
	local Rated = TS.RatedHeat
	local function profile(Dt)
		local T = Th.NewState(Ambient)
		local Out = {}
		run(TS, T, 300, Dt, Rated, Spec.RatedW, { Rad = true, Scale = TimeScale })
		Out[1], Out[2], Out[7] = T.Tc, T.Tb, T.To
		run(TS, T, 300, Dt, _G.IdleHeatW, Spec.IdleW, { Rad = true, Scale = TimeScale })
		Out[3], Out[4], Out[8] = T.Tc, T.Tb, T.To
		-- No radiator: boil-over.
		local T2 = Th.NewState(Ambient)
		run(TS, T2, 240, Dt, Rated, Spec.RatedW, { Scale = TimeScale })
		Out[5], Out[6], Out[9] = T2.Tc, T2.Tb, T2.To
		return Out
	end
	local Ref = profile(1 / 128)
	for _, Tick in ipairs({ 16, 33, 66 }) do
		local P = profile(1 / Tick)
		for I = 1, #Ref do
			check(math.abs(P[I] - Ref[I]) < 1.0, "tickrate " .. Tick .. " matches 128", I, P[I], Ref[I])
		end
	end
	print(("tickrate 16..128: full-load radiator %.2f °C, idle %.2f °C, boil-over metal %.1f °C (max spread < 1 K)"):format(Ref[1], Ref[3], Ref[6]))
end

------------------------------------------------------------------ other kinds
do
	-- Gas turbine (AGT1500 class): oil-cooled bearings only, never boils its oil.
	local Agt = { id = "AGT", name = "AGT 1500 Large Turbine", category = "Turbine", fuel = "Multifuel", enginetype = "Turbine",
		torque = 5355, idlerpm = 1000, limitrpm = 3000, weight = 1134 }
	local S = M.Engine.Build(Agt, ACE.GetEngineTorqueCurve(Agt))
	local TS = Th.Build(S, 1134, Builtin)
	local T = Th.NewState(Ambient)
	run(TS, T, 3600, 1 / 33, TS.RatedHeat, S.RatedW)
	check(T.Tc < 120 and Th.Derate(TS, T.Tb) == 1, "turbine oil stays cool at full power", T.Tc)

	-- Electric motor: no implicit cooler, so with nothing linked half its peak losses for an hour
	-- overheat it, and a linked radiator holds them.
	local Leaf = { id = "E", name = "Electric motor", category = "Electric", fuel = "Electric", enginetype = "Electric",
		torque = 280, idlerpm = 10, limitrpm = 10400, weight = 60 }
	local SE = M.Engine.Build(Leaf, ACE.GetEngineTorqueCurve(Leaf))
	local TSE = Th.Build(SE, 60, 1)
	check(TSE.BuiltinUA == 0, "motor has no implicit cooler", TSE.BuiltinUA)
	local TE = Th.NewState(Ambient)
	run(TSE, TE, 3600, 1 / 33, TSE.RatedHeat * 0.5, SE.RatedW)
	check(Th.Derate(TSE, TE.Tb) < 1, "uncooled motor at half its peak losses overheats", TE.Tb)
	local TR = Th.NewState(Ambient)
	run(TSE, TR, 3600, 1 / 33, TSE.RatedHeat * 0.5, SE.RatedW, { Rad = true, Speed = 10 })
	check(TR.Tc < 100 and Th.Derate(TSE, TR.Tb) == 1, "motor with a radiator at half its peak losses stays cool", TR.Tc)
	print(("turbine full power: oil %.0f °C; motor at half peak losses: %.0f °C windings uncooled, %.0f °C coolant with a radiator"):format(T.Tc, TE.Tb, TR.Tc))
end

------------------------------------------------------------------ lubricating oil
do
	local TS = Th.Build(Spec, 665, Builtin)
	local K = TS.K
	check(TS.Co and TS.Co > 0 and TS.Goc > 0, "diesel has a sump oil node")
	print(("UTD-20 class oil: %.0f L, %.0f kJ/K, %.0f kW of the %.0f kW rated heat into the oil, %.1f kW/K to the coolant"):format(
		TS.OilL, TS.Co / 1e3, TS.OilRatedHeat / 1e3, TS.RatedHeat / 1e3, TS.Goc / 1e3))

	-- Walther fit goes through its two data points; viscosity falls with temperature.
	check(math.abs(Th.OilViscosity(TS, 40) - K.OilNu40) < 0.01 * K.OilNu40, "Walther at 40 °C", Th.OilViscosity(TS, 40))
	check(math.abs(Th.OilViscosity(TS, 100) - K.OilNu100) < 0.01 * K.OilNu100, "Walther at 100 °C", Th.OilViscosity(TS, 100))
	local Prev = math.huge
	for C = -30, 160, 10 do
		local Nu = Th.OilViscosity(TS, C)
		check(Nu < Prev, "viscosity falls with temperature", C, Nu)
		Prev = Nu
	end

	-- Friction multiplier: 1 at the fit's reference, about twice at 20 °C, clamped.
	check(math.abs(Th.FrictionMul(TS, K.OilRef) - 1) < 1e-9, "warm oil: friction as fitted")
	local M20 = Th.FrictionMul(TS, 20)
	check(M20 > 1.6 and M20 < 2.4, "20 °C oil about doubles friction", M20)
	check(Th.FrictionMul(TS, -40) == K.FrictionMulMax and Th.FrictionMul(TS, 200) == K.FrictionMulMin, "multiplier clamps")
	check(Th.FrictionMul(TS, nil) == 1, "no oil temperature: no change")

	-- The engine model reads it, and unset means unchanged.
	local W = 1500 * math.pi / 30
	local F1 = M.Engine.FrictionTorque(Spec, W, 0.5)
	Spec.FrictionMul = 2
	local F2 = M.Engine.FrictionTorque(Spec, W, 0.5)
	Spec.FrictionMul = nil
	check(math.abs(F2 - 2 * F1) < 1e-9 and M.Engine.FrictionTorque(Spec, W, 0.5) == F1, "FrictionTorque applies Spec.FrictionMul", F1, F2)
	-- Building the thermal spec with a cold-oil multiplier set gives the same sizing.
	Spec.FrictionMul = 3
	local TSc = Th.Build(Spec, 665, Builtin)
	check(Spec.FrictionMul == 3, "Build leaves the multiplier alone")
	Spec.FrictionMul = nil
	check(math.abs(TSc.RatedHeat - TS.RatedHeat) < 1e-6 and math.abs(TSc.Goc - TS.Goc) < 1e-6, "sizing ignores the multiplier")

	-- Oil share of the heat: friction-driven, capped.
	local Qo = Th.OilHeat(TS, TS.RatedHeat, Spec.RatedW, 1)
	check(Qo > 0.05 * TS.RatedHeat and Qo <= K.OilMaxFrac * TS.RatedHeat + 1e-9, "oil takes a share of rated heat", Qo)

	-- Full load with a radiator: oil runs above the coolant, below the hot-oil warning.
	local T = Th.NewState(Ambient)
	run(TS, T, 3600, 1 / 33, TS.RatedHeat, Spec.RatedW, { Rad = true })
	check(T.To > T.Tc + 5 and T.To < K.OilHot, "full-load oil above coolant, not overheating", T.Tc, T.To)
	check(Th.DamageRate(TS, T.Tb, T.To) == 0, "no oil wear at full load with a radiator")
	print(("full load with radiator: coolant %.1f °C, oil %.1f °C, block %.0f °C; friction x%.2f"):format(T.Tc, T.To, T.Tb, Th.FrictionMul(TS, T.To)))

	-- Energy: at steady state everything the engine makes leaves through radiator and skins.
	local Out = T.Qrad + TS.Gs * (T.Tb - Ambient) + TS.Gos * (T.To - Ambient)
	check(math.abs(Out - TS.RatedHeat) < 0.02 * TS.RatedHeat, "steady state balances", Out, TS.RatedHeat)

	-- Idle warm-up from cold: the oil starts viscous and thins as the engine warms.
	local Tw = Th.NewState(Ambient)
	local Cold = Th.FrictionMul(TS, Tw.To)
	run(TS, Tw, 3600, 1 / 33, _G.IdleHeatW, Spec.IdleW, { Rad = true })
	check(Cold > 1.6 and Th.FrictionMul(TS, Tw.To) < 1.15, "friction falls as the oil warms", Cold, Tw.To)
	print(("idle from 20 °C: friction x%.2f cold, x%.2f after an hour (oil %.0f °C)"):format(Cold, Th.FrictionMul(TS, Tw.To), Tw.To))

	-- Boil-over: the oil follows the coolant up and past its own damage temperature.
	local Tb = Th.NewState(Ambient)
	run(TS, Tb, 1800, 1 / 33, TS.RatedHeat, Spec.RatedW)
	check(Tb.Boiling and Tb.To > Tb.Tc, "boiling engine's oil runs hotter than its coolant", Tb.To)
	check(Th.DamageRate(TS, Tb.Tb, Tb.To) >= Th.DamageRate(TS, Tb.Tb), "hot oil adds wear")
	print(("after 30 min boiling: oil %.0f °C, oil wear %.2f%%/s on top of the block's %.2f%%/s"):format(
		Tb.To, (Th.DamageRate(TS, Tb.Tb, Tb.To) - Th.DamageRate(TS, Tb.Tb)) * 100, Th.DamageRate(TS, Tb.Tb) * 100))

	-- A petrol car engine gets a thinner oil, sized by displacement.
	local Car = { id = "2.0-I4", name = "2.0L I4 Petrol", category = "I4", fuel = "Petrol", enginetype = "I4",
		torque = 200, idlerpm = 800, limitrpm = 6500, displacement = 2.0, weight = 150 }
	local SC = M.Engine.Build(Car, ACE.GetEngineTorqueCurve(Car))
	local TC = Th.Build(SC, 150, Builtin)
	check(TC.OilL and TC.OilL > 2 and TC.OilL < 5, "car sump 2-5 L", TC.OilL)

	-- Motors have no oil; a turbine's coolant is its oil.
	local Leaf = { id = "E", name = "Electric motor", category = "Electric", fuel = "Electric", enginetype = "Electric",
		torque = 280, idlerpm = 10, limitrpm = 10400, weight = 60 }
	local SE = M.Engine.Build(Leaf, ACE.GetEngineTorqueCurve(Leaf))
	local TSE = Th.Build(SE, 60, 1)
	local TE = Th.NewState(Ambient)
	Th.Step(TE, TSE, 1000, SE.RatedW, 1, { Ambient = Ambient, Running = true })
	check(TSE.Co == nil and TE.To == nil and Th.FrictionMul(TSE, TE.To) == 1, "motor has no oil node")
	local Agt = { id = "AGT", name = "AGT 1500 Large Turbine", category = "Turbine", fuel = "Multifuel", enginetype = "Turbine",
		torque = 5355, idlerpm = 1000, limitrpm = 3000, weight = 1134 }
	local SA = M.Engine.Build(Agt, ACE.GetEngineTorqueCurve(Agt))
	local TSA = Th.Build(SA, 1134, Builtin)
	local TA = Th.NewState(Ambient)
	run(TSA, TA, 60, 1 / 33, TSA.RatedHeat, SA.RatedW)
	check(TSA.Co == nil and TA.To == TA.Tc, "turbine oil is its coolant")
end

-- Air-cooled: finned heads cooled by the engine's own air flow plus ram air; the oil is the
-- only liquid. Steady state after an hour of game time.
do
	local function steady(Def, HeatFrac, SpeedFrac, AirSpeed)
		local S = M.Engine.Build(Def, ACE.GetEngineTorqueCurve(Def))
		local TS = Th.Build(S, Def.weight, Builtin)
		local T = Th.NewState(Ambient)
		for _ = 1, 3600 do
			Th.Step(T, TS, TS.RatedHeat * HeatFrac, TS.RatedW * SpeedFrac, 1, { Ambient = Ambient, AirSpeed = AirSpeed, Load = HeatFrac })
		end
		return T, TS
	end
	-- Volkswagen 1.6 L class: ~40 kW, ~110 kg, fan-cooled.
	local VW = { id = "1.6-B4", name = "1.6L Flat 4 Petrol", category = "B4", fuel = "Petrol", enginetype = "B4", cooling = "air",
		torque = 105, idlerpm = 850, limitrpm = 4600, weight = 110 }
	local T, TS = steady(VW, 1, 1, 0)
	check(TS.Kind == "air" and TS.FinArea > 0, "flat four with cooling = air is air-cooled", TS.Kind)
	check(T.Tb > 150 and T.Tb < 250, "VW-class heads at full load standing in the air-cooled range", T.Tb)
	check(T.Tc > 70 and T.Tc < 110, "VW-class oil held by its cooler", T.Tc)
	-- Lycoming O-360-A: 180 hp at 2,700 rpm, 117 kg, four 1.48 L cylinders (Wikipedia). Climbing
	-- at full power (~40 m/s) it should sit under Lycoming's 435 °F (224 °C) climb recommendation
	-- and well above economy cruise.
	local O360 = { id = "5.9-B4", name = "5.9L Flat 4 Petrol", category = "B4", fuel = "Petrol", enginetype = "B4", cooling = "air",
		torque = 474, idlerpm = 700, limitrpm = 2700, weight = 117 }
	local Climb = steady(O360, 1, 1, 40)
	check(Climb.Tb > 190 and Climb.Tb < 224, "O-360 climbing at full power under the 224 C recommendation", Climb.Tb)
	-- Motorcycle single, Yamaha SR500 class (~24 kW at 6,500 rpm): no fan, cools only on riding speed.
	local Single = { id = "0.5-I1", name = "500cc Single", category = "Single", fuel = "Petrol", enginetype = "Single", cooling = "air",
		torque = 37, idlerpm = 1000, limitrpm = 6500, weight = 40, displacement = 0.5 }
	local Hot = steady(Single, 1, 1, 0)
	local Riding = steady(Single, 0.5, 0.6, 25)
	check(Hot.Tb > 260 and Hot.FinV == 0, "fanless single overheats at full load standing", Hot.Tb)
	check(Riding.Tb < 220, "fanless single cruising at 90 km/h stays cool", Riding.Tb)
	-- Ram air helps a fan-cooled engine too.
	local Flying = steady(VW, 1, 1, 40)
	check(Flying.Tb < T.Tb - 5, "ram air lowers head temperature", T.Tb, Flying.Tb)
	-- Engines are liquid-cooled unless they say otherwise.
	local RadialDef = { id = "11.0-R7", name = "11.0 R7 Petrol", category = "Radial", fuel = "Petrol", enginetype = "Radial",
		torque = 1050, idlerpm = 600, limitrpm = 4400, weight = 95 }
	local Radial = M.Engine.Build(RadialDef, ACE.GetEngineTorqueCurve(RadialDef))
	check(not Radial.AirCooled, "a radial without cooling = air is liquid-cooled")
	-- Liquid-cooled engines are untouched.
	check(Th.KindOf(Spec) == "diesel" and not Spec.AirCooled, "UTD-20 stays liquid-cooled")
end

print(("thermal self-test: %d checks passed"):format(Passed))

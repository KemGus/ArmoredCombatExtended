--[[
	Engine thermal model: two lumped masses (engine metal + oil, and the coolant circuit), a wax
	thermostat, a belt-driven water pump, and radiators as cross-flow heat exchangers solved with
	the effectiveness-NTU method. Pure Lua, no GMod calls, so it can be unit-tested under LuaJIT.

	    Cb·dTb/dt = Q_in - Gbc·(Tb - Tc) - Gs·(Tb - Ta)
	    Cc·dTc/dt = Gbc·(Tb - Tc) - Σ G_i·(Tc - Ta)        G_i = ε_i·Cmin_i  (each heat exchanger)

	Q_in is the heat the combustion gas and friction put into the engine's walls; it reaches the
	air only through the coolant (the radiators) and, weakly, through the engine's own skin (Gs).
	The step is solved exactly for conductances frozen over the step, so results do not depend
	on the tickrate.

	References (full list and status in docs/mobility-sources.md, section thermal_model.lua):
	- J. B. Heywood, Internal Combustion Engine Fundamentals, 2nd ed., 2018, ch. 12.
	- MIT 2.61 Internal Combustion Engines lecture notes, lecture 18 "Engine Heat Transfer":
	  heat transfer / fuel energy ∝ BMEP^-0.2 · N^-0.2; material limits (liner oil film ~200 °C,
	  aluminium ~300 °C).
	- Padmaraman et al., "Heat Dissipation Characteristics of a FSAE Racecar Radiator",
	  Int. J. Heat and Technology 39(5), 2021: ε-NTU cross-flow relation, core discharge
	  coefficient 0.75, fan-induced face velocity 1.2 m/s at standstill.
	- Kim & Bullard, Int. J. Refrigeration 25(3), 2002: louvered-fin air-side h grows about as
	  the square root of face velocity (j ∝ Re^-0.49).
	- Hella thermostat range brochure: wax thermostats start to open at 78-82 °C, fully open 95 °C.
	- Cummins QSB5.9-G1 genset spec sheet; Kharkiv V-2 family: cooling system 90-95 L.
]]

ACE = ACE or {}
ACE.Mobility = ACE.Mobility or {}

local Thermal = {}
ACE.Mobility.Thermal = Thermal

local max  = math.max
local min  = math.min
local abs  = math.abs
local exp  = math.exp
local sqrt = math.sqrt

local function clamp(V, Lo, Hi)
	if V < Lo then return Lo end
	if V > Hi then return Hi end
	return V
end

-- Coolant: 50/50 ethylene glycol near 90 °C, cp 3.5 kJ/(kg·K), density 1.05 kg/L (MEGlobal
-- ethylene glycol product guide, tables for 50 vol-%). Turbines circulate oil: cp 2.0, 0.87 kg/L.
local GlycolC = 3500 * 1.05 -- J/(K·L)
local OilC    = 2000 * 0.87 -- J/(K·L)
Thermal.CoolantCPerLitre = GlycolC

-- Air at ~40 °C through a radiator.
local AirRho, AirCp = 1.13, 1007

--[[
	Per-kind constants.
	LPerKW: coolant in the whole circuit per kW of rated power. Published: Kharkiv V-2 family
	  90-95 L at 370-580 kW (0.16-0.25), Cummins QSB5.9-G1 genset 25.6 L at 137 kW (0.19);
	  passenger cars carry less (~0.06). 0.15 is used where no displacement is known.
	LPerLitre: coolant per litre of displacement, used when the engine has one. It scales with
	  the size of the water jackets rather than the power: V-2 90-95 L for 38.9 L (2.4), and
	  passenger cars about 2-3.5 L per litre (6-7 L on a 2 L engine). 2.3 is used (estimated).
	  Sizing by power gave a 6.2 L petrol V6 about 50 L, four times a car's circuit, and idle
	  warm-up took most of an hour.
	WarmFrac: share of the engine's dry mass that warms with the coolant (block, head, oil).
	  Starter, alternator, flywheel, bellhousing and brackets are outside the water jacket and
	  lag far behind; 0.6 is used (estimated). With it a car engine idles up to the thermostat
	  in about 15-20 minutes and much faster when driven, as real ones do.
	BlockCp: effective specific heat of an engine's mass [J/(kg·K)]: cast iron 460, steel 490,
	  aluminium 900, with some oil (2,000); 500 for a mostly-iron diesel.
	DeltaBlock: how far the engine metal sits above the coolant at rated heat [K]. The MIT 2.61
	  lecture shows a head at 2000 rpm WOT with coolant at 95 °C running 120-200 °C depending on
	  location; 25 K is used for the lumped average (estimated).
	PumpDeltaT: coolant temperature rise through the engine at rated heat [K]; sets the pump's
	  flow. 5-10 K is the usual design range; 7 K is used (estimated).
	Open / Full: thermostat start-to-open and fully-open coolant temperatures [°C] (Hella).
	Boil: coolant boiling point under the pressure cap [°C]. A 1 bar gauge cap puts water at
	  120 °C (steam tables, 2 bar abs = 120.2 °C); glycol raises it a little, not credited.
	FilmBoil: fraction of the metal-to-coolant conductance left once the coolant boils. Past the
	  critical heat flux a vapour film insulates the wall (the Nukiyama boiling curve drops the
	  heat transfer coefficient by an order of magnitude); 0.2 is a lumped average (estimated).
	Derate*, Damage*: engine metal temperatures [°C]. Above DerateStart a hot charge and, for
	  spark ignition, knock-limited spark retard cost torque, falling linearly to DerateMin at
	  DerateEnd. Past DamageStart (the liner oil film limit, ~200 °C per MIT 2.61) the engine
	  loses health at DamageRate of its maximum per second per 50 K. These shapes are estimated
	  for gameplay; the anchoring temperatures are cited.
	CoolantMax: most of the fuel energy that can go to the coolant at light load (20-60% range,
	  FSAE wiki "Cooling"; Heywood ch. 12).
	Builtin: multiplier on ace_engine_builtin_cooling for this kind (how generously the engine's
	  own cooling is sized).
]]
Thermal.Kinds = {
	liquid = {
		LPerKW = 0.15, LPerLitre = 2.3, WarmFrac = 0.6, FluidC = GlycolC, BlockCp = 500, DeltaBlock = 25, PumpDeltaT = 7,
		Open = 82, Full = 95, Boil = 120, FilmBoil = 0.2,
		DerateStart = 150, DerateEnd = 250, DerateMin = 0.6,
		DamageStart = 200, DamageRate = 0.005, CoolantMax = 0.6, Builtin = 1,
	},
	si = {
		-- As liquid, but knock makes spark-ignition engines lose more torque when hot.
		LPerKW = 0.15, LPerLitre = 2.3, WarmFrac = 0.6, FluidC = GlycolC, BlockCp = 500, DeltaBlock = 25, PumpDeltaT = 7,
		Open = 82, Full = 95, Boil = 120, FilmBoil = 0.2,
		DerateStart = 140, DerateEnd = 250, DerateMin = 0.5,
		DamageStart = 200, DamageRate = 0.005, CoolantMax = 0.6, Builtin = 1,
	},
	electric = {
		-- Liquid-cooled motor and inverter on an electric pump: no thermostat. The windings are
		-- the "metal"; class H insulation is rated to 180 °C (IEC 60085), so damage starts
		-- there and torque is limited from 150 °C the way motor controllers derate.
		LPerKW = 0.03, FluidC = GlycolC, BlockCp = 450, DeltaBlock = 40, PumpDeltaT = 5,
		Open = -273, Full = -272, Boil = 120, FilmBoil = 0.2, ElectricPump = true,
		DerateStart = 150, DerateEnd = 200, DerateMin = 0.5,
		-- No implicit cooler: a standalone motor is cooled only by the radiators linked to it,
		-- and a motor housing with room for a core gets that core modelled as a real exchanger
		-- (ENT:UpdateBuiltinCooler). An implicit one sized at half the rated heat kept every
		-- motor cool with nothing linked.
		DamageStart = 180, DamageRate = 0.005, Builtin = 0,
	},
	turbine = {
		-- Air-cooled by its own through-flow; only bearing and gearbox oil is cooled (CoolantFrac
		-- 0.02 in engine_model.lua). The oil cooler is generously sized; oil does not boil here.
		LPerKW = 0.02, FluidC = OilC, BlockCp = 500, DeltaBlock = 30, PumpDeltaT = 10,
		Open = 80, Full = 95, Boil = 200, FilmBoil = 1,
		DerateStart = 200, DerateEnd = 300, DerateMin = 0.8,
		DamageStart = 250, DamageRate = 0.005, Builtin = 3,
	},
}
Thermal.Kinds.diesel = Thermal.Kinds.liquid
Thermal.Kinds.rotary = Thermal.Kinds.si

-- Heat transfer coefficient from an engine's outer skin: natural convection to air is
-- 2-25 W/(m²·K) (Incropera, Fundamentals of Heat and Mass Transfer, table 1.1). Engines sit in
-- a hull, so no speed dependence is credited.
local SkinH = 10
-- Packaged engine density used to estimate its skin area from its mass [kg/m³] (estimated:
-- a 665 kg UTD-20 fills about 0.8 m³).
local EngineDensity = 800

--[[
	Radiator air side. Louvered-fin automotive cores: area density ~1,200 m²/m³ (Shah & Sekulić,
	Fundamentals of Heat Exchanger Design, 2003: compact automotive cores 1,000-2,500 m²/m³),
	air-side h ≈ 85 W/(m²·K) with fin efficiency at 5 m/s face velocity, scaling as v^0.5 (Kim &
	Bullard 2002). The air side dominates a compact core's thermal resistance (the louvered-fin
	literature puts it at 80% or more), so the coolant side and tube walls are taken as ideal, as
	Padmaraman et al. 2021 do for the walls.
]]
Thermal.CoreAreaDensity = 1200
Thermal.CoreH5          = 85
-- Face velocities [m/s]. A fan sized at ~30 W per litre of core moves ~4 m/s through a 4-5 cm
-- core (P = Δp·Q/η with Δp ≈ 150 Pa and η ≈ 0.4); the fan power scales with core volume, so the
-- velocity holds for thicker cores. The FSAE rig measured 1.2 m/s from a small fan. Still air
-- still draws ~0.3 m/s by natural draught through a hot core (estimated).
Thermal.FanFace     = 4
Thermal.NaturalFace = 0.3
-- Ram air: the bare-core discharge coefficient is 0.75 (Padmaraman et al.); installed behind
-- grilles or armour louvres about half of that reaches the core (estimated), and a thicker
-- core than 5 cm lets through less, as the square root of its depth.
Thermal.RamCoeff  = 0.4
Thermal.RamDepth0 = 0.05

--- Picks the thermal kind for an engine spec.
-- @param Spec Engine spec from ACE.Mobility.Engine.Build.
-- @return string Key into Thermal.Kinds.
function Thermal.KindOf(Spec)
	return Spec.Kind or "liquid"
end

--- Effectiveness of a cross-flow heat exchanger, both fluids unmixed (Incropera eq. 11.32,
-- as used by Padmaraman et al. 2021).
-- @param UA number Overall conductance [W/K].
-- @param Ca number Capacity rate of one stream [W/K].
-- @param Cb number Capacity rate of the other stream [W/K].
-- @return number Effectiveness 0..1, and Cmin [W/K].
function Thermal.CrossFlowEffectiveness(UA, Ca, Cb)
	local Cmin, Cmax = min(Ca, Cb), max(Ca, Cb)
	if Cmin <= 0 or UA <= 0 then return 0, 0 end
	local Ntu = UA / Cmin
	local Cr = Cmin / Cmax
	if Cr < 1e-6 then return 1 - exp(-Ntu), Cmin end
	local Eps = 1 - exp((1 / Cr) * Ntu ^ 0.22 * (exp(-Cr * Ntu ^ 0.78) - 1))
	return clamp(Eps, 0, 1), Cmin
end

--- Air side of a radiator core at a given face velocity.
-- @param FrontM2 number Frontal (face) area [m²].
-- @param DepthM number Core depth along the airflow [m].
-- @param Face number Face velocity [m/s].
-- @return number UA [W/K] and air capacity rate [W/K].
function Thermal.RadiatorAir(FrontM2, DepthM, Face)
	Face = max(Face, 0.05)
	local H = Thermal.CoreH5 * sqrt(Face / 5)
	local UA = H * Thermal.CoreAreaDensity * FrontM2 * DepthM
	local Cair = AirRho * AirCp * Face * FrontM2
	return UA, Cair
end

--- Face velocity through a radiator core from vehicle speed and its fan.
-- @param DepthM number Core depth [m].
-- @param SpeedMS number Vehicle speed [m/s].
-- @param Fan number Fan speed fraction 0..1.
-- @return number Face velocity [m/s].
function Thermal.FaceVelocity(DepthM, SpeedMS, Fan)
	local Ram = Thermal.RamCoeff * abs(SpeedMS) * sqrt(Thermal.RamDepth0 / max(DepthM, Thermal.RamDepth0))
	local FanV = Thermal.FanFace * clamp(Fan or 0, 0, 1)
	-- Fan and ram pressures add; pressure goes as velocity squared.
	return max(sqrt(Ram * Ram + FanV * FanV), Thermal.NaturalFace)
end

--- Heat rejected by a radiator with unrestricted coolant flow, for menus and overlays.
-- @param FrontM2 number Frontal area [m²].
-- @param DepthM number Core depth [m].
-- @param Face number Face velocity [m/s].
-- @param ITD number Coolant inlet minus air temperature [K].
-- @return number Heat rejected [W].
function Thermal.RadiatorRating(FrontM2, DepthM, Face, ITD)
	local UA, Cair = Thermal.RadiatorAir(FrontM2, DepthM, Face)
	local Eps, Cmin = Thermal.CrossFlowEffectiveness(UA, Cair, 1e12)
	return Eps * Cmin * ITD
end

-- Heat the engine rejects to its coolant at rated power [W], from the engine model itself.
local function ratedHeat(Spec)
	local E = ACE.Mobility.Engine
	local K = Spec.K
	local W = Spec.RatedW
	if Spec.Kind == "electric" then
		return E.MotorLoss(Spec, Spec.BrakeWOT(W)) + E.FrictionTorque(Spec, W, 0) * W
	end
	if Spec.Kind == "turbine" then
		return E.TurbineFuelRate(Spec, 1) * K.LHV * K.CoolantFrac
	end
	local Pfuel = E.IndicatedWOT(Spec, W) * W / K.EtaIndicated
	return Pfuel * K.CoolantFrac + E.FrictionTorque(Spec, W, 1) * W
end

--- Builds an engine's thermal description.
-- @param Spec Engine spec from ACE.Mobility.Engine.Build.
-- @param MassKg number Engine mass [kg].
-- @param Builtin number Built-in cooling: heat the engine's own cooling system rejects at
-- 100 °C coolant, 20 °C air and rated pump speed, as a fraction of rated heat (0 = none).
-- @return table Thermal spec.
function Thermal.Build(Spec, MassKg, Builtin)
	local Kind = Thermal.KindOf(Spec)
	local K = Thermal.Kinds[Kind] or Thermal.Kinds.liquid
	local Qr = max(ratedHeat(Spec), 100)
	local Pkw = max(Spec.RatedPower or 0, 1000) / 1000
	MassKg = max(MassKg or 100, 10)

	local S = {
		Kind = Kind, K = K, EngineSpec = Spec,
		RatedHeat = Qr,
		RatedW = max(Spec.RatedW or 1, 1),
		CoolantL = max((K.LPerLitre and Spec.DispL) and K.LPerLitre * Spec.DispL or Pkw * K.LPerKW, 1),
		Cb = MassKg * (K.WarmFrac or 1) * K.BlockCp,
		Gbc = Qr / K.DeltaBlock,
		PumpC = Qr / K.PumpDeltaT,
	}
	S.Cc = S.CoolantL * K.FluidC
	local Area = 6 * (MassKg / EngineDensity) ^ (2 / 3)
	S.Gs = SkinH * Area

	-- The built-in cooling system is a heat exchanger with a belt-driven fan: its air flow is
	-- twice the coolant capacity rate at rated speed, and its UA is found so that it rejects
	-- the requested share at 100 °C coolant and 20 °C air.
	S.BuiltinCair = 2 * S.PumpC
	S.BuiltinUA = 0
	local Target = max(Builtin or 0, 0) * K.Builtin * Qr
	if Target > 0 then
		local Lo, Hi = 0, Qr * 100
		for _ = 1, 60 do
			local Mid = 0.5 * (Lo + Hi)
			local Eps, Cmin = Thermal.CrossFlowEffectiveness(Mid, S.PumpC, S.BuiltinCair)
			if Eps * Cmin * 80 < Target then Lo = Mid else Hi = Mid end
		end
		S.BuiltinUA = 0.5 * (Lo + Hi)
	end
	return S
end

--- Creates the runtime state, everything at ambient.
-- @param Ambient number Air temperature [°C].
function Thermal.NewState(Ambient)
	return { Tb = Ambient, Tc = Ambient, Qrad = 0, Vented = 0, Thermostat = 0 }
end

--- Share of the engine's heat input that goes to the coolant, scaled for load and speed.
-- engine_model.lua charges a fixed CoolantFrac of fuel energy (its full-load value). Heat
-- transfer per unit fuel energy grows at light load and low speed as BMEP^-0.2 · N^-0.2 (MIT
-- 2.61 lecture 18, from Nu ∝ Re^0.8), up to CoolantMax of the fuel energy.
-- @param TS table Thermal spec.
-- @param HeatJ number Heat the engine model reported (fuel share plus friction) [J].
-- @param FuelKg number Fuel burned over the same interval [kg].
-- @param Load number Air/fuel fraction 0..1.
-- @param W number Crank speed [rad/s].
-- @return number Heat into the engine metal [J].
function Thermal.CoolantHeat(TS, HeatJ, FuelKg, Load, W)
	local Spec = TS.EngineSpec
	local EK = Spec.K
	if not EK.EtaIndicated or Spec.Kind == "turbine" or (FuelKg or 0) <= 0 then return max(HeatJ or 0, 0) end
	local FuelJ = FuelKg * EK.LHV
	local Base = FuelJ * EK.CoolantFrac
	local Friction = max(HeatJ - Base, 0)
	local Scale = clamp(Load or 1, 0.05, 1) ^ -0.2 * clamp(abs(W or 0) / TS.RatedW, 0.1, 1) ^ -0.2
	-- Friction work ends up in the oil and coolant too; the total stays within CoolantMax.
	return min(Base * Scale + Friction, max((TS.K.CoolantMax or 1) * FuelJ, Base + Friction))
end

--- Thermostat opening 0..1 at a coolant temperature.
function Thermal.Thermostat(TS, Tc)
	local K = TS.K
	return clamp((Tc - K.Open) / (K.Full - K.Open), 0, 1)
end

--- Torque multiplier from the engine metal temperature.
-- @return number 1 when healthy, down to the kind's DerateMin.
function Thermal.Derate(TS, Tb)
	local K = TS.K
	local F = clamp((Tb - K.DerateStart) / (K.DerateEnd - K.DerateStart), 0, 1)
	return 1 - (1 - K.DerateMin) * F
end

--- Health lost per second, as a fraction of maximum health, from the engine metal temperature.
function Thermal.DamageRate(TS, Tb)
	local K = TS.K
	return max(Tb - K.DamageStart, 0) / 50 * K.DamageRate
end

-- Exact solution of the linear two-node system over H seconds, conductances frozen.
-- u = Tb - Ta, v = Tc - Ta:  Cb·u' = P - Gbc(u - v) - Gs·u,  Cc·v' = Gbc(u - v) - Gr·v.
-- Gs > 0 keeps the system non-singular; its eigenvalues are real and negative.
local function solve2(u, v, P, Cb, Cc, Gbc, Gs, Gr, H)
	local a11, a12 = -(Gbc + Gs) / Cb, Gbc / Cb
	local a21, a22 = Gbc / Cc, -(Gbc + Gr) / Cc
	-- Fixed point.
	local Vs = P / (Gr + Gs * (Gbc + Gr) / Gbc)
	local Us = Vs * (Gbc + Gr) / Gbc
	local du, dv = u - Us, v - Vs

	local Tr = a11 + a22
	local Det = a11 * a22 - a12 * a21
	local Disc = max(Tr * Tr / 4 - Det, 0)
	local Root = sqrt(Disc)
	local L1, L2 = Tr / 2 + Root, Tr / 2 - Root
	local E11, E12, E21, E22
	if Root * H < 1e-9 then
		-- Repeated eigenvalue: e^{AH} = e^{LH}(I + (A - LI)H).
		local E = exp(L1 * H)
		E11, E12 = E * (1 + (a11 - L1) * H), E * a12 * H
		E21, E22 = E * a21 * H, E * (1 + (a22 - L1) * H)
	else
		-- Sylvester: e^{AH} = [e^{L1 H}(A - L2 I) - e^{L2 H}(A - L1 I)] / (L1 - L2).
		local X1, X2 = exp(L1 * H), exp(L2 * H)
		local D = L1 - L2
		E11 = (X1 * (a11 - L2) - X2 * (a11 - L1)) / D
		E12 = (X1 - X2) * a12 / D
		E21 = (X1 - X2) * a21 / D
		E22 = (X1 * (a22 - L2) - X2 * (a22 - L1)) / D
	end
	return Us + E11 * du + E12 * dv, Vs + E21 * du + E22 * dv
end

--- Advances the thermal state.
-- @param T table State from Thermal.NewState.
-- @param TS table Thermal spec.
-- @param Heat number Heat input to the engine metal [W].
-- @param W number Crank speed [rad/s] (drives the water pump and built-in fan).
-- @param H number Step length [s] (already multiplied by any time scale).
-- @param Opts table|nil { Ambient = °C, Running = bool (electric pump), Exchangers = {
-- { UA = W/K, Cair = W/K }, ... }, ExtraC = extra coolant heat capacity from radiators [J/K] }.
function Thermal.Step(T, TS, Heat, W, H, Opts)
	if H <= 0 then return T end
	local K = TS.K
	local Ta = Opts and Opts.Ambient or 20
	local Exchangers = Opts and Opts.Exchangers

	-- Pump: belt-driven, flow proportional to crank speed; electric pumps run while switched on.
	local PumpFrac
	if K.ElectricPump then
		PumpFrac = (Opts and Opts.Running) and 1 or 0
	else
		PumpFrac = clamp(abs(W) / TS.RatedW, 0, 1.2)
	end
	local X = Thermal.Thermostat(TS, T.Tc)
	T.Thermostat = X
	local Flow = X * TS.PumpC * PumpFrac

	-- Coolant flow divides between the built-in cooler and linked radiators by conductance.
	local BuiltinUA = TS.BuiltinUA * PumpFrac
	local SumUA = BuiltinUA
	if Exchangers then
		for I = 1, #Exchangers do SumUA = SumUA + Exchangers[I].UA end
	end

	local Gr = 0
	if Flow > 0 and SumUA > 0 then
		if BuiltinUA > 0 then
			local Eps, Cmin = Thermal.CrossFlowEffectiveness(BuiltinUA, Flow * BuiltinUA / SumUA, TS.BuiltinCair * PumpFrac)
			Gr = Gr + Eps * Cmin
		end
		if Exchangers then
			for I = 1, #Exchangers do
				local X2 = Exchangers[I]
				local Eps, Cmin = Thermal.CrossFlowEffectiveness(X2.UA, Flow * X2.UA / SumUA, X2.Cair)
				local G = Eps * Cmin
				X2.G = G
				Gr = Gr + G
			end
		end
	elseif Exchangers then
		for I = 1, #Exchangers do Exchangers[I].G = 0 end
	end

	-- Film boiling: the metal-to-coolant conductance collapses over the last 3 K to boiling.
	local Boil = clamp((T.Tc - (K.Boil - 3)) / 3, 0, 1)
	local Gbc = TS.Gbc * (1 - (1 - K.FilmBoil) * Boil)
	local Cc = TS.Cc + (Opts and Opts.ExtraC or 0)

	local U, V = solve2(T.Tb - Ta, T.Tc - Ta, max(Heat, 0), TS.Cb, Cc, Gbc, TS.Gs, Gr, H)
	T.Tb, T.Tc = U + Ta, V + Ta

	-- The pressure cap holds the coolant at its boiling point; the excess leaves as steam.
	T.Boiling = T.Tc >= K.Boil
	if T.Boiling then
		T.Vented = T.Vented + (T.Tc - K.Boil) * Cc
		T.Tc = K.Boil
	end
	T.Qrad = Gr * (T.Tc - Ta)
	return T
end

return Thermal

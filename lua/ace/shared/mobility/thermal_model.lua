--[[
	Engine thermal model: three lumped masses (the engine metal, the coolant circuit and the
	lubricating oil), a wax thermostat, a belt-driven water pump, and radiators as cross-flow heat
	exchangers solved with the effectiveness-NTU method. Pure Lua, no GMod calls, so it can be
	unit-tested under LuaJIT.

	    Cb·dTb/dt = Q_in - Q_oil - Gbc·(Tb - Tc) - Gs·(Tb - Ta)
	    Cc·dTc/dt = Gbc·(Tb - Tc) + Goc·(To - Tc) - Σ G_i·(Tc - Ta)   G_i = ε_i·Cmin_i
	    Co·dTo/dt = Q_oil - Goc·(To - Tc) - Gos·(To - Ta)

	Q_in is the heat the combustion gas and friction put into the engine; it reaches the air only
	through the coolant (the radiators) and, weakly, through the engine's own skin (Gs) and oil
	pan (Gos). Q_oil is the part of it dissipated in the oil: most of the bearing, valve train
	and ring friction, and a little of the piston's gas heat (Heywood ch. 12-13). The oil gives
	it up to the coolant through the oil cooler and the coolant-jacketed crankcase (Goc). The
	metal-coolant pair is solved exactly for conductances frozen over the step, and the oil node
	exactly against the coolant temperature at the start of the step, so results do not depend
	on the tickrate. The oil's temperature sets its viscosity, and with it the engine's rubbing
	friction (Thermal.FrictionMul).

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
	- ASTM D341: Walther viscosity-temperature relation for petroleum oils. SAE J300: engine oil
	  viscosity grades (kinematic viscosity at 100 °C).
	- Incropera, table A.5: properties of engine oil.
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
-- ethylene glycol product guide, tables for 50 vol-%). Engine oil: cp 2.0 kJ/(kg·K), 0.87 kg/L
-- (Incropera table A.5, unused engine oil: cp 1.91-2.34 kJ/(kg·K) and 0.88-0.83 kg/L over
-- 300-400 K). Turbines circulate oil as their coolant; piston engines carry it in the sump.
local GlycolC = 3500 * 1.05 -- J/(K·L)
local OilC    = 2000 * 0.87 -- J/(K·L)
Thermal.CoolantCPerLitre = GlycolC
Thermal.OilCPerLitre = OilC

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
	  aluminium 900; 500 for a mostly-iron diesel. The sump oil is its own node (Oil* below).
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

	Lubricating oil (piston and rotary engines; turbines circulate oil as their coolant, OilIsCoolant,
	and motors have none, NoOil):
	OilLPerLitre: sump oil per litre of displacement. Service fill capacities run about 2-2.7 L
	  per litre on heavy-duty diesels (a 5.9 L Cummins B-series ~14 L, 15 L truck engines ~40 L)
	  and 1-2 L per litre on petrol engines (4-4.5 L on a 2 L four, 5-8 L on a 6 L V8): 2.0 for
	  diesels and 1.5 for petrol engines are used (estimated from service data, not re-checked).
	  OilLPerKW is the fallback with no displacement (0.1 L/kW, estimated).
	OilFricFrac: share of the friction work dissipated in the oil rather than the liner. Heywood
	  ch. 13 splits rubbing friction about half to the pistons and rings, the rest to bearings,
	  valve train and auxiliaries; the bearings and valve train heat their oil, and about half of
	  the ring friction heats the liner wall instead: 0.6 (estimated).
	OilGasFrac: share of the combustion gas heat reaching the oil, through the piston crown,
	  undercrown and rings (oil-cooled pistons): 0.05 (estimated). OilMaxFrac caps the oil's share
	  of all the engine's heat at 0.5 (estimated), for idle where friction is all the work done.
	OilDelta: oil above the coolant at rated heat [K]. Sump oil commonly runs 100-120 °C at full
	  load with the coolant at 90-95 °C; 20 K is used (estimated). It sets the oil cooler and
	  crankcase conductance Goc, which falls to OilStill of it with the oil pump stopped (the
	  pump is gear-driven off the crank; 0.2, estimated: the sump still conducts into the block).
	OilNu40, OilNu100: kinematic viscosity of the oil [mm²/s] at 40 and 100 °C, interpolated with
	  the ASTM D341 Walther relation. Diesels: SAE 15W-40 (SAE J300 grade 40 is 12.5-16.3 mm²/s
	  at 100 °C; 14.5 and 110 at 40 °C as typical heavy-duty oil data sheets give). Petrol:
	  SAE 10W-30 (grade 30 is 9.3-12.5; 10.5 and 70).
	OilRef: oil temperature at which the friction model's fits apply [°C]. The FMEP constants
	  in engine_model.lua were fitted to motoring tests of fully warm engines: 90 (estimated).
	ViscExp: friction multiplier = (ν / ν_ref)^ViscExp. Hydrodynamic film friction grows with
	  viscosity, boundary and mixed friction does not, so FMEP grows much more slowly than the
	  viscosity: 0.24 (estimated) gives a 20 °C engine about twice its warm friction and 0 °C
	  about 2.8 times, in line with cold-start friction measurements (Heywood ch. 13 notes
	  friction falls substantially as the oil warms). FrictionMulMin and FrictionMulMax clamp it:
	  thinned oil saves little once the film is down to boundary contact (0.8), and the curve is
	  not extrapolated past 4, reached near -15 °C (both estimated).
	OilHot: the overlay warns of hot oil above this [°C]. OilDamageStart: past it the oil film
	  thins and oxidises fast enough to wear bearings and rings [°C]. API engine oil oxidation
	  tests (Sequence IIIG/IIIH) hold the oil at about 150 °C, the top of what oils are qualified
	  for (as recalled, not re-checked); 130 and 150 are used. Wear then runs at OilDamageRate of
	  maximum health per second per 50 K, as the block does (estimated).
]]
-- Oil properties shared by the piston-engine kinds; the grade differs.
local function oilKind(K, Grade)
	K.OilLPerKW, K.OilFricFrac, K.OilGasFrac, K.OilMaxFrac = 0.1, 0.6, 0.05, 0.5
	K.OilDelta, K.OilStill, K.OilRef = 20, 0.2, 90
	K.ViscExp, K.FrictionMulMin, K.FrictionMulMax = 0.24, 0.8, 4
	K.OilHot, K.OilDamageStart, K.OilDamageRate = 130, 150, 0.005
	for Key, Value in pairs(Grade) do K[Key] = Value end
	return K
end
local Diesel15W40 = { OilLPerLitre = 2.0, OilNu40 = 110, OilNu100 = 14.5 }
local Petrol10W30 = { OilLPerLitre = 1.5, OilNu40 = 70, OilNu100 = 10.5 }
Thermal.Kinds = {
	liquid = oilKind({
		LPerKW = 0.15, LPerLitre = 2.3, WarmFrac = 0.6, FluidC = GlycolC, BlockCp = 500, DeltaBlock = 25, PumpDeltaT = 7,
		Open = 82, Full = 95, Boil = 120, FilmBoil = 0.2,
		DerateStart = 150, DerateEnd = 250, DerateMin = 0.6,
		DamageStart = 200, DamageRate = 0.005, CoolantMax = 0.6, Builtin = 1,
	}, Diesel15W40),
	si = oilKind({
		-- As liquid, but knock makes spark-ignition engines lose more torque when hot.
		LPerKW = 0.15, LPerLitre = 2.3, WarmFrac = 0.6, FluidC = GlycolC, BlockCp = 500, DeltaBlock = 25, PumpDeltaT = 7,
		Open = 82, Full = 95, Boil = 120, FilmBoil = 0.2,
		DerateStart = 140, DerateEnd = 250, DerateMin = 0.5,
		DamageStart = 200, DamageRate = 0.005, CoolantMax = 0.6, Builtin = 1,
	}, Petrol10W30),
	electric = {
		-- Liquid-cooled motor and inverter on an electric pump: no thermostat. The windings are
		-- the "metal"; class H insulation is rated to 180 °C (IEC 60085), so damage starts
		-- there and torque is limited from 150 °C the way motor controllers derate.
		LPerKW = 0.03, FluidC = GlycolC, BlockCp = 450, DeltaBlock = 40, PumpDeltaT = 5,
		Open = -273, Full = -272, Boil = 120, FilmBoil = 0.2, ElectricPump = true, NoOil = true,
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
		Open = 80, Full = 95, Boil = 200, FilmBoil = 1, OilIsCoolant = true,
		DerateStart = 200, DerateEnd = 300, DerateMin = 0.8,
		DamageStart = 250, DamageRate = 0.005, Builtin = 3,
	},
}
Thermal.Kinds.diesel = Thermal.Kinds.liquid
Thermal.Kinds.rotary = Thermal.Kinds.si

--[[
	Air-cooled piston engines (radials, flat aero engines, old boxers, motorcycle engines, the
	finned Tatra and Continental tank engines). The cylinders and heads carry fins and lose their
	heat straight to the air blown through them; the only liquid is the oil, which collects heat
	from the crankcase, bearings and cylinder walls and loses it in an oil cooler. So for these
	kinds the model's "coolant" node is the oil (OilIsCoolant, with a thermostatic oil-cooler
	valve) and the "metal" node is the finned cylinders, whose temperature is what a cylinder
	head temperature gauge reads.
	FinPerCyl: finned area of one cylinder over its swept volume to the power 2/3, so it grows
	  with the cylinder's surface. 73 (estimated): it puts a Lycoming O-360 (four 1.48 L cylinders,
	  3.8 m² of fins) at about 215 °C climbing at full power and 170 °C cruising, against
	  Lycoming's 435 °F (224 °C) climb and 400 °F (205 °C) cruise recommendations.
	FinChord: fin length along the air flow [m], for the flat-plate correlation (estimated, 5 cm).
	FinEff: fin efficiency, 0.8 (aluminium fins, Incropera ch. 3; estimated).
	WashV: air speed between the fins at rated engine speed from the engine's own blower or, on
	  an aircraft, the propeller slipstream through the cowl baffles [m/s]; it follows engine
	  speed. Engines without a fan (motorcycles, Spec.NoBlower) get none. 20 is used (estimated: a light aircraft's static slipstream is 25-35 m/s, the
	  baffles pass part of its dynamic pressure). RamCoeff: share of the flight or driving speed
	  that reaches the fins through the cowl or louvres (estimated, 0.5). RamBare: the same for a
	  bare cylinder standing in the wind with no cowl or fan, as on a motorcycle (estimated, 0.8).
	GasShare: the combustion heat an air-cooled cylinder takes in, over a liquid-cooled one's
	  (CoolantFrac in engine_model.lua). NACA measured the heat carried off by the cooling air of
	  a cowled radial at about 40 % of indicated power at high power and 70 % at low power (NACA
	  Report 719 and the Cleveland laboratory memoranda); with an indicated efficiency of 0.36,
	  40 % is 0.14 of the fuel energy against 0.28 for a liquid-cooled engine, so 0.5. The rise at
	  low power is the BMEP^-0.2 scaling in Thermal.CoolantHeat. The hotter cylinder walls take
	  less heat from the gas and the exhaust carries more.
	OilShare, OilGap: the oil takes OilShare of the rated heat when the cylinders run OilGap above
	  it [K]; 0.12 and 100 (estimated: oil coolers on air-cooled aero engines are sized at about a
	  tenth of the power). The oil cooler is built in, sized to reject that share.
	DerateStart, DamageStart: cylinder head temperatures [°C]. Lycoming and Continental limit
	  their heads to 500 °F (260 °C) and 460 °F (238 °C) (operator's manuals, as recalled, not
	  re-checked); detonation margin falls from about 230 °C.
]]
local function airKind(Grade, DerateMin)
	return oilKind({
		AirCooled = true, OilIsCoolant = true,
		LPerKW = 0.1, LPerLitre = Grade.OilLPerLitre, WarmFrac = 0.8, FluidC = OilC, BlockCp = 700, PumpDeltaT = 10,
		Open = 80, Full = 95, Boil = 300, FilmBoil = 1,
		OilShare = 0.12, OilGap = 100, GasShare = 0.5,
		FinPerCyl = 73, FinChord = 0.05, FinEff = 0.8, WashV = 20, RamCoeff = 0.5, RamBare = 0.8,
		DerateStart = 230, DerateEnd = 320, DerateMin = DerateMin,
		DamageStart = 260, DamageRate = 0.005, CoolantMax = 0.6, Builtin = 0,
	}, Grade)
end
Thermal.Kinds.air = airKind(Petrol10W30, 0.5)
Thermal.Kinds.airdiesel = airKind(Diesel15W40, 0.6)

-- Air between the fins (about 60 °C): conductivity [W/(m·K)], kinematic viscosity [m²/s],
-- Prandtl number (Incropera table A.4).
local FinAirK, FinAirNu, FinAirPr = 0.029, 1.9e-5, 0.7
-- Natural convection from hot fins in still air [W/(m²·K)] (Incropera table 1.1: 2-25).
local FinNaturalH = 8

--- Heat transfer coefficient on an air-cooled engine's fins: laminar flat plate,
-- Nu = 0.664·Re^0.5·Pr^(1/3) (Incropera eq. 7.30), over the fin chord.
-- @param K table Air-cooled thermal kind.
-- @param V number Air speed between the fins [m/s].
-- @return number h [W/(m²·K)].
function Thermal.FinH(K, V)
	if V <= 0 then return FinNaturalH end
	local Re = V * K.FinChord / FinAirNu
	return max(0.664 * Re ^ 0.5 * FinAirPr ^ (1 / 3) * FinAirK / K.FinChord, FinNaturalH)
end

--- Air speed between an air-cooled engine's fins.
-- @param K table Air-cooled thermal kind.
-- @param SpeedFrac number Engine speed over rated speed (drives the blower or propeller).
-- @param AirSpeed number Vehicle or aircraft speed through the air [m/s].
-- @param NoBlower boolean|nil True for engines with no fan of their own (ram air only).
-- @return number Air speed [m/s].
function Thermal.FinAirSpeed(K, SpeedFrac, AirSpeed, NoBlower)
	local Wash = NoBlower and 0 or K.WashV * clamp(SpeedFrac, 0, 1.2)
	local Ram = (NoBlower and K.RamBare or K.RamCoeff) * abs(AirSpeed or 0)
	-- Blower and ram pressures add; pressure goes as velocity squared.
	return sqrt(Wash * Wash + Ram * Ram)
end

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
	if Spec.AirCooled then return Spec.Kind == "diesel" and "airdiesel" or "air" end
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
-- Sized with warm oil: the oil viscosity multiplier the engine carries at the moment is ignored.
local function ratedHeat(Spec, GasShare)
	local E = ACE.Mobility.Engine
	local K = Spec.K
	local W = Spec.RatedW
	local Mul = Spec.FrictionMul
	Spec.FrictionMul = nil
	local Q
	if Spec.Kind == "electric" then
		Q = E.MotorLoss(Spec, Spec.BrakeWOT(W)) + E.FrictionTorque(Spec, W, 0) * W
	elseif Spec.Kind == "turbine" then
		Q = E.TurbineFuelRate(Spec, 1) * K.LHV * K.CoolantFrac
	else
		local Pfuel = E.IndicatedWOT(Spec, W) * W / K.EtaIndicated
		Q = Pfuel * K.CoolantFrac * (GasShare or 1) + E.FrictionTorque(Spec, W, 1) * W
	end
	Spec.FrictionMul = Mul
	return Q
end

-- Walther (ASTM D341): log10(log10(ν + 0.7)) = A - B·log10(T), T in K, through two points.
local function waltherFit(Nu40, Nu100)
	local Z40 = math.log10(math.log10(Nu40 + 0.7))
	local Z100 = math.log10(math.log10(Nu100 + 0.7))
	local L40, L100 = math.log10(313.15), math.log10(373.15)
	local B = (Z40 - Z100) / (L100 - L40)
	return Z40 + B * L40, B
end

--- Heat dissipated in the oil out of an engine's heat input.
-- Most of the friction work (bearings, valve train, part of the rings) and a little of the
-- combustion gas heat, capped at the kind's OilMaxFrac of the total.
-- @param TS table Thermal spec.
-- @param HeatW number Heat into the engine [W] (Thermal.CoolantHeat over time).
-- @param W number Crank speed [rad/s].
-- @param Load number Air/fuel fraction 0..1.
-- @return number Heat into the oil [W], 0 for engines without an oil node.
function Thermal.OilHeat(TS, HeatW, W, Load)
	local K = TS.K
	if not TS.Co or HeatW <= 0 then return 0 end
	local Pf = ACE.Mobility.Engine.FrictionTorque(TS.EngineSpec, W, clamp(Load or 1, 0, 1)) * abs(W)
	return min(K.OilFricFrac * Pf + K.OilGasFrac * max(HeatW - Pf, 0), K.OilMaxFrac * HeatW)
end

--- Kinematic viscosity of an engine's oil (ASTM D341 Walther interpolation).
-- @param TS table Thermal spec.
-- @param To number Oil temperature [°C].
-- @return number Viscosity [mm²/s], or nil without an oil node.
function Thermal.OilViscosity(TS, To)
	if not TS.OilA then return end
	-- The relation holds from the pour point to past 150 °C; clamp outside that.
	local Tk = clamp(To, -40, 200) + 273.15
	return 10 ^ (10 ^ (TS.OilA - TS.OilB * math.log10(Tk))) - 0.7
end

--- Multiplier on the engine's rubbing friction from its oil temperature.
-- Read by ACE.Mobility.Engine.FrictionTorque as Spec.FrictionMul.
-- @param TS table Thermal spec.
-- @param To number|nil Oil temperature [°C].
-- @return number 1 for warm oil, more when cold, slightly less when hot.
function Thermal.FrictionMul(TS, To)
	local K = TS.K
	if not TS.OilA or not To then return 1 end
	local Ratio = Thermal.OilViscosity(TS, To) / TS.OilNuRef
	return clamp(Ratio ^ K.ViscExp, K.FrictionMulMin, K.FrictionMulMax)
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
	local Qr = max(ratedHeat(Spec, K.GasShare), 100)
	local Pkw = max(Spec.RatedPower or 0, 1000) / 1000
	MassKg = max(MassKg or 100, 10)

	local S = {
		Kind = Kind, K = K, EngineSpec = Spec,
		RatedHeat = Qr,
		RatedW = max(Spec.RatedW or 1, 1),
		CoolantL = max((K.LPerLitre and Spec.DispL) and K.LPerLitre * Spec.DispL or Pkw * K.LPerKW, 1),
		Cb = MassKg * (K.WarmFrac or 1) * K.BlockCp,
		Gbc = K.AirCooled and K.OilShare * Qr / K.OilGap or Qr / K.DeltaBlock,
		PumpC = Qr / K.PumpDeltaT,
	}
	S.Cc = S.CoolantL * K.FluidC
	local Area = 6 * (MassKg / EngineDensity) ^ (2 / 3)
	S.Gs = SkinH * Area
	if K.AirCooled then
		-- The fins sit on the cylinders: each carries FinPerCyl times its own size squared.
		local Cyl = max(Spec.Cylinders or 4, 1)
		S.FinArea = K.FinPerCyl * Cyl * (max(Spec.Vd or 0.001, 1e-5) / Cyl) ^ (2 / 3)
		-- The oil is an air-cooled engine's only liquid: its viscosity sets the friction.
		S.OilA, S.OilB = waltherFit(K.OilNu40, K.OilNu100)
		S.OilNuRef = Thermal.OilViscosity(S, K.OilRef)
	end

	-- Sump oil: its own thermal mass, losing heat to the coolant (Goc) and through the oil pan,
	-- the bottom one of the engine's six faces (Gos, taken out of the skin).
	if K.OilLPerLitre and not K.NoOil and not K.OilIsCoolant then
		S.OilL = max((Spec.DispL and K.OilLPerLitre * Spec.DispL) or Pkw * K.OilLPerKW, 0.5)
		S.Co = S.OilL * OilC
		S.Gos = S.Gs / 6
		S.Gs = S.Gs - S.Gos
		S.OilA, S.OilB = waltherFit(K.OilNu40, K.OilNu100)
		S.OilNuRef = Thermal.OilViscosity(S, K.OilRef)
		local Mul = Spec.FrictionMul
		Spec.FrictionMul = nil
		S.OilRatedHeat = Thermal.OilHeat(S, Qr, S.RatedW, 1)
		Spec.FrictionMul = Mul
		S.Goc = max(S.OilRatedHeat, 1) / K.OilDelta
	end

	-- The built-in cooling system is a heat exchanger with a belt-driven fan: its air flow is
	-- twice the coolant capacity rate at rated speed, and its UA is found so that it rejects
	-- the requested share at 100 °C coolant and 20 °C air.
	S.BuiltinCair = 2 * S.PumpC
	S.BuiltinUA = 0
	local Target = max(Builtin or 0, 0) * K.Builtin * Qr
	-- An air-cooled engine's built-in cooler is its oil cooler, part of the engine itself.
	if K.AirCooled then Target = K.OilShare * Qr end
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
	return { Tb = Ambient, Tc = Ambient, To = Ambient, Qrad = 0, Vented = 0, Thermostat = 0, OilHeat = 0, OilToCoolant = 0 }
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
-- @return number Heat into the engine, metal and oil together [J] (Thermal.Step splits it).
function Thermal.CoolantHeat(TS, HeatJ, FuelKg, Load, W)
	local Spec = TS.EngineSpec
	local EK = Spec.K
	if not EK.EtaIndicated or Spec.Kind == "turbine" or (FuelKg or 0) <= 0 then return max(HeatJ or 0, 0) end
	local FuelJ = FuelKg * EK.LHV
	local Base = FuelJ * EK.CoolantFrac
	local Friction = max(HeatJ - Base, 0)
	Base = Base * (TS.K.GasShare or 1)
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

--- Health lost per second, as a fraction of maximum health, from the engine metal temperature
-- and, for engines with a sump, the oil temperature (a thinned, oxidising oil film wears the
-- bearings and rings).
-- @param TS table Thermal spec.
-- @param Tb number Metal temperature [°C].
-- @param To number|nil Oil temperature [°C].
-- @return number Fraction of maximum health per second.
function Thermal.DamageRate(TS, Tb, To)
	local K = TS.K
	local Rate = max(Tb - K.DamageStart, 0) / 50 * K.DamageRate
	if To and (TS.Co or K.AirCooled) then
		Rate = Rate + max(To - K.OilDamageStart, 0) / 50 * K.OilDamageRate
	end
	return Rate
end

-- Exact solution of the linear two-node system over H seconds, conductances frozen.
-- u = Tb - Ta, v = Tc - Ta:  Cb·u' = P - Gbc(u - v) - Gs·u,  Cc·v' = Pc + Gbc(u - v) - Gr·v.
-- Gs > 0 keeps the system non-singular; its eigenvalues are real and negative.
local function solve2(u, v, P, Pc, Cb, Cc, Gbc, Gs, Gr, H)
	local a11, a12 = -(Gbc + Gs) / Cb, Gbc / Cb
	local a21, a22 = Gbc / Cc, -(Gbc + Gr) / Cc
	local Tr = a11 + a22
	local Det = a11 * a22 - a12 * a21
	-- Fixed point: A·x + b = 0 with b = (P / Cb, Pc / Cc).
	local b1, b2 = P / Cb, Pc / Cc
	local Us = (a12 * b2 - a22 * b1) / Det
	local Vs = (a21 * b1 - a11 * b2) / Det
	local du, dv = u - Us, v - Vs

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
-- @param Heat number Heat input to the engine, metal and oil together [W].
-- @param W number Crank speed [rad/s] (drives the water and oil pumps and built-in fan).
-- @param H number Step length [s] (already multiplied by any time scale).
-- @param Opts table|nil { Ambient = °C, Running = bool (electric pump), Load = air/fuel
-- fraction 0..1 (sets the friction share of the heat, default 1), AirSpeed = m/s through the
-- air (air-cooled engines), Exchangers = {
-- { UA = W/K, Cair = W/K }, ... }, ExtraC = extra coolant heat capacity from radiators [J/K] }.
-- Sets T.Tb, T.Tc, T.To (oil; nil for motors, the coolant for turbines), T.Thermostat,
-- T.Boiling, T.Qrad (radiator heat rejection, W), T.OilHeat and T.OilToCoolant (W), and for
-- air-cooled engines T.FinV (air speed between the fins, m/s) and T.Qfin (fin heat, W).
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

	--[[
		Oil: exact over the step against the coolant temperature at its start. The oil pump is
		gear-driven off the crank, so the oil cooler's conductance follows engine speed down to
		what the stagnant sump still conducts into the block. Its coolant side film-boils like
		the water jacket. The heat it passes to the coolant is the step's average, so energy is
		conserved.
	]]
	Heat = max(Heat, 0)
	local Pb, Pc = Heat, 0
	if TS.Co then
		local To = T.To or T.Tc
		local Qo = Thermal.OilHeat(TS, Heat, W, Opts and Opts.Load)
		local Goc = TS.Goc * (K.OilStill + (1 - K.OilStill) * min(PumpFrac, 1)) * (1 - (1 - K.FilmBoil) * Boil)
		local G = Goc + TS.Gos
		local Teq = (Qo + Goc * T.Tc + TS.Gos * Ta) / G
		local Kh = G * H / TS.Co
		local Decay = exp(-Kh)
		local Avg = Teq + (To - Teq) * (1 - Decay) / Kh
		T.To = Teq + (To - Teq) * Decay
		Pc = Goc * (Avg - T.Tc)
		Pb = Heat - Qo
		T.OilHeat, T.OilToCoolant = Qo, Pc
	end

	-- Air-cooled: the fins lose heat to the air blown through them, on top of the bare skin.
	local Gs = TS.Gs
	if K.AirCooled then
		local FinV = Thermal.FinAirSpeed(K, abs(W) / TS.RatedW, Opts and Opts.AirSpeed, TS.EngineSpec.NoBlower)
		local Gfin = TS.FinArea * K.FinEff * Thermal.FinH(K, FinV)
		Gs = Gs + Gfin
		T.FinV, T.Qfin = FinV, Gfin * (T.Tb - Ta)
	end

	local U, V = solve2(T.Tb - Ta, T.Tc - Ta, Pb, Pc, TS.Cb, Cc, Gbc, Gs, Gr, H)
	T.Tb, T.Tc = U + Ta, V + Ta

	-- The pressure cap holds the coolant at its boiling point; the excess leaves as steam.
	T.Boiling = T.Tc >= K.Boil
	if T.Boiling then
		T.Vented = T.Vented + (T.Tc - K.Boil) * Cc
		T.Tc = K.Boil
	end
	T.Qrad = Gr * (T.Tc - Ta)
	-- A turbine's coolant is its oil; a motor has no oil circuit modelled.
	if K.OilIsCoolant then
		T.To = T.Tc
	elseif not TS.Co then
		T.To = nil
	end
	return T
end

return Thermal

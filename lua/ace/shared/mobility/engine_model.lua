--[[
	Engine model: indicated torque, friction and pumping losses, idle governor,
	rev limiter, stall/start and fuel/heat flow. Pure Lua, no GMod calls, so it
	can be unit-tested under LuaJIT.

	References (full list in docs/mobility-sources.md):
	- J. B. Heywood, Internal Combustion Engine Fundamentals, 2nd ed., McGraw-Hill 2018.
	  Ch. 2 (mean effective pressure, T = mep·Vd/(2π·nR)), ch. 13 (friction, pumping),
	  ch. 12 (energy balance), App. D (fuel heating values).
	- Chen & Flynn, SAE 650733 (1965): FMEP = A + B·pmax + C·Sp + D·Sp², Sp = mean piston
	  speed. Constants fitted to measured motoring torque: EPA ALPHA engine packages (SI) and
	  the VECTO generic engines' motoring curves (diesel).
	- Inertia: VECTO DeclarationData.Engine (diesel), EPA ALPHA engine packages (SI),
	  Gao et al. 2019 (motors), Forecast International AGT1500 (turbines).
	- Motors: Burress, ORNL 2013 (2012 LEAF motor/inverter efficiency), Nissan e-Pedal (regen).
	- Turbines: GlobalSecurity M1 specifications (idle fuel flow), 14 CFR 33.73 (spool-up bound).
]]

ACE = ACE or {}
ACE.Mobility = ACE.Mobility or {}

local Engine = {}
ACE.Mobility.Engine = Engine

local pi    = math.pi
local max   = math.max
local min   = math.min
local abs   = math.abs
local exp   = math.exp
local floor = math.floor

local RPMToRad = pi / 30
local BarToPa  = 1e5
local sin, cos, sqrt = math.sin, math.cos, math.sqrt

--[[
	Cylinder gas springs (Engine.GasTorque). With its valves shut a cylinder is a sealed volume
	of air: turning the crank against it compresses the air, which pushes back on the piston.
	That is what holds a car parked in gear with the engine off, and what makes a stopping
	engine shudder and rock back before it settles.
	Atmosphere: 1.013 bar. Intake valve closing 45 deg after bottom centre, exhaust valve
	opening 45 deg before it: typical four-stroke timing, 40-60 deg each (Heywood 6.3). The gas
	is trapped only between the two.
	RodRatio: crank radius over connecting rod length, 0.25-0.33 in production engines
	(Heywood 2.2 gives rod length over crank radius as 3-4).
	Heat: compressing the charge heats it (adiabatic, gamma 1.4 for air) and the walls draw that
	heat off with a time constant WallTau. Squeezed slowly (a parked car), the charge stays at
	wall temperature and the spring is isothermal and lossless; squeezed at about the speed of
	WallTau, part of the work leaves as heat and the spring damps, which is what stops a crank
	that gets pushed round from bouncing on its cylinders. WallTau: trapped air of a 0.5 L
	cylinder is ~0.6 g (c_v 718 J/kg·K, so 0.43 J/K), against ~0.02 m² of wall at a quiescent
	heat transfer coefficient of ~100 W/m²·K (Heywood 12.4 puts motored low-speed values at
	100-300): 0.43 / (100 · 0.02) ~ 0.2 s. Trapped mass and wall area both grow with bore,
	so the same value is used for every size (an estimate, not a measurement).
	Leak: the charge escapes past the rings at a rate proportional to its excess pressure.
	Blowby in a healthy engine is about 1 % of the charge per cycle (Heywood 8.6), lost mostly
	while the cylinder is near peak pressure: at 2,000 rpm a cycle is 60 ms and the
	high-pressure quarter of it 15 ms, at about 40 bar over ambient. So 0.01 of the charge in
	0.015 s per 40 bar: GasLeak = 0.01 / 0.015 / 40 = 0.017 of a cylinder's charge per second
	per bar of excess pressure. A cylinder held at 9 bar over ambient loses ~15 % a second, so
	a car held on compression alone creeps as the charge bleeds away, as real ones do.
	The springs are resolved crank angle by crank angle only while the engine turns slowly
	(full below 60 rpm, gone above 150): over a whole cycle a gas spring returns what it took,
	and what it loses at speed (heat, blowby) is already inside the motoring friction fit.
	Faster, the substeps could not follow the crank angle anyway.
]]
local Atmosphere  = 1.013 * BarToPa
local ValveIVC    = pi + math.rad(45)       -- cycle angle the trapped charge starts at
local ValveEVO    = 3 * pi - math.rad(45)   -- and where it is let out
local RodRatio    = 0.3
local GasLeak     = 0.01 / 0.015 / 40       -- charge fraction per second per bar of excess
local Gamma       = 1.4
local WallTau     = 0.2
local GasFullW    = 60 * RPMToRad
local GasOffW     = 150 * RPMToRad
local Cycle       = 4 * pi

local function clamp(v, lo, hi)
	if v < lo then return lo end
	if v > hi then return hi end
	return v
end

-- Catmull-Rom sample of an ACE torque curve (same maths as ACE.CalcCurve, repeated
-- here so the model does not depend on GMod's math.Clamp).
local function sampleCurve(Points, Pos)
	local Count = #Points
	if Count < 3 then return 0 end
	if Pos <= 0 then return Points[1] end
	if Pos >= 1 then return Points[Count] end

	local T = (Pos * (Count - 1)) % 1
	local Current = floor(Pos * (Count - 1) + 1)
	local P0 = Points[clamp(Current - 1, 1, Count - 2)]
	local P1 = Points[clamp(Current, 1, Count - 1)]
	local P2 = Points[clamp(Current + 1, 2, Count)]
	local P3 = Points[clamp(Current + 2, 3, Count)]

	return 0.5 * ((2 * P1) + (P2 - P0) * T + (2 * P0 - 5 * P1 + 4 * P2 - P3) * T ^ 2 + (3 * P1 - P0 - 3 * P2 + P3) * T ^ 3)
end
Engine.SampleCurve = sampleCurve

--[[
	Per-kind constants. Every value and its source is listed in docs/mobility-sources.md.
	FMEP (Chen-Flynn): A [bar], B [-], C [bar·s/m], D [bar·s²/m²], with Sp the mean piston
	  speed 2·S·N [m/s]. Motoring MEP (fuel cut, closed throttle) = A + B·PmaxIdle + PumpClosed
	  + C·Sp + D·Sp². That sum was least-squares fitted to measured motoring torque:
	  SI: EPA ALPHA packages (Mazda 2.0 SKYACTIV-G, Chevrolet 2.5 LCV, Toyota 2.5 A25A, Honda
	  1.5 L15B7, GM 4.3 LV3), 19 points, rms error 12%: 0.953 + 0.0462·Sp + 0.0021·Sp².
	  Diesel: VECTO generic 12.7 L and 6.9 L motoring curves plus the EPA BMW N57, 12 points,
	  rms error 22% (the two VECTO engines differ by about that much): 0.905 + 0.0136·Sp²;
	  a free linear term fitted negative, so C is 0.
	  The constant is split with B = 0.005 (Chen-Flynn load term, 0.004-0.006 in the
	  literature) and the pumping value below; A is what remains.
	PumpClosed: pumping MEP with the throttle shut [bar]; PumpOpen at wide-open throttle.
	  SI engines idle at ~0.3 bar manifold pressure, so closed-throttle pumping is ~0.7-0.8 bar
	  (Heywood 13.2). Diesels are unthrottled: pumping stays near the WOT value, which is why
	  diesels have weak engine braking.
	PmaxIdle: motoring peak pressure from polytropic compression p·rc^n (SI: 0.3 bar manifold,
	  rc 10, n 1.3 -> 6 bar; diesel: 1 bar, rc 16, n 1.35 -> 42 bar). PmaxFull: typical
	  full-load peak pressure (Heywood 9.2, 10.2).
	EtaIndicated: gross indicated fuel conversion efficiency (Heywood 5.7): SI ~0.36, DI diesel ~0.45.
	CoolantFrac: share of fuel energy rejected to coolant (Heywood 12.1, table 12.1).
	IdleAuthority: most air/fuel the idle governor may add. A petrol idle-air valve or
	  drive-by-wire idle controller only opens far enough to catch the engine, not to pull a car; a diesel's mechanical governor can deliver
	  full fuel to hold idle, which is why diesels crawl in gear with no throttle.
	LHV: lower heating value [J/kg] (Heywood App. D).
CompressionRatio: geometric compression ratio, the same values PmaxIdle is computed from
  (Heywood 1.3: SI 8-12, diesel 12-24). GasSpring: the cylinders are modelled one by one as
  gas springs while the engine stands or turns slowly (see Engine.GasTorque).
]]
Engine.Kinds = {
	si = {
		A = 0.173, B = 0.005, C = 0.0462, D = 0.0021,
		PumpClosed = 0.75, PumpOpen = 0.15,
		PmaxIdle = 6, PmaxFull = 60,
		EtaIndicated = 0.36, CoolantFrac = 0.28, LHV = 43.3e6,
		Strokes = 4, StallFrac = 0.35, IdleAuthority = 0.45,
		CompressionRatio = 10, GasSpring = true,
	},
	diesel = {
		A = 0.445, B = 0.005, C = 0, D = 0.0136,
		PumpClosed = 0.25, PumpOpen = 0.2,
		PmaxIdle = 42, PmaxFull = 150,
		EtaIndicated = 0.45, CoolantFrac = 0.25, LHV = 42.6e6,
		Strokes = 4, StallFrac = 0.4, IdleAuthority = 1, DroopGovernor = true,
		CompressionRatio = 16, GasSpring = true,
	},
	rotary = {
		-- A Wankel fires once per rotor per crank revolution; treated as a 4-stroke of
		-- twice the chamber displacement, the usual convention for comparisons.
		-- No published rotary motoring data was found: friction uses the SI fit.
		A = 0.173, B = 0.005, C = 0.0462, D = 0.0021,
		PumpClosed = 0.75, PumpOpen = 0.15,
		PmaxIdle = 6, PmaxFull = 55,
		EtaIndicated = 0.30, CoolantFrac = 0.30, LHV = 43.3e6,
		Strokes = 4, StallFrac = 0.35, IdleAuthority = 0.45,
	},
	turbine = {
		-- Free power turbine: the output shaft is not the gas generator, it can sit at 0 RPM
		-- under load without stalling (Abrams-style creep). Losses are bearings/windage only.
		-- Efficiency: AGT1500 full-power SFC 0.30 kg/kWh (Forecast International 2008) on
		-- 42.8 MJ/kg fuel: 3.6 / (0.30 * 42.8) = 0.28.
		-- IdleSpool: gas-generator idle as a fraction of full-power fuel flow. The M1 burns
		-- 10 US gal/h at basic idle (GlobalSecurity, M1 specifications) = 30 kg/h of JP-8, and
		-- 0.30 kg/kWh x 1,119 kW = 336 kg/h at full power, so idle is 9% of full flow.
		-- SpoolTime: first-order time constant of the gas generator. 1.2 s takes idle to 95%
		-- power in 3.5 s, inside the 5 s that 14 CFR 33.73 allows a certified turbine engine
		-- (no AGT1500 figure was found).
		EtaIndicated = 0.28, CoolantFrac = 0.02, LHV = 42.8e6,
		SpoolTime = 1.2, IdleSpool = 0.09,
	},
	electric = {
		-- Motor + inverter losses as a fraction of rated power (Prated = peak power), with
		-- t = |torque| / peak torque and w = |speed| / max speed:
		--   CopperLoss·t² (stator I²R), InverterLoss·t (switch conduction, roughly ∝ current),
		--   IronLoss·w² (core loss and windage, felt as shaft drag).
		-- Least-squares fitted to the ORNL 2012 LEAF motor+inverter map (Burress 2013: combined
		-- peak above 96%, a wide region above 90%, lower at low speed and torque). The fit
		-- peaks at 95.5% and gives 91% at the peak-torque corner.
		CopperLoss = 0.03, InverterLoss = 0.065, IronLoss = 0.037, BearingFrac = 0.002,
		-- Speed (fraction of max) below which regen fades to zero: at 5% of top speed the fitted
		-- losses eat all the recovered power.
		RegenFadeFrac = 0.05,
	},
}

local CylindersByCategory = {
	Single = 1, I2 = 2, I3 = 3, I4 = 4, I5 = 5, I6 = 6,
	V2 = 2, V4 = 4, V6 = 6, V8 = 8, V10 = 10, V12 = 12,
	B4 = 4, B6 = 6, Radial = 7, Rotary = 2, -- ACE radials are all seven-cylinder ("R7")
}

local function kindOf(Def)
	local EType = Def.enginetype or ""
	local Fuel = Def.fuel or "Petrol"
	if Fuel == "Electric" or EType == "Electric" then return "electric" end
	if EType == "Turbine" or EType == "GroundTurbine" or Def.category == "Turbine" then return "turbine" end
	if EType == "Wankel" or Def.category == "Rotary" then return "rotary" end
	if Fuel == "Diesel" or Fuel == "Multifuel" or EType == "GenericDiesel" then return "diesel" end
	return "si"
end

--- Reads the displacement of an engine definition in litres.
-- Uses the explicit `displacement` field, otherwise the "5.7L" style number in the name or id.
-- @param Def Engine definition table.
-- @return Displacement in litres, or nil if it cannot be found.
function Engine.Displacement(Def)
	if Def.displacement then return Def.displacement end
	local FromName = Def.name and string.match(Def.name, "(%d+%.?%d*)%s*L")
	if FromName then return tonumber(FromName) end
	local FromId = Def.id and string.match(Def.id, "^(%d+%.?%d*)")
	if FromId then return tonumber(FromId) end
	return nil
end

--[[
	Rotating inertia of crank + flywheel + clutch when a definition has no measured value [kg·m²].
	Diesel: the EU VECTO declaration formula (DeclarationData.Engine.EngineInertia, manual
	  gearbox, so the clutch is included): up to 3.2 L 0.4·V; 3.2-5 L 0.989·V - 1.885; above
	  5 L 1.3 (clutch) + 0.41 + 0.27·V, V in litres. VECTO's own generic engines: 12.74 L ->
	  5.15, 6.87 L -> 3.57.
	Petrol and rotary: least-squares line through the EPA ALPHA engine inertias for 1.04 L
	  (0.075), 2.5 L (0.095) and 2.69 L (0.13): 0.046 + 0.026·V. Beyond ~3 L this is an
	  extrapolation; no published figure for large petrol engines was found.
]]
local function estimateInertia(DispL, Kind)
	if Kind == "diesel" then
		if DispL <= 3.2 then return 0.4 * DispL end
		if DispL <= 5 then return 0.989 * DispL - 1.885 end
		return 1.71 + 0.27 * DispL
	end
	return 0.046 + 0.026 * DispL
end

-- Distance of a piston from top centre and its rate with crank angle (slider-crank).
local function pistonTravel(Gas, Theta)
	local R, L = Gas.Crank, Gas.Rod
	local S, C = sin(Theta), cos(Theta)
	local Root = sqrt(L * L - R * R * S * S)
	return R * (1 - C) + L - Root, R * S * (1 + R * C / Root)
end

--[[
	Most torque the cylinders' air puts against turning the crank forwards slowly from rest:
	each sealed cylinder holds ambient air trapped at intake closing, compressed isothermally,
	all cylinders summed at every crank angle (one compressing while another expands).
]]
local function compressionPeak(Gas)
	local Worst = 0
	for Step = 0, 719 do
		local Angle = Step / 720 * Cycle
		local Torque = 0
		for I = 1, Gas.Count do
			local Phase = (Angle + (I - 1) * Gas.Interval) % Cycle
			if Phase > ValveIVC and Phase < ValveEVO then
				local Travel, Rate = pistonTravel(Gas, Phase)
				local V = Gas.Vc + Gas.Area * Travel
				local Trapped = Gas.Vc + Gas.Area * pistonTravel(Gas, ValveIVC)
				Torque = Torque + (Atmosphere * Trapped / V - Atmosphere) * Gas.Area * Rate
			end
		end
		Worst = min(Worst, Torque)
	end
	return -Worst
end

-- Engines are liquid-cooled unless their definition says cooling = "air" (or the player picks it
-- in the engine menu). Most ACE definitions make two to five times the power per kilogram of
-- real air-cooled engines, more than finned cylinders of their size can shed.
-- Air-cooled types with no cooling fan of their own: motorcycle engines cool on riding speed
-- alone. Others (fan-cooled boxers and tank engines, aircraft engines behind their propeller)
-- get an engine-driven air flow; a definition overrides it with blower = true or false.
local NoBlowerTypes = { Single = true, V2 = true }

--- Whether an engine definition is air-cooled (finned cylinders, no coolant).
-- @param Def Engine definition.
-- @return boolean
function Engine.IsAirCooled(Def)
	return Def.cooling == "air"
end

--- Builds the physical description of an engine from its ACE definition.
-- @param Def Engine definition (fields torque, idlerpm, limitrpm, fuel, enginetype, category,
-- name; optional displacement [L], cylinders, stroke [m], inertia [kg·m²]).
-- @param Curve Torque curve points (0..1), normally ACE.GetEngineTorqueCurve(Def).
-- @return Spec table consumed by the other Engine functions.
function Engine.Build(Def, Curve)
	local Kind = kindOf(Def)
	local K = Engine.Kinds[Kind]
	local Spec = {
		Kind       = Kind,
		K          = K,
		Curve      = Curve,
		PeakTorque = Def.torque,
		IdleRPM    = Def.idlerpm,
		LimitRPM   = Def.limitrpm,
		IdleW      = Def.idlerpm * RPMToRad,
		LimitW     = Def.limitrpm * RPMToRad,
	}
	if (Kind == "si" or Kind == "diesel") and Engine.IsAirCooled(Def) then
		Spec.AirCooled = true
		if Def.blower == false or (Def.blower == nil and NoBlowerTypes[Def.enginetype or ""]) then Spec.NoBlower = true end
	end

	local DispL = Engine.Displacement(Def)
	if not DispL or DispL <= 0 then
		-- Unknown size: back out displacement from peak torque via BMEP. Heywood 2.7 puts
		-- naturally aspirated SI at ~10 bar and turbo diesels at ~15-20 bar at peak torque.
		local Bmep = (Kind == "diesel") and 16 or 10
		DispL = Def.torque * 4 * pi / (Bmep * BarToPa) * 1000
	end
	Spec.DispL = DispL
	Spec.Vd = DispL / 1000

	local Cyl = Def.cylinders or CylindersByCategory[Def.category] or CylindersByCategory[Def.enginetype]
		or tonumber((Def.name or ""):match("%f[%w][VIRW](%d%d?)%f[%W]")) or 4
	Spec.Cylinders = Cyl

	if K.Strokes then
		-- Square engine (bore = stroke) when geometry is not given.
		local Vcyl = Spec.Vd / Cyl
		Spec.Stroke = Def.stroke or (4 * Vcyl / pi) ^ (1 / 3)
		-- Converts a mean effective pressure [Pa] into crank torque [N·m] (Heywood eq. 2.19).
		Spec.MepToTorque = Spec.Vd / (2 * pi * (K.Strokes / 2))
	end

	if K.GasSpring then
		-- Cylinder geometry for the gas springs. Every field can come from the definition, so
		-- an engine built from bore, stroke and cylinder count describes itself fully.
		local Vcyl = Spec.Vd / Cyl
		local Rc = Def.compression or K.CompressionRatio
		local Crank = Spec.Stroke / 2
		Spec.Gas = {
			Count    = Cyl,
			Area     = Vcyl / Spec.Stroke,                    -- piston area, m²
			Crank    = Crank,                                 -- crank radius, m
			Rod      = Crank / (Def.rodratio or RodRatio),    -- connecting rod length, m
			Vcyl     = Vcyl,                                  -- swept volume per cylinder, m³
			Vc       = Vcyl / (Rc - 1),                       -- clearance volume, m³
			Interval = 4 * pi / Cyl,                          -- even firing interval, rad
		}
		Spec.Gas.Peak = compressionPeak(Spec.Gas)
	end

	Spec.Inertia = Def.inertia or estimateInertia(DispL, Kind)
	-- Motor rotors: power fit through Gao et al. 2019 (ORNL), table 1: 280 N·m -> 0.03,
	-- 700 -> 0.06, 874 -> 0.08 kg·m².
	if Kind == "electric" then Spec.Inertia = Def.inertia or 0.03 * (Def.torque / 280) ^ 0.86 end
	-- Free power turbine seen at the output shaft. AGT1500: power turbine rotor 0.141 kg·m²
	-- at 22,500 rpm through a 7.5:1 reduction = 7.93 kg·m² at 3,000 rpm, peak torque
	-- 5,355 N·m (Forecast International; Gas Turbine World). Other turbines keep the same
	-- stored energy per unit of power: J scales with torque and inversely with output speed.
	if Kind == "turbine" then
		Spec.Inertia = Def.inertia or 7.93 * (Def.torque / 5355) * (3000 / max(Def.limitrpm, 1))
	end

	local Count = Curve and #Curve or 0
	local Span = max(Spec.LimitRPM - Spec.IdleRPM, 1)
	-- Torque at wide-open throttle straight off the definition's curve.
	Spec.BrakeWOT = function(W)
		local RPM = W / RPMToRad
		local Perc = (RPM - Spec.IdleRPM) / Span
		local Frac
		if Perc < 0 and Kind == "turbine" and Count >= 2 then
			-- A free power turbine keeps gaining torque down to output stall: torque falls about
			-- linearly with output speed at fixed gas-generator power, so extend the curve's
			-- first segment down to 0 rpm.
			Frac = Curve[1] + (Curve[1] - Curve[2]) * -Perc * (Count - 1)
		else
			-- Below idle a piston engine's curve is undefined; per-cycle torque stays roughly at
			-- its idle value (volumetric efficiency is high at low speed), so hold the first point.
			-- Curves are normalised to peak: clip the spline's overshoot at flat-to-falling knees.
			Frac = min(sampleCurve(Curve, Perc), 1)
		end
		return max(Frac * Spec.PeakTorque, 0)
	end

	-- Peak power over the curve and the speed it occurs at.
	local Best, BestW = 0, Spec.LimitW
	for I = 1, 64 do
		local W = Spec.LimitW * I / 64
		local P = Spec.BrakeWOT(W) * W
		if P > Best then Best, BestW = P, W end
	end
	Spec.RatedPower = Best
	Spec.RatedW = BestW

	return Spec
end

--- Electrical-side loss of a motor and its inverter (copper and switching), in watts.
-- Core loss and windage are not included: they act as shaft drag (Engine.FrictionTorque).
-- @param Spec Electric engine spec.
-- @param Torque Electromagnetic torque in N·m (either sign).
-- @return Loss in W.
function Engine.MotorLoss(Spec, Torque)
	local K = Spec.K
	local T = abs(Torque) / Spec.PeakTorque
	return Spec.RatedPower * (K.CopperLoss * T * T + K.InverterLoss * T)
end

--- Fuel mass flow of a turbine at a given gas-generator state.
-- The gas generator burns fuel for the power it makes whatever the output shaft does, so a
-- stalled power turbine at full throttle burns full-power fuel.
-- @param Spec Turbine engine spec.
-- @param Spool Gas-generator power fraction 0..1.
-- @return Fuel flow in kg/s.
function Engine.TurbineFuelRate(Spec, Spool)
	local K = Spec.K
	return Spool * Spec.RatedPower / K.EtaIndicated / K.LHV
end

local SampleSpecs = setmetatable({}, { __mode = "k" })

--- Brake torque at wide-open throttle for an engine definition, as the drivetrain sees it.
-- Used by the engine menu graph. Specs are cached per definition table.
-- @param Def Engine definition.
-- @param RPM Crank (output shaft) speed in rpm.
-- @return Torque in N·m; 0 past the limit for motors and turbines, which cut drive there.
function Engine.CurveSample(Def, RPM)
	local Spec = SampleSpecs[Def]
	if not Spec then
		local Curve = ACE.GetEngineTorqueCurve and ACE.GetEngineTorqueCurve(Def) or Def.torquecurve
		Spec = Engine.Build(Def, Curve)
		SampleSpecs[Def] = Spec
	end
	local W = RPM * RPMToRad
	if (Spec.Kind == "electric" or Spec.Kind == "turbine") and W > Spec.LimitW then return 0 end
	return Spec.BrakeWOT(max(W, 0))
end
ACE.Mobility.EngineCurveSample = Engine.CurveSample

--- Friction torque (rubbing + accessories) at a given speed and load, Chen-Flynn.
-- @param Spec Engine spec (optional Spec.FrictionMul: oil viscosity multiplier, default 1).
-- @param W Crank speed in rad/s.
-- @param Load Air/fuel fraction 0..1 (sets peak cylinder pressure).
-- @return Friction torque in N·m (positive, opposes rotation).
function Engine.FrictionTorque(Spec, W, Load)
	local K = Spec.K
	if K.IronLoss then
		-- Motors: bearing drag plus core loss and windage, IronLoss·Prated·w² as a torque.
		local Lw = max(Spec.LimitW, 1)
		return Spec.PeakTorque * K.BearingFrac + K.IronLoss * Spec.RatedPower * abs(W) / (Lw * Lw)
	end
	if not K.A then
		-- Turbines: bearings and windage, about 1-2% of peak torque at speed.
		local Frac = 0.01 + 0.01 * min(abs(W) / max(Spec.LimitW, 1), 1.5)
		return Spec.PeakTorque * Frac
	end
	local Sp = abs(W) * Spec.Stroke / pi -- mean piston speed, 2·S·N
	local Pmax = K.PmaxIdle + (K.PmaxFull - K.PmaxIdle) * Load
	local Fmep = K.A + K.B * Pmax + K.C * Sp + K.D * Sp * Sp
	-- The fit is for fully warm oil; Spec.FrictionMul (set from the oil temperature by
	-- ACE.Mobility.Thermal.FrictionMul) raises it for cold, viscous oil. Unset means warm.
	return Fmep * BarToPa * Spec.MepToTorque * (Spec.FrictionMul or 1)
end

--- Pumping torque: manifold vacuum against exhaust back-pressure.
-- Pumping is a flow loss: the manifold vacuum is pulled by the engine's own air flow, so it
-- builds up from nothing at standstill to its full value at idle. Held at full value at rest it
-- acted as static friction and held parked cars on slopes their compression could not.
-- @param Spec Engine spec.
-- @param Load Air fraction 0..1.
-- @param W Optional crank speed in rad/s; when given, the loss fades in up to idle speed.
-- @return Pumping torque in N·m (positive, opposes rotation).
function Engine.PumpingTorque(Spec, Load, W)
	local K = Spec.K
	if not K.PumpClosed then return 0 end
	local Pmep = K.PumpClosed + (K.PumpOpen - K.PumpClosed) * Load
	local Flow = W and min(abs(W) / max(Spec.IdleW, 1), 1) or 1
	return Pmep * BarToPa * Spec.MepToTorque * Flow
end

--- Torque of the cylinders' trapped air on the crank, crank angle by crank angle.
-- Advances the crank angle and each cylinder's trapped charge by Dt at the state's speed.
-- Each cylinder is a sealed volume between intake closing and exhaust opening: entering that
-- window (turning either way) it traps air at ambient pressure, which then follows p·V = const
-- and bleeds past the rings (see the constants at the top of this file). Cylinders fire evenly
-- (four-stroke, 720/N degrees apart).
-- @param Spec Engine spec (needs Spec.Gas).
-- @param State Engine state; uses W, Angle (crank angle in the 720 degree cycle) and Charge
-- ({ Trapped, Heat, Volume } per sealed cylinder).
-- @param Dt Time step in seconds.
-- @return Torque on the crank in N·m (positive turns it forwards).
function Engine.GasTorque(Spec, State, Dt)
	local Gas = Spec.Gas
	if not Gas then return 0 end
	local W = State.W
	local Weight = clamp((GasOffW - abs(W)) / (GasOffW - GasFullW), 0, 1)
	local Charge = State.Charge
	if State.Running or Weight == 0 then
		-- Running, or turning fast: the cycle-mean models carry it, nothing is held over.
		if Charge then State.Charge = nil end
		State.Angle = ((State.Angle or 0) + W * Dt) % Cycle
		return 0
	end
	if not Charge then
		Charge = {}
		State.Charge = Charge
	end

	local Angle = State.Angle or 0
	local Torque = 0
	for I = 1, Gas.Count do
		local Phase = (Angle + (I - 1) * Gas.Interval) % Cycle
		if Phase > ValveIVC and Phase < ValveEVO then
			local Travel, Rate = pistonTravel(Gas, Phase)
			local V = Gas.Vc + Gas.Area * Travel
			local C = Charge[I]
			if not C then
				-- Air trapped as the valve shuts: ambient pressure, wall temperature.
				C = { Trapped = V, Heat = 1, Volume = V }
				Charge[I] = C
			end
			-- Heat is the charge's temperature over wall temperature: adiabatic change for the
			-- volume swept since last step, then cooling (or warming) towards the wall.
			local Heat = C.Heat * (C.Volume / V) ^ (Gamma - 1)
			Heat = 1 + (Heat - 1) * exp(-Dt / WallTau)
			-- Trapped is the volume the air would take at ambient pressure and wall temperature.
			local P = Atmosphere * C.Trapped * Heat / V
			Torque = Torque + (P - Atmosphere) * Gas.Area * Rate
			C.Trapped = max(C.Trapped - GasLeak * Gas.Vcyl * (P - Atmosphere) / BarToPa * Dt, 0)
			C.Heat, C.Volume = Heat, V
		else
			Charge[I] = nil
		end
	end
	State.Angle = (Angle + W * Dt) % Cycle
	return Torque * Weight
end

--- Indicated (combustion) torque at wide-open throttle, i.e. brake torque plus the losses the
-- dyno curve already had to overcome.
function Engine.IndicatedWOT(Spec, W)
	local Brake = Spec.BrakeWOT(W)
	if not Spec.K.A then return Brake + Engine.FrictionTorque(Spec, W, 1) end
	return Brake + Engine.FrictionTorque(Spec, W, 1) + Engine.PumpingTorque(Spec, 1)
end

--- Creates the per-entity runtime state.
function Engine.NewState(Spec)
	return {
		W        = 0,        -- crank speed, rad/s
		Running  = false,    -- combustion enabled
		Cranking = 0,        -- > 0 while the starter turns the crank: cranking left before its thermal cut-out, s
		StarterOn = false,   -- start requested (Active held) and the engine has not caught yet
		StarterHeat = 0,     -- starter winding heat, 0 cold .. 1 thermal cut-out
		StarterCut = false,  -- thermal cut-out open, waiting to cool
		StarterJ = 0,        -- electrical energy the starter drew since the entity last billed it, J
		IdleInt  = 0.15,     -- idle governor integrator (air fraction)
		Spool    = 0,        -- turbine gas generator spool 0..1
		Cut      = false,    -- rev limiter fuel cut latched
		Load     = 0,        -- effective air fraction used last step
		Torque   = 0,        -- net brake torque last step, N·m
		FuelRate = 0,        -- kg/s
		HeatRate = 0,        -- W into the engine block / coolant
		Stalled  = false,
		Angle    = 0,        -- crank angle within the 720 degree cycle, rad
		Charge   = nil,      -- trapped air per sealed cylinder (Engine.GasTorque)
		Direction = 1,       -- electric motors: selected direction, +1 forward, -1 reverse
		PreheatLeft = 0,     -- glow plug preheat still to run before the starter engages, s
		Glow     = 0,        -- glow plug heat, 0 cold .. 1 at working temperature
		CrankWarm = 0,       -- warming of the cylinder walls by the compression strokes, K
		SyncAngle = 0,       -- crank angle turned since the start was requested, rad
		Fire     = 0,        -- share of the cycles that fire, 0..1
		-- Set by the entity each tick (nil: a warm engine on a 20 °C day): AirC, BlockC, CoolantC.
		Spec     = Spec,
	}
end

--[[
	Starter motor. A series-wound DC motor: the field is in series with the armature, so the
	flux follows the current, torque is c·I² and the back-EMF c·I·ω (Chapman, Electric Machinery
	Fundamentals, the series DC motor, unsaturated). Fed from a battery of open-circuit voltage
	U0 that sags under load:
	    I = U / (R + c·ω),  T = c·I²,  U = U0 - (sag)
	so torque falls hyperbolically with speed, T = Tstall·x² / (1 + ω/ωk)², where x is the
	terminal voltage relative to the starter's rated one and ωk = R/c the speed at which it
	gives its most power (a quarter of Tstall·ωk). The circuit draws Pe = Pstall·x² / (1 + ω/ωk)
	and loses Pe - T·ω = Pstall·x² / (1 + ω/ωk)² as heat in its windings.
	A sagging or flat battery turns the starter slower and weaker (x² on torque), and a flat one
	not at all. The battery's sag is solved with the same current, so a small pack fed hard sags
	more than a large one.
	StarterKneeW: ωk, 200 rpm at the crank: starters are matched so their most power falls at
	  the engine's cranking speed (150-300 rpm, Heywood 7.6). Estimated.
	StarterRefSag: the starter is rated at its stall current from a battery whose terminal
	  voltage drops 20 % (12 V systems sit near 9.6-10 V while cranking; SAE J537 lets a
	  battery fall to 7.2 V at its cold cranking current). Estimated. An engine with no battery
	  linked cranks on its own lead-acid battery (Battery.StarterPack*, battery_model.lua), which
	  is that battery when full and warm.
	Spec.StarterMul: the starter's size relative to the standard one (a player setting, default
	  1). Torque and current scale with it at the same max-power speed.
	StarterDrag: an ideal series motor speeds up without limit as its load falls; a real one
	  is held back by brush and bearing friction, windage and armature reaction, so that its
	  no-load speed is only 2-3 times its max-power speed (starter characteristic curves, Bosch
	  Automotive Handbook, starting systems; pinion-to-ring-gear ratios 1:10-1:15). Modelled as a
	  constant drag that puts the free speed at 2.5 x ωk (500 rpm at the crank, estimated). Before
	  it, a warm 3.3 L diesel cranked at 600 rpm, its idle speed; now about 380 rpm.
	Duty: manufacturers allow 30 s of cranking, then about 2 minutes to cool (Delco Remy
	  cranking motor instructions); heavy-duty starters carry a thermal over-crank switch that
	  opens when the windings get too hot and closes once they cool. StarterDuty: 30 s at the
	  max-power point from cold opens it; StarterCoolTau: windings cool with a 60 s time constant
	  (estimated: a 2-minute rest brings them back within 14 % of cold); StarterReset: the switch
	  closes again once half the heat is gone (estimated). A starter held against a load it
	  cannot turn (locked) heats four times faster and cuts out in about 6 s.
]]
local StarterKneeW   = 200 * RPMToRad
local StarterRefSag  = 0.2
local StarterDuty    = 30
local StarterCoolTau = 60
local StarterReset   = 0.5
-- The motor's own drag as a share of stall torque, so that unloaded it runs no faster than
-- StarterFreeR times its max-power speed (see StarterDrag in the comment above).
local StarterFreeR   = 2.5
local StarterDrag    = 1 / (1 + StarterFreeR) ^ 2
-- Heating rate so that 30 s at the max-power point (winding loss Pstall/4) reaches the cut-out
-- with the cooling acting all along: Heat(t) = Rate·τ·(1 - e^(-t/τ)).
local StarterHeatTime = StarterCoolTau * (1 - exp(-StarterDuty / StarterCoolTau))
Engine.StarterRefSag = StarterRefSag

--- Rated torque and power of an engine's starter.
-- Stall torque is a margin over breakaway: four times the losses at rest plus 1.5 times the
-- cylinders' compression peak (starter selection works from the engine's breakaway torque,
-- Bosch Automotive Handbook, starting systems). Spec.StarterMul scales the result.
-- @param Spec table Engine spec.
-- @return number Stall torque at the crank [N·m], at the rated terminal voltage.
-- @return number Electrical power drawn at stall [W] (Tstall·ωk); the most mechanical power
-- (at ωk) is a quarter of it.
function Engine.StarterRating(Spec)
	local Stall = Engine.StarterBaseStall(Spec) * max(Spec.StarterMul or 1, 0.1)
	return Stall, Stall * StarterKneeW
end

--- Stall torque of the standard starter for an engine, before the size setting.
-- @param Spec table Engine spec.
-- @return number Stall torque at the crank [N·m].
function Engine.StarterBaseStall(Spec)
	local Stall = Spec.StarterStall
	if not Stall then
		-- Sized from warm-oil friction: the starter is a property of the motor and its battery,
		-- not of the oil. Cold, viscous oil (Spec.FrictionMul) then makes it crank slower, as it
		-- does in reality.
		local Mul = Spec.FrictionMul
		Spec.FrictionMul = nil
		local Breakaway = Spec.Gas and 1.5 * Spec.Gas.Peak or 0
		Stall = 4 * (Engine.FrictionTorque(Spec, 0, 0) + Engine.PumpingTorque(Spec, 0)) + Breakaway
		Spec.FrictionMul = Mul
		Spec.StarterStall = Stall
	end
	return Stall
end

-- Seconds of cranking left before the thermal cut-out, at the rated load.
local function starterTimeLeft(State)
	return max(StarterDuty * (1 - (State.StarterHeat or 0)), 1e-3)
end

--[[
	Catching: when a cranked engine fires. Nothing here is a timer; an engine catches once enough
	of its cycles fire to run it up past the speed it would stall at, and that depends on how
	fast the starter turns it and how hot the air gets in the cylinders.
	SyncAngle: no fuel or spark for the first two revolutions. An engine controller needs up to
	  two crank turns to find top centre from the crank and cam sensors before it injects (Bosch
	  Automotive Handbook, engine management: synchronisation), and a mechanical injection pump
	  must fill its lines. Estimated.
	FireLoW, FireHiW: firing speed. Below ~60 rpm spark-ignition mixtures do not form well and a
	  diesel's injection pump cannot build its pressure; by ~100 rpm both fire every cycle. Heywood
	  7.6 gives cranking speeds of 150-300 rpm and minimum firing speeds well below them; the
	  60-100 rpm band is estimated. Cold petrol needs ColdFireShiftW more at -20 °C (fuel
	  evaporates poorly; estimated).
	Wall wetting (petrol): much of the first fuel injected lands on the port and cylinder walls
	  as a film and only reaches the charge as that film builds up and evaporates (the x-tau
	  fuel film model, Aquino, SAE 810494), so the first cycles run lean and fire weakly. The
	  share that arrives is 1 - exp(-t/tau) after t seconds of fuelling. tau is WetTau = 0.3 s
	  with the charge at 55 °C (a warm engine on a 20 °C day) and doubles every WetDoubleK =
	  35 K colder, as petrol's vapour pressure falls: 0.6 s at 20 °C, 1.3 s at -20 °C
	  (estimated; Aquino's evaporation time constants run from tenths of a second warm to
	  seconds cold).
	Compression ignition (diesels): the air must get hot enough to light the fuel. At the end of
	  compression it is at T = Tcharge·rc^(n-1). The charge is the outside air warmed by the walls
	  it is drawn past: Tcharge = Tair + WallShare·(Tblock - Tair) (estimated), plus whatever
	  cranking and glow plugs add. The exponent n falls from CrankNHot (near-adiabatic, running
	  speed) towards 1 (isothermal) as the strokes slow down and the walls take the heat away
	  (Heywood 10.6, cold starting): n = CrankNHot - (CrankNHot - 1)·ωh/(ω + ωh). ωh = 48 rpm
	  gives n ≈ 1.28 at 150 rpm, so a warm diesel's cranking compression pressure (1 bar·16^1.28)
	  is ~35 bar, in the 28-35 bar workshop compression-test range (estimated).
	  IgnitionLoK..IgnitionHiK: 700-780 K, from no cycle to every cycle firing. Estimated so
	  that a diesel without glow plugs behaves as direct-injection diesels do: it starts in
	  about a second at 20 °C, cranks for seconds around 0 °C and does not start at -20 °C
	  (the 3.3 L V4 of the tests: 0.8 s, 4.9 s at 0 °C, 9.7 s at -10 °C, none at -20 °C).
	  Cranking at 250 rpm the charge reaches ~775 K warm, ~690 K at 20 °C and ~600 K at -20 °C
	  before the walls warm up.
	CrankWarmK, CrankWarmTau: each compression stroke leaves some of its heat in the walls and the
	  residual gas, so a cold diesel that is cranked for a while gets closer to firing (estimated:
	  up to 40 K, time constant 5 s; it cools off with a 60 s time constant once the crank stops).
	Glow plugs: GlowBoostK is how much hotter the charge gets with the plugs at working
	  temperature (estimated: a 900-1,000 °C tip in each chamber). They heat with a time constant
	  GlowTau = 1.5 s (95 % in 4.5 s; steel glow plugs reach 850 °C in 2-5 s, Bosch glow plug
	  data) and draw GlowW = 150 W each (12 V plugs take 10-25 A heating up, ~8 A hot; estimated).
	  The controller preheats before cranking, longest when cold: PreheatMax (a setting, default
	  5 s) at -20 °C coolant and below, nothing at 10 °C and above, linear in between (estimated
	  from glow-time-against-coolant maps of ~2-20 s; passenger-car direct-injection diesels skip
	  the preheat above about +10 °C coolant and start at once). The plugs stay on while it
	  cranks. PreheatMax 0 means no glow plugs.
	CatchMargin: the engine counts as running (the starter drops out) once it fires past 1.15 x
	  its stall speed, the speed below which a running engine stalls (estimated).
]]
local SyncAngle      = 4 * pi
local FireLoW        = 60 * RPMToRad
local FireHiW        = 100 * RPMToRad
local ColdFireShiftW = 40 * RPMToRad
local WetTau         = 0.3
local WetWarmC       = 55
local WetDoubleK     = 35
local CrankNHot      = 1.37
local CrankNHalfW    = 48 * RPMToRad
local WallShare      = 0.5
local IgnitionLoK    = 700
local IgnitionHiK    = 780
local CrankWarmK     = 40
local CrankWarmTau   = 5
local CrankCoolTau   = 60
local GlowBoostK     = 100
local GlowTau        = 1.5
local GlowW          = 150
local PreheatColdC   = -20
local PreheatWarmC   = 10
local DefaultPreheat = 5
local CatchMargin    = 1.15
-- Temperatures when the entity has not set them: a warm engine on a 20 °C day.
local WarmAirC, WarmBlockC = 20, 90

Engine.DefaultPreheat = DefaultPreheat
Engine.GlowW = GlowW

local function smooth(X)
	X = clamp(X, 0, 1)
	return X * X * (3 - 2 * X)
end

-- Outside air and engine metal temperatures for starting, °C.
local function startTemps(State)
	local Air = State.AirC or WarmAirC
	return Air, State.BlockC or (State.AirC and Air or WarmBlockC)
end

--- Glow plug preheat a diesel runs before its starter engages.
-- @param Spec table Engine spec (Spec.PreheatMax: preheat at -20 °C, s; nil: Engine.DefaultPreheat).
-- @param State table Engine state (CoolantC, or BlockC, °C).
-- @return number Seconds; 0 for engines without glow plugs and for warm diesels.
function Engine.PreheatTime(Spec, State)
	if Spec.Kind ~= "diesel" then return 0 end
	local Max = max(Spec.PreheatMax or DefaultPreheat, 0)
	local _, Block = startTemps(State)
	local Coolant = State.CoolantC or Block
	return Max * clamp((PreheatWarmC - Coolant) / (PreheatWarmC - PreheatColdC), 0, 1)
end

--- Temperature of the air at the end of compression at a crank speed (diesels).
-- @param Spec table Engine spec.
-- @param State table Engine state (temperatures, CrankWarm, Glow).
-- @param W number Crank speed, rad/s.
-- @return number Kelvin.
function Engine.CompressionTemp(Spec, State, W)
	local Gas = Spec.Gas
	local Rc = Gas and (Gas.Vcyl + Gas.Vc) / Gas.Vc or Spec.K.CompressionRatio or 10
	local Air, Block = startTemps(State)
	local Charge = 273.15 + Air + WallShare * (Block - Air) + (State.CrankWarm or 0) + GlowBoostK * (State.Glow or 0)
	local N = CrankNHot - (CrankNHot - 1) * CrankNHalfW / (abs(W) + CrankNHalfW)
	return Charge * Rc ^ (N - 1)
end

--- Share of the cycles that fire at a crank speed, given fuel.
-- @param Spec table Engine spec.
-- @param State table Engine state.
-- @param W number Crank speed, rad/s.
-- @return number 0..1.
function Engine.FireFraction(Spec, State, W)
	local S = abs(W)
	if Spec.Kind == "diesel" then
		local Speed = smooth((S - FireLoW) / (FireHiW - FireLoW))
		if Speed <= 0 then return 0 end
		return Speed * smooth((Engine.CompressionTemp(Spec, State, S) - IgnitionLoK) / (IgnitionHiK - IgnitionLoK))
	end
	local Air, Block = startTemps(State)
	local Charge = Air + WallShare * (Block - Air)
	local Lo = FireLoW + ColdFireShiftW * clamp((20 - Charge) / 40, 0, 1)
	return smooth((S - Lo) / (FireHiW - FireLoW))
end

--- Share of the injected petrol that reaches the cylinders during a start (spark ignition).
-- @param State table Engine state (FuelTime: seconds fuelled so far; temperatures).
-- @return number 0..1.
function Engine.WallWetting(State)
	local Air, Block = startTemps(State)
	local Tau = WetTau * 2 ^ clamp((WetWarmC - (Air + WallShare * (Block - Air))) / WetDoubleK, -1, 3)
	return 1 - exp(-(State.FuelTime or 0) / Tau)
end

--- Requests a start. Combustion engines preheat (diesels with glow plugs, when cold), then
-- crank on their starter until they catch, for as long as the start is held (Engine.Stop
-- releases it) and the battery and the starter's thermal cut-out allow.
-- @param State table Engine state.
function Engine.Start(State)
	local Spec = State.Spec
	if Spec.Kind == "electric" or Spec.Kind == "turbine" then
		State.Running = true
		State.Stalled = false
		return
	end
	State.StarterOn = true
	State.SyncAngle = 0
	State.FuelTime = 0
	State.PreheatLeft = Engine.PreheatTime(Spec, State)
	State.Cranking = (State.StarterCut or State.PreheatLeft > 0) and 0 or starterTimeLeft(State)
	State.Stalled = false
end

--- Stops combustion (key off or out of fuel) and releases the starter. The crank keeps
-- spinning down on friction.
-- @param State table Engine state.
function Engine.Stop(State)
	State.Running = false
	State.StarterOn = false
	State.Cranking = 0
	State.PreheatLeft = 0
end

--[[
	One step of the starter and the glow plugs: the starter's torque on the crank, the energy both
	draw (State.StarterJ, billed to the battery by the entity) and the starter's winding heat.
	State.StarterSupply describes the battery (nil: a full, warm battery that never runs down,
	see StarterRefSag):
	  Volt     open-circuit voltage relative to that battery's when full and new (0 when flat)
	  Sag      fractional voltage drop the starter's stall power alone would cause (k·Pstall,
	           with k the battery's resistive loss per watt, Battery.StarterSupply)
	  EnergyJ  energy left in it, J (nil: unlimited)
]]
local function starterStep(Spec, State, W, Dt)
	local Heat = State.StarterHeat or 0
	local Torque = 0
	local Starting = State.StarterOn and not State.Running
	local Supply = State.StarterSupply
	local Volt = Supply and Supply.Volt or 1
	if Supply and Supply.EnergyJ and Supply.EnergyJ <= (State.StarterJ or 0) then Volt = 0 end

	-- Glow plugs: on from the moment the start is requested until the engine runs, while the
	-- battery has anything to give.
	local Plugs = Spec.Kind == "diesel" and (Spec.PreheatMax or DefaultPreheat) > 0
	local GlowOn = Plugs and Starting and Volt > 0
	local GlowTarget = GlowOn and 1 or 0
	State.Glow = GlowTarget + ((State.Glow or 0) - GlowTarget) * exp(-Dt / GlowTau)
	if GlowOn then State.StarterJ = (State.StarterJ or 0) + GlowW * Spec.Cylinders * Dt end

	-- The cylinder walls warm up while the crank is turned over.
	local Turning = abs(W) > FireLoW
	local WarmTarget = Turning and CrankWarmK or 0
	State.CrankWarm = WarmTarget + ((State.CrankWarm or 0) - WarmTarget) * exp(-Dt / (Turning and CrankWarmTau or CrankCoolTau))

	-- The controller waits for the preheat before it engages the starter.
	local Preheating = Starting and (State.PreheatLeft or 0) > 0
	if Preheating and (GlowOn or not Plugs) then
		State.PreheatLeft = max(State.PreheatLeft - Dt, 0)
	end
	State.Preheating = Preheating

	if Starting and not Preheating then
		if Heat >= 1 then State.StarterCut = true end
		if State.StarterCut and Heat <= StarterReset then State.StarterCut = false end
		if not State.StarterCut then
			local Stall, StallW = Engine.StarterRating(Spec)
			local Sag = Supply and Supply.Sag or StarterRefSag
			if Volt > 0 then
				local R = max(W, 0) / StarterKneeW
				-- Terminal voltage x (relative to the rated one) from x = x0·(1 - Sag·x²/(1 + R)),
				-- in the form that stays accurate when the sag is small.
				local X0 = Volt / (1 - StarterRefSag)
				local B = Sag / (1 + R)
				local X = 2 * X0 / (1 + sqrt(1 + 4 * X0 * X0 * B))
				local F = X * X / (1 + R)
				-- Less the motor's own brush, bearing and windage drag; the pinion's overrunning
				-- clutch never lets it hold the crank back.
				Torque = max(Stall * (F / (1 + R) - StarterDrag), 0)
				State.StarterJ = (State.StarterJ or 0) + StallW * F * Dt
				-- Winding loss over the loss at the max-power point (StallW / 4).
				Heat = Heat + 4 * F / (1 + R) * Dt / StarterHeatTime
			end
		end
	end
	State.StarterHeat = Heat * exp(-Dt / StarterCoolTau)
	State.Cranking = Torque > 0 and starterTimeLeft(State) or 0
	-- How hard the starter is pulling, 0..1: 1 when it is bogged down against a load it cannot
	-- turn (the sound of a struggling starter), falling as it spins up freely.
	State.StarterLoad = Torque > 0 and clamp(1 / (1 + max(W, 0) / StarterKneeW), 0, 1) or 0
	return Torque
end

--[[
	Idle governor. A PI controller on air fraction, like an idle air control valve or a
	diesel governor's low-idle spring. Gains are normalised by the air fraction needed to
	overcome losses at idle, so the same numbers work from a 50 cc single to a tank V12.
]]
local function idleAir(Spec, State, Dt)
	-- Until the engine has caught, the start map runs richer with more air (fast idle).
	local Auth = State.Caught and Spec.K.IdleAuthority or max(Spec.K.IdleAuthority, 0.6)
	local Err = (Spec.IdleW - State.W) / Spec.IdleW
	State.IdleInt = clamp(State.IdleInt + Err * 2.5 * Dt, 0, Auth)
	return clamp(State.IdleInt + Err * 1.5, 0, Auth)
end

--- Limits a motor's generating (braking) torque to the charging power the battery accepts.
-- @param Spec Electric engine spec.
-- @param State Engine state. State.RegenLimitW is the most charging power the battery takes
-- (set by the entity from the battery's charge acceptance); nil means no limit.
-- @param Torque Braking torque magnitude wanted, N·m.
-- @param Speed Shaft speed magnitude, rad/s.
-- @return Braking torque magnitude allowed, N·m.
function Engine.GeneratorLimit(Spec, State, Torque, Speed)
	local Limit = State.RegenLimitW
	if not Limit or Torque <= 0 then return Torque end
	-- Power reaching the battery: shaft power less the motor and inverter losses.
	local Charge = Torque * Speed - Engine.MotorLoss(Spec, Torque)
	if Charge > Limit then return Torque * max(Limit, 0) / Charge end
	return Torque
end

--- Advances the engine's own control state and returns the torque it applies to the crank.
-- Call this once per solver substep with the crank speed the drivetrain solver left.
-- @param State Engine state.
-- @param Throttle Pedal 0..1. Electric motors also take -1..0: a regenerative braking command
-- (fraction of the motor's torque envelope). 0 is no regen. A motor drives in the direction
-- State.Direction selects (+1 forward, -1 reverse); other engines only turn forwards.
-- @param Dt Substep length in seconds.
-- @param Opts Optional { NoStall = bool, HasFuel = bool }.
-- @return Drive torque (combustion, starter or motor, and the cylinders' gas springs) in N·m, and loss torque magnitude in N·m
-- (friction and pumping). Losses are returned separately so the caller can apply them as
-- friction that never reverses the crank.
function Engine.Step(State, Throttle, Dt, Opts)
	local Spec = State.Spec
	local K = Spec.K
	local W = State.W
	local HasFuel = not Opts or Opts.HasFuel ~= false
	local NoStall = Opts and Opts.NoStall

	if Spec.Kind == "electric" then
		-- A motor has no idle, no stall and no starter: at 0 rpm it gives full torque.
		local On = State.Running and HasFuel
		local Pedal = clamp(Throttle, 0, 1)
		local Speed = abs(W)
		local Envelope = Spec.BrakeWOT(Speed)
		local Dir = State.Direction == -1 and -1 or 1

		--[[
			The inverter commands torque in the selected direction (State.Direction, +1 forward,
			-1 reverse). A motor turning the selected way is driven up to its rated top speed. One
			still turning the other way (reverse selected while rolling forward) gets the same
			torque, which now opposes its rotation: a four-quadrant drive brakes it as a generator
			down to standstill and then drives it the new way, so the rotor and everything geared
			to it slow through zero instead of reversing at once. At speed the braking charges the
			battery and is limited to what the battery accepts, like regen; near standstill it
			draws power (plugging), which is how a controller finishes the stop.
		]]
		local Drive = 0
		if On and Pedal > 0 then
			if W * Dir >= 0 then
				if Speed <= Spec.LimitW then Drive = Dir * Pedal * Envelope end
			else
				Drive = Dir * Engine.GeneratorLimit(Spec, State, Pedal * Envelope, Speed)
			end
		end

		-- Regenerative braking on a negative throttle: the motor brakes as a generator and
		-- charges the battery, in either direction of rotation. It is applied as drag, so it
		-- slows the crank but can never spin it backwards.
		local Regen = 0
		if On and Throttle < 0 then
			local Fade = clamp(Speed / (K.RegenFadeFrac * Spec.LimitW), 0, 1)
			Regen = Engine.GeneratorLimit(Spec, State, clamp(-Throttle, 0, 1) * Envelope * Fade, Speed)
		end

		local Friction = Engine.FrictionTorque(Spec, W, 0)
		local Sign = W >= 0 and 1 or -1
		-- Electromagnetic torque: drive minus regen (regen always opposes rotation).
		local Tem = Drive - Regen * Sign
		local Copper = Engine.MotorLoss(Spec, Tem)

		State.Load = Pedal
		State.Regen = Regen
		State.Torque = Drive - (Friction + Regen) * Sign
		-- Electric "fuel" is energy: battery power in W, negative while regenerating.
		State.FuelRate = Tem * W + Copper
		State.HeatRate = Copper + Friction * Speed
		return Drive, Friction + Regen
	end

	if Spec.Kind == "turbine" then
		-- The output shaft is a free power turbine: nothing to stall, no idle governor on it.
		local Target = (State.Running and HasFuel) and (K.IdleSpool + (1 - K.IdleSpool) * clamp(Throttle, 0, 1)) or 0
		-- Gas generator spool lag: first order, time constant SpoolTime. The exact discrete
		-- form, so the response is the same at any tickrate or substep count.
		State.Spool = State.Spool + (Target - State.Spool) * (1 - exp(-Dt / K.SpoolTime))
		local Over = W > Spec.LimitW
		local Drive = Over and 0 or State.Spool * Spec.BrakeWOT(max(W, 0))
		local Loss = Engine.FrictionTorque(Spec, W, State.Spool)
		State.Load = State.Spool
		State.Torque = Drive - Loss * (W >= 0 and 1 or -1)
		State.FuelRate = Engine.TurbineFuelRate(Spec, State.Spool)
		State.HeatRate = State.FuelRate * K.LHV * K.CoolantFrac
		return Drive, Loss
	end

	-- Reciprocating / rotary combustion engines.
	local Load = 0
	-- Firing (see "Catching" above): a share of the cycles fires, set by crank speed and, for
	-- diesels, the compression temperature. With the start held the engine is fuelled on the
	-- start map once it has synchronised, however the crank is turned: by the starter, or
	-- rolling in gear with the starter cut out or the battery flat (a push start). The fired
	-- cycles run it up, and once it fires past its stall speed it runs and the start is
	-- released, as the starter relay drops out on a running engine.
	local Fire = 0
	if HasFuel and (State.Running or State.StarterOn) then
		Fire = Engine.FireFraction(Spec, State, W)
	end
	if State.StarterOn and not State.Running then
		State.SyncAngle = (State.SyncAngle or 0) + abs(W) * Dt
		if HasFuel and State.SyncAngle >= SyncAngle then
			Load = max(clamp(Throttle, 0, 1), max(K.IdleAuthority, 0.6))
			State.FuelTime = (State.FuelTime or 0) + Dt
			if Spec.Kind ~= "diesel" then Fire = Fire * Engine.WallWetting(State) end
		else
			Fire = 0
		end
	end

	if State.Running and HasFuel then
		local Pedal = clamp(Throttle, 0, 1)
		Load = max(Pedal, idleAir(Spec, State, Dt))

		if K.DroopGovernor then
			-- Diesel all-speed governor: fuel ramps out between rated and high-idle
			-- (+6%) instead of a hard cut.
			local Hi = Spec.LimitW * 1.06
			Load = min(Load, clamp((Hi - W) / (Hi - Spec.LimitW), 0, 1))
		else
			-- Spark-ignition rev limiter as modern engine controllers do it: a progressive
			-- cylinder cut over the last ~150 RPM rather than an on/off fuel cut, so the engine
			-- holds the limit and burns only what holding it takes (Bosch Automotive Handbook,
			-- 10th ed., engine management: speed limitation by selective injection cut-off).
			local Band = 150 * RPMToRad
			Load = min(Load, clamp((Spec.LimitW + 0.5 * Band - W) / Band, 0, 1))
			State.Cut = W > Spec.LimitW + 0.5 * Band
		end

		-- Once the engine has run up to idle, dropping back below the stall speed stalls it.
		if W > Spec.IdleW * 0.9 then State.Caught = true end
		if State.Caught and not NoStall and W < Spec.IdleW * K.StallFrac then
			State.Running = false
			State.Stalled = true
			Load = 0
		end
	end

	if Load <= 0 then Fire = 0 end
	State.Fire = Fire
	-- Injected fuel follows Load; only the cycles that fire make torque and heat (a misfiring
	-- cold diesel blows the rest out unburnt).
	local Injected = Load * Engine.IndicatedWOT(Spec, max(W, 0))
	local Combustion = Injected * Fire
	local Loss = Engine.FrictionTorque(Spec, W, Load * Fire) + Engine.PumpingTorque(Spec, Load, W)

	-- Caught: past its stall speed and firing well enough to keep itself turning without the
	-- starter. It runs from here and the start is released.
	if State.StarterOn and not State.Running and Combustion > Loss and W > Spec.IdleW * K.StallFrac * CatchMargin then
		State.Running = true
		State.Caught = false
		State.StarterOn = false
		State.Cranking = 0
		State.IdleInt = 0.2
	end
	local GasSpring = Engine.GasTorque(Spec, State, Dt)

	-- Starter motor fed from the battery (starterStep): pushes the first cylinder over
	-- compression from rest, then cranks.
	local Starter = starterStep(Spec, State, W, Dt)

	State.Load = Load
	State.StarterTorque = Starter
	State.GasTorque = GasSpring
	State.Torque = Combustion + Starter + GasSpring - Loss * (W >= 0 and 1 or -1)

	local Pfuel = Combustion * max(W, 0) / K.EtaIndicated
	State.FuelRate = Injected * max(W, 0) / K.EtaIndicated / K.LHV
	-- Coolant heat: the share of fuel energy measured in the coolant on test beds. Friction
	-- heat is part of that measurement (it ends up in the oil and coolant), so it is not added
	-- again (Heywood 12.1, table 12.1).
	State.HeatRate = Pfuel * K.CoolantFrac

	return Combustion + Starter + GasSpring, Loss
end

--- Estimates how long a start takes: the engine alone (in neutral, no accessories) from rest
-- with the start held, until it runs. Used by the engine menu.
-- @param Spec table Engine spec (StarterMul and PreheatMax are used).
-- @param Opts table|nil { AirC, BlockC, CoolantC (°C; nil: warm), FrictionMul (oil), Supply
-- (State.StarterSupply), MaxTime (s, default 20) }.
-- @return number|nil Seconds from the start request until it runs, nil if it does not.
-- @return number Of that, seconds spent preheating.
function Engine.SimulateStart(Spec, Opts)
	Opts = Opts or {}
	if Spec.Kind == "electric" or Spec.Kind == "turbine" then return 0, 0 end
	local OldMul = Spec.FrictionMul
	Spec.FrictionMul = Opts.FrictionMul
	local State = Engine.NewState(Spec)
	State.AirC, State.BlockC, State.CoolantC = Opts.AirC, Opts.BlockC, Opts.CoolantC
	State.StarterSupply = Opts.Supply
	Engine.Start(State)
	local Preheat = State.PreheatLeft or 0

	local Dt, T, J = 0.002, 0, Spec.Inertia
	local Result
	while T < (Opts.MaxTime or 20) do
		local Drive, Loss = Engine.Step(State, 0, Dt)
		-- Losses act as friction: they slow the crank but never turn it backwards.
		local W = State.W + Drive / J * Dt
		local Drag = Loss / J * Dt
		if W > Drag then W = W - Drag elseif W < -Drag then W = W + Drag else W = 0 end
		State.W = W
		T = T + Dt
		if State.Running then
			Result = T
			break
		end
	end
	Spec.FrictionMul = OldMul
	return Result, Preheat
end

return Engine

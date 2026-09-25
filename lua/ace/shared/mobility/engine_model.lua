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
]]
Engine.Kinds = {
	si = {
		A = 0.173, B = 0.005, C = 0.0462, D = 0.0021,
		PumpClosed = 0.75, PumpOpen = 0.15,
		PmaxIdle = 6, PmaxFull = 60,
		EtaIndicated = 0.36, CoolantFrac = 0.28, LHV = 43.3e6,
		Strokes = 4, StallFrac = 0.35, IdleAuthority = 0.45,
	},
	diesel = {
		A = 0.445, B = 0.005, C = 0, D = 0.0136,
		PumpClosed = 0.25, PumpOpen = 0.2,
		PmaxIdle = 42, PmaxFull = 150,
		EtaIndicated = 0.45, CoolantFrac = 0.25, LHV = 42.6e6,
		Strokes = 4, StallFrac = 0.4, IdleAuthority = 1, DroopGovernor = true,
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

	local DispL = Engine.Displacement(Def)
	if not DispL or DispL <= 0 then
		-- Unknown size: back out displacement from peak torque via BMEP. Heywood 2.7 puts
		-- naturally aspirated SI at ~10 bar and turbo diesels at ~15-20 bar at peak torque.
		local Bmep = (Kind == "diesel") and 16 or 10
		DispL = Def.torque * 4 * pi / (Bmep * BarToPa) * 1000
	end
	Spec.DispL = DispL
	Spec.Vd = DispL / 1000

	local Cyl = Def.cylinders or CylindersByCategory[Def.category] or 4
	Spec.Cylinders = Cyl

	if K.Strokes then
		-- Square engine (bore = stroke) when geometry is not given.
		local Vcyl = Spec.Vd / Cyl
		Spec.Stroke = Def.stroke or (4 * Vcyl / pi) ^ (1 / 3)
		-- Converts a mean effective pressure [Pa] into crank torque [N·m] (Heywood eq. 2.19).
		Spec.MepToTorque = Spec.Vd / (2 * pi * (K.Strokes / 2))
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
-- @param Spec Engine spec.
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
	return Fmep * BarToPa * Spec.MepToTorque
end

--- Pumping torque: manifold vacuum against exhaust back-pressure.
-- @param Spec Engine spec.
-- @param Load Air fraction 0..1.
-- @return Pumping torque in N·m (positive, opposes rotation).
function Engine.PumpingTorque(Spec, Load)
	local K = Spec.K
	if not K.PumpClosed then return 0 end
	local Pmep = K.PumpClosed + (K.PumpOpen - K.PumpClosed) * Load
	return Pmep * BarToPa * Spec.MepToTorque
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
		Cranking = 0,        -- starter time remaining, s
		IdleInt  = 0.15,     -- idle governor integrator (air fraction)
		Spool    = 0,        -- turbine gas generator spool 0..1
		Cut      = false,    -- rev limiter fuel cut latched
		Load     = 0,        -- effective air fraction used last step
		Torque   = 0,        -- net brake torque last step, N·m
		FuelRate = 0,        -- kg/s
		HeatRate = 0,        -- W into the engine block / coolant
		Stalled  = false,
		Spec     = Spec,
	}
end

--- Requests a start. Combustion engines crank on their starter until they catch.
function Engine.Start(State)
	local Spec = State.Spec
	if Spec.Kind == "electric" or Spec.Kind == "turbine" then
		State.Running = true
		State.Stalled = false
		return
	end
	State.Cranking = 3
	State.Stalled = false
end

--- Stops combustion (key off or out of fuel). The crank keeps spinning down on friction.
function Engine.Stop(State)
	State.Running = false
	State.Cranking = 0
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

--- Advances the engine's own control state and returns the torque it applies to the crank.
-- Call this once per solver substep with the crank speed the drivetrain solver left.
-- @param State Engine state.
-- @param Throttle Pedal 0..1. Electric motors also take -1..0: a regenerative braking command
-- (fraction of the motor's torque envelope). 0 is no regen.
-- @param Dt Substep length in seconds.
-- @param Opts Optional { NoStall = bool, HasFuel = bool }.
-- @return Drive torque (combustion, starter or motor) in N·m, and loss torque magnitude in N·m
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
		-- The inverter stops driving past the rated top speed.
		local Drive = (On and Speed <= Spec.LimitW) and Pedal * Envelope or 0

		-- Regenerative braking on a negative throttle: the motor brakes as a generator and
		-- charges the battery. It is applied as drag, so it slows the crank but can never spin
		-- it backwards.
		local Regen = 0
		if On and Throttle < 0 then
			local Fade = clamp(Speed / (K.RegenFadeFrac * Spec.LimitW), 0, 1)
			Regen = clamp(-Throttle, 0, 1) * Envelope * Fade
			-- A full (or refusing) battery takes no charge: State.RegenLimitW is the most
			-- charging power it accepts, set by the entity; nil means no limit.
			local Limit = State.RegenLimitW
			if Limit and Regen > 0 then
				local Charge = Regen * Speed - Engine.MotorLoss(Spec, Regen)
				if Charge > Limit then Regen = Regen * max(Limit, 0) / Charge end
			end
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
	if State.Cranking > 0 and not State.Running then
		State.Cranking = State.Cranking - Dt
		-- Engines fire once cranked past ~120-150 RPM with fuel (Heywood 7.6; starter
		-- cranking speeds are 150-300 RPM).
		if HasFuel and W > 130 * RPMToRad then
			State.Running = true
			State.Caught = false
			State.Cranking = 0
			State.IdleInt = 0.2
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

	local Combustion = Load * Engine.IndicatedWOT(Spec, max(W, 0))
	local Loss = Engine.FrictionTorque(Spec, W, Load) + Engine.PumpingTorque(Spec, Load)

	local Starter = 0
	if State.Cranking > 0 and not State.Running then
		-- Starter motor: series-wound DC, torque falling linearly from stall to its free speed;
		-- sized to crank at 200-250 RPM against the engine's motoring losses.
		local Free = 450 * RPMToRad
		local StallTq = 4 * (Engine.FrictionTorque(Spec, 0, 0) + Engine.PumpingTorque(Spec, 0))
		Starter = StallTq * clamp(1 - W / Free, 0, 1)
	end
	-- How hard the starter is pulling, 0..1: 1 when it is bogged down against a load it cannot
	-- turn (the sound of a struggling starter), falling as it spins up freely.
	State.StarterLoad = Starter > 0 and clamp(1 - W / (450 * RPMToRad), 0, 1) or 0

	State.Load = Load
	State.StarterTorque = Starter
	State.Torque = Combustion + Starter - Loss * (W >= 0 and 1 or -1)

	local Pind = Combustion * max(W, 0)
	local Pfuel = Pind / K.EtaIndicated
	State.FuelRate = Pfuel / K.LHV
	-- Coolant heat: the share of fuel energy measured in the coolant on test beds. Friction
	-- heat is part of that measurement (it ends up in the oil and coolant), so it is not added
	-- again (Heywood 12.1, table 12.1).
	State.HeatRate = Pfuel * K.CoolantFrac

	return Combustion + Starter, Loss
end

return Engine

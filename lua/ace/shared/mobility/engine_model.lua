--[[
	Engine model: indicated torque, friction and pumping losses, idle governor,
	rev limiter, stall/start and fuel/heat flow. Pure Lua, no GMod calls, so it
	can be unit-tested under LuaJIT.

	References (full list in docs/mobility-sources.md):
	- J. B. Heywood, Internal Combustion Engine Fundamentals, 2nd ed., McGraw-Hill 2018.
	  Ch. 2 (mean effective pressure, T = mep·Vd/(2π·nR)), ch. 13 (friction, pumping),
	  ch. 12 (energy balance), App. D (fuel heating values).
	- Chen & Flynn, SAE 650733 (1965): FMEP = A + B·pmax + C·Sf + D·Sf², Sf = ω·S/2.
	  Gasoline constants from the x-engineer.org worked example (2.0 L I4).
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
	Per-kind constants.
	FMEP (Chen-Flynn): A [bar], B [-], C [bar·s/m], D [bar·s²/m²].
	PumpClosed: pumping MEP with the throttle shut [bar]; PumpOpen at wide-open throttle.
	  SI engines idle at ~0.3 bar manifold pressure, so closed-throttle pumping is ~0.7-0.8 bar
	  (Heywood 13.2). Diesels are unthrottled: pumping stays near the WOT value, which is why
	  diesels have weak engine braking.
	Pmax: peak cylinder pressure at no load / full load [bar] (Heywood 9.2, 10.2).
	EtaIndicated: gross indicated fuel conversion efficiency (Heywood 5.7): SI ~0.36, DI diesel ~0.45.
	CoolantFrac: share of fuel energy rejected to coolant (Heywood 12.1, table 12.1).
	IdleAuthority: most air/fuel the idle governor may add. A petrol idle-air valve or
	  drive-by-wire idle controller only opens far enough to catch the engine, not to pull a car; a diesel's mechanical governor can deliver
	  full fuel to hold idle, which is why diesels crawl in gear with no throttle.
	LHV: lower heating value [J/kg] (Heywood App. D).
]]
Engine.Kinds = {
	si = {
		A = 0.3, B = 0.006, C = 0.05, D = 0.00085,
		PumpClosed = 0.75, PumpOpen = 0.15,
		PmaxIdle = 15, PmaxFull = 60,
		EtaIndicated = 0.36, CoolantFrac = 0.28, LHV = 43.4e6,
		Strokes = 4, StallFrac = 0.35, IdleAuthority = 0.45,
	},
	diesel = {
		A = 0.4, B = 0.005, C = 0.05, D = 0.00085,
		PumpClosed = 0.25, PumpOpen = 0.2,
		PmaxIdle = 40, PmaxFull = 150,
		EtaIndicated = 0.45, CoolantFrac = 0.25, LHV = 42.6e6,
		Strokes = 4, StallFrac = 0.4, IdleAuthority = 1, DroopGovernor = true,
	},
	rotary = {
		-- A Wankel fires once per rotor per crank revolution; treated as a 4-stroke of
		-- twice the chamber displacement, the usual convention for comparisons.
		A = 0.45, B = 0.006, C = 0.06, D = 0.001,
		PumpClosed = 0.75, PumpOpen = 0.15,
		PmaxIdle = 12, PmaxFull = 55,
		EtaIndicated = 0.30, CoolantFrac = 0.30, LHV = 43.4e6,
		Strokes = 4, StallFrac = 0.35, IdleAuthority = 0.45,
	},
	turbine = {
		-- Free power turbine: the output shaft is not the gas generator, it can sit at 0 RPM
		-- under load without stalling (Abrams-style creep). Losses are bearings/windage only.
		EtaIndicated = 0.25, CoolantFrac = 0.02, LHV = 42.8e6,
		SpoolTime = 1.2, IdleSpool = 0.12,
	},
	electric = {
		EtaIndicated = 0.9, CoolantFrac = 0.08,
	},
}

local CylindersByCategory = {
	Single = 1, I2 = 2, I3 = 3, I4 = 4, I5 = 5, I6 = 6,
	V2 = 2, V4 = 4, V6 = 6, V8 = 8, V10 = 10, V12 = 12,
	B4 = 4, B6 = 6, Radial = 9, Rotary = 2,
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
	Rotating inertia of crank + flywheel + clutch when a definition has no measured value.
	Fitted to published figures: 1.6 L I4 ≈ 0.12 kg·m², 5.7 L V8 ≈ 0.35, 12 L truck diesel
	≈ 1.9 (with its heavy flywheel), 38.9 L V-2/AVDS-class ≈ 5.5. Diesels carry heavier
	flywheels (×1.6) to smooth fewer, stronger firing pulses. Sources in docs/mobility-sources.md.
]]
local function estimateInertia(DispL, Kind)
	local J = 0.075 * DispL ^ 1.15
	if Kind == "diesel" then J = J * 1.6 end
	if Kind == "rotary" then J = J * 0.7 end
	return J
end

--- Builds the physical description of an engine from its ACE definition.
-- @param Def Engine definition (fields torque, idlerpm, limitrpm, fuel, enginetype, category, name, torquecurve).
-- @param Curve Torque curve points (0..1) already adjusted for fuel type.
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
	if Kind == "electric" then Spec.Inertia = Def.inertia or 0.02 * (Def.torque / 100) ^ 0.8 end
	if Kind == "turbine" then Spec.Inertia = Def.inertia or 0.5 * (Def.torque / 1000) ^ 0.8 end

	-- Torque at wide-open throttle straight off the definition's curve.
	Spec.BrakeWOT = function(W)
		local RPM = W / RPMToRad
		local Perc = (RPM - Spec.IdleRPM) / (Spec.LimitRPM - Spec.IdleRPM)
		-- Below idle the curve is undefined; per-cycle torque stays roughly at its idle value
		-- (volumetric efficiency is high at low speed), so hold the first point.
		local Tq = sampleCurve(Curve, Perc) * Spec.PeakTorque
		return max(Tq, 0)
	end

	return Spec
end

--- Friction torque (rubbing + accessories) at a given speed and load, Chen-Flynn.
-- @param Spec Engine spec.
-- @param W Crank speed in rad/s.
-- @param Load Air/fuel fraction 0..1 (sets peak cylinder pressure).
-- @return Friction torque in N·m (positive, opposes rotation).
function Engine.FrictionTorque(Spec, W, Load)
	local K = Spec.K
	if not K.A then
		-- Turbines and motors: bearings and windage, about 1-2% of peak torque at speed.
		local Frac = 0.01 + 0.01 * min(abs(W) / max(Spec.LimitW, 1), 1.5)
		return Spec.PeakTorque * Frac
	end
	local Sf = abs(W) * Spec.Stroke / 2
	local Pmax = K.PmaxIdle + (K.PmaxFull - K.PmaxIdle) * Load
	local Fmep = K.A + K.B * Pmax + K.C * Sf + K.D * Sf * Sf
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
-- @param Throttle Pedal 0..1.
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
		local Load = State.Running and HasFuel and clamp(Throttle, 0, 1) or 0
		local Drive = Load * Spec.BrakeWOT(abs(W))
		local Loss = Engine.FrictionTorque(Spec, W, Load)
		State.Load = Load
		State.Torque = Drive - Loss * (W >= 0 and 1 or -1)
		local Pmech = max(Drive * W, 0)
		State.FuelRate = Pmech / K.EtaIndicated -- electric "fuel" is energy: W
		State.HeatRate = State.FuelRate - Pmech + Loss * abs(W)
		return Drive, Loss
	end

	if Spec.Kind == "turbine" then
		local Target = (State.Running and HasFuel) and (K.IdleSpool + (1 - K.IdleSpool) * clamp(Throttle, 0, 1)) or 0
		-- Gas generator spool lag: first order, time constant SpoolTime.
		State.Spool = State.Spool + (Target - State.Spool) * (1 - exp(-Dt / K.SpoolTime))
		local Over = W > Spec.LimitW
		local Drive = Over and 0 or State.Spool * Spec.BrakeWOT(max(W, 0))
		local Loss = Engine.FrictionTorque(Spec, W, State.Spool)
		State.Load = State.Spool
		State.Torque = Drive - Loss * (W >= 0 and 1 or -1)
		local Pfuel = (State.Spool * Spec.PeakTorque * Spec.LimitW * 0.5) / K.EtaIndicated
		State.FuelRate = Pfuel / K.LHV
		State.HeatRate = Pfuel * K.CoolantFrac
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
			if W > Spec.LimitW then State.Cut = true end
			if State.Cut and W < Spec.LimitW - 150 * RPMToRad then State.Cut = false end
			if State.Cut then Load = 0 end
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

	State.Load = Load
	State.Torque = Combustion + Starter - Loss * (W >= 0 and 1 or -1)

	local Pind = Combustion * max(W, 0)
	local Pfuel = Pind / K.EtaIndicated
	State.FuelRate = Pfuel / K.LHV
	-- Coolant heat: the fuel-energy share plus mechanical friction, which ends up in the oil
	-- and coolant as well.
	State.HeatRate = Pfuel * K.CoolantFrac + Engine.FrictionTorque(Spec, W, Load) * abs(W)

	return Combustion + Starter, Loss
end

return Engine

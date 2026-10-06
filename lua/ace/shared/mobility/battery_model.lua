--[[
	Battery model: a Li-ion (NMC/graphite) traction pack as one lumped thermal mass, with
	resistive losses, CC-CV charge acceptance, temperature limits from the battery management
	system, and wear (capacity fade and resistance growth). Pure Lua, no GMod calls, so it can be
	unit-tested under LuaJIT.

	Energy is counted in watt-hours of stored charge. The engine asks for terminal power; the
	pack loses I²R on top of it, which heats the cells:

	    P_loss = Loss1C · R · P² / E_nom        (P in W, E_nom in Wh; R relative to new)

	so a pack delivering its own capacity per hour (1C) loses Loss1C of it. The cells cool to the
	air through the pack's skin, and the step is solved exactly, so results do not depend on the
	tickrate.

	Wear follows the semi-empirical ageing model of Schmalstieg et al. 2014 for NMC/graphite
	18650 cells, as reproduced by NREL's BLAST-Lite (nmc111_gr_Sanyo2Ah_2014.py):
	  calendar  Q_loss = α(V, T) · t^0.75            t in days, T in K
	  cycling   Q_loss = β(V, DOD) · √Q               Q = charge throughput per cell in Ah
	  resistance grows the same way (t^0.75 calendar, linear in Q for cycling).
	α rises with cell voltage (so a pack held full ages about twice as fast as one at half
	charge) and with temperature through an Arrhenius term (an overheated pack ages many times
	faster); β rises with depth of discharge and with voltage away from 3.67 V.

	References (full list in docs/mobility-sources.md, section Batteries):
	- J. Schmalstieg, S. Käbitz, M. Ecker, D. U. Sauer, "A holistic aging model for
	  Li(NiMnCo)O2 based 18650 lithium-ion batteries", J. Power Sources 257 (2014) 325-334;
	  coefficients and the OCV table as reproduced in NREL BLAST-Lite.
	- LG Chem INR21700-M50 product specification: 5.0 Ah, 3.63 V, DCIR 30 mΩ, charge 0-50 °C,
	  discharge up to 60 °C, standard charge CC-CV to 4.2 V.
	- Battery University BU-409 "Charging Lithium-ion": 1C CC reaches 4.2 V at ~85 % charge,
	  the CV stage ends when the current falls to 3-5 % of the Ah rating.
	- Steinhardt et al., J. Power Sources 522 (2022) 230829: cylindrical cell heat capacity,
	  median 912 J/(kg·K); steel 480 J/(kg·K).
]]

ACE = ACE or {}
ACE.Mobility = ACE.Mobility or {}

local Battery = {}
ACE.Mobility.Battery = Battery

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

--[[
	Constants. Every value and its source is listed in docs/mobility-sources.md.
	Loss1C: resistive loss as a fraction of power at a 1C rate, R·I/V for one cell. LG M50:
	  30 mΩ DC resistance × 5 A / 3.63 V = 0.041.
	CellCp: specific heat of the cells [J/(kg·K)], Steinhardt 2022 median for cylindrical cells.
	CaseCp: steel housing [J/(kg·K)], Steinhardt 2022 table 3.
	SkinH: natural convection from the pack's outer skin [W/(m²·K)]; Incropera table 1.1 gives
	  2-25, the same 10 the engine skin uses (estimated).
	PlateH: cells to coolant through a liquid cold plate [W/(m²·K)] (estimated, inside the
	  100-1000 range of forced liquid convection, Incropera table 1.1), over PlateShare of the
	  pack's outer area (plates under the modules and fins between them: about a third,
	  estimated).
	LoopC: coolant flow of a battery loop as a capacity rate [W/K]: about 10 L/min of
	  water-glycol (estimated from 8-15 L/min EV battery pumps) times 3.5 kJ/(L·K).
	ChargeC: constant-current charge rate [1/h]. BU-409 describes the standard 1C charge; the
	  M50 allows 0.7C continuous, EV packs accept more for short periods.
	CVStart: state of charge where the cell reaches 4.2 V at 1C and the constant-voltage
	  taper begins (BU-409 table 2: ~85 %).
	CutoffC: current [C] where the CV stage ends and the charge is complete (BU-409: 3-5 %).
	ChargeTmax, DischargeTmax: cell temperature limits [°C] (M50: charge 0-50, discharge to
	  60). The BMS tapers power over the last TaperK kelvin below each limit (estimated).
	CellAh: capacity of the cell the ageing model was fitted to (BLAST-Lite: 2.15 Ah); the
	  pack's throughput is scaled to one such cell.
]]
Battery.Loss1C        = 0.03 * 5 / 3.63
Battery.CellCp        = 912
Battery.CaseCp        = 480
Battery.SkinH         = 10
Battery.PlateH        = 300
Battery.PlateShare    = 1 / 3
Battery.LoopC         = 10 / 60 * 3500
Battery.ChargeC       = 1
Battery.CVStart       = 0.85
Battery.CutoffC       = 0.04
Battery.ChargeTmax    = 50
Battery.DischargeTmax = 60
Battery.TaperK        = 5
Battery.CellAh        = 2.15

-- Schmalstieg et al. 2014 coefficients, as in BLAST-Lite.
local Age = {
	QcalA = 7.543, QcalB = -23.75, QcalE = -6976, Qcalp = 0.75,
	QcycA = 7.348e-3, QcycV = 3.667, QcycC = 7.6e-4, QcycD = 4.081e-3,
	RcalA = 5.270, RcalB = -16.32, RcalE = -5986, Rcalp = 0.75,
	RcycA = 2.153e-4, RcycV = 3.725, RcycC = -1.521e-5, RcycD = 2.798e-4,
}
Battery.Age = Age

-- Open-circuit voltage of the cell against state of charge, every 10 % from the BLAST-Lite table
-- (Schmalstieg et al. fig. 1, Ecker et al. 2014 for 0 and 10 %).
local OCV = { 3.331, 3.491, 3.581, 3.627, 3.655, 3.697, 3.775, 3.869, 3.965, 4.073, 4.162 }

--- Open-circuit cell voltage at a state of charge.
-- @param SOC number State of charge 0..1.
-- @return number Volts.
function Battery.OCV(SOC)
	local X = clamp(SOC, 0, 1) * 10
	local I = math.floor(X)
	if I >= 10 then return OCV[11] end
	local F = X - I
	return OCV[I + 1] + (OCV[I + 2] - OCV[I + 1]) * F
end

--- Builds a pack's description.
-- @param NominalWh number Capacity when new [Wh].
-- @param CellKg number Mass of the cells [kg].
-- @param CaseKg number Mass of the housing [kg].
-- @param AreaM2 number Outer surface area [m²].
-- @return table Pack spec.
function Battery.Build(NominalWh, CellKg, CaseKg, AreaM2)
	return {
		NominalWh = max(NominalWh, 1e-3),
		C = max(CellKg * Battery.CellCp + CaseKg * Battery.CaseCp, 1),
		G = max(AreaM2 or 0, 0) * Battery.SkinH,
		PlateG = max(AreaM2 or 0, 0) * Battery.PlateShare * Battery.PlateH,
	}
end

--- Creates a new (unworn) pack state at a temperature.
-- @param Ambient number Cell temperature [°C].
-- @return table State.
function Battery.NewState(Ambient)
	return {
		T = Ambient or 20,
		-- Wear, as fractions of the new capacity / resistance.
		QLossCal = 0, QLossCyc = 0, RGainCal = 0, RGainCyc = 0,
		-- Cycling in progress: the current half cycle (charge or discharge run).
		HalfAh = 0, HalfStartSOC = nil, HalfDir = 0, QCycBase = 0, RCycBase = 0,
		HeatJ = 0,   -- loss heat waiting for the next thermal step
		DaysAged = 0,
	}
end

--- Fraction of the new capacity the pack still has.
-- @param State table Pack state.
-- @return number 0..1.
function Battery.Health(State)
	return clamp(1 - State.QLossCal - State.QLossCyc, 0, 1)
end

--- Internal resistance relative to new.
-- @param State table Pack state.
-- @return number >= 1.
function Battery.Resistance(State)
	return 1 + max(State.RGainCal + State.RGainCyc, 0)
end

--- Resistive loss at a terminal power.
-- @param Spec table Pack spec.
-- @param State table Pack state.
-- @param PowerW number Terminal power [W], either sign.
-- @return number Loss [W].
function Battery.LossW(Spec, State, PowerW)
	return Battery.Loss1C * Battery.Resistance(State) * PowerW * PowerW / Spec.NominalWh
end

local function taper(T, Limit)
	return clamp((Limit - T) / Battery.TaperK, 0, 1)
end

--- What a pack offers an engine's starter motor (the engine state's StarterSupply, see the
-- starter in engine_model.lua).
-- Open-circuit voltage follows the state of charge (OCV table) and is scaled by the BMS's
-- discharge derate, so a hot pack cranks weaker and one at its discharge limit not at all.
-- The sag is the pack's resistive loss as a fraction of power (Loss1C·R·P/E, as in LossW)
-- at the starter's stall power: the voltage drop that power alone would cause.
-- @param Spec table Pack spec.
-- @param State table Pack state.
-- @param SOC number State of charge 0..1.
-- @param StallW number The starter's electrical power at stall [W] (Engine.StarterRating).
-- @return number Open-circuit voltage relative to a full new pack's (0..1).
-- @return number Sag at the stall power, as a fraction of the open-circuit voltage.
function Battery.StarterSupply(Spec, State, SOC, StallW)
	local Volt = Battery.OCV(SOC) / OCV[11] * Battery.DischargeDerate(State)
	local Sag = Battery.Loss1C * Battery.Resistance(State) * max(StallW, 0) / Spec.NominalWh
	return Volt, Sag
end

--- Most power the discharge side of the BMS allows, as a fraction of full: 1 while cool, falling
-- to 0 at the discharge temperature limit.
-- @param State table Pack state.
-- @return number 0..1.
function Battery.DischargeDerate(State)
	return taper(State.T, Battery.DischargeTmax)
end

--- Charging power the pack accepts at its state of charge (CC-CV).
-- Constant current up to CVStart, then the constant-voltage stage: the current falls with the
-- remaining charge, which gives the exponential taper of a real CV stage. Below the cut-off
-- current the charge is complete and nothing more is accepted. The BMS also stops charging
-- near the charge temperature limit.
-- @param Spec table Pack spec.
-- @param State table Pack state.
-- @param SOC number Stored energy over the current (worn) capacity, 0..1.
-- @return number Accepted terminal power [W].
function Battery.ChargeAcceptW(Spec, State, SOC)
	local Health = Battery.Health(State)
	local C = Battery.ChargeC * min(1, (1 - clamp(SOC, 0, 1)) / (1 - Battery.CVStart))
	if C < Battery.CutoffC then return 0 end
	-- C-rate is relative to the capacity the pack has now.
	return C * Spec.NominalWh * Health * taper(State.T, Battery.ChargeTmax)
end

--- State of charge at which the CV stage ends (the pack reads full).
-- @return number 0..1.
function Battery.FullSOC()
	return 1 - Battery.CutoffC * (1 - Battery.CVStart) / Battery.ChargeC
end

--- Stored energy change for a terminal energy transfer, and the heat it makes.
-- Discharging takes the losses from the store on top of the delivered energy; charging stores
-- the input less the losses.
-- @param Spec table Pack spec.
-- @param State table Pack state (loss heat is added to State.HeatJ).
-- @param TerminalWh number Energy at the terminals [Wh]: positive charges, negative discharges.
-- @param Dt number Time it took [s].
-- @return number Change of stored energy [Wh].
function Battery.Transfer(Spec, State, TerminalWh, Dt)
	if TerminalWh == 0 then return 0 end
	local PowerW = TerminalWh * 3600 / max(Dt, 1e-6)
	local LossWh = Battery.LossW(Spec, State, PowerW) * max(Dt, 1e-6) / 3600
	-- A loss larger than the transfer would mean an impossible current; cap at half the energy
	-- (matched load, the most a source can deliver).
	LossWh = min(LossWh, 0.5 * abs(TerminalWh))
	State.HeatJ = State.HeatJ + LossWh * 3600
	return TerminalWh - LossWh
end

--- Records charge throughput for cycle ageing.
-- Throughput is scaled to one cell of the fitted type: moving the whole capacity once is CellAh.
-- A half cycle (a run of charging or of discharging) ends when the flow reverses; its depth is
-- the state-of-charge swing, and its ageing is settled then (and kept current while it runs).
-- @param State table Pack state.
-- @param DeltaSOC number Change of state of charge, relative to the new capacity (signed).
-- @param SOC number State of charge now, 0..1.
function Battery.AddThroughput(State, DeltaSOC, SOC)
	if DeltaSOC == 0 then return end
	local Dir = DeltaSOC > 0 and 1 or -1
	if Dir ~= State.HalfDir then
		-- Flow reversed: settle the finished half cycle.
		State.QCycBase = State.QLossCyc
		State.RCycBase = State.RGainCyc
		State.HalfAh = 0
		State.HalfDir = Dir
		State.HalfStartSOC = SOC - DeltaSOC
	end
	State.HalfAh = State.HalfAh + abs(DeltaSOC) * Battery.CellAh

	local Start = State.HalfStartSOC or SOC
	local DOD = clamp(abs(SOC - Start), 0, 1)
	local V = Battery.OCV(0.5 * (SOC + Start))

	-- Capacity: β·√Q, continued from the loss already there (equivalent-throughput form).
	local Beta = Age.QcycA * (V - Age.QcycV) ^ 2 + Age.QcycC + Age.QcycD * DOD
	local QEq = (State.QCycBase / Beta) ^ 2
	State.QLossCyc = Beta * sqrt(QEq + State.HalfAh)

	-- Resistance: linear in throughput.
	local BetaR = max(Age.RcycA * (V - Age.RcycV) ^ 2 + Age.RcycC + Age.RcycD * DOD, 0)
	State.RGainCyc = State.RCycBase + BetaR * State.HalfAh
end

--- Calendar ageing over a time at the present temperature and state of charge.
-- Uses the t^0.75 law continued from the loss already there, so conditions may change from
-- step to step.
-- @param State table Pack state.
-- @param SOC number State of charge 0..1.
-- @param Days number Time [days].
function Battery.CalendarAge(State, SOC, Days)
	if Days <= 0 then return end
	local V = Battery.OCV(SOC)
	local TK = State.T + 273.15
	local A = max((Age.QcalA * V + Age.QcalB) * 1e6 * exp(Age.QcalE / TK), 1e-30)
	local AR = max((Age.RcalA * V + Age.RcalB) * 1e5 * exp(Age.RcalE / TK), 1e-30)
	local T0 = (State.QLossCal / A) ^ (1 / Age.Qcalp)
	State.QLossCal = A * (T0 + Days) ^ Age.Qcalp
	local R0 = (State.RGainCal / AR) ^ (1 / Age.Rcalp)
	State.RGainCal = AR * (R0 + Days) ^ Age.Rcalp
	State.DaysAged = State.DaysAged + Days
end

--- Conductance from the cells to the air through a liquid loop and linked radiators, [W/K].
-- The cold plate and the radiators are in series; the coolant's own heat capacity is left out
-- (a few litres against hundreds of kilograms of cells).
-- @param Spec table Pack spec.
-- @param Radiators table List of { UA = W/K, Cair = W/K } air sides, already shared out.
-- @return number Conductance [W/K], and the radiators' part of it.
function Battery.LoopG(Spec, Radiators)
	local Gr = 0
	for _, R in ipairs(Radiators) do
		local Eps, Cmin = ACE.Mobility.Thermal.CrossFlowEffectiveness(R.UA, R.Cair, Battery.LoopC)
		Gr = Gr + Eps * Cmin
	end
	if Gr <= 0 or (Spec.PlateG or 0) <= 0 then return 0, 0 end
	return 1 / (1 / Spec.PlateG + 1 / Gr), Gr
end

--- Advances the pack's temperature: the loss heat collected since the last call goes in, the
-- skin loses heat to the air. Exact for a constant heat input over the step.
-- @param Spec table Pack spec.
-- @param State table Pack state.
-- @param Dt number Real time since the last call [s].
-- @param Ambient number Air temperature [°C].
-- @param Scale number Heat time scale (ace_heat_timescale): heat moves this many times faster.
-- @param LoopG number|nil Extra conductance to the air through a cooling loop [W/K] (Battery.LoopG).
function Battery.ThermalStep(Spec, State, Dt, Ambient, Scale, LoopG)
	if Dt <= 0 then return end
	Scale = Scale or 1
	local H = Dt * Scale
	-- The collected heat, as the power it was made at, acts over the scaled step (as the engine's
	-- coolant does in ACE.EngineThermalThink).
	local P = State.HeatJ / Dt
	State.HeatJ = 0
	local Ta = Ambient or 20
	local G = Spec.G + (LoopG or 0)
	if G > 0 then
		local Ts = Ta + P / G
		State.T = Ts + (State.T - Ts) * exp(-G * H / Spec.C)
	else
		State.T = State.T + P * H / Spec.C
	end
end

--[[
	The engine's own starter battery: lead-acid, for piston and rotary engines with no ACE battery
	linked to their starter. It is not an entity; it lives on the engine and is kept charged by
	the engine's alternator while it runs. It starts full. There is no trickle charge while the
	engine is off.

	Kinetic battery model (Manwell & McGowan, Solar Energy 50 (1993) 399-405): the charge sits in
	two wells, an "available" one (share LeadAvailShare of the capacity) that the terminals draw
	from directly, and a "bound" one that flows into it in proportion to the difference of their
	levels. A battery cranked hard empties its available well long before it is really empty,
	so it goes flat while cranking and then recovers part of its charge after a rest, as lead-acid
	batteries do (Battery University BU-502: the rate-capacity effect). Levels are fractions
	0..1 of each well.

	LeadWhPerW: capacity per watt of the starter's rated (most) power. A car's 1.4 kW starter
	  runs from a 12 V 60 Ah (720 Wh) battery, a heavy truck's 7 kW from 24 V 2 x 12 V 140 Ah
	  (3.4 kWh): 0.5 Wh per W (estimated from those two; Bosch Automotive Handbook, starter
	  batteries).
	LeadAvailShare: 0.3, so at cranking currents (5-10 C) about a third of the charge can be
	  drawn before the voltage collapses, in line with Peukert's law for lead-acid (exponent
	  1.2-1.3: a 60 Ah battery at 400 A gives out ~17 Ah). Estimated.
	LeadRecoverTau: with no load the two wells level out with a 10 minute time constant
	  (estimated: a "dead" battery cranks again after a few minutes' rest).
	LeadFlatLevel, LeadLiveLevel: the voltage collapses once the available well is down to 2 %;
	  the battery then reads flat until it has recovered to 10 % (about two minutes' rest
	  after a first flat; estimated).
	Open-circuit voltage: 12.7 V full, 11.8 V empty (2.12-1.97 V per cell; Battery University
	  BU-903), linear, read from the available well.
	Sag at the starter's stall power: the starter's rated 20 % when full and warm (see
	  StarterRefSag in engine_model.lua), rising as the available well empties (x(1 + 1.5·(1 -
	  level)), sulphated plates and acid depletion at the plates; estimated) and in the cold
	  (x(1 + (20 - T)/40) below 20 °C: a lead-acid battery gives about half its power at
	  -18 °C, the SAE J537 cold cranking rating point; estimated).
	Charge acceptance: LeadChargeC = 0.25 C in bulk (flooded lead-acid accepts 0.1-0.3 C,
	  BU-403), tapering to nothing as the available well fills past 80 %, at a charge
	  efficiency of 0.85 (lead-acid coulombic efficiency 80-90 %, BU-403).
]]
Battery.LeadWhPerW      = 0.5
Battery.LeadAvailShare  = 0.3
Battery.LeadRecoverTau  = 600
Battery.LeadVoltFull    = 12.7
Battery.LeadVoltEmpty   = 11.8
Battery.LeadRefSag      = 0.2
Battery.LeadChargeC     = 0.25
Battery.LeadTaperFrom   = 0.8
Battery.LeadChargeEff   = 0.85
Battery.LeadFlatLevel   = 0.02
Battery.LeadLiveLevel   = 0.1

--- Creates an engine's built-in lead-acid starter battery, full.
-- @param RatedW number The starter's rated (most) mechanical power [W], a quarter of its stall power.
-- @return table Pack: CapJ (capacity, J), Avail and Bound (well levels 0..1).
function Battery.StarterPack(RatedW)
	return { CapJ = max(RatedW, 1) * Battery.LeadWhPerW * 3600, Avail = 1, Bound = 1 }
end

--- Resizes a built-in starter battery (the starter size setting changed), keeping its levels.
-- @param Pack table Pack from Battery.StarterPack.
-- @param RatedW number The starter's rated power [W].
function Battery.StarterPackResize(Pack, RatedW)
	Pack.CapJ = max(RatedW, 1) * Battery.LeadWhPerW * 3600
end

--- State of charge of a built-in starter battery, both wells together.
-- @param Pack table Pack.
-- @return number 0..1.
function Battery.StarterPackSOC(Pack)
	local C = Battery.LeadAvailShare
	return clamp(C * Pack.Avail + (1 - C) * Pack.Bound, 0, 1)
end

--- What a built-in starter battery offers the starter (engine state's StarterSupply).
-- @param Pack table Pack.
-- @param AirC number|nil Battery (outside air) temperature [°C].
-- @return number Open-circuit voltage relative to a full battery's (0 when flat).
-- @return number Sag at the starter's stall power, as a fraction of the open-circuit voltage.
-- @return number Energy that can be drawn now (the available well) [J].
function Battery.StarterPackSupply(Pack, AirC)
	local Level = clamp(Pack.Avail, 0, 1)
	local EnergyJ = Level * Battery.LeadAvailShare * Pack.CapJ
	-- Pulled down to its flat level the voltage collapses, and it needs to recover to the
	-- live level before it turns the engine again.
	if Level <= Battery.LeadFlatLevel then Pack.Flat = true end
	if Pack.Flat and Level >= Battery.LeadLiveLevel then Pack.Flat = false end
	if Pack.Flat or EnergyJ <= 0 then return 0, 0, 0 end
	local Volt = (Battery.LeadVoltEmpty + (Battery.LeadVoltFull - Battery.LeadVoltEmpty) * Level) / Battery.LeadVoltFull
	local Cold = 1 + max(20 - (AirC or 20), 0) / 40
	return Volt, Battery.LeadRefSag * (1 + 1.5 * (1 - Level)) * Cold, EnergyJ
end

--- Draws energy from a built-in starter battery's available well.
-- @param Pack table Pack.
-- @param Joules number Energy taken at the terminals [J].
function Battery.StarterPackDraw(Pack, Joules)
	Pack.Avail = max(Pack.Avail - Joules / (Battery.LeadAvailShare * Pack.CapJ), 0)
end

--- Charging power a built-in starter battery accepts now.
-- @param Pack table Pack.
-- @return number Watts at the terminals.
function Battery.StarterPackAcceptW(Pack)
	local Taper = clamp((1 - Pack.Avail) / (1 - Battery.LeadTaperFrom), 0, 1)
	return Battery.LeadChargeC * Pack.CapJ / 3600 * Taper
end

--- Charges a built-in starter battery.
-- @param Pack table Pack.
-- @param Joules number Energy delivered to the terminals [J]; LeadChargeEff of it is stored.
function Battery.StarterPackCharge(Pack, Joules)
	Pack.Avail = min(Pack.Avail + Joules * Battery.LeadChargeEff / (Battery.LeadAvailShare * Pack.CapJ), 1)
end

--- Lets charge flow between a built-in starter battery's wells (exact for the step).
-- @param Pack table Pack.
-- @param Dt number Seconds.
function Battery.StarterPackStep(Pack, Dt)
	if Dt <= 0 then return end
	local C = Battery.LeadAvailShare
	local Total = C * Pack.Avail + (1 - C) * Pack.Bound
	local Diff = (Pack.Bound - Pack.Avail) * exp(-Dt / Battery.LeadRecoverTau)
	Pack.Avail = clamp(Total - (1 - C) * Diff, 0, 1)
	Pack.Bound = clamp(Total + C * Diff, 0, 1)
end

return Battery

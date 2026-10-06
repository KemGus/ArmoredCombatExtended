-- Self-tests for the starter motor (lua/ace/shared/mobility/engine_model.lua): a series-wound DC
-- motor fed by a battery that sags, cranking for as long as the start is held, with a thermal
-- cut-out. Also the radiator fan load at cranking speed (ace_radiator, affinity laws).
-- Reference figures are in docs/mobility-sources.md.
local root = assert(arg[1], "usage: ace_mobility_starter_luajit_selftest.lua <ACE repo>")
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

local Passed = 0
local Verbose = os.getenv("ACE_TEST_VERBOSE")
local function check(Cond, Label, ...)
	if Verbose then print(Label, ...) end
	if not Cond then error(("FAIL %s %s"):format(Label, table.concat({ ... }, " ")), 2) end
	Passed = Passed + 1
end

-- The engine of the MRAP ATPC recording (data/ace_mobility_log/20261005_191524).
local V4 = { id = "3.3L-V4", name = "3.3L V4 Diesel", category = "V4", fuel = "Diesel", enginetype = "V4",
	torque = 720, idlerpm = 600, limitrpm = 3900 }

-- The rig always fuels the engine and has no accessories: these tests set both per tick.
local Fuel, Load = true, nil
local Build = M.Drivetrain.Build
M.Drivetrain.Build = function(Eng)
	Eng.HasFuel = Fuel
	Eng.AccessoryTorque = Load and Load(Eng.State) or 0
	return Build(Eng)
end

-- A vehicle in neutral with the start held. Returns the vehicle.
local function crank(Def, Supply)
	local V = Rig.New({ EngineDef = Def, Mass = 3000, WheelRadius = 0.5, Ratios = { 3 }, Final = 4, Tick = 0.015 })
	V.Gear = 0
	V.State.StarterSupply = Supply
	E.Start(V.State)
	return V
end

local function runFor(V, Seconds, Fn)
	Rig.Run(V, V.Time + Seconds, nil, Fn)
	return V
end

------------------------------------------------------------------ cranks while the start is held
do
	Fuel, Load = false, nil
	local V = runFor(crank(V4), 10)
	check(V.State.StarterOn and V.State.Cranking > 0, "still cranking after 10 s with the start held")
	check(Rig.RPM(V) > 150, "cranks a warm engine above its firing speed", Rig.RPM(V))
	E.Stop(V.State)
	runFor(V, 0.1)
	check(V.State.Cranking == 0 and (V.State.StarterTorque or 0) == 0, "releasing the start stops the starter")

	Fuel = true
	local W = crank(V4)
	local Caught
	runFor(W, 3, function(X) if X.State.Running and not Caught then Caught = X.Time end end)
	check(Caught and Caught < 1, "fires with its own battery", Caught)
	check(not W.State.StarterOn and W.State.Cranking == 0, "the start is released once it fires")
end

------------------------------------------------------------------ thermal cut-out
do
	Fuel = false
	-- Held against a load it cannot turn: a locked starter heats four times faster.
	Load = function() return 1e4 end
	local V, Cut, Again = crank(V4), nil, nil
	runFor(V, 120, function(X)
		if X.State.StarterCut and not Cut then Cut = X.Time end
		if Cut and not X.State.StarterCut and not Again then Again = X.Time end
	end)
	check(Cut and Cut > 4 and Cut < 9, "locked starter cuts out after about 6 s", Cut)
	check(Again and Again - Cut > 30 and Again - Cut < 60, "and cranks again once cooled", Again and Again - Cut)

	-- Cranking near its max-power point (~200 rpm): about the rated 30 s. (The starter's own
	-- drag takes 26 N·m of its torque, so 74 N·m of load holds it where 100 used to.)
	Load = function() return 74 end
	local W, Cut2, CrankingCut = crank(V4), nil, nil
	runFor(W, 60, function(X)
		if X.State.StarterCut and not Cut2 then Cut2, CrankingCut = X.Time, X.State.Cranking end
	end)
	check(Cut2 and Cut2 > 12 and Cut2 < 35, "loaded cranking cuts out near the 30 s rating", Cut2)
	check(CrankingCut == 0, "no cranking while cut out", CrankingCut)
	Load = nil
end

------------------------------------------------------------------ battery
do
	Fuel = false
	local Spec = E.Build(V4, ACE.GetEngineTorqueCurve(V4))
	local _, StallW = E.StarterRating(Spec)
	check(StallW > 3000 and StallW < 15000, "stall power of a 3.3 L diesel starter is a few kW", StallW)

	local function pack(Wh)
		local P = B.Build(Wh, Wh / 200, Wh / 2000, 0.5)
		return P, B.NewState(20)
	end
	local function supply(Wh, SOC)
		local P, S = pack(Wh)
		local Volt, Sag = B.StarterSupply(P, S, SOC, StallW)
		return { Volt = Volt, Sag = Sag, EnergyJ = Wh * SOC * 3600 }
	end
	local function speedAfter(Supply, T)
		return Rig.RPM(runFor(crank(V4, Supply), T or 4))
	end

	local Big, Small, Low = speedAfter(supply(20000, 1)), speedAfter(supply(500, 1)), speedAfter(supply(20000, 0.05))
	check(Small < Big, "a small pack sags more and cranks slower", Small, Big)
	check(Low < Big, "a nearly empty pack cranks slower", Low, Big)
	check(speedAfter({ Volt = 0, Sag = 0, EnergyJ = 0 }) < 1, "a flat battery does not crank")

	-- The starter's energy is drawn from the battery: no more than it holds.
	local V = runFor(crank(V4, supply(20000, 1)), 2)
	local Drawn = V.State.StarterJ
	check(Drawn > 2 * 1000 and Drawn < 2 * StallW, "cranking draws kilowatts", Drawn / 2)
	local Tiny = { Volt = 1, Sag = 0.2, EnergyJ = 500 }
	local T = runFor(crank(V4, Tiny), 2)
	check(T.State.StarterJ <= 500 + StallW * 0.015 / 8 + 1, "stops when the battery's energy is used up", T.State.StarterJ)
	check(T.State.Cranking == 0, "and stops cranking")
end

------------------------------------------------------------------ radiator fan at cranking speed
do
	-- The recording: a 3.45 kW belt-driven fan (55 N·m at 600 rpm idle) on the hot engine.
	-- Taken at its idle torque at any speed (the old radiator code) it held the crank at 78 rpm
	-- with the starter of that time. A fan's torque goes with speed squared below idle.
	Fuel = true
	local Spec = E.Build(V4, ACE.GetEngineTorqueCurve(V4))
	local IdleTq = 3450 / Spec.IdleW
	Load = function(S)
		local Speed = math.abs(S.W)
		local Tq = IdleTq
		if Speed < Spec.IdleW then Tq = Tq * (Speed / Spec.IdleW) ^ 2 end
		return Tq
	end
	local V, Caught = crank(V4), nil
	runFor(V, 3, function(X) if X.State.Running and not Caught then Caught = X.Time end end)
	check(Caught and Caught < 1, "fires with the fan on", Caught)
	Load = nil
end

------------------------------------------------------------------ cold oil
do
	-- The starter is sized from warm-oil friction: cold, viscous oil cranks slower, it does not
	-- get a stronger starter.
	Fuel, Load = false, nil
	local Warm = crank(V4)
	local Cold = crank(V4)
	Cold.Spec.FrictionMul = 3
	check(E.StarterRating(Cold.Spec) == E.StarterRating(Warm.Spec), "stall torque ignores oil temperature")
	local Fresh = E.Build(V4, ACE.GetEngineTorqueCurve(V4))
	Fresh.FrictionMul = 3
	check(math.abs(E.StarterRating(Fresh) - E.StarterRating(Warm.Spec)) < 1e-9, "even when first rated cold")
	runFor(Warm, 4)
	runFor(Cold, 4)
	check(Rig.RPM(Cold) < Rig.RPM(Warm), "cold oil cranks slower", Rig.RPM(Cold), Rig.RPM(Warm))
end

------------------------------------------------------------------ catching: firing speed and temperature
local Defs = {}
do
	local Saved = ACE.DefineEngine
	function ACE.DefineEngine(Id, Data) Data.id = Id Defs[Id] = Data end
	for _, Name in ipairs({ "v8.lua", "v12.lua" }) do
		local F = assert(io.open(root .. "/lua/ace/shared/engines/" .. Name, "rb"))
		assert(loadstring(F:read("*a"), Name))()
		F:close()
	end
	ACE.DefineEngine = Saved
end
local V8, V12 = assert(Defs["5.7-V8"]), assert(Defs["27.0-V12"])

local function spec(Def, Mul)
	local S = E.Build(Def, ACE.GetEngineTorqueCurve(Def))
	S.StarterMul = Mul
	return S
end
local Warm = {}
local Mild = { AirC = 20, BlockC = 20, CoolantC = 20, FrictionMul = 2 }
local Frozen = { AirC = -20, BlockC = -20, CoolantC = -20, FrictionMul = 4 }

do
	-- A start is not instant, and no timer decides it: two revolutions to synchronise, then the
	-- fired cycles run the engine up past its stall speed.
	local T = E.SimulateStart(spec(V8), Warm)
	check(T and T > 0.25 and T < 1, "warm petrol V8 starts in well under a second", T)
	local TC = E.SimulateStart(spec(V8), Frozen)
	check(TC and TC > T * 1.5 and TC < 3, "a frozen petrol engine cranks longer", TC, T)
	local D = E.SimulateStart(spec(V4), Warm)
	check(D and D > 0.3 and D < 1.5, "warm diesel starts at once", D)

	-- Diesels: compression temperature. Warm at cranking speed it lights every cycle; a 20 °C
	-- engine lights once cranking has warmed its walls, a -20 °C one only with glow plugs.
	local S = spec(V4)
	local W250 = 250 * math.pi / 30
	local WarmState = E.NewState(S)
	check(E.FireFraction(S, WarmState, W250) > 0.99, "warm diesel fires every cycle at 250 rpm", E.CompressionTemp(S, WarmState, W250))
	check(E.FireFraction(S, WarmState, 120 * math.pi / 30) < 0.5, "but not when cranked slowly", E.CompressionTemp(S, WarmState, 120 * math.pi / 30))
	local MildState = E.NewState(S)
	MildState.AirC, MildState.BlockC = 20, 20
	check(E.FireFraction(S, MildState, W250) == 0, "20 °C diesel: not on the first strokes", E.CompressionTemp(S, MildState, W250))
	MildState.CrankWarm = 40
	check(E.FireFraction(S, MildState, W250) > 0.9, "but once cranking has warmed the walls", E.CompressionTemp(S, MildState, W250))
	local ColdState = E.NewState(S)
	ColdState.AirC, ColdState.BlockC, ColdState.CrankWarm = -20, -20, 40
	check(E.FireFraction(S, ColdState, W250) == 0, "-20 °C diesel does not fire unaided", E.CompressionTemp(S, ColdState, W250))
	ColdState.Glow = 1
	check(E.FireFraction(S, ColdState, W250) > 0.99, "glow plugs light it", E.CompressionTemp(S, ColdState, W250))
	check(E.FireFraction(S, WarmState, 40 * math.pi / 30) == 0, "nothing fires below firing speed")
	check(E.FireFraction(spec(V8), WarmState, 40 * math.pi / 30) == 0, "petrol neither")

	-- Preheat: longest frozen, none warm; the starter waits for it and the plugs draw current.
	check(E.PreheatTime(S, WarmState) == 0, "warm diesel needs no preheat")
	check(math.abs(E.PreheatTime(S, ColdState) - E.DefaultPreheat) < 1e-9, "frozen diesel preheats the full time")
	check(E.PreheatTime(spec(V8), ColdState) == 0, "petrol engines have no glow plugs")
	local NoPlugs = spec(V4)
	NoPlugs.PreheatMax = 0
	check(E.PreheatTime(NoPlugs, ColdState) == 0, "preheat 0 means no glow plugs")

	Fuel, Load = true, nil
	local V = crank(V4)
	V.State.AirC, V.State.BlockC, V.State.CoolantC = -20, -20, -20
	E.Start(V.State)
	runFor(V, 2)
	check(V.State.Preheating and V.State.Cranking == 0 and Rig.RPM(V) < 1, "preheating: the starter waits", Rig.RPM(V))
	check(V.State.Glow > 0.6 and V.State.StarterJ > 2 * 150 * 4 * 0.9, "glow plugs heat and draw current", V.State.Glow, V.State.StarterJ)

	-- The whole start, frozen: preheat, then crank until it catches. Without glow plugs it
	-- cranks on and never fires.
	local DS, DP = E.SimulateStart(spec(V4), Frozen)
	check(DS and DP == E.DefaultPreheat and DS > DP + 0.3 and DS < DP + 5, "frozen diesel starts after preheat", DS, DP)
	local NP = spec(V4)
	NP.PreheatMax = 0
	check(E.SimulateStart(NP, Frozen) == nil, "frozen diesel without glow plugs does not start")

	-- A big diesel: the stock starter cannot spin it fast enough through frozen oil; a bigger one can.
	local Big, Mul2 = E.SimulateStart(spec(V12), Frozen), E.SimulateStart(spec(V12, 2), Frozen)
	check(Big == nil and Mul2 ~= nil, "frozen 27 L V12 needs a bigger starter", Big, Mul2)
	local BigWarm, BigMild = E.SimulateStart(spec(V12), Warm), E.SimulateStart(spec(V12), Mild)
	check(BigWarm and BigWarm < 2 and BigMild and BigMild > BigWarm + 2, "27 L V12: about a second warm, preheat and longer at 20 °C", BigWarm, BigMild)
	local Small, Large = E.SimulateStart(spec(V8, 0.5), Mild), E.SimulateStart(spec(V8, 2), Mild)
	check(Small and Large and Large < Small, "a bigger starter starts sooner", Large, Small)
	check(E.StarterRating(spec(V8, 2)) == 2 * E.StarterRating(spec(V8)), "starter size scales its torque")

	-- Push start: battery flat, start held, rolled in gear.
	Fuel = true
	local P = Rig.New({ EngineDef = V4, Mass = 3000, WheelRadius = 0.5, Ratios = { 3 }, Final = 4, Tick = 0.015, Speed = 4 })
	P.State.StarterSupply = { Volt = 0, Sag = 0, EnergyJ = 0 }
	E.Start(P.State)
	runFor(P, 3)
	check(P.State.Running, "push start fires it with a flat battery", Rig.RPM(P))
end

------------------------------------------------------------------ built-in starter battery
do
	local Spec = E.Build(V4, ACE.GetEngineTorqueCurve(V4))
	local _, StallW = E.StarterRating(Spec)
	local Pack = B.StarterPack(StallW / 4)
	check(math.abs(Pack.CapJ / 3600 - StallW / 4 * 0.5) < 1e-6, "sized at 0.5 Wh per W of starter", Pack.CapJ / 3600)
	local Volt, Sag, EnergyJ = B.StarterPackSupply(Pack, 20)
	check(Volt == 1 and math.abs(Sag - E.StarterRefSag) < 1e-9 and EnergyJ > 0, "full and warm: the starter's rated supply")
	local _, ColdSag = B.StarterPackSupply(Pack, -20)
	check(ColdSag > 1.9 * Sag, "a cold battery sags twice as much", ColdSag)

	-- Held on a warm engine with no fuel: cranks for minutes, then the battery goes flat.
	Fuel, Load = false, nil
	local V = crank(V4)
	local Flat
	runFor(V, 1200, function(X)
		local S = X.State
		local Sup = S.StarterSupply or {}
		Sup.Volt, Sup.Sag, Sup.EnergyJ = B.StarterPackSupply(Pack, 20)
		S.StarterSupply = Sup
		B.StarterPackDraw(Pack, S.StarterJ or 0)
		S.StarterJ = 0
		B.StarterPackStep(Pack, X.Tick)
		if not Flat and Sup.Volt <= 0 then Flat = X.Time end
	end)
	check(Flat and Flat > 120 and Flat < 1200, "a held start runs the battery flat after minutes", Flat)
	check(B.StarterPackSOC(Pack) > 0.3, "flat at the terminals with charge still bound in the plates", B.StarterPackSOC(Pack))

	-- Rest recovers some of it (kinetic battery model).
	local Before = Pack.Avail
	B.StarterPackStep(Pack, 300)
	check(Pack.Avail > Before + 0.1, "five minutes' rest gives it some charge back", Before, Pack.Avail)

	-- The alternator puts it back: bulk at 0.25 C, tapering as it fills.
	local Accept = B.StarterPackAcceptW(Pack)
	check(math.abs(Accept - 0.25 * Pack.CapJ / 3600) < 1e-6, "bulk charge at 0.25 C", Accept)
	local T = 0
	while B.StarterPackSOC(Pack) < 0.95 and T < 36000 do
		B.StarterPackCharge(Pack, B.StarterPackAcceptW(Pack))
		B.StarterPackStep(Pack, 1)
		T = T + 1
	end
	check(T > 1800 and T < 36000, "recharging from flat takes hours, as lead-acid does", T / 3600)
	check(B.StarterPackAcceptW(Pack) < Accept, "acceptance tapers as it fills")
end

------------------------------------------------------------------ motors and turbines
do
	local Leaf = { id = "leaf", name = "LEAF EM61", category = "Electric", fuel = "Electric", enginetype = "Electric",
		torque = 280, idlerpm = 0, limitrpm = 10390, inertia = 0.03 }
	local S = E.NewState(E.Build(Leaf, ACE.GetEngineTorqueCurve(Leaf)))
	E.Start(S)
	check(S.Running and S.Cranking == 0 and not S.StarterOn, "a motor needs no starter")
end

print(("Mobility starter self-test: PASS (%d assertions)"):format(Passed))

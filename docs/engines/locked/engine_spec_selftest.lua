-- LOCKED (P4). Checks the engine spec contract in docs/engines/contracts.md: motor type
-- registration, ClampParams, fixed-engine passthrough, caps, balance and Thrust output.
-- Copied to tests/lua/ace_engine_spec_luajit_selftest.lua by P4; the implementer must not edit it.
local root = assert(arg[1], "usage: ace_engine_spec_luajit_selftest.lua <ACE repo>")
root = root:gsub("\\", "/"):gsub("/$", "")

ACE = ACE or {}
assert(loadfile(root .. "/lua/ace/shared/mobility/engine_spec.lua"))()

local Spec = ACE.EngineSpec
assert(type(ACE.DefineMotorType) == "function", "ACE.DefineMotorType missing")
assert(type(Spec) == "table" and type(Spec.Resolve) == "function" and type(Spec.ClampParams) == "function")
assert(type(ACE.MotorTypes) == "table" and type(ACE.EngineBalance) == "table" and type(ACE.EngineCaps) == "table")

local function near(A, B, Tol) return math.abs(A - B) <= (Tol or 1e-6) * math.max(1, math.abs(B)) end

-- Registration errors happen at registration, not at spawn.
assert(not pcall(ACE.DefineMotorType, "NoResolve", { Name = "x", Output = "Shaft", Params = {} }), "missing Resolve must error")
assert(not pcall(ACE.DefineMotorType, "NoParams", { Name = "x", Output = "Shaft", Resolve = function() return {} end }), "missing Params must error")
assert(not pcall(ACE.DefineMotorType, "BadOut", { Name = "x", Output = "Rocket", Params = {}, Resolve = function() return {} end }), "bad Output must error")

-- A simple shaft type: torque = Size * 100, weight = Size * 50, hull 10 L.
local TestParams = {
	{ Name = "Size", Kind = "number", Min = 1, Max = 10, Default = 2 },
	{ Name = "Fuel", Kind = "enum", Options = { "Petrol", "Diesel" }, Default = "Petrol" },
	{ Name = "Turbo", Kind = "bool", Default = false },
}
local function testResolve(P)
	return {
		name = "Test " .. P.Size, model = "models/engines/test.mdl", fuel = P.Fuel, enginetype = "GenericPetrol",
		torque = P.Size * 100, peakpower = P.Size * 100 * 4000 / 9549, weight = P.Size * 50,
		idlerpm = 800, peakminrpm = 2000, peakmaxrpm = 4000, peaktqrpm = 3000, peakpowerrpm = 4000, limitrpm = 5000,
		flywheelmass = 0.2, displacement = P.Size,
		torquecurve = { 0.5, 0.6, 0.7, 0.8, 0.9, 1, 1, 1, 0.95, 0.9, 0.85, 0.8, 0.75 },
	}
end
ACE.DefineMotorType("TestShaft", { Name = "Test", Output = "Shaft", Params = TestParams, Resolve = testResolve,
	Model = function() return { { Model = "models/engines/test.mdl" } }, { Mins = { x = 0, y = 0, z = 0 }, Maxs = { x = 10, y = 10, z = 10 } } end })
assert(ACE.MotorTypes.TestShaft, "registered type not in ACE.MotorTypes")

-- Re-registering replaces (reload-safe).
ACE.DefineMotorType("TestShaft", { Name = "Test v2", Output = "Shaft", Params = TestParams, Resolve = testResolve })
assert(ACE.MotorTypes.TestShaft.Name == "Test v2", "re-registering must replace")
ACE.DefineMotorType("TestShaft", { Name = "Test", Output = "Shaft", Params = TestParams, Resolve = testResolve })

-- ClampParams: defaults, unknown keys dropped, numbers clamped, bad enum -> default, input untouched.
local Raw = { Type = "TestShaft", Size = 99, Fuel = "Plutonium", Junk = 1 }
local C = Spec.ClampParams(Raw)
assert(C.Size == 10, "Size not clamped to Max: " .. tostring(C.Size))
assert(C.Fuel == "Petrol", "bad enum must fall back to default")
assert(C.Turbo == false, "missing bool must take its default")
assert(C.Junk == nil, "unknown key must be dropped")
assert(C.Type == "TestShaft" and C.V ~= nil, "Type and V must be kept/filled")
assert(Raw.Size == 99 and Raw.Junk == 1, "ClampParams must not modify its input")
assert(Spec.ClampParams({ Type = "TestShaft", Size = -5 }).Size == 1, "Size not clamped to Min")
assert(not pcall(Spec.ClampParams, { Type = "NoSuchType" }) or Spec.ClampParams({ Type = "NoSuchType" }) == nil,
	"unknown Type must error or return nil, never a spec")

-- Fixed engine: every definition field comes through unchanged, as a copy.
local Def = { id = "5.7-V8", name = "5.7L V8", model = "models/engines/v8m.mdl", weight = 400, torque = 600,
	peakpower = 250, peakpowerrpm = 5000, peaktqrpm = 3500, idlerpm = 700, peakminrpm = 3000, peakmaxrpm = 5500,
	limitrpm = 6500, flywheelmass = 0.3, fuel = "Petrol", enginetype = "GenericPetrol", sound = "x.wav", pitch = 100,
	torquecurve = { 1, 1, 1, 1, 1, 1, 1, 1, 1, 1, 1, 1, 1 }, CoolingArea = 0.4 }
local Fixed = Spec.Resolve(Def, nil)
for K, V in pairs(Def) do
	if type(V) ~= "table" then assert(Fixed[K] == V, "fixed passthrough changed " .. K) end
end
assert(Fixed ~= Def, "Resolve must return a copy, not the definition")
Fixed.torque = 1
assert(Def.torque == 600, "mutating the spec must not change the definition")
assert(Fixed.capped == nil or #Fixed.capped == 0, "stock engines are never capped")
assert((Fixed.output or "Shaft") == "Shaft")

-- Custom engine: stats come from the type, params are kept, deterministic.
local A = Spec.Resolve(nil, { Type = "TestShaft", Size = 3 })
local B = Spec.Resolve(nil, { Type = "TestShaft", Size = 3 })
assert(A.motortype == "TestShaft" and A.output == "Shaft")
assert(A.params and A.params.Size == 3 and A.params.Fuel == "Petrol", "spec must carry the clamped params")
assert(near(A.torque, 300) and near(B.torque, A.torque), "custom torque wrong or not deterministic")
assert(A.real and near(A.real.torque, 300), "spec.real must hold the uncapped, unbalanced figures")
assert(type(A.torquecurve) == "table" and #A.torquecurve == 13)

-- Caps: a type that is far too light gets torque and power scaled together and recorded.
ACE.DefineMotorType("TestTooLight", { Name = "Too light", Output = "Shaft", Params = TestParams,
	Resolve = function(P) local S = testResolve(P); S.weight = 1; return S end,
	Caps = { KWPerKg = 2 } })
local L = Spec.Resolve(nil, { Type = "TestTooLight", Size = 10 })
assert(L.peakpower / L.weight <= 2 + 1e-6, "KWPerKg cap not applied: " .. L.peakpower / L.weight)
assert(near(L.torque / L.real.torque, L.peakpower / L.real.peakpower, 1e-6), "torque and power must scale together")
assert(L.limitrpm == 5000 and L.idlerpm == 800, "caps must not touch rpm figures")
assert(type(L.capped) == "table" and #L.capped >= 1, "cap must be recorded in spec.capped")
local Rec = L.capped[1]
assert(Rec.stat and Rec.from and Rec.to and Rec.rule, "capped entry needs stat/from/to/rule")
assert(near(L.real.torque, 1000), "real figures are from before the cap")

-- Torque per displacement cap.
ACE.DefineMotorType("TestDense", { Name = "Dense", Output = "Shaft", Params = TestParams, Resolve = testResolve,
	Caps = { NmPerDispL = 50 } })
local D = Spec.Resolve(nil, { Type = "TestDense", Size = 4 })
assert(D.torque / D.displacement <= 50 + 1e-6, "NmPerDispL cap not applied")

-- Uncapped type stays untouched.
assert(A.capped == nil or #A.capped == 0, "no caps defined -> nothing capped")

-- Balance multiplier applies after caps and only to its fuel.
ACE.EngineBalance.Diesel = 0.5
local Pd = Spec.Resolve(nil, { Type = "TestShaft", Size = 3, Fuel = "Diesel" })
local Pp = Spec.Resolve(nil, { Type = "TestShaft", Size = 3, Fuel = "Petrol" })
assert(near(Pd.torque, 150) and near(Pd.real.torque, 300), "balance must scale the in-game figure only")
assert(near(Pp.torque, 300), "balance must only touch its own fuel")
ACE.EngineBalance.Diesel = nil

-- Thrust output: no shaft torque into a gearbox, a thrust figure instead.
ACE.DefineMotorType("TestThrust", { Name = "Pulse", Output = "Thrust",
	Params = { { Name = "Size", Kind = "number", Min = 1, Max = 5, Default = 1 } },
	Resolve = function(P) return { name = "Pulse", model = "models/engines/test.mdl", weight = 20 * P.Size, thrust = 500 * P.Size, fuel = "Petrol" } end })
local T = Spec.Resolve(nil, { Type = "TestThrust", Size = 2 })
assert(T.output == "Thrust" and near(T.thrust, 1000), "thrust spec wrong")
assert((T.torque or 0) == 0, "thrust types have no shaft torque")

print("ace_engine_spec_luajit_selftest: OK")

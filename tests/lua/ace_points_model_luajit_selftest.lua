local root = assert(arg[1], "usage: ace_points_model_luajit_selftest.lua <ACE repo>")
root = root:gsub("\\\\", "/"):gsub("/$", "")

ACE = {}
function istable(value) return type(value) == "table" end
function ACE.IsEnt(value) return value ~= nil end
dofile(root .. "/lua/ace/shared/sh_ace_entity_state.lua")

dofile(root .. "/lua/ace/shared/sh_ace_points_model.lua")

local empty = { Type = "APHE", maxPen = 200, FrArea = math.pi * 5 ^ 2, blastMass = 0 }
local loaded = { Type = "APHE", maxPen = 200, FrArea = math.pi * 5 ^ 2, blastMass = 60 }

assert(ACE.Points.IntrinsicValueMul(empty) == 1.0,
	"zero-filler APHE must not receive HE utility value")
assert(ACE.Points.GatePen(empty) == empty.maxPen,
	"zero-filler APHE must retain only its kinetic penetration gate")
assert(ACE.Points.IntrinsicValueMul(loaded) == 1.5,
	"loaded APHE must receive HE payload value")
assert(ACE.Points.GatePen(loaded) > ACE.Points.GatePen(empty),
	"loaded APHE filler must add HE-equivalent threat reach")
assert(ACE.Points.BaseRoundCost(loaded) > ACE.Points.BaseRoundCost(empty),
	"loaded APHE filler must add round cost")

local primitive = {
	GetClass = function() return "prop_physics" end,
	ACE = { MaxArmour = 100, MaxHealth = 100 },
}
local pricedMm, pricedHp = ACE.Points.PropArmor(primitive)
assert(pricedMm and pricedHp == 100, "ordinary prop armor must retain its normal health")
primitive.ACE_PrimitivePropertiesPending = true
assert(ACE.Points.PropArmor(primitive) == nil,
	"Primitive armor must stay out of pricing while its properties are pending")

local function near(actual, expected, message)
	assert(math.abs(actual - expected) <= 1e-9 * math.max(1, math.abs(expected)), message)
end

for _, fuel in ipairs({ "Petrol", "Diesel", "Multifuel", "Electric", "Unknown" }) do
	near(ACE.Points.EngineCost(1000, fuel), ACE.Points.EngineCost(1000),
		"equal peak power must cost the same across fuel types")
end
near(ACE.Points.EngineCost(2000), 2 * ACE.Points.EngineCost(1000),
	"engine points must remain linear in power")
assert(ACE.Points.CrewCost(false) == 0 and ACE.Points.CrewCost(true) == 0,
	"all required crew must be free")
assert(ACE.Points.SustainedRps(0.1, 1, 0, "SBC", 3)
	> ACE.Points.SustainedRps(0.1, 1, 0, "SBC", 2),
	"free loaders must still increase the gun's priced cadence")

ACE.ArmorTypes = {}
for _, file in ipairs({ "rha", "cast", "ceramic", "du", "titanium", "aluminum", "era", "rubber", "textolite" }) do
	dofile(root .. "/lua/ace/shared/armor/" .. file .. ".lua")
end

-- Execute the billing and preview callers as well as the shared model, so dropping the
-- third pricing input at either call site cannot pass a pure-model-only test.
local function readSource(path)
	local file = assert(io.open(root .. "/lua/" .. path, "r"))
	local source = file:read("*a")
	file:close()
	return source
end
local shared = readSource("ace/shared/sh_ace_functions.lua")
assert(loadstring(assert(shared:match("(function ACE.GetSurvivabilityIndex%b().-\nend)"))))()
local tool = readSource("weapons/gmod_tool/stools/acearmorprop.lua")
local previewSource = assert(tool:match("(local function getArmorPointPreview%b().-\n\tend)"))
local preview = assert(loadstring(previewSource .. "\nreturn getArmorPointPreview"))()

for mat, material in pairs(ACE.ArmorTypes) do
	for _, thickness in ipairs({ 0.1, 1, 10, 100, 1000 }) do
		local ke, chem = ACE.Points.MaterialEff(mat)
		local curve = mat == "ERA" and 1 or material.curve
		local effective, efficiency = ACE.Points.MaterialArmor(thickness, mat)
		near(effective, thickness ^ curve * (0.7 * ke + 0.3 * chem),
			"pricing must use the material's ordinary curve or ERA's active linear path")
		near(efficiency * thickness * material.massMod, effective,
			"efficiency must equal RHA mass divided by material mass at equal protection")

		local prop = {
			GetClass = function() return "prop_physics" end,
			ACE = { MaxArmour = thickness, MaxHealth = 100, Material = mat, Armour = 0, Health = 0 },
		}
		local points = ACE.Points.ArmorProp(effective, 100, efficiency)
		near(ACE.GetSurvivabilityIndex(prop), points, "server billing must include mass efficiency")
		near(preview(thickness, 100, mat), points, "preview must match server billing")
		near(2 * ACE.Points.ArmorProp(effective, 50, efficiency), points,
			"splitting an equal-thickness plate's area/health must preserve total points")
	end
end

local rhaMm, rhaEfficiency = ACE.Points.MaterialArmor(100, "RHA")
local tiMm, tiEfficiency = ACE.Points.MaterialArmor(100 / 1.7, "Ti")
local castMm, castEfficiency = ACE.Points.MaterialArmor(100 / 0.98, "CHA")
near(tiMm, rhaMm, "fixture must compare equal protection")
near(castMm, rhaMm, "fixture must compare equal protection")
near(rhaEfficiency, 1, "RHA is the mass-efficiency baseline")
assert(ACE.Points.ArmorProp(tiMm, 100, tiEfficiency) > ACE.Points.ArmorProp(rhaMm, 100),
	"mass-reducing titanium must pay a premium at equal protection")
assert(ACE.Points.ArmorProp(castMm, 100, castEfficiency) < ACE.Points.ArmorProp(rhaMm, 100),
	"mass-inefficient cast armor must receive a discount at equal protection")
near(ACE.Points.EffectiveMm(100, 1, 1), 100, "legacy three-argument thickness calls must remain valid")
local unknownMm, unknownEfficiency = ACE.Points.MaterialArmor(100, "Unknown")
near(unknownMm, rhaMm, "unknown materials must keep the RHA billing fallback")
near(unknownEfficiency, 1, "unknown materials must have no mass adjustment")
near(preview(100, 100, "Unknown"), ACE.Points.ArmorProp(100, 100),
	"unknown-material preview and billing must agree")
for _, thickness in ipairs({ 0, -1 }) do
	local effective, efficiency = ACE.Points.MaterialArmor(thickness, "Rub")
	assert(effective == 0 and efficiency == 1, "empty armor must not divide by zero")
	assert(preview(thickness, 100, "Rub") == 0, "empty preview must be free")
end

local rackRate = ACE.Points.RackRate(2, 1)
local rackScore = ACE.Points.RoundScore(loaded)
local rackBaseCost = ACE.Points.BaseRoundCost(loaded)
local rackPricedRate = math.max(rackRate, 1 / 30)
local rackWithoutRound = math.max(ACE.PointsModel.kGun * rackPricedRate * rackScore, 100)
local rackWithRound = ACE.Points.RackCostFromRate(rackRate, rackScore, rackBaseCost)
local rackExpected = (rackWithoutRound + rackBaseCost) * ACE.PointsModel.Scale
assert(math.abs(rackWithRound - rackExpected) < 1e-9,
	"rack firepower must add the selected round's base cost exactly once")
assert(math.abs(rackWithoutRound * ACE.PointsModel.Scale
	+ rackBaseCost * ACE.PointsModel.Scale - rackWithRound) < 1e-9,
	"rack delivery and base-round points must sum to the billed total")
assert(math.abs(ACE.Points.RackCostFromRate(rackRate, rackScore)
	- rackWithoutRound * ACE.PointsModel.Scale) < 1e-9,
	"rack pricing without the optional base cost must preserve the old result")
assert(math.abs(ACE.Points.RackCost(2, 1, rackScore)
	- rackWithoutRound * ACE.PointsModel.Scale) < 1e-9,
	"rack wrapper without the optional base cost must preserve the old result")
local rackFloor = ACE.Points.RackCostFromRate(0, 0, rackBaseCost)
assert(math.abs(rackFloor - (100 + rackBaseCost) * ACE.PointsModel.Scale) < 1e-9,
	"rack flat floor must apply before the base-round addition")

print("ACE points model LuaJIT self-test: PASS")

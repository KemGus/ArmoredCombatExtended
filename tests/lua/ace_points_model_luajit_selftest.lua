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
for _, class in ipairs({ "SBC", "C", "HW", "AL" }) do
	for loaders = 0, 4 do
		near(ACE.Points.SustainedRps(0.1, 1, 0, class, loaders), 0.1,
			"crew count must not change priced cadence")
		near(ACE.Points.SustainedRps(2, 4, 6, class, loaders), 0.5,
			"magazine reload must still reduce priced cadence")
	end
end

local configuredGunRps = ACE.GetGunConfiguredRps
ACE.GetGunConfiguredRps = function(_, limit) return limit / 60 end
local pricingGun = { MagSize = 1, MagReload = 0, Class = "SBC", ROFLimit = 60 }
for loaders = 0, 4 do
	pricingGun.LoaderCount = loaders
	near(ACE.Points.GunSustainedRps(pricingGun, {}, {}), 1,
		"gun adapter must not reintroduce loader pricing")
end
pricingGun.ROFLimit = 30
near(ACE.Points.GunSustainedRps(pricingGun, {}, {}), 0.5,
	"gun adapter must retain the configured rate limit")
ACE.GetGunConfiguredRps = configuredGunRps

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
local pricingSource = shared:sub(assert(shared:find("local function resolveGunPricingCandidate", 1, true)),
	assert(shared:find("-- Tells a player when their weapon priced", 1, true)) - 1)
assert(loadstring(pricingSource))()
local convertRound, configuredRate = ACE.Points.RoundFromBullet, ACE.GetGunConfiguredRps
ACE.Points.RoundFromBullet = function(round) return round end
ACE.GetGunConfiguredRps = function(_, _, round) return round.rate end
local lowRound = { Type = "APFSDS", maxPen = 200, FrArea = 1, rate = 0.2 }
local highRound = { Type = "THEATFS", maxPen = 1000, FrArea = 1, rate = 0.1 }
local function ammo(round, capacity, index)
	return { BulletData = round, Capacity = capacity, Ammo = capacity,
		EntIndex = function() return index end }
end
local lowCrate, highCrate = ammo(lowRound, 9, 1), ammo(highRound, 3, 2)
local mixedGun = { GetClass = function() return "acf_gun" end, AmmoLink = { lowCrate } }
local lowCost = ACE.GetGunFirepowerPoints(mixedGun)
mixedGun.AmmoLink = { highCrate }
local highCost = ACE.GetGunFirepowerPoints(mixedGun)
mixedGun.AmmoLink = { lowCrate, highCrate }
near(ACE.GetGunFirepowerPoints(mixedGun), 0.75 * lowCost + 0.25 * highCost,
	"9 low and 3 high rounds must weight complete gun costs 75/25")
local mixedReadout = ACE.GetGunFirepowerReadout(mixedGun)
assert(mixedReadout.AmmoMix and not mixedReadout.Round,
	"mixed readout must not label a single round as the billed best round")
local comma, roundNumber = string.Comma, math.Round
string.Comma, math.Round = tostring, function(value) return math.floor(value + 0.5) end
assert(ACE.GetGunFirepowerPricingLine(mixedReadout, true):find("capacity-weighted", 1, true),
	"tool explanation must identify the weighted ammo mix")
string.Comma, math.Round = comma, roundNumber
lowCrate.Ammo, highCrate.Ammo = 0, 0
near(ACE.GetGunFirepowerPoints(mixedGun), mixedReadout.Points,
	"firing or resupplying must not change design points")
lowCrate.Capacity, highCrate.Capacity = 18, 6
near(ACE.GetGunFirepowerPoints(mixedGun), mixedReadout.Points,
	"doubling inventory at the same mix must not double cost")
mixedGun.AmmoLink = { ammo(lowRound, 9, 3), highCrate, ammo(lowRound, 9, 4) }
near(ACE.GetGunFirepowerPoints(mixedGun), mixedReadout.Points,
	"splitting the same rounds across crates must preserve cost")
mixedGun.AmmoLink = { lowCrate, ammo(highRound, 0, 5), ammo(highRound, nil, 6) }
near(ACE.GetGunFirepowerPoints(mixedGun), lowCost,
	"zero or missing capacities must not dilute the loadout")
mixedGun.AmmoLink = {}
near(ACE.GetGunFirepowerPoints(mixedGun), ACE.Points.GunCost(0, 0, 0),
	"unlinked guns must retain the weapon minimum")
local rackReload = ACE.GetRackConfiguredReloadTime
ACE.GetRackConfiguredReloadTime = function() return 2 end
local rack = { GetClass = function() return "acf_rack" end, MaxMissile = 1,
	AmmoLink = { lowCrate, highCrate } }
local rate = ACE.Points.RackRate(2, 1)
local rackExpected = math.max(
	ACE.Points.RackCostFromRate(rate, ACE.Points.RoundScore(lowRound), ACE.Points.BaseRoundCost(lowRound)),
	ACE.Points.RackCostFromRate(rate, ACE.Points.RoundScore(highRound), ACE.Points.BaseRoundCost(highRound)))
near(ACE.GetGunFirepowerPoints(rack), rackExpected, "racks must retain strongest-candidate pricing")
ACE.GetRackConfiguredReloadTime = rackReload
ACE.Points.RoundFromBullet, ACE.GetGunConfiguredRps = convertRound, configuredRate
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

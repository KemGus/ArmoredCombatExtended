ACE = ACE or {}
ACE.Points = ACE.Points or {}

--[[-----------------------------------------------------------------------------
	ACE Contraption Points -- pricing model

	Ammo count is not a points input; linked round capability prices guns and racks.
	Retune the calibrated constants together against the reference corpus.
	The pure model must load under vanilla Lua 5.1; GMod calls belong in the adapters.
-------------------------------------------------------------------------------]]

-- ================================================================
--  SECTION 1 -- PURE MODEL  (vanilla Lua 5.1; no GMod calls)
-- ================================================================

-- Retune these fields together and mutate them in place because Model retains this table.
ACE.PointsModel = ACE.PointsModel or {
	kGun   = 5.408,            -- firepower scale
	kArmor = 0.259845,         -- armor survivability scale
	kEng   = 1.501,            -- engine power scale
	P50    = 548.5,            -- gate half-point: pen where a round defeats half the meta
	Scale  = 0.65,             -- global display scale; sets how much of PointsLimit real fielded
	                           -- vehicles use, deliberately independent of the corpus fit below
}

local Model = ACE.PointsModel

local pi   = math.pi
local sqrt = math.sqrt
local max  = math.max
local min  = math.min

-- --- FIXED structural constants (NOT calibration knobs) ---
local FRAREA_REF = pi * 5.0 ^ 2   -- 100mm reference round cross-section (radius 5cm), cm^2
local BLAST_REF  = 6.0            -- kg filler reference
-- HE lethality pen-equivalent: 30 * filler_kg^(2/3) mm -- the splash coverage channel
-- (blast radius^2 scales with kg^(2/3)).
local HE_EQUIV   = 30.0
-- Armor actually defeated by blast: filler_kg x HEPower / HEBlastPenetration (the damage
-- code's own blast-penetration channel). Used by the gate so heavy ordnance that genuinely
-- penetrates through blast is judged by that real reach rather than only its splash equivalent.
local HE_BLAST_PEN_PER_KG = 8000.0 / 3500.0
local ROUND_COST_FLOOR = 1.0        -- every configured round has a non-zero weapon-pricing input
-- HE's splash, module damage, and soft-target utility add value beyond its direct lethality terms.
local HE_INTRINSIC_VALUE_MULT = 1.50
-- GATE is LINEAR (GATE_EXP = 1): effectiveness = pen/(pen+P50). Kept linear for legibility;
-- a saturating (Hill-style) fit prices the corpus the same, so no exponent term is needed.
local GUN_FLAT    = 20.0          -- no weapon is free (utility launchers price here)
local RACK_FLAT   = 100.0
-- 30s engagement window: a rack's sustained rate is capped at tubes/window -- it is NOT an
-- infinite-reload DPS machine. Tubes are launcher hardware (mountpoint count), not a
-- carried-round choice; keeps missiles/planes sanely priced. Also sets the gun/rack priced-rate
-- floor (1/RACK_WINDOW): no mounted delivery system prices below one round per window, closing
-- the slow-alpha and tiny-ROFLimit aliases of the same cheese.
local RACK_WINDOW = 30.0
-- Balance reference: an identical unguided warhead fired by a 5 rpm gun. A ready
-- tube pays the remaining 3 rpm of value in addition to its 2 rpm delivery allowance.
local RACK_REFERENCE_RPS = 5.0 / 60.0
local RACK_READY_RPS = RACK_REFERENCE_RPS - 1.0 / RACK_WINDOW
local EXP_MM = 1.4                -- armor thickness exponent (intensive term -- untouched)
-- Armor HP exponent. LINEAR/extensive on purpose: N props of the same total HP price
-- identically to 1 prop, so splitting armor into fragments is points-neutral. A sub-linear
-- exponent would reward that split as a pricing exploit.
local EXP_HP = 1.0

-- --- type tables ---
local DAMAGE_MULT = {   -- post-pen damage multipliers (acf_globals.lua:253-261 ACE.*DamageMult)
	AP = 2.0, APHE = 1.75, APDS = 3.0, APFSDS = 3.0, HVAP = 2.0,
	HEAT = 6.0, HE = 2.0, HESH = 1.2, HP = 8.0, FL = 1.4,
}
local TYPE_MAP = {      -- round type id -> damage family
	AP = "AP", APHE = "APHE", APDS = "APDS", APFSDS = "APFSDS", HVAP = "HVAP",
	HP = "HP", CAP = "AP",
	HEAT = "HEAT", HEATFS = "HEAT", THEAT = "HEAT", THEATFS = "HEAT", CHEAT = "HEAT",
	GLATGM = "HEAT", ["GLATGM-HE"] = "HE",
	HE = "HE", HEFS = "HE", CHE = "HE",
	HESH = "HESH",
	SM = "SM", FLR = "SM", CHF = "SM", FL = "FL", Refill = "Refill",
}
local function hasHEPayload(round, fam)
	if fam == "HE" then return true end
	if fam ~= "APHE" then return false end

	return (tonumber(round.blastMass) or 0) > 0
end
-- HEAT jet family: the shaped-charge slug caliber (not the shell body) sets the area.
local HEAT_FAMILY = { HEAT = true, HEATFS = true, THEAT = true, THEATFS = true, CHEAT = true, GLATGM = true }
local UTILITY     = { SM = true, Refill = true }   -- smoke, chaff, flares, and refill carry no damage
-- Guidance names omitted from this table use a 1.0 multiplier.
local GUIDANCE = {
	Dumb = 0.5,
	Straight_Running = 0.6,
	Radar = 1.4,
	Semiactive = 0.8,
	Infrared = 1.2,
	Top_Attack_IR = 1.8,
	GPS = 0.7,
	GPS_TerrainAvoidant = 0.8,
	AntiRadiation = 0.6, --Cost lowered to increase viability of antiradiation missiles as a backup weapon.
	Beam_Riding = 0.8, --Beamriding is an inferior guidance method due to inability to see in 3d and wasted energy.
}

-- Total rack-price ratios against the reference gun, applied after weapon floors.
-- Unlisted guidance keeps its existing relative factor; guns/explosives are unchanged.
local RACK_GUIDANCE = {
	Dumb = 0.7, Laser = 1.1, Infrared = 2.5, Radar = 2.5, Top_Attack_IR = 3.5,
}

--- Returns the rack's guidance price ratio against the reference gun.
-- @param round table Converted round configuration.
-- @return number Guidance ratio; unspecified guidance uses parity.
function ACE.Points.RackGuidanceMul(round)
	local guidance = round and round.guidance
	return RACK_GUIDANCE[guidance] or GUIDANCE[guidance] or 1.0
end

-- Lethality once the round is inside armor: base damage plus the hole it tears
-- (frontal area x the type's damage multiplier, normalized so a 100mm AP shell = 1.0; HEAT
-- uses its jet cross-section, not the shell body), plus the explosive payload it delivers
-- (sqrt of filler kg vs a 6kg reference). Utility (smoke/refill) rounds return 0,0,0.
function ACE.Points.PostPenParts(round)
	local t = round.Type
	if not t or t == "" then t = "AP" end
	local fam = TYPE_MAP[t] or "AP"
	if UTILITY[fam] then return 0.0, 0.0, 0.0 end

	local mult = DAMAGE_MULT[fam] or 1.0
	local slug = tonumber(round.SlugCaliber) or 0
	local area
	if HEAT_FAMILY[t] and slug ~= 0 then
		area = pi * (slug / 2) ^ 2            -- shaped-charge jet, not shell body
	else
		area = tonumber(round.FrArea) or 0.0
	end

	local blast = tonumber(round.blastMass) or 0.0
	return 1.0,
		(area * mult) / (FRAREA_REF * DAMAGE_MULT.AP),    -- FrArea normalized vs 100mm AP
		sqrt(max(blast, 0.0) / BLAST_REF)
end

-- The three parts summed: the per-round "inside-armor damage" multiplier.
function ACE.Points.PostPenMult(round)
	local base, hole, blast = ACE.Points.PostPenParts(round)
	return base + hole + blast
end

-- Penetration used for lethality: raw maxPen, but HE/APHE/HESH payloads floor it at a
-- blast-equivalent so big fillers still register a threat even with token stated pen.
function ACE.Points.LethalityPen(round)
	local pen = tonumber(round.maxPen) or 0.0
	local fam = TYPE_MAP[round.Type or "AP"] or "AP"
	if hasHEPayload(round, fam) or fam == "HESH" then
		local blast = tonumber(round.blastMass) or 0.0
		pen = max(pen, HE_EQUIV * blast ^ (2.0 / 3.0))
	end
	return pen
end

-- Guidance multiplier for a round (1.0 for everything but guided missile ammo). Public so
-- displays can show the "x 1.5 guidance" factor instead of hiding it inside baseRoundCost.
function ACE.Points.GuidanceMul(round)
	local g = round.guidance
	if g and g ~= "" then
		return GUIDANCE[g] or 1.0
	end
	return 1.0
end

-- Intrinsic value beyond direct lethality terms; shared by billing and explanatory readouts.
function ACE.Points.IntrinsicValueMul(round)
	local fam = TYPE_MAP[round and round.Type or "AP"] or "AP"
	return hasHEPayload(round, fam) and HE_INTRINSIC_VALUE_MULT or 1.0
end

-- Intrinsic cost of one configured round. Inventory count is not billed, but every weapon
-- multiplies this value by its own delivery rate and threat factor.
--- Computes intrinsic round value, optionally before guidance for rack pricing.
-- @param round table Converted round configuration.
-- @param unguided boolean Omit guidance when the weapon applies it to its final price.
-- @return number Intrinsic round value.
function ACE.Points.BaseRoundCost(round, unguided)
	local cost = ACE.Points.LethalityPen(round) * ACE.Points.PostPenMult(round)
		* (unguided and 1.0 or ACE.Points.GuidanceMul(round)) * ACE.Points.IntrinsicValueMul(round)
	return max(cost, ROUND_COST_FLOOR)
end

-- Share of the meta this pen defeats. The curve is continuous from zero with no minimum share.
function ACE.Points.Gate(pen)
	pen = tonumber(pen) or 0
	if pen <= 0 then return 0 end
	return pen / (pen + Model.P50)
end

-- Penetration the GATE judges a round by. HE/APHE payloads use their blast lethality reach because splash,
-- module damage, and soft-target effects create combat value without literal armor penetration;
-- HESH retains only the damage code's literal blast-penetration channel.
function ACE.Points.GatePen(round)
	local pen = tonumber(round.maxPen) or 0.0
	local fam = TYPE_MAP[round.Type or "AP"] or "AP"
	if hasHEPayload(round, fam) then
		pen = max(pen, ACE.Points.LethalityPen(round))
		local blast = tonumber(round.blastMass) or 0.0
		pen = max(pen, blast * HE_BLAST_PEN_PER_KG)
	elseif fam == "HESH" then
		local blast = tonumber(round.blastMass) or 0.0
		pen = max(pen, blast * HE_BLAST_PEN_PER_KG)
	end
	return pen
end

-- Round score = threat * baseRoundCost.
function ACE.Points.RoundScore(round)
	return ACE.Points.Gate(ACE.Points.GatePen(round)) * ACE.Points.BaseRoundCost(round)
end

-- Candidate ordering is final weapon output, then per-shot score, then stable source order.
function ACE.Points.IsBetterCandidate(candidate, best)
	if not best then return true end
	if candidate.FinalScore ~= best.FinalScore then return candidate.FinalScore > best.FinalScore end
	if candidate.RoundScore ~= best.RoundScore then return candidate.RoundScore > best.RoundScore end
	return candidate.SourceIndex < best.SourceIndex
end

--- Prices magazine-aware cadence without crew reload modifiers.
-- @param baseRps number Configured rounds per second, including the wire ROFLimit.
-- @param magSize number Magazine capacity.
-- @param magReload number Magazine reload time in seconds.
-- @return number Sustained rounds per second used for points.
function ACE.Points.SustainedRps(baseRps, magSize, magReload)
	local base   = tonumber(baseRps) or 0
	local mag    = tonumber(magSize) or 0
	local magrel = tonumber(magReload) or 0

	if mag > 1 and magrel > 0 and base > 0 then
		base = mag / (mag / base + magrel)
	end
	return base
end

-- Gun firepower cost (scaled). This is called once per gun entity; identical guns therefore
-- add linearly instead of sharing or deduplicating the round cost.
function ACE.Points.GunCost(sustainedRps, baseRoundCost, threat)
	local pricedRps = max(tonumber(sustainedRps) or 0, 1.0 / RACK_WINDOW)
	return max(Model.kGun
		* pricedRps
		* (tonumber(baseRoundCost) or 0)
		* (tonumber(threat) or 0), GUN_FLAT) * Model.Scale
end

function ACE.Points.RackRate(reloadTime, maxMissile)
	local rt = tonumber(reloadTime) or 0
	if rt == 0 then rt = 10.0 end
	local mm = tonumber(maxMissile) or 0
	if mm == 0 then mm = 1 end
	return min(1.0 / max(rt, 0.5), mm / RACK_WINDOW)
end

--- Prices rack delivery and one base-round charge per ready tube.
-- @param rate number Sustained rounds per second.
-- @param bestScore number Selected round's threat-weighted score.
-- @param baseRoundCost number Selected round's base cost.
-- @param maxMissile number Ready tube count, default/minimum 1.
-- @param guidance number Final guidance ratio; omitted retains legacy helper pricing.
-- @return number Scaled rack points.
-- @return number Scaled ready-tube points.
-- @return number Scaled total before flat minima, with the delivery-rate floor applied.
function ACE.Points.RackCostFromRate(rate, bestScore, baseRoundCost, maxMissile, guidance)
	local pricedRate = max(tonumber(rate) or 0, 1.0 / RACK_WINDOW)
	local tubes = max(tonumber(maxMissile) or 1, 1)
	if guidance then
		local score = max(tonumber(bestScore) or 0, 0)
		local scale = Model.Scale * guidance
		local delivery = Model.kGun * pricedRate * score
		local ready = Model.kGun * RACK_READY_RPS * score
		local deliveryFloor = GUN_FLAT / (RACK_WINDOW * RACK_REFERENCE_RPS)
		local readyFloor = GUN_FLAT - deliveryFloor
		local readyPoints = max(ready, readyFloor) * tubes * scale
		return max(delivery, deliveryFloor * tubes) * scale + readyPoints, readyPoints,
			(delivery + ready * tubes) * scale
	end
	local deliveryCost = max(Model.kGun * pricedRate
		* (tonumber(bestScore) or 0), RACK_FLAT)
	local readyCost = max(tonumber(baseRoundCost) or 0, 0) * max(tonumber(maxMissile) or 1, 1)
	return (deliveryCost + readyCost) * Model.Scale
end

-- Public so readouts can tell a player when the priced-rate floor changed their bill, instead
-- of leaving the window a silently duplicated magic number.
function ACE.Points.RateFloor()
	return 1.0 / RACK_WINDOW
end

--- Prices a rack from its configured reload time and ready capacity.
-- @param reloadTime number Configured reload time in seconds.
-- @param maxMissile number Ready tube count.
-- @param bestScore number Selected round's threat-weighted score.
-- @param baseRoundCost number Selected round's base cost.
-- @param guidance number Final guidance ratio; omitted retains legacy helper pricing.
-- @return number Scaled rack points.
function ACE.Points.RackCost(reloadTime, maxMissile, bestScore, baseRoundCost, guidance)
	return ACE.Points.RackCostFromRate(ACE.Points.RackRate(reloadTime, maxMissile), bestScore, baseRoundCost, maxMissile, guidance)
end

-- Mounted charges use one tube-window without the rack hardware floor. Stored ammo remains free.
function ACE.Points.ChargeCost(fillerKg)
	fillerKg = tonumber(fillerKg) or 0
	if fillerKg <= 0 then return 0 end
	local round = { Type = "HE", maxPen = 0, FrArea = 0, blastMass = fillerKg, guidance = "Dumb" }
	return Model.kGun * (1.0 / RACK_WINDOW) * ACE.Points.RoundScore(round) * Model.Scale
end

--- Blends normal-incidence protection after the material's thickness curve.
-- @param armourMm number Nominal armor thickness in mm.
-- @param ke number Kinetic effectiveness.
-- @param chem number Chemical effectiveness.
-- @param curve number Optional thickness exponent, default 1.
-- @return number Blended effective thickness in mm.
function ACE.Points.EffectiveMm(armourMm, ke, chem, curve)
	return max(tonumber(armourMm) or 0, 0) ^ (tonumber(curve) or 1)
		* (0.7 * (tonumber(ke) or 1) + 0.3 * (tonumber(chem) or 1))
end

--- Prices protection and its mass efficiency relative to RHA.
-- @param effMm number Blended effective thickness in mm.
-- @param maxHealth number Undamaged prop health.
-- @param massEfficiency number Optional equal-protection mass ratio, default 1.
-- @return number Scaled armor points.
function ACE.Points.ArmorProp(effMm, maxHealth, massEfficiency)
	return Model.kArmor * 100.0
		* ((tonumber(effMm) or 0) / 50.0) ^ EXP_MM
		* ((tonumber(maxHealth) or 0) / 75.0) ^ EXP_HP
		* (tonumber(massEfficiency) or 1)
		* Model.Scale
end

--- Prices peak engine power independently of fuel type.
-- @param hp number Peak horsepower (peakkw / 0.7457).
-- @return number Scaled engine points.
function ACE.Points.EngineCost(hp)
	return Model.kEng * (tonumber(hp) or 0) * Model.Scale
end

--- Keeps required crew and their reload benefits free.
-- @return number Zero crew points.
function ACE.Points.CrewCost()
	return 0
end

-- ================================================================
--  SECTION 2 -- ADAPTERS  (GLua; entity -> plain values -> pure funcs)
-- ================================================================

-- Guidance table keys replace spaces and dashes with underscores.
local function normalizeGuidanceName(name)
	if not isstring(name) or name == "" then return nil end
	return (name:gsub("%s+", "_"):gsub("%-", "_"))
end

-- Guidance may be a serialized string, keyed table, or ordered mode list.
local function resolveGuidanceName(guidanceValue)
	if isstring(guidanceValue) then
		local name = ACE.GetConfigurableName(guidanceValue, "")
		if name == "" then name = guidanceValue end
		return normalizeGuidanceName(name)
	elseif istable(guidanceValue) then
		local name = guidanceValue.ClassName or guidanceValue.class or guidanceValue.GuidanceName
			or guidanceValue.Guidance or guidanceValue.Type
		if name == nil then name = guidanceValue[1] end
		return normalizeGuidanceName(name)
	end
	return nil
end

-- KE/CHEM weights, mass modifier, pricing thickness curve. Unknown materials use RHA.
-- ERA's active detonation path uses linear thickness, not its depleted-plate curve.
local MATERIAL_EFF = {
	RHA   = { 1.0,    1.0,          1.0,   1.0 },
	CHA   = { 0.98,   0.98,         1.2,   1.0 },
	Cer   = { 2.05,   2.05,         1.2,   0.99 },
	DU    = { 3.0,    3.0,          2.43,  1.06 },
	Ti    = { 1.7,    1.7,          0.61,  1.0 },
	Alum  = { 0.8325, 0.8325 / 5.0, 0.333, 0.92 },
	ERA   = { 2.5,    8.0,          2.0,   1.0 },
	Rub   = { 0.05,   3.0,          0.2,   0.93 },
	Texto = { 0.5,    1.2,          0.35,  0.94 },
}

-- Returns nil for unknown materials so display code can fall back to live material data.
function ACE.Points.MaterialEff(mat)
	local eff = MATERIAL_EFF[mat]
	if not eff then return nil end
	return eff[1], eff[2]
end

--- Resolves shared billing and preview inputs for a material.
-- @param armourMm number Nominal armor thickness in mm.
-- @param mat string Material identifier; unknown materials price as RHA.
-- @return number Blended effective thickness in mm.
-- @return number RHA mass divided by material mass at equal blended protection and area.
function ACE.Points.MaterialArmor(armourMm, mat)
	armourMm = tonumber(armourMm) or 0
	if armourMm <= 0 then return 0, 1 end

	local eff = MATERIAL_EFF[mat or "RHA"] or MATERIAL_EFF.RHA
	local effMm = ACE.Points.EffectiveMm(armourMm, eff[1], eff[2], eff[4])
	return effMm, effMm / (armourMm * eff[3])
end

-- Build the plain pricing round from a gun/crate/rack BulletData table. nil if not a table.
function ACE.Points.RoundFromBullet(bdata)
	if not istable(bdata) then return nil end

	local round = {
		Type        = ACE.ResolveAmmoType(nil, bdata),   -- bdata branch: bdata.Type or bdata.RoundType
		maxPen      = ACE.GetAmmoMaxPen(bdata),
		FrArea      = tonumber(bdata.FrArea) or 0,
		SlugCaliber = tonumber(bdata.SlugCaliber),       -- HEAT family only; nil otherwise
		blastMass   = ACE.GetAmmoBlastMass(bdata),
	}

	-- Guidance folds the old per-missile pricing premium into baseRoundCost. Candidates:
	-- BulletData.guidance/Guidance, else Data7 (the runtime-configured guidance object the
	-- legacy pricing read). GLATGM (gun-launched grenade ammo) opts out, as it always has.
	-- Non-missiles carry none, so guidance stays nil (1.0).
	local guid = bdata.guidance or bdata.Guidance or bdata.Data7
	if guid ~= nil and not ACE.IsGLATGMAmmoType(bdata.Type) then
		round.guidance = resolveGuidanceName(guid)
	end

	return round
end

--- Resolves priced gun cadence without loader bonuses or uncrewed penalties.
-- ROFLimit remains a pricing input and its trigger path must dirty points.
-- @param gun Entity Gun being priced.
-- @param bdata table Candidate bullet data.
-- @param crate Entity Candidate ammo crate.
-- @return number Sustained rounds per second used for points.
function ACE.Points.GunSustainedRps(gun, bdata, crate)
	if not ACE.IsEnt(gun) then return 0 end
	local base = ACE.GetGunConfiguredRps(gun, tonumber(gun.ROFLimit) or 0, bdata, crate)
	return ACE.Points.SustainedRps(base, gun.MagSize, gun.MagReload)
end

-- Mounted charge (scalable explosives / bombs family) -> scaled points. Prices the charge's
-- REAL filler mass -- self.FillerMass, kg of HE, set once at spawn from the scaled charge
-- volume -- as mounted ordnance via ACE.Points.ChargeCost. 0 for a filler-less/invalid entity.
function ACE.Points.ChargeEntCost(ent)
	if not ACE.IsEnt(ent) then return 0 end
	return ACE.Points.ChargeCost(tonumber(ent.FillerMass) or 0)
end

--- Resolves a prop's static armor pricing inputs.
-- Skips components, pods and props with no armor/health. Uses undamaged state, shared
-- with the armor-tool preview.
-- @param ent Entity Armor prop.
-- @return number Effective thickness, or nil for an excluded/unready entity.
-- @return number Undamaged health.
-- @return number Relative mass efficiency.
function ACE.Points.PropArmor(ent)
	if not ACE.IsEnt(ent) then return nil end
	if ent.ACE_PrimitiveArmorPending or ent.ACE_PrimitivePropertiesPending
		or ent.ACE_PrimitiveRestoreSavedArmor then
		return nil
	end

	local cls = ent:GetClass() or ""
	if cls:sub(1, 4) == "acf_" or cls:sub(1, 4) == "ace_" or cls:sub(1, 5) == "gmod_"
		or cls:find("pod", 1, true) then
		return nil
	end

	local acf = ACE.GetEntityState(ent)
	if not istable(acf) then return nil end

	local armourMm = tonumber(acf.MaxArmour) or 0
	local hp       = tonumber(acf.MaxHealth) or 0
	if armourMm <= 0 or hp <= 0 then return nil end

	local effMm, massEfficiency = ACE.Points.MaterialArmor(armourMm, acf.Material or ent.ACE_Material)
	return effMm, hp, massEfficiency
end

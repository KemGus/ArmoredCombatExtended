-- Standalone unit tests for the ERA cut model (lua/acf/shared/sh_ace_era.lua).
-- Loads the real production files, no GMod required.
--
-- Run from the repo root with any Lua 5.1+:
--   lua tests/era_math_test.lua
--
-- ComputeCut(Gen, Type, penMM, caliberMM, aoaDeg, healthRatio, velMS, projMassKg)
--   aoaDeg: 0 = perpendicular (face-on), higher = grazing.

-- GMod math extensions the production code uses, shimmed for stock Lua.
math.Clamp = math.Clamp or function(v, a, b) return math.max(a, math.min(b, v)) end
math.Round = math.Round or function(v, d) local m = 10 ^ (d or 0) return math.floor(v * m + 0.5) / m end

ACE = { ArmorTypes = {} }
ACF = { SlopeEffectFactor = 1.1 }
SERVER = false

dofile("lua/acf/shared/sh_ace_era.lua")
dofile("lua/acf/shared/armor/era.lua")
dofile("lua/acf/shared/armor/era2.lua")
dofile("lua/acf/shared/armor/era3.lua")

local ERA = ACE.ERA
local G1, G2, G3 = ERA.Generations["ERA"], ERA.Generations["ERA2"], ERA.Generations["ERA3"]
assert(G1 and G2 and G3, "generation registration failed")

local Failed, Passed = 0, 0
local function check(name, cond, detail)
	if cond then Passed = Passed + 1 else
		Failed = Failed + 1
		print(("FAIL: %s%s"):format(name, detail and (" -- " .. detail) or ""))
	end
end
local function isFinite(x) return x == x and x ~= math.huge and x ~= -math.huge end

-- Reference penetrators: type, pen(mm), caliber(mm), vel(m/s), mass(kg).
-- Caliber is the PENETRATOR (dart) caliber the damage code reports, not the gun:
-- a min-subcaliber 120mm tank APFSDS works out to ~25mm, ~3.4 kg.
local APFSDS = { "APFSDS", 550, 25, 1500, 3.4 }  -- tank sabot dart
local ACAPFS = { "APFSDS", 120, 13, 1400, 0.3 }  -- 30mm autocannon dart (thin, light)
local AP     = { "AP",     180, 85, 900,  9 }    -- full-bore AP shot
local HEAT   = { "HEAT",   450, 60, nil,  nil }  -- 105mm HEAT slug
local THEAT  = { "THEAT",  450, 60, nil,  nil }  -- tandem precursor/main jet
local function cut(gen, p, aoa, hp, velOverride, massOverride, plateLen, travel)
	local vel = velOverride; if vel == nil then vel = p[4] end
	local mass = massOverride; if mass == nil then mass = p[5] end
	return ERA.ComputeCut(gen, p[1], p[2], p[3], aoa, hp or 1, vel, mass, plateLen, travel)
end

----------------------------------------------------------------------------
-- 1. Stability: finite, 0..1 cut, 0..0.35 deflect across a wide sweep.
----------------------------------------------------------------------------
do
	local ok = true
	local types = { "AP", "APDS", "APFSDS", "HVAP", "HEAT", "THEATFS", "Unknown" }
	for _, gen in ipairs({ G1, G2, G3 }) do
		for _, t in ipairs(types) do
			for _, pen in ipairs({ 0, 1, 90, 550, 2000 }) do
				for _, cal in ipairs({ 0, 5, 30, 120, 200 }) do
					for _, aoa in ipairs({ 0, 30, 60, 89 }) do
						for _, hp in ipairs({ 0, 0.4, 1 }) do
							for _, vel in ipairs({ 0, 800, 1800 }) do
								local c, d = ERA.ComputeCut(gen, t, pen, cal, aoa, hp, vel, 5)
								if not (isFinite(c) and isFinite(d) and c >= 0 and c <= 1 and d >= 0 and d <= 0.35) then
									ok = false
									print(("  bad: %s %s pen=%s cal=%s aoa=%s hp=%s vel=%s -> %s/%s")
										:format(gen.id, t, pen, cal, aoa, hp, vel, tostring(c), tostring(d)))
								end
							end
						end
					end
				end
			end
		end
	end
	check("stability sweep (finite, cut 0..1, deflect 0..0.35)", ok)
end

----------------------------------------------------------------------------
-- 2. Degenerate inputs -> zero.
----------------------------------------------------------------------------
check("zero penetration -> zero cut", ERA.ComputeCut(G2, "APFSDS", 0, 120, 60, 1, 1500, 6) == 0)
check("zero caliber -> zero cut", ERA.ComputeCut(G2, "APFSDS", 550, 0, 60, 1, 1500, 6) == 0)

----------------------------------------------------------------------------
-- 3. Caps and floors per generation.
----------------------------------------------------------------------------
for _, gen in ipairs({ G1, G2, G3 }) do
	local keMax, heatMax = 0, 0
	for aoa = 0, 89, 5 do
		keMax = math.max(keMax, (cut(gen, AP, aoa)))        -- light rod -> pushes the cap; parens truncate multi-return
		heatMax = math.max(heatMax, (cut(gen, HEAT, aoa)))
	end
	check(gen.id .. " KE cut <= cap", keMax <= gen.MaxCutKE + 1e-9, "max " .. keMax)
	check(gen.id .. " HEAT cut <= cap", heatMax <= gen.MaxCutHEAT + 1e-9, "max " .. heatMax)

	-- Heavy long rod, face-on: still at least the floor when triggered.
	check(gen.id .. " KE floor holds", cut(gen, APFSDS, 0) >= gen.MinCutKE - 1e-9, "got " .. cut(gen, APFSDS, 0))
	check(gen.id .. " HEAT floor holds", cut(gen, HEAT, 0) >= gen.MinCutHEAT - 1e-9, "got " .. cut(gen, HEAT, 0))
end

----------------------------------------------------------------------------
-- 4. Physical monotonicity: angle, velocity, mass/rod-length, health.
----------------------------------------------------------------------------
do
	-- Grazing hits engage more plate than face-on.
	check("KE: grazing >= face-on", cut(G2, APFSDS, 75) >= cut(G2, APFSDS, 0))
	check("HEAT: grazing >= face-on", cut(G2, HEAT, 75) >= cut(G2, HEAT, 0))

	-- At equal penetration, a SLOWER rod is cut more (plate has more time).
	local slow = cut(G2, APFSDS, 60, 1, 1100, 6)
	local fast = cut(G2, APFSDS, 60, 1, 1900, 6)
	check("slower rod cut more at equal pen", slow > fast, ("%.3f vs %.3f"):format(slow, fast))

	-- A heavier / longer rod (more mass, same caliber) is cut less.
	local light = cut(G2, APFSDS, 60, 1, 1500, 4)
	local heavy = cut(G2, APFSDS, 60, 1, 1500, 9)
	check("longer/heavier rod cut less", heavy <= light, ("%.3f vs %.3f"):format(heavy, light))

	-- Damaged bricks react weaker.
	check("damaged brick reacts weaker", cut(G2, APFSDS, 60, 0.5) <= cut(G2, APFSDS, 60, 1))
end

----------------------------------------------------------------------------
-- 5. Jets cut hard, never deflected; solid rods can be deflected.
----------------------------------------------------------------------------
do
	local c, d = ERA.ComputeCut(G1, "HEAT", 450, 60, 60, 1)
	check("gen1 vs HEAT strong", c >= 0.5, "got " .. c)
	check("jets never deflected", d == 0)

	local _, d2 = ERA.ComputeCut(G2, "AP", 180, 85, 60, 1, 900, 9)
	check("solid rods can deflect", d2 > 0, "got " .. d2)
end

----------------------------------------------------------------------------
-- 5b. HEAT family (HEAT, THEAT, HEATFS, THEATFS): all behave as jets - cut hard,
--     never deflected, and obey the per-generation floor/cap/ordering. (The
--     tandem precursor->main interaction and Gen 3 surviving a precursor live in
--     ERA.ArmorResolution + the round logic, so they are exercised in-game with
--     ace_era_debug, not in this pure-math unit test.)
----------------------------------------------------------------------------
do
	for _, t in ipairs({ "HEAT", "THEAT", "HEATFS", "THEATFS" }) do
		for _, gen in ipairs({ G1, G2, G3 }) do
			local c, d = ERA.ComputeCut(gen, t, 500, 60, 60, 1)
			check(("%s vs %s: cut in [floor,cap], no deflect"):format(gen.id, t),
				c >= gen.MinCutHEAT - 1e-9 and c <= gen.MaxCutHEAT + 1e-9 and d == 0,
				("cut %.3f defl %.3f"):format(c, d))
		end
	end

	-- Faster FS jets are not deflected and stay within the HEAT band.
	check("HEATFS treated as a jet (no deflect)", select(2, ERA.ComputeCut(G2, "HEATFS", 600, 50, 45, 1)) == 0)

	-- Gen ordering for tandem jets.
	local t1 = ERA.ComputeCut(G1, "THEAT", 450, 60, 60, 1)
	local t2 = ERA.ComputeCut(G2, "THEAT", 450, 60, 60, 1)
	local t3 = ERA.ComputeCut(G3, "THEAT", 450, 60, 60, 1)
	check("THEAT: gen3 >= gen2 >= gen1", t3 >= t2 and t2 >= t1, ("%.2f/%.2f/%.2f"):format(t1, t2, t3))
end

----------------------------------------------------------------------------
-- 6. Generation ordering: newer >= older.
----------------------------------------------------------------------------
for _, aoa in ipairs({ 0, 45, 75 }) do
	local k1, k2, k3 = cut(G1, APFSDS, aoa), cut(G2, APFSDS, aoa), cut(G3, APFSDS, aoa)
	check("KE gen3>=gen2>=gen1 @aoa " .. aoa, k3 >= k2 and k2 >= k1, ("%.3f/%.3f/%.3f"):format(k1, k2, k3))
	local h1, h2, h3 = cut(G1, HEAT, aoa), cut(G2, HEAT, aoa), cut(G3, HEAT, aoa)
	check("HEAT gen3>=gen2>=gen1 @aoa " .. aoa, h3 >= h2 and h2 >= h1, ("%.3f/%.3f/%.3f"):format(h1, h2, h3))
end

----------------------------------------------------------------------------
-- 7. Balance reference bands (tuning targets; sloped = aoa 60).
----------------------------------------------------------------------------
do
	-- Gen 1 does ~nothing to a long rod (casing only).
	check("gen1 APFSDS negligible at all angles <= 0.05", cut(G1, APFSDS, 0) <= 0.05 and cut(G1, APFSDS, 75) <= 0.05,
		("%.3f / %.3f"):format(cut(G1, APFSDS, 0), cut(G1, APFSDS, 75)))
	check("gen2 sloped APFSDS in 0.18..0.30", cut(G2, APFSDS, 60) >= 0.18 and cut(G2, APFSDS, 60) <= 0.30, "got " .. cut(G2, APFSDS, 60))
	check("gen3 sloped APFSDS in 0.28..0.45", cut(G3, APFSDS, 60) >= 0.28 and cut(G3, APFSDS, 60) <= 0.45, "got " .. cut(G3, APFSDS, 60))
	check("gen1 sloped HEAT in 0.55..0.80", cut(G1, HEAT, 60) >= 0.55 and cut(G1, HEAT, 60) <= 0.80, "got " .. cut(G1, HEAT, 60))
	check("gen3 sloped HEAT >= 0.85", cut(G3, HEAT, 60) >= 0.85, "got " .. cut(G3, HEAT, 60))
end

----------------------------------------------------------------------------
-- 7b. Brick geometry: bigger bricks bite more for Gen 2/3, not Gen 1.
----------------------------------------------------------------------------
do
	-- plateLen, travel in mm. Small brick vs large brick at the same sloped hit.
	local g2small = cut(G2, APFSDS, 60, 1, nil, nil, 150, 60)
	local g2large = cut(G2, APFSDS, 60, 1, nil, nil, 600, 200)
	check("gen2: larger brick cuts more", g2large > g2small, ("%.3f vs %.3f"):format(g2large, g2small))

	local g3small = cut(G3, APFSDS, 60, 1, nil, nil, 150, 60)
	local g3large = cut(G3, APFSDS, 60, 1, nil, nil, 600, 200)
	check("gen3: larger brick cuts more (and most of all)", g3large > g3small and (g3large - g3small) >= (g2large - g2small),
		("g2 +%.3f, g3 +%.3f"):format(g2large - g2small, g3large - g3small))

	local g1small = cut(G1, APFSDS, 60, 1, nil, nil, 150, 60)
	local g1large = cut(G1, APFSDS, 60, 1, nil, nil, 600, 200)
	check("gen1: brick size barely matters vs KE", math.abs(g1large - g1small) < 0.01, ("%.4f vs %.4f"):format(g1large, g1small))
end

----------------------------------------------------------------------------
-- 8. Effective-armor estimate is positive and ordered (menus / E2 / SF).
----------------------------------------------------------------------------
do
	local ke1, ke2, ke3 = ERA.EstimateEffectiveArmor(G1, "KE"), ERA.EstimateEffectiveArmor(G2, "KE"), ERA.EstimateEffectiveArmor(G3, "KE")
	check("effective KE armor ordered & positive", ke1 > 0 and ke3 >= ke2 and ke2 >= ke1, ("%.0f/%.0f/%.0f"):format(ke1, ke2, ke3))
	local h1, h3 = ERA.EstimateEffectiveArmor(G1, "HEAT"), ERA.EstimateEffectiveArmor(G3, "HEAT")
	check("effective HEAT armor positive & ordered", h1 > 0 and h3 >= h1, ("%.0f/%.0f"):format(h1, h3))
end

----------------------------------------------------------------------------
-- Readable demonstration output. The "cut" is the share of the round's
-- penetration the ERA removes; the round keeps the rest. Reference brick below
-- is the per-generation recommended size unless noted.
----------------------------------------------------------------------------
local angles = { 0, 15, 30, 45, 60, 75 }

local function shellLine(p)
	if p[1] == "HEAT" or p[1] == "THEAT" then
		return ("%s: %dmm jet caliber, %dmm RHA penetration (chemical, no rod mass)"):format(p[1], p[3], p[2])
	end
	return ("%s: %dmm caliber (~%.0fmm core), %dmm pen, %d m/s, %.1f kg dart")
		:format(p[1], p[3], p[3] * (ERA.RodData[p[1]] and ERA.RodData[p[1]].DiaFrac or 1), p[2], p[4], p[5])
end

-- Brick geometry (mm) for each generation's recommended size, forward = "Up"
-- (so plate length = sqrt(L*W), travel = H).
local function brick(gen)
	local s = gen.RecommendedSize
	if not s then return nil, nil end
	return math.sqrt(s.L * s.W) * 25.4, s.H * 25.4
end

local function AngleTable(p)
	print("\n" .. shellLine(p))
	print("  cut % vs angle of attack (0 = face-on/perpendicular, 75 = grazing), recommended brick:")
	io.write(("  %-20s"):format("generation"))
	for _, a in ipairs(angles) do io.write((" %5d"):format(a)) end
	print("")
	for _, gen in ipairs({ G1, G2, G3 }) do
		local pl, tv = brick(gen)
		io.write(("  %-20s"):format(gen.sname))
		for _, a in ipairs(angles) do io.write((" %4.0f%%"):format((cut(gen, p, a, 1, nil, nil, pl, tv)) * 100)) end
		print(("   (%.0fx%.0fmm plate, %.0fmm deep)"):format(pl or 0, pl or 0, tv or 0))
	end
end

print("\n=================== ERA reaction demonstration ===================")
AngleTable(APFSDS)
AngleTable(AP)
AngleTable(HEAT)

-- Brick size matters for Gen 2/3 but not Gen 1 (sloped 120mm APFSDS).
print("\nBrick size effect (120mm APFSDS, 30-degree sloped hit, cut %):")
print(("  %-20s %12s %12s %12s"):format("generation", "small 5x5x2", "recommended", "large 16x10x6"))
for _, gen in ipairs({ G1, G2, G3 }) do
	local pl, tv = brick(gen)
	local small = cut(gen, APFSDS, 60, 1, nil, nil, math.sqrt(5 * 5) * 25.4, 2 * 25.4)
	local rec   = cut(gen, APFSDS, 60, 1, nil, nil, pl, tv)
	local large = cut(gen, APFSDS, 60, 1, nil, nil, math.sqrt(16 * 10) * 25.4, 6 * 25.4)
	print(("  %-20s %11.0f%% %11.0f%% %11.0f%%"):format(gen.sname, small * 100, rec * 100, large * 100))
end

----------------------------------------------------------------------------
-- Before / after: the OLD ERA was one material with a flat effectiveness
-- multiplier (3x LOS vs KE, 10x vs HEAT) and a near-total stop once triggered,
-- with NO generations and NO dependence on shell speed/mass/diameter. It also
-- scaled with whatever thickness you set, so thick "ERA" was huge base armor.
----------------------------------------------------------------------------
local function OldERACut(family, penMM, brickMM, aoaDeg)
	-- Reconstructs the original era.lua triggered branch (single ERA material).
	local eff    = family == "HEAT" and 10 or 3
	local sensor = family == "HEAT" and 16 or 4
	local los    = brickMM / math.max(math.cos(math.rad(aoaDeg)), 0.05) -- LOS armor at angle
	local blast  = eff * los
	if penMM > blast / sensor then
		return math.min(blast / penMM, 0.98) -- old "Loss" = share of pen removed
	end
	return 0
end

print("\nBefore / after (cut %, 30-degree sloped hit). OLD = single flat-multiplier")
print("ERA at the given set thickness; NEW = generation + shell physics + fixed casing.")
print(("  %-26s %8s %8s"):format("case", "OLD", "NEW"))
local function ba(label, family, p, gen, oldThick)
	local pl, tv = brick(gen)
	local newCut = cut(gen, p, 60, 1, nil, nil, pl, tv)
	print(("  %-26s %7.0f%% %7.0f%%"):format(label, OldERACut(family, p[2], oldThick, 60) * 100, newCut * 100))
end
ba("APFSDS vs Gen1 casing 3mm", "KE",   APFSDS, G1, G1.CasingMM)
ba("APFSDS vs Gen2 casing 5mm", "KE",   APFSDS, G2, G2.CasingMM)
ba("APFSDS vs Gen3 casing 6mm", "KE",   APFSDS, G3, G3.CasingMM)
ba("HEAT vs Gen1 casing 3mm",   "HEAT", HEAT,   G1, G1.CasingMM)
ba("HEAT vs Gen3 casing 6mm",   "HEAT", HEAT,   G3, G3.CasingMM)
print("  (OLD also let you set e.g. 100mm 'ERA' -> 3x = 300mm effective base armor,")
print("   stacking as cheap heavy armor; NEW fixes the casing and reacts physically.)")

----------------------------------------------------------------------------
print(("\n%d passed, %d failed"):format(Passed, Failed))
if Failed > 0 then os.exit(1) end

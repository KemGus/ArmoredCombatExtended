-- Scalable-guns integration test: loads the REAL loader, gun class files and legacy
-- alias table with a minimal GMod mock environment, then verifies the unified
-- scalable-gun migration end to end: synthetic defs, alias resolution,
-- scaling laws, envelope clamping, ammo-family crossfeed.
-- usage: luajit ace_scalable_guns_integration.lua <ace-repo>
local repo = assert(arg[1], "usage: luajit ace_scalable_guns_integration.lua <ace-repo>")

SERVER = true
ACE = { Year = 3000, Translation = { GunClasses = setmetatable({}, { __index = function() return "" end }) } }

isstring = function(v) return type(v) == "string" end
istable = function(v) return type(v) == "table" end
isentity = function(v) return type(v) == "table" and v.__isent == true end
isfunction = function(v) return type(v) == "function" end
function AddCSLuaFile() end
math.Clamp = math.Clamp or function(v, mn, mx) return math.max(mn, math.min(mx, v)) end
math.Round = math.Round or function(v, d)
	local m = 10 ^ (d or 0)
	return math.floor(v * m + 0.5) / m
end

-- table.Inherit: copy missing keys from base (GMod semantics, shallow-ish)
function table.Inherit(t, base)
	for k, v in pairs(base) do
		if t[k] == nil then
			if type(v) == "table" then
				local c = {}
				for kk, vv in pairs(v) do c[kk] = vv end
				t[k] = c
			else
				t[k] = v
			end
		end
	end
	return t
end
function table.HasValue(t, v)
	for _, x in pairs(t) do if x == v then return true end end
	return false
end

local VectorMeta = {}
VectorMeta.__index = function(t, k)
	if k == 1 then return t.x elseif k == 2 then return t.y elseif k == 3 then return t.z end
	return VectorMeta[k]
end
VectorMeta.__mul = function(a, b)
	if type(a) == "number" then return Vector(a * b.x, a * b.y, a * b.z) end
	if type(b) == "number" then return Vector(a.x * b, a.y * b, a.z * b) end
	return Vector(a.x * b.x, a.y * b.y, a.z * b.z)
end
function Vector(x, y, z) return setmetatable({ x = x or 0, y = y or 0, z = z or 0 }, VectorMeta) end

-- predeclare table-valued namespaces so the function-stub metatable never captures them
ACE.Weapons = {}
ACE.Classes = {}
ACE.AmmoCrates = {}
ACE.MuzzleFlashes = {}
ACE.GSounds = {}
ACE.ModelData = {}
ACE.MineData = {}
ACE.Fuse = {}

dofile(repo .. "/lua/ace/shared/sh_ace_gunpack.lua")

-- auto-stub only after the kernel: its `ACE.X = ACE.X or {}` idiom must see nil
setmetatable(ACE, { __index = function(t, k)
	local f = function() end
	rawset(t, k, f)
	return f
end })

-- the loader scans ace/shared/<folder>/*.lua itself; mock file.Find/include
-- to serve the real repo files so the test exercises the true load path
local gunfilelist = {
	"atrifle.lua", "autocannon.lua", "autoloader.lua", "breechautoloader.lua", "cannon.lua",
	"flarelauncher.lua", "grenadelauncher.lua", "heavymachinegun.lua", "howitzer.lua",
	"machinegun.lua", "mortar.lua", "rotaryautocannon.lua", "semiauto.lua",
	"smokelauncher.lua", "smoothcannon.lua",
}
file = {
	Find = function(pattern)
		if pattern:find("ace/shared/guns/") then return gunfilelist end
		return {}
	end
}
function include(path)
	local real = repo .. "/lua/" .. path
	local chunk = assert(loadfile(real), "cannot load " .. real)
	local ok, err = pcall(chunk)
	if not ok then error("include " .. path .. " failed: " .. tostring(err)) end
end

dofile(repo .. "/lua/ace/shared/sh_ace_loader.lua")
dofile(repo .. "/lua/ace/shared/ace_legacy_gun_aliases.lua")

-- test scaffolding
local passed, failed = 0, 0
local function check(cond, msg)
	if cond then passed = passed + 1 else failed = failed + 1 print("FAIL: " .. msg) end
end
local function close(a, b, tol) return math.abs(a - b) <= (tol or 0.01) * math.max(math.abs(b), 1) end

local GS = ACE.GunScale
local Guns = ACE.Weapons.Guns
local Classes = ACE.Classes.GunClass

-- 1. synthetic defs exist: one per class, named by class id
for _, cls in ipairs({ "C", "SBC", "AL", "BAL", "HW", "SA", "AC", "MO", "ATR", "HMG", "GL", "FGL", "MG", "RAC", "SL" }) do
	check(Guns[cls] ~= nil, "synthetic def exists: " .. cls)
end
check(Classes.BAL ~= nil, "BAL class registered")
check(Classes.BAL.ammofamily == "AL", "BAL shares AL ammo family")

-- 2. the ladder is gone
check(Guns["120mmC"] == nil, "120mmC ladder def retired")
check(Guns["37mmC"] == nil, "37mmC ladder def retired")
check(Guns["20mmHRAC"] == nil, "HRAC defs retired")

-- 3. alias resolution: legacy id resolves to class + authored spec
local def, calMM, len = GS.ResolveSpec("120mmC")
check(def ~= nil and def.id == "C", "120mmC resolves to class C")
check(close(calMM, 120, 0.001), "120mmC authored caliber 120mm (got " .. tostring(calMM) .. ")")
check(close(len, 45, 0.001), "120mmC authored length L45")

-- keyed legacy id: suffix wins over alias defaults
local def2, cal2, len2 = GS.ResolveSpec("120mmC@140x55")
check(def2 and def2.id == "C", "keyed legacy id resolves to class C")
check(close(cal2, 140, 0.001), "key suffix caliber wins (got " .. tostring(cal2) .. ")")
check(close(len2, 55, 0.001), "key suffix length wins")

-- 4. pivot invariance: class C at base spec costs the authored 2100kg
local stats = GS.Stats(Guns.C, 12.0, 45)
check(close(stats.mass, 2100, 0.001), "cannon pivot mass 2100kg (got " .. stats.mass .. ")")

-- 5. the 2A46 calibration: SBC at 125mm lands near 2500kg
local sbc = GS.Stats(Guns.SBC, 12.5, 48)
check(close(sbc.mass, 2500, 0.02), "125mm smoothbore ~2.5t (got " .. math.floor(sbc.mass) .. ")")

-- 6. overhead floor: tiny cannon mass doesn't collapse to pure cubic
local small = GS.Stats(Guns.C, 5.0, 45)
local purecubic = 2100 * (5 / 12) ^ 3
check(small.mass > purecubic * 1.5, "overhead floor keeps 50mm cannon off pure cubic (got " .. math.floor(small.mass) .. " vs cubic " .. math.floor(purecubic) .. ")")

-- 7. envelope clamping: cannon caliber stops at 200mm
local lim = GS.Limits("C")
check(close(lim.calmax, 20, 0.001), "cannon max caliber 20cm")
check(close(lim.calmin, 3.7, 0.001), "cannon min caliber 3.7cm")
local ncal = (GS.Normalize("C", 250, 45))
check(close(ncal, 200, 0.001), "250mm request clamps to 200mm")

-- 8. SpecString round-trip contract: empty means the id's own default spec
check(GS.SpecString("140mmC", 140, 45) == "", "alias-at-default SpecString empty (got '" .. GS.SpecString("140mmC", 140, 45) .. "')")
check(GS.SpecString("140mmC", 120, 45) == "120x45", "alias-at-pivot SpecString explicit (got '" .. GS.SpecString("140mmC", 120, 45) .. "')")
check(GS.SpecString("120mmC", 120, 45) == "", "pivot-alias at pivot stays empty (got '" .. GS.SpecString("120mmC", 120, 45) .. "')")

-- 9. caliber-only classes: length axis locked
local glm = GS.Limits("GL")
check(glm.lenmin == glm.lenmax, "grenade launcher length axis locked")

-- 10. rof cap scaling: smaller caliber cycles faster
local big = GS.Stats(Guns.C, 12.0, 45)
local sml = GS.Stats(Guns.C, 6.0, 45)
check(big.maxrof and sml.maxrof and sml.maxrof > big.maxrof, "maxrof scales inverse with caliber")
check(close(big.maxrof, 19, 0.001), "base maxrof 19 at pivot")

-- 11. drum autoloader mag mechanics
check(Guns.AL.magsize == 12, "AL drum magsize 12")
local alstats = GS.Stats(Guns.AL, 12.0, 45)
check(alstats.magreload and close(alstats.magreload, 35, 0.001), "AL magreload 35 at pivot")

-- 12. ammo family crossfeed: BAL eats AL ammo — exercise the actual fit
-- function with mock gun/bullet tables rather than only checking metadata
check(type(GS.AmmoFits) == "function", "AmmoFits is a function")
check(Classes.BAL.ammofamily == "AL", "BAL shares the AL ammo family")
if type(GS.AmmoFits) == "function" then
	-- Mocks mirror the entity shape: guns carry ScalableSpec/Class/Caliber
	-- (cm), rounds carry the crate's BulletData Id/Caliber.
	local mockGun = { ScalableSpec = true, Class = "BAL", Id = "120mmBAL", Caliber = 12 }
	local alRound = { Id = "120mmAL", Caliber = 12 }
	check(GS.AmmoFits(mockGun, alRound) == true, "BAL accepts AL-family round")
	local cRound = { Id = "120mmC", Caliber = 12 }
	check(GS.AmmoFits(mockGun, cRound) ~= true, "BAL rejects cannon round")
end

-- 13. every legacy alias resolves
local unresolved = {}
for id in pairs(ACE.LegacyGunAliases) do
	local d = GS.ResolveSpec(id)
	if not d then unresolved[#unresolved + 1] = id end
end
check(#unresolved == 0, "all 84 legacy aliases resolve (" .. #unresolved .. " unresolved" .. (#unresolved > 0 and ": " .. table.concat(unresolved, ",") or "") .. ")")

-- 14. effective-caliber naming data: synthetic def names carry no caliber digits
check(not tostring(Guns.C.name):match("%d"), "class C name has no caliber digits")

-- 15. ResolveDef alias transparency: legacy ids behave as their class def everywhere
check(GS.ResolveDef("120mmC") == Guns.C, "ResolveDef maps 120mmC to synthetic class def")
check(GS.ResolveDef("120mmC@140x55") == Guns.C, "ResolveDef maps keyed legacy id to class def")
check(GS.Limits("120mmC") ~= nil, "Limits works on legacy id")
local lmcal = (GS.Normalize("120mmC", nil, nil))
check(lmcal ~= nil, "Normalize works on legacy id")

-- 16. migration suffix fallback: non-ACE ids resolve into envelopes
local mdef, mcal = GS.ResolveSpec("40mmC")
check(mdef and mdef.id == "C", "40mmC migration resolves to cannon")
check(close(mcal, 40, 0.001), "40mmC migration caliber preserved")
local rdef, rcal = GS.ResolveSpec("127mmRAC")
check(rdef and rdef.id == "RAC", "127mmRAC migration resolves to rotary")
check(close(rcal, 127, 0.001), "127mmRAC authored caliber surfaces pre-clamp")
local ncal127 = (GS.Normalize("127mmRAC", rcal, nil))
check(close(ncal127, 30, 0.001), "127mmRAC clamps to RAC envelope max 30mm")
local sdef, slen = select(1, GS.ResolveSpec("90mmSC"))
if sdef then slen = select(3, GS.ResolveSpec("90mmSC")) end
check(sdef and sdef.id == "C", "90mmSC migration folds to cannon")
check(close(slen, 20, 0.001), "90mmSC migration gets shortcannon length L20")
local sbdef = GS.ResolveSpec("120mmSB")
check(sbdef and sbdef.id == "SBC", "ACF-3 smoothbore SB suffix maps to ACE SBC")
-- exact ACE legacy aliases still win over the migration fallback
local llen = select(3, GS.ResolveSpec("120mmC"))
check(llen == 45, "ACE legacy 120mmC keeps authored L45 (not migration default)")
-- garbage ids still fail closed
check(GS.ResolveSpec("not_a_gun") == nil, "garbage id does not resolve")
check(GS.ResolveSpec("120mmXX") == nil, "unknown suffix does not resolve")

print(string.format("ace_scalable_guns_integration: %d passed, %d failed", passed, failed))

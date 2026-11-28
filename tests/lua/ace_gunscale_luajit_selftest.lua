-- Offline coverage for the ACE.GunScale stat kernel: key parsing, limits,
-- stat monotonicity, ammo-fit rules and barrel resolution.
local repo = assert(arg[1], "usage: luajit ace_gunscale_luajit_selftest.lua <ace-repo>")

SERVER = true
ACE = {}

isstring = function(v) return type(v) == "string" end
istable = function(v) return type(v) == "table" end
isentity = function(v) return type(v) == "table" and v.__isent == true end
function AddCSLuaFile() end
math.Clamp = math.Clamp or function(v, mn, mx) return math.max(mn, math.min(mx, v)) end
math.Round = math.Round or function(v, d)
	local m = 10 ^ (d or 0)
	return math.floor(v * m + 0.5) / m
end

local VectorMeta = {}
VectorMeta.__index = function(t, k)
	if k == 1 then return t.x elseif k == 2 then return t.y elseif k == 3 then return t.z end
	return VectorMeta[k]
end
VectorMeta.__newindex = function(t, k, v)
	if k == 1 then t.x = v elseif k == 2 then t.y = v elseif k == 3 then t.z = v else rawset(t, k, v) end
end
VectorMeta.__add = function(a, b) return Vector(a.x + b.x, a.y + b.y, a.z + b.z) end
VectorMeta.__sub = function(a, b) return Vector(a.x - b.x, a.y - b.y, a.z - b.z) end
VectorMeta.__mul = function(a, b)
	if type(a) == "number" then return Vector(a * b.x, a * b.y, a * b.z) end
	if type(b) == "number" then return Vector(a.x * b, a.y * b, a.z * b) end
	return Vector(a.x * b.x, a.y * b.y, a.z * b.z)
end
VectorMeta.Dot = function(a, b) return a.x * b.x + a.y * b.y + a.z * b.z end
function Vector(x, y, z) return setmetatable({ x = x or 0, y = y or 0, z = z or 0 }, VectorMeta) end

-- Minimal registries mirroring the loader output.
ACE.Classes = {
	GunClass = {
		C  = { id = "C",  type = "Gun", scalable = { cal = {0.85, 1.25}, len = {0.8, 1.4} }, borelength = 45 },
		MO = { id = "MO", type = "Gun", scalable = { cal = {0.85, 1.25} } },
		SA = { id = "SA", type = "Gun", scalable = { cal = {0.85, 1.25}, len = {0.8, 1.4} }, borelength = 45 },
		HMG = { id = "HMG", type = "Gun", longbarrel = { index = 2, submodel = 4, newpos = "muzzle2" } },
		AL = { id = "AL", type = "Gun", scalable = { cal = {0.85, 1.25}, len = {0.8, 1.4} }, borelength = 45 },
	}
}
ACE.Weapons = {
	Guns = {
		["120mmC"] = {
			id = "120mmC", gunclass = "C", caliber = 12.0, weight = 2100, name = "120mm Cannon",
			model = "models/tankgun/tankgun_120mm.mdl",
			round = { maxlength = 110, propweight = 18 },
		},
		["100mmC"] = {
			id = "100mmC", gunclass = "C", caliber = 10.0, weight = 1200,
			model = "models/tankgun/tankgun_100mm.mdl",
			round = { maxlength = 93, propweight = 11 },
		},
		["30mmHMG"] = {
			id = "30mmHMG", gunclass = "HMG", caliber = 3.0, weight = 180,
			model = "models/machinegun/machinegun_30mm_compact.mdl",
			round = { maxlength = 24, propweight = 0.34 },
		},
		-- Scalable def on a model with no barrel joint: legacy axial stretch.
		["120mmCNB"] = {
			id = "120mmCNB", gunclass = "C", caliber = 12.0, weight = 2100,
			model = "models/props_junk/propane_tank001a.mdl",
			round = { maxlength = 110, propweight = 18 },
		},
		-- Caliber-only scalable class (mortars/autocannons): no len range.
		["120mmM"] = {
			id = "120mmM", gunclass = "MO", caliber = 12.0, weight = 600,
			model = "models/mortar/mortar_120mm.mdl",
			round = { maxlength = 110, propweight = 6 },
		},
		-- Barrel-scalable def on a -y rig (semiautocannon).
		["45mmSA"] = {
			id = "45mmSA", gunclass = "SA", caliber = 4.5, weight = 300,
			model = "models/autocannon/semiautocannon_45mm.mdl",
			round = { maxlength = 60, propweight = 1.5 },
		},
		-- Two weapon lines sharing one class: the menu split keys off def.family.
		["120mmAL"] = {
			id = "120mmAL", gunclass = "AL", caliber = 12.0, weight = 2700, name = "120mm Drum Autoloader",
			family = "drum", model = "models/tankgun/tankgun_al_120mm.mdl",
			round = { maxlength = 100, propweight = 15 },
		},
		["120mmBAL"] = {
			id = "120mmBAL", gunclass = "AL", caliber = 12.0, weight = 4700, name = "120mm Breech Autoloader",
			family = "BAL", model = "models/tankgun_new/tankgun_120mm.mdl",
			round = { maxlength = 100, propweight = 15 },
		},
	}
}

dofile(repo .. "/lua/ace/shared/sh_ace_gunpack.lua")

local GS = ACE.GunScale
local pass, fail = 0, 0
local function check(cond, msg)
	if cond then
		pass = pass + 1
	else
		fail = fail + 1
		print("FAIL: " .. msg)
	end
end
local function near(a, b, eps, msg)
	check(math.abs(a - b) <= (eps or 1e-6), string.format("%s (got %s, want %s)", msg, a, b))
end

-- ParseKey ---------------------------------------------------------------
local base, cal, len = GS.ParseKey("120mmC@140x55")
check(base == "120mmC" and cal == 140 and len == 55, "ParseKey full key")
base, cal, len = GS.ParseKey("120mmC@140")
check(base == "120mmC" and cal == 140 and len == nil, "ParseKey cal-only key")
base, cal, len = GS.ParseKey("120mmC")
check(base == "120mmC" and cal == nil and len == nil, "ParseKey plain id")
base = GS.ParseKey("120mmC@junk")
check(base == "120mmC@junk", "ParseKey invalid suffix keeps whole id")
base = GS.ParseKey(nil)
check(base == nil, "ParseKey nil-safe")

-- Key/ParseSpec round trip --------------------------------------------------
check(GS.Key("120mmC", 140, 55) == "120mmC@140x55", "Key build")
check(GS.Key("120mmC", 140) == "120mmC@140", "Key cal-only")
check(GS.Key("120mmC") == "120mmC", "Key no params")
local oc, ol = GS.ParseSpec("140x55")
check(oc == 140 and ol == 55, "ParseSpec")
oc, ol = GS.ParseSpec("")
check(oc == nil and ol == nil, "ParseSpec empty")
oc, ol = GS.ParseSpec("120mmC@130x50")
check(oc == 130 and ol == 50, "ParseSpec tolerates full key")

-- ResolveDef / Limits -------------------------------------------------------
check(GS.ResolveDef("120mmC@140x55") == ACE.Weapons.Guns["120mmC"], "ResolveDef keyed")
check(GS.ResolveDef("30mmHMG@99") == ACE.Weapons.Guns["30mmHMG"], "ResolveDef keyed MG")
check(GS.ResolveDef("bogus@12") == nil, "ResolveDef unknown base")

local lim = GS.Limits("120mmC")
check(lim ~= nil, "Limits for scalable class C")
near(lim.basecal, 12, 1e-9, "Limits basecal")
near(lim.baselen, 45, 1e-9, "Limits baselen from class")
near(lim.calmin, 12 * 0.85, 1e-9, "Limits calmin")
near(lim.calmax, 12 * 1.25, 1e-9, "Limits calmax")
near(lim.lenmin, 45 * 0.8, 1e-9, "Limits lenmin")
near(lim.lenmax, 45 * 1.4, 1e-9, "Limits lenmax")
check(GS.Limits("30mmHMG") == nil, "Non-scalable class has no limits")
check(GS.Limits("120mmC@140x55") ~= nil, "Limits via keyed id")

-- Caliber-only class: length axis locks to baselen (lenmin == lenmax).
local mlim = GS.Limits("120mmM")
check(mlim ~= nil, "Limits for cal-only class MO")
near(mlim.lenmin, mlim.baselen, 1e-9, "Cal-only lenmin locks to baselen")
near(mlim.lenmax, mlim.baselen, 1e-9, "Cal-only lenmax locks to baselen")
local mc, ml = GS.Normalize("120mmM", 140, 60)
near(mc, 140, 1e-9, "Cal-only Normalize caliber")
near(ml, mlim.baselen, 1e-9, "Cal-only Normalize len clamps to baselen")
check(GS.SpecString("120mmM", 140, mlim.baselen) == "140", "Cal-only SpecString drops len")
local pc, pl = GS.ParseSpec("140")
check(pc == 140 and pl == nil, "ParseSpec cal-only suffix")
local mst = GS.Stats(ACE.Weapons.Guns["120mmM"], 14, mlim.baselen)
near(mst.calscale, 14 / 12, 1e-9, "Cal-only stats calscale")
near(mst.lenscale, 1, 1e-9, "Cal-only stats lenscale is 1")
local sa = GS.BarrelJoints["models/autocannon/semiautocannon_45mm.mdl"]
check(sa ~= nil, "semiautocannon split entry registered")
check(sa and sa.bore.y == -1, "semiautocannon bore runs -y")

-- Family grouping (unified menu) ------------------------------------------
local fam = GS.Family("C")
check(fam ~= nil, "Family for class C")
check(fam and #fam.defs == 3, "Family C covers all C defs")
check(fam.defs[1].id == "100mmC", "Family defs caliber-sorted")
near(fam.calmin, 10 * 0.85, 1e-9, "Family calmin is union min")
near(fam.calmax, 12 * 1.25, 1e-9, "Family calmax is union max")
check(GS.Family("HMG") == nil, "Non-scalable class has no family")
check(GS.ResolveFamilyDef(fam, 105).id == "100mmC", "FamilyDef resolves low")
check(GS.ResolveFamilyDef(fam, 115).id == "120mmC", "FamilyDef resolves high")
check(GS.Family("MO") ~= nil, "Cal-only class still gets a family")
check(GS.IsScalableId("120mmC") and not GS.IsScalableId("30mmHMG"), "IsScalableId")

-- Families split + display names ------------------------------------------
local fams = GS.Families("C")
check(fams ~= nil and #fams == 1, "Families C single entry")
check(fams and fams[1].key == "", "Families C unkeyed")
fams = GS.Families("AL")
check(fams ~= nil and #fams == 2, "Families AL splits into two lines")
check(fams and fams[1].key == "BAL" and fams[2].key == "drum", "Families AL keys sorted")
check(fams and fams[1].name == "Breech Autoloader", "Families AL breech display name")
check(fams and fams[2].name == "Drum Autoloader", "Families AL drum display name")
check(fams and #fams[1].defs == 1 and fams[1].defs[1].id == "120mmBAL", "Families AL breech holds only breech defs")
check(GS.Families("HMG") == nil, "Non-scalable class has no families")

local def120 = ACE.Weapons.Guns["120mmC"]
check(GS.DisplayName(def120, 120, 45) == "120mm Cannon", "DisplayName base spec verbatim")
check(GS.DisplayName(def120, 140, 45) == "140mm Cannon", "DisplayName caliber replaces")
check(GS.DisplayName(def120, 120, 55) == "120mm Cannon L55", "DisplayName length suffix")
check(GS.DisplayName(def120, 140, 55) == "140mm Cannon L55", "DisplayName both axes")
check(GS.DisplayName(def120) == "120mm Cannon", "DisplayName defaults to base")
check(GS.DisplayName(def120, nil, 55) == "120mm Cannon L55", "DisplayName nil cal stays base")
local defM = ACE.Weapons.Guns["120mmM"]
defM.name = "120mm Mortar"
check(GS.DisplayName(defM, 140, 45) == "140mm Mortar", "DisplayName cal-only never suffixed")
check(GS.DisplayName(ACE.Weapons.Guns["120mmAL"], 130, 45) == "130mm Drum Autoloader", "DisplayName mid-name caliber")

-- Normalize -----------------------------------------------------------------
local nc, nl = GS.Normalize("120mmC", 140, 55)
check(nc == 140 and nl == 55, "Normalize in-range")
nc, nl = GS.Normalize("120mmC", 500, 99)
near(nc, 150, 1e-9, "Normalize clamps cal to calmax")
near(nl, 63, 0.01, "Normalize clamps len to lenmax")
nc, nl = GS.Normalize("120mmC", 1, 1)
near(nc, 102, 1e-9, "Normalize clamps cal to calmin")
near(nl, 36, 0.01, "Normalize clamps len to lenmin")
nc, nl = GS.Normalize("120mmC")
near(nc, 120, 1e-9, "Normalize defaults cal")
check(nl == 45, "Normalize defaults len")
nc, nl = GS.Normalize("30mmHMG", 40, 10)
check(nc == nil and nl == nil, "Normalize non-scalable returns nil")

-- Stats ---------------------------------------------------------------------
local s = GS.Stats(ACE.Weapons.Guns["120mmC"], 12, 45)
near(s.mass, 2100, 1e-6, "Stats base mass")
near(s.mvmod, 1, 1e-9, "Stats base mvmod")
near(s.chamberLen, 110, 1e-9, "Stats base chamber")
near(s.propLimit, 18, 1e-9, "Stats base prop limit")
check(s.scale.x == 1 and s.scale.y == 1 and s.scale.z == 1, "Stats base scale identity")

-- Monotonicity: bigger caliber -> more mass, bigger chamber/prop/scale.
local s2 = GS.Stats(ACE.Weapons.Guns["120mmC"], 14, 45)
check(s2.mass > s.mass, "Stats mass monotonic in caliber")
check(s2.chamberLen > s.chamberLen, "Stats chamber monotonic in caliber")
check(s2.propLimit > s.propLimit, "Stats prop limit monotonic in caliber")
near(s2.propLimit / s.propLimit, (14 / 12) ^ 3, 1e-6, "Stats prop limit scales cal^3")
check(s2.scale.x > 1 and s2.scale.y > 1, "Stats scale grows")

-- Monotonicity: longer bore -> more mass + more mvmod (diminishing returns).
local s3 = GS.Stats(ACE.Weapons.Guns["120mmC"], 12, 63)
check(s3.mass > s.mass, "Stats mass monotonic in length")
check(s3.mvmod > 1, "Stats mvmod grows with length")
check(s3.mvmod <= GS.MVMax, "Stats mvmod clamped high")
local s4 = GS.Stats(ACE.Weapons.Guns["120mmC"], 12, 36)
check(s4.mvmod < 1 and s4.mvmod >= GS.MVMin, "Stats mvmod shrinks but clamped")
check(s3.scale.x == 1 and s3.split ~= nil, "Barreled model carries uniform scale + split")
check(s3.lenscale > 1, "Stats lenscale reports the tube ratio")

-- Models without a barrel joint keep the legacy uniform axial stretch.
local s3f = GS.Stats(ACE.Weapons.Guns["120mmCNB"], 12, 63)
check(s3f.split == nil, "Jointless model has no split")
check(s3f.scale.x > s2.scale.x, "Length adds axial scale (jointless)")
check(s3f.scale.y == 1, "Length does not grow Y scale (jointless)")

-- Non-scalable def: identity stats.
local sn = GS.Stats(ACE.Weapons.Guns["30mmHMG"], nil, nil)
near(sn.mass, 180, 1e-6, "Non-scalable stats mass")
near(sn.mvmod, 1, 1e-9, "Non-scalable stats mvmod")

-- SpecString -----------------------------------------------------------------
check(GS.SpecString("120mmC", 120, 45) == "", "SpecString empty at base")
check(GS.SpecString("120mmC", 140, 55) == "140x55", "SpecString scaled")
check(GS.SpecString("30mmHMG", 30, 20) == "", "SpecString non-scalable")

-- AmmoFits ------------------------------------------------------------------
local gun = { Id = "30mmHMG", Class = "HMG", Caliber = 3.0 }
check(GS.AmmoFits(gun, { Id = "30mmHMG" }) == true, "Legacy exact-id accept")
local ok, reason = GS.AmmoFits(gun, { Id = "20mmHMG" })
check(ok == false and reason == "Wrong ammo type!", "Legacy exact-id reject")
ok = GS.AmmoFits(gun, { Id = "30mmHMG@3.5" })
check(ok == false, "Legacy gun rejects keyed ammo")

gun = {
	Id = "120mmC", Class = "C", Caliber = 12.0,
	ScalableSpec = lim, ChamberLen = 110, PropLimit = 18,
}
check(GS.AmmoFits(gun, { Id = "120mmC", Caliber = 12, ProjLength = 60, PropLength = 50, PropMass = 17 }) == true,
	"Scalable accepts base round")
check(GS.AmmoFits(gun, { Id = "120mmC@120", Caliber = 12, ProjLength = 60, PropLength = 50, PropMass = 17 }) == true,
	"Scalable accepts keyed same-caliber round")
ok = GS.AmmoFits(gun, { Id = "120mmC@140", Caliber = 14, ProjLength = 60, PropLength = 50, PropMass = 17 })
check(ok == false, "Scalable rejects wrong caliber")
ok = GS.AmmoFits(gun, { Id = "100mmC@120", Caliber = 12, ProjLength = 60, PropLength = 50, PropMass = 17 })
check(ok == true, "Scalable accepts cross-def same-caliber round")
ok = GS.AmmoFits(gun, { Id = "120mmC", Caliber = 12, ProjLength = 80, PropLength = 40, PropMass = 15 })
check(ok == false, "Scalable rejects over-length round")
ok = GS.AmmoFits(gun, { Id = "120mmC", Caliber = 12, ProjLength = 60, PropLength = 50, PropMass = 25 })
check(ok == false, "Scalable rejects over-charge round")
ok = GS.AmmoFits(gun, { Id = "9M133 ASM", Caliber = 12 })
check(ok == false, "Scalable rejects unknown/mismatched class round")

-- ResolveBarrel --------------------------------------------------------------
local fakeGun = {
	__isent = true, Class = "HMG", Id = "30mmHMG",
	GetBodygroup = function(_, idx) return idx == 2 and 4 or 0 end,
}
check(GS.ResolveBarrel(fakeGun) == "muzzle2", "ResolveBarrel longbarrel active")
fakeGun.GetBodygroup = function() return 0 end
check(GS.ResolveBarrel(fakeGun) == "muzzle", "ResolveBarrel longbarrel inactive")

ACE.Weapons.Guns["barrelTest"] = {
	id = "barrelTest", gunclass = "C", caliber = 10, weight = 1000,
	barrels = {
		{ index = 1, submodel = 0, muzzle = "muzzle" },
		{ index = 1, submodel = 2, muzzle = "muzzle_far", length = 60 },
	},
	round = { maxlength = 90, propweight = 10 },
}
fakeGun = {
	__isent = true, Class = "C", Id = "barrelTest",
	GetBodygroup = function(_, idx) return idx == 1 and 2 or 0 end,
}
local attach, entry = GS.ResolveBarrel(fakeGun)
check(attach == "muzzle_far" and entry.length == 60, "ResolveBarrel def barrels")
fakeGun.GetBodygroup = function() return 0 end
check(GS.ResolveBarrel(fakeGun) == "muzzle", "ResolveBarrel def barrels fallback")

-- Piecewise map ---------------------------------------------------------------
-- The joint/tubelen constants below are not tunable flavor — they were
-- measured offline from each model's physics mesh (breech/tube boundary and
-- barrel length in model space) and live in ACE.GunScale.BarrelJoints.
-- tankgun_120mm: joint (18.6,0,-0.212), bore +x, tubelen 188.4.
local sp = GS.BarrelInfo("models/tankgun/tankgun_120mm.mdl")
check(sp ~= nil, "BarrelInfo registered")
near(sp.joint.x, 18.6, 0.01, "BarrelInfo joint x")
check(GS.BarrelInfo("models/props_junk/x.mdl") == nil, "BarrelInfo unknown model")

local uni = Vector(1.2, 1.2, 1.2)
-- Breech side of the joint: uniform scale only.
local mp = GS.MapPoint(Vector(10, 2, 0), uni, sp, 1.25)
near(mp.x, 12, 1e-9, "MapPoint breech side unchanged")
-- Joint point is continuous.
mp = GS.MapPoint(Vector(18.6, 0, -0.212), uni, sp, 1.25)
near(mp.x, 18.6 * 1.2, 1e-6, "MapPoint joint continuous")
-- Tube side stretches about the joint.
mp = GS.MapPoint(Vector(100, 3, -1), uni, sp, 1.25)
near(mp.x, (100 + (100 - 18.6) * 0.25) * 1.2, 1e-6, "MapPoint tube stretched")
near(mp.y, 3.6, 1e-9, "MapPoint y uniform")
near(mp.z, -1.2, 1e-9, "MapPoint z uniform")
-- Past the tube end the stretch caps at tubelen: muzzle attachments and
-- muzzledev verts slide rigidly instead of over-stretching.
mp = GS.MapPoint(Vector(300, 0, -0.212), Vector(1, 1, 1), sp, 1.25)
near(mp.x, 300 + 0.25 * 188.4, 1e-6, "MapPoint slide caps at tubelen")
-- lenScale 1 is identity.
mp = GS.MapPoint(Vector(207.9, 0, -0.212), Vector(1, 1, 1), sp, 1.0)
near(mp.x, 207.9, 1e-9, "MapPoint identity at lenScale 1")
-- No split entry: plain per-axis scale.
mp = GS.MapPoint(Vector(10, 2, 3), uni, nil, 1.5)
near(mp.x, 12, 1e-9, "MapPoint nil split uniform x")
near(mp.y, 2.4, 1e-9, "MapPoint nil split uniform y")
near(mp.z, 3.6, 1e-9, "MapPoint nil split uniform z")
-- tankgun_new: joint x=18, tube len 192, bore +x (re-measured from the
-- physics mesh — the original registry entry claimed -y, which sheared
-- scaled hulls sideways instead of stretching them forward).
local spn = GS.BarrelInfo("models/tankgun_new/tankgun_120mm.mdl")
check(spn and spn.bore.x == 1, "tankgun_new bore runs +x")
mp = GS.MapPoint(Vector(150, -24, 0), Vector(1, 1, 1), spn, 1.25)
near(mp.x, 150 + (150 - 18) * 0.25, 0.01, "tankgun_new maps along +x bore")
near(mp.y, -24, 1e-9, "tankgun_new y untouched")
mp = GS.MapPoint(Vector(300, 0, 0), Vector(1, 1, 1), spn, 1.25)
near(mp.x, 300 + 0.25 * 192, 0.01, "tankgun_new slide caps at tubelen")

-- ClampCalMM -----------------------------------------------------------------
near(GS.ClampCalMM("120mmC", 999), 150, 1e-9, "ClampCalMM clamps to max")
near(GS.ClampCalMM("120mmC", 140), 140, 1e-9, "ClampCalMM in-range")
near(GS.ClampCalMM("30mmHMG", 99), 30, 1e-9, "ClampCalMM non-scalable -> base")

print(string.format("ace_gunscale_luajit_selftest: %d passed, %d failed", pass, fail))
if fail > 0 then os.exit(1) end

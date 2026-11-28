--[[
	ACE scalable-gun stat kernel.

	A scalable gun is one entity (acf_gun) whose effective caliber and bore
	length are parameters applied on top of a fixed registry definition:

		- Caliber scales the render matrix, physics hull, mass, chamber and
		  propellant limits uniformly (X x Y x Z).
		- Bore length is expressed in calibers ("L55") and adds an extra axial
		  (X) stretch on the tube plus a diminishing-returns muzzle velocity
		  modifier.

	Parameterized identities travel as key strings so one field carries both
	parameters through the menu cvars, dupe data and crate RoundId:

		"120mmC"          -> plain legacy id
		"120mmC@140"      -> 140mm effective caliber, base bore length
		"120mmC@140x55"   -> 140mm effective caliber, L55 bore

	GunSpec (spawn tool cvar + dupe field) carries only the suffix part:
	"140x55". Ammo crates carry the key in RoundId/BulletData.Id, so every
	existing consumer that resolves a def table just needs ParseKey/ResolveDef.

	Definitions opt in via their class (or per-def override):

		ACE.DefineGunClass("C", {
			...
			borelength = 45,                      -- nominal L/d of the base model
			scalable   = { cal = {0.85, 1.25},    -- caliber multipliers of def.caliber
			             len = {0.8, 1.4} },      -- length multipliers of borelength
		})

	Per-def overrides: borelength (calibers), calrange {minMM,maxMM},
	lenrange {min,max calibers}, tubefrac (mass fraction of the tube, 0-1),
	scalable = false (opt out) or scalable = {cal=..., len=...} (override).

	Defs can instead declare discrete bodygroup barrels:

		barrels = {
			{ index = 2, submodel = 0, muzzle = "muzzle",  length = 44 },
			{ index = 2, submodel = 4, muzzle = "muzzle2", length = 55 },
		}

	The legacy class-level `longbarrel` table keeps working and is treated as a
	two-entry barrels list.

	========================================================================
	HOW THE PIECES FIT TOGETHER (and how to reproduce/extend this system)

	Four files carry one scalable gun from menu trigger to rendered entity:

		1. lua/ace/shared/guns/<class>.lua — the ENVELOPE. One file per gun
		   class; declares base caliber/length, min/max slider ranges, pivot
		   mass, tubefrac/massoverhead, sound/muzzleflash. This is the only
		   file you touch for balance retunes.
		2. lua/ace/shared/sh_ace_gunpack.lua (this file) — the KERNEL. Pure
		   math: envelope clamping (Normalize), the mass law, the muzzle-
		   velocity law, scale vectors, key parsing. No per-gun data here.
		3. GunScale.BarrelJoints below — per-MODEL geometry: where the breech
		   ends and the tube begins, so length stretch elongates the barrel
		   instead of the whole gun. Required only for length-scaled models.
		4. lua/ace/shared/ace_legacy_gun_aliases.lua — generated compat data
		   mapping retired per-caliber ids onto classes; never hand-edit.

	Common tasks, step by step:

	ADD A NEW GUN CLASS (say a railgun):
		a. Create lua/ace/shared/guns/railgun.lua following cannon.lua: pick
		   the model, measure its real proportions, set caliber/length
		   envelope, pivot mass, tubefrac. The class registers itself.
		b. If the model should length-scale, measure its joint/tubelen (see
		   the BarrelJoints header below) and add a registry entry.
		c. Add legacy aliases ONLY if old dupes reference ids for it.
		d. Extend tests/lua/ace_scalable_guns_integration.lua expectations.

	ADD A NEW MODEL VARIANT to an existing class: measure joint/tubelen for
	the model (below), add one BarrelJoints line, done — the envelope math
	is model-independent.

	RETUNE BALANCE (mass too heavy, MV too strong): edit the class file's
	envelope numbers, or the kernel-wide defaults in the tunables block if
	the change is truly universal. Never special-case inside the kernel.

	KEY FORMAT decoded once more, since everything keys off it:
	"120mmC@140x55" = base def 120mmC, dialed to 140mm caliber, L/55 bore.
	The part after '@' is the "spec"; it rides dupes, crates and menu cvars.
]]--

AddCSLuaFile()

ACE = ACE or {}
ACE.GunScale = ACE.GunScale or {}

local GunScale = ACE.GunScale

-- Tunables for the scaling laws. These are kernel-wide defaults; per-class
-- values (caliber/length envelopes, pivot mass, tubefrac) live in the class
-- files under lua/ace/shared/guns/. To add a new scalable gun class, copy an
-- existing class file — you should not need to touch anything in this file.
--
-- Muzzle velocity (MV) scales with barrel length: a longer tube gives the
-- propellant gases more time to accelerate the shell, but with diminishing
-- returns. The law is
--     mvmod = clamp((len / baselen) ^ MVLengthExp, MVMin, MVMax)
-- so at the pivot length mvmod is exactly 1, L/70 vs L/45 gives +16%, and
-- very short or long barrels saturate at the clamps instead of running away.
GunScale.MVLengthExp   = GunScale.MVLengthExp   or 0.35  -- diminishing-returns exponent for MV vs barrel length
GunScale.MVMin         = GunScale.MVMin         or 0.80  -- shortest-barrel MV multiplier floor
GunScale.MVMax         = GunScale.MVMax         or 1.20  -- longest-barrel MV multiplier cap
GunScale.DefTubeFrac   = GunScale.DefTubeFrac   or 0.44  -- default barrel mass fraction; calibrated from the Rh-120 L/44 -> L/55 weight delta
GunScale.DefBoreLength = GunScale.DefBoreLength or 45    -- L/d pivot for classes that don't declare a length envelope
GunScale.DefCalRange   = GunScale.DefCalRange   or { 0.85, 1.25 } -- fallback caliber slider range as a fraction of pivot
GunScale.DefLenRange   = GunScale.DefLenRange   or { 0.8, 1.4 }   -- fallback length slider range as a fraction of pivot
GunScale.CalEpsilon    = GunScale.CalEpsilon    or 0.051 -- cm, ammo-fit tolerance
GunScale.LenEpsilon    = GunScale.LenEpsilon    or 0.51  -- cm, chamber slack
GunScale.PropSlack     = GunScale.PropSlack     or 1.02  -- prop mass tolerance
GunScale.SoundPitch    = GunScale.SoundPitch    ~= false -- deeper sound on bigger guns

-- Per-model barrel-split registry for the rebuilt rigs (tools/modelrig):
-- every model carries `tube` and `muzzledev` bones, children of the barrel
-- bone. Geometry, in model space looking down the gun:
--
--     breech        joint          tube end (muzzle device zone)
--     [==== breech body ====][====== barrel tube ======][dev]
--     |<-- rigid-ish zone -->|<-- length-stretch zone -->|
--     origin            joint pos                  joint + bore * tubelen
--
-- Length scaling stretches only the region past `joint` along `bore` —
-- the breech keeps its shape while the barrel elongates. `joint` is the
-- bind-space position of the breech/tube boundary (the
-- tube bone origin), `bore` the normalized bind-space direction toward the
-- muzzle, `tubelen` the J->T span (the muzzledev slide distance per unit of
-- lenScale), and `mdir` the slide direction in the parent (barrel) frame for
-- ManipulateBonePosition. Models without an entry fall back to stretching the
-- whole entity axially.
--
-- Where the numbers come from: every entry was measured offline from the
-- model's own files, not eyeballed in game. `joint`/`tubelen` come from the
-- physics mesh convex vertices (find the radius transition where the fat
-- breech cylinder narrows to the thin tube — that plane is the joint, and
-- tubelen is the distance from there to the muzzle-end vertices); `bore` is
-- the mesh's long axis direction in bind space; `mdir` reads straight out of
-- the model's bone hierarchy. The measurement scripts live in the gmodkit
-- harness (out/mdl_bones.py, out/mdl_bounds.py). To measure a NEW model:
-- dump its physics convexes, plot vertex radius vs position along the long
-- axis, and read off the same two distances — expect a few millimeters of
-- slack either way, the hull math is not sensitive to small joint error.
GunScale.BarrelJoints = {
	["models/autocannon/semiautocannon_25mm.mdl"] = { joint = Vector(0, -15.6251, 0), bore = Vector(0, -1, 0), tubelen = 28.33, mdir = Vector(1, 0, 0) },
	["models/autocannon/semiautocannon_37mm.mdl"] = { joint = Vector(0, -23.1251, 0), bore = Vector(0, -1, 0), tubelen = 41.92, mdir = Vector(1, 0, 0) },
	["models/autocannon/semiautocannon_45mm.mdl"] = { joint = Vector(0, -28.1251, 0), bore = Vector(0, -1, 0), tubelen = 50.99, mdir = Vector(1, 0, 0) },
	["models/autocannon/semiautocannon_57mm.mdl"] = { joint = Vector(22.5, 0, 0), bore = Vector(1, 0, 0), tubelen = 86.5, mdir = Vector(1, 0, 0) },
	["models/autocannon/semiautocannon_76mm.mdl"] = { joint = Vector(0, -59.3752, 0), bore = Vector(0, -1, 0), tubelen = 107.64, mdir = Vector(1, 0, 0) },
	["models/howitzer/howitzer_105mm.mdl"] = { joint = Vector(0, -5.5782, -0.8198), bore = Vector(0, -1, 0), tubelen = 95.88, mdir = Vector(1, 0, 0) },
	["models/howitzer/howitzer_122mm.mdl"] = { joint = Vector(0, -6.4815, -0.953), bore = Vector(0, -1, 0), tubelen = 111.47, mdir = Vector(1, 0, 0) },
	["models/howitzer/howitzer_155mm.mdl"] = { joint = Vector(8.24, 0, 0), bore = Vector(1, 0, 0), tubelen = 141.63, mdir = Vector(1, 0, 0) },
	["models/howitzer/howitzer_203mm.mdl"] = { joint = Vector(0, -10.792, -1.5864), bore = Vector(0, -1, 0), tubelen = 185.54, mdir = Vector(1, 0, 0) },
	["models/howitzer/howitzer_240mm.mdl"] = { joint = Vector(0, -12.7555, -1.8746), bore = Vector(0, -1, 0), tubelen = 219.24, mdir = Vector(1, 0, 0) },
	["models/howitzer/howitzer_290mm.mdl"] = { joint = Vector(0, -15.407, -2.2645), bore = Vector(0, -1, 0), tubelen = 264.85, mdir = Vector(1, 0, 0) },
	["models/howitzer/howitzer_406mm.mdl"] = { joint = Vector(94.185, -0.19, -0.3132), bore = Vector(1, 0, 0), tubelen = 292.86, mdir = Vector(0, 0.0449, -0.999) },
	["models/howitzer/howitzer_75mm.mdl"] = { joint = Vector(0, -3.9524, -0.5813), bore = Vector(0, -1, 0), tubelen = 67.99, mdir = Vector(1, 0, 0) },
	["models/tankgun/tankgun_100mm.mdl"] = { joint = Vector(15.5, 0, -0.1767), bore = Vector(1, 0, 0), tubelen = 157.00, mdir = Vector(1, 0, 0) },
	["models/tankgun/tankgun_120mm.mdl"] = { joint = Vector(18.6, 0, -0.212), bore = Vector(1, 0, 0), tubelen = 188.40, mdir = Vector(1, 0, 0) },
	["models/tankgun/tankgun_140mm.mdl"] = { joint = Vector(21.7, 0, -0.2473), bore = Vector(1, 0, 0), tubelen = 219.80, mdir = Vector(1, 0, 0) },
	["models/tankgun/tankgun_170mm.mdl"] = { joint = Vector(23.87, 0, -0.2721), bore = Vector(1, 0, 0), tubelen = 241.78, mdir = Vector(1, 0, 0) },
	["models/tankgun/tankgun_170mmsb.mdl"] = { joint = Vector(29.5606, 0, 0.2583), bore = Vector(1, 0, 0), tubelen = 193.93, mdir = Vector(0, 0, -1) },
	["models/tankgun/tankgun_37mm.mdl"] = { joint = Vector(5.735, 0, -0.0654), bore = Vector(1, 0, 0), tubelen = 58.09, mdir = Vector(1, 0, 0) },
	["models/tankgun/tankgun_50mm.mdl"] = { joint = Vector(7.75, 0, -0.0883), bore = Vector(1, 0, 0), tubelen = 78.50, mdir = Vector(1, 0, 0) },
	["models/tankgun/tankgun_75mm.mdl"] = { joint = Vector(11.625, 0, -0.1325), bore = Vector(1, 0, 0), tubelen = 117.75, mdir = Vector(1, 0, 0) },
	["models/tankgun/tankgun_85mm.mdl"] = { joint = Vector(9.7144, -0.1497, 0), bore = Vector(1, 0, 0), tubelen = 133.04, mdir = Vector(1, 0, 0) },
	["models/tankgun/tankgun_al_100mm.mdl"] = { joint = Vector(13.175, 0, -0.1029), bore = Vector(1, 0, 0), tubelen = 133.45, mdir = Vector(1, 0, 0) },
	["models/tankgun/tankgun_al_120mm.mdl"] = { joint = Vector(15.81, 0, -0.1234), bore = Vector(1, 0, 0), tubelen = 160.14, mdir = Vector(1, 0, 0) },
	["models/tankgun/tankgun_al_140mm.mdl"] = { joint = Vector(18.445, 0, -0.144), bore = Vector(1, 0, 0), tubelen = 186.83, mdir = Vector(1, 0, 0) },
	["models/tankgun/tankgun_al_170mm.mdl"] = { joint = Vector(22.3185, 0, -0.1743), bore = Vector(1, 0, 0), tubelen = 226.06, mdir = Vector(1, 0, 0) },
	["models/tankgun/tankgun_al_50mm.mdl"] = { joint = Vector(6.5875, 0, -0.0514), bore = Vector(1, 0, 0), tubelen = 66.72, mdir = Vector(1, 0, 0) },
	["models/tankgun/tankgun_al_75mm.mdl"] = { joint = Vector(9.8813, 0, -0.0771), bore = Vector(1, 0, 0), tubelen = 100.09, mdir = Vector(1, 0, 0) },
	["models/tankgun/tankgun_short_100mm.mdl"] = { joint = Vector(15.5, 0, -0.1293), bore = Vector(1, 0, 0), tubelen = 79.50, mdir = Vector(1, 0, 0) },
	["models/tankgun/tankgun_short_120mm.mdl"] = { joint = Vector(18.6, 0, -0.1552), bore = Vector(1, 0, 0), tubelen = 95.40, mdir = Vector(1, 0, 0) },
	["models/tankgun/tankgun_short_140mm.mdl"] = { joint = Vector(7.6062, 0.0066, -0.181), bore = Vector(1, 0, 0), tubelen = 111.29, mdir = Vector(1, 0, 0) },
	["models/tankgun/tankgun_short_170mm.mdl"] = { joint = Vector(13.0312, 0.0082, -0.2263), bore = Vector(1, 0, 0), tubelen = 135.59, mdir = Vector(1, 0, 0) },
	["models/tankgun/tankgun_short_37mm.mdl"] = { joint = Vector(5.735, 0, -0.0478), bore = Vector(1, 0, 0), tubelen = 29.42, mdir = Vector(1, 0, 0) },
	["models/tankgun/tankgun_short_50mm.mdl"] = { joint = Vector(7.75, 0, -0.0647), bore = Vector(1, 0, 0), tubelen = 39.75, mdir = Vector(1, 0, 0) },
	["models/tankgun/tankgun_short_75mm.mdl"] = { joint = Vector(11.625, 0, -0.097), bore = Vector(1, 0, 0), tubelen = 59.62, mdir = Vector(1, 0, 0) },
	["models/tankgun/tankgun_short_85mm.mdl"] = { joint = Vector(9.7144, -0.1096, 0), bore = Vector(1, 0, 0), tubelen = 67.36, mdir = Vector(1, 0, 0) },
	["models/tankgun_new/tankgun_100mm.mdl"] = { joint = Vector(-24.0002, 19, -0.0848), bore = Vector(0, -1, 0), tubelen = 170.00, mdir = Vector(0, -1, 0) },
	["models/tankgun_new/tankgun_120mm.mdl"] = { joint = Vector(18, 0, 0), bore = Vector(1, 0, 0), tubelen = 192, mdir = Vector(1, 0, 0) },
	["models/tankgun_new/tankgun_140mm.mdl"] = { joint = Vector(-24.0003, 17, -0.1187), bore = Vector(0, -1, 0), tubelen = 238.00, mdir = Vector(1, 0, 0) },
	["models/tankgun_new/tankgun_170mm.mdl"] = { joint = Vector(-24.0004, 15.5, -0.1441), bore = Vector(0, -1, 0), tubelen = 289.00, mdir = Vector(0, -1, 0) },
	["models/tankgun_new/tankgun_50mm.mdl"] = { joint = Vector(-24.0001, 21.5, -0.0424), bore = Vector(0, -1, 0), tubelen = 85.00, mdir = Vector(0, -1, 0) },
	["models/tankgun_new/tankgun_75mm.mdl"] = { joint = Vector(-24.0002, 20.25, -0.0636), bore = Vector(0, -1, 0), tubelen = 127.50, mdir = Vector(0, -1, 0) },
}

-- Parameterized gun keys. A scalable gun is identified everywhere (dupes,
-- networking, ammo crates) by a string of the form
--     <baseid>@<caliberMM>x<lengthCal>
-- for example "120mmC@140x55" means: the gun whose base id is "120mmC", but
-- bored out to 140mm with an L/55 barrel. The "x<length>" part is optional
-- for classes without a length envelope. KEY_PATTERN splits such a key into
-- its pieces; OPTS_PATTERN parses just the parameter part ("140x55"), which
-- is what the duplicator stores in the GunSpec field and what the
-- acemenu_gunspec convar carries.
local KEY_PATTERN  = "^(.-)@(%d+%.?%d*)x?(%d*%.?%d*)$"
local OPTS_PATTERN = "^(%d+%.?%d*)x?(%d*%.?%d*)$"

--- Splits a parameterized id into its base id and optional scale parameters.
-- Example: ParseKey("120mmC@140x55") returns "120mmC", 140, 55;
-- ParseKey("120mmC") returns "120mmC", nil, nil.
-- @param id string Gun id or key ("120mmC", "120mmC@140x55").
-- @usage local base, calMM, len = ACE.GunScale.ParseKey("120mmC@140x55")
-- @return string base Base definition id.
-- @return number|nil calMM Effective caliber in millimeters, if present.
-- @return number|nil len Bore length in calibers, if present.
function GunScale.ParseKey( id )
	if not isstring( id ) then return id end

	local base, cal, len = string.match( id, KEY_PATTERN )
	if not base then return id end

	return base, tonumber( cal ), ( len ~= "" and tonumber( len ) or nil )
end

--- Builds a parameterized key from a base id and scale parameters.
-- @param id string Base definition id.
-- @param calMM number|nil Effective caliber in millimeters.
-- @param len number|nil Bore length in calibers.
-- @return string
function GunScale.Key( id, calMM, len )
	if not isstring( id ) or not calMM then return id end

	return id .. "@" .. calMM .. ( len and ( "x" .. len ) or "" )
end

--- Parses a GunSpec string — the bare parameter suffix without a base id
-- ("140x55", or caliber-only "140"), returning nil for an empty string.
-- Named after the duplicator's GunSpec field whose format it parses.
-- These functions live on ACE.GunScale (not as locals) because they are the
-- public kernel API: entities, tools, starfall/e2 extensions and the spawn
-- menu all call them from outside this file.
-- @return number|nil calMM caliber in millimeters
-- @return number|nil len barrel length in calibers (L/d)
function GunScale.ParseSpec( str )
	if not isstring( str ) or str == "" then return end

	local cal, len = string.match( str, OPTS_PATTERN )
	if cal then return tonumber( cal ), tonumber( len ) end

	-- Tolerate a full key being passed as opts.
	local _, kcal, klen = GunScale.ParseKey( str )
	return kcal, klen
end

--- Resolves a possibly-parameterized id to its registry definition.
-- Migration suffix map for ids that never existed in ACE: ACF-3 (and older)
-- dupes carry caliber-keyed ids whose class suffix differs from ACE's legacy
-- naming. When neither the gun table nor the exact legacy aliases know an
-- id, a clean "<caliber>mm<SUFFIX>" parse through this map resolves it to the
-- matching scalable class at that caliber, clamped to the class envelope —
-- so a 127mmRAC pastes as a 30mm rotary (the envelope max) instead of an
-- error, and ACF-3 smoothbores/shortcannons land in the right ACE classes.
-- ACE-native suffixes double as generic fallbacks for the same reason.
GunScale.MigrationSuffixes = GunScale.MigrationSuffixes or {
	C   = { class = "C" },
	AC  = { class = "AC" },  HAC = { class = "AC" },
	MG  = { class = "MG" },  HMG = { class = "HMG" },
	RAC = { class = "RAC" }, HRAC = { class = "RAC" },
	SA  = { class = "SA" },
	HW  = { class = "HW" },
	GL  = { class = "GL" },  CL  = { class = "GL" },
	MO  = { class = "MO" },  M   = { class = "MO" },
	SBC = { class = "SBC" }, SB  = { class = "SBC" },
	SC  = { class = "C", len = 20 }, -- shortcannon fold: short tube cannon
	AL  = { class = "AL" },  BAL = { class = "BAL" },
	ATR = { class = "ATR" }, SL  = { class = "SL" }, FGL = { class = "FGL" },
}

local MIGRATION_PATTERN = "^(%d+%.?%d*)mm([A-Z]+)$"

--- Resolves a non-ACE id to a migration pseudo-alias, or nil when the id
-- does not parse as a clean caliber+known-suffix combination.
-- @param base string The id with any key suffix already stripped
-- @return table|nil {class, caliber (cm), len?}
function GunScale.MigrationAlias( base )
	if not isstring( base ) then return end
	local cal, suffix = string.match( base, MIGRATION_PATTERN )
	if not cal then return end
	local entry = GunScale.MigrationSuffixes[ suffix ]
	if not entry then return end
	return { class = entry.class, caliber = tonumber( cal ) / 10, len = entry.len, migration = true }
end

-- Drop-in replacement for ACE.Weapons.Guns[id] wherever the id may be a key.
-- @param id string Gun id, optionally carrying a @key suffix
-- @return table|nil Gun definition, or nil if the base id is unknown.
function GunScale.ResolveDef( id )
	local base = GunScale.ParseKey( id )
	local def = ACE.Weapons.Guns[ base ]
	if def then return def end

	local alias = ACE.LegacyGunAliases and ACE.LegacyGunAliases[ base ]
	if not alias then alias = GunScale.MigrationAlias( base ) end
	if alias then return ACE.Weapons.Guns[ alias.class ] end
end

--- Resolves a possibly-parameterized id to def + parameters.
-- @return table|nil def
-- @return number|nil calMM
-- @return number|nil len
function GunScale.Resolve( id )
	local base, calMM, len = GunScale.ParseKey( id )
	return ACE.Weapons.Guns[ base ], calMM, len
end

--- Resolves any id shape to its def + effective spec. Handles synthetic
-- class ids ("C", "C@140x55"), keyed legacy ids ("120mmC@140x55" — the shape
-- dupes saved since the scalable-keys introduction carry) and bare legacy
-- ids ("120mmC") through ACE.LegacyGunAliases: the alias carries the
-- authored caliber/length, and key suffix parameters override them, so an
-- old keyed dupe pastes into the class system at the same spec.
-- @return table|nil def Synthetic (or surviving) def of the resolved class
-- @return number|nil calMM Effective caliber in millimeters
-- @return number|nil len Bore length in calibers
-- @param id string Gun id or legacy alias, optionally carrying a @key suffix
-- @return string|nil baseid The base id as given (for .Id reporting)
function GunScale.ResolveSpec( id )
	local base, calMM, len = GunScale.ParseKey( id )
	if not isstring( base ) then return end

	local def = ACE.Weapons.Guns[ base ]
	if def then return def, calMM, len, base end

	local alias = ACE.LegacyGunAliases and ACE.LegacyGunAliases[ base ]
	if not alias then alias = GunScale.MigrationAlias( base ) end
	if not alias then return end

	def = ACE.Weapons.Guns[ alias.class ]
	if not def then return end

	return def, calMM or ( alias.caliber and alias.caliber * 10 ), len or alias.len, base
end

--- Returns the scalability envelope for a def (or keyed id), or nil when the
-- def/class does not support scaling. All calibers are in centimeters, all
-- lengths in calibers.
-- @return table|nil {basecal, baselen, calmin, calmax, lenmin, lenmax, tubefrac, hasbarrels}
function GunScale.Limits( id )
	local def = GunScale.ResolveDef( id )
	if not def then return end

	local class = ACE.Classes.GunClass[ def.gunclass ]
	local sc = def.scalable
	if sc == nil then sc = class and class.scalable end
	if not sc then return end

	local calMul = ( istable( sc ) and sc.cal ) or GunScale.DefCalRange
	-- `scalable = {cal=...}` without a len range is caliber-only: the length
	-- axis locks to the base bore length (lenmin == lenmax hides the slider).
	local lenMul = ( istable( sc ) and sc.len ) or ( istable( sc ) and { 1, 1 } ) or GunScale.DefLenRange
	local baselen = def.borelength or ( class and class.borelength ) or GunScale.DefBoreLength
	local calr = def.calrange
	local lenr = def.lenrange

	return {
		basecal    = def.caliber,
		baselen    = baselen,
		calmin     = calr and ( calr[1] / 10 ) or def.caliber * calMul[1],
		calmax     = calr and ( calr[2] / 10 ) or def.caliber * calMul[2],
		lenmin     = lenr and lenr[1] or baselen * lenMul[1],
		lenmax     = lenr and lenr[2] or baselen * lenMul[2],
		tubefrac   = def.tubefrac or ( class and class.tubefrac ) or GunScale.DefTubeFrac,
		overhead   = def.massoverhead or ( class and class.massoverhead ) or 0,
		hasbarrels = def.barrels ~= nil or ( class and ( class.barrels or class.longbarrel ) ~= nil ),
	}
end

--- Whether a def (or keyed id) supports parameter scaling.
-- @return boolean
function GunScale.IsScalableId( id )
	return GunScale.Limits( id ) ~= nil
end

--- Groups a gunclass' scalable defs into a family descriptor for the unified
-- menu: one tree entry per class whose sliders span the union envelope, each
-- caliber resolving to the nearest concrete def (see ResolveFamilyDef).
-- @return table|nil {class, defs (caliber-sorted), calmin, calmax, lenmin, lenmax}
function GunScale.Family( gunclass )
	local defs
	for id, def in pairs( ACE.Weapons.Guns ) do
		if def.gunclass == gunclass and GunScale.Limits( id ) then
			defs = defs or {}
			defs[#defs + 1] = def
		end
	end
	if not defs then return end

	table.sort( defs, function( a, b ) if a.caliber ~= b.caliber then return a.caliber < b.caliber end return tostring( a.id ) < tostring( b.id ) end )

	local fam = { class = gunclass, defs = defs,
		calmin = math.huge, calmax = 0, lenmin = math.huge, lenmax = 0 }
	for _, def in ipairs( defs ) do
		local lim = GunScale.Limits( def.id )
		fam.calmin = math.min( fam.calmin, lim.calmin )
		fam.calmax = math.max( fam.calmax, lim.calmax )
		fam.lenmin = math.min( fam.lenmin, lim.lenmin )
		fam.lenmax = math.max( fam.lenmax, lim.lenmax )
	end
	return fam
end

--- Groups a gunclass' scalable defs into one family PER DISTINCT `def.family`
-- key. Drum and breech autoloaders share gunclass "AL" but are different
-- weapon lines: marking the defs with `family = "BAL"` etc keeps them in
-- separate menu entries. Defs without a family key group under "". Each
-- family gets `key` and a display `name` derived from its first def's name
-- with the leading caliber stripped ("50mm Drum Autoloader" -> "Drum
-- Autoloader"); single-family classes never show it, the class name wins.
-- @return table|nil array of family descriptors (same shape as Family)
function GunScale.Families( gunclass )
	local byKey, order
	for id, def in pairs( ACE.Weapons.Guns ) do
		if def.gunclass == gunclass and GunScale.Limits( id ) then
			local k = def.family or ""
			if not byKey or not byKey[k] then
				byKey = byKey or {}
				byKey[k] = {}
				order = order or {}
				order[#order + 1] = k
			end
			local t = byKey[k]
			t[#t + 1] = def
		end
	end
	if not order then return end

	table.sort( order )

	local fams = {}
	for _, k in ipairs( order ) do
		local defs = byKey[k]
		table.sort( defs, function( a, b ) if a.caliber ~= b.caliber then return a.caliber < b.caliber end return tostring( a.id ) < tostring( b.id ) end )

		local fam = { class = gunclass, key = k, defs = defs,
			calmin = math.huge, calmax = 0, lenmin = math.huge, lenmax = 0 }
		for _, def in ipairs( defs ) do
			local lim = GunScale.Limits( def.id )
			fam.calmin = math.min( fam.calmin, lim.calmin )
			fam.calmax = math.max( fam.calmax, lim.calmax )
			fam.lenmin = math.min( fam.lenmin, lim.lenmin )
			fam.lenmax = math.max( fam.lenmax, lim.lenmax )
		end

		local first = defs[1].name or defs[1].id
		fam.name = string.match( first, "^[%d.]+mm%s*(.+)$" ) or first

		fams[#fams + 1] = fam
	end
	return fams
end

--- The display name for a def at the given effective caliber/length. At exact
-- base spec this is the def's own name verbatim (bit-exact for anything
-- comparing it). When scaled, the first caliber mention in the name is
-- replaced by the effective one ("120mm Cannon" at 140mm -> "140mm Cannon";
-- "Shortened 30mm Heavy Machinegun" -> "Shortened 40mm Heavy Machinegun"),
-- or prepended when the name mentions no caliber, and a length suffix is
-- appended when the bore length deviates ("... L55").
-- @return string
function GunScale.DisplayName( def, calMM, len )
	if not istable( def ) then return "?" end

	local lim = GunScale.Limits( def.id )
	if not lim then return def.name or def.id end

	calMM = calMM or lim.basecal * 10
	len = len or lim.baselen

	local scaledCal = math.abs( calMM - lim.basecal * 10 ) >= 0.05
	local scaledLen = lim.lenmin < lim.lenmax and math.abs( len - lim.baselen ) >= 0.5
	if not scaledCal and not scaledLen then return def.name or def.id end

	local name = def.name or def.id
	local calstr = string.format( "%g", calMM ) .. "mm"
	if string.find( name, "[%d.]+mm" ) then
		name = string.gsub( name, "[%d.]+mm", calstr, 1 )
	else
		name = calstr .. " " .. name
	end

	if scaledLen then
		name = name .. " L" .. string.format( "%g", len )
	end

	return name
end

--- Picks the def in `fam` whose base caliber is closest to calMM: the
-- "nearest def" the unified menu entry spawns (its model, stats, limits).
-- @return table def
function GunScale.ResolveFamilyDef( fam, calMM )
	local best, bd
	for _, def in ipairs( fam.defs ) do
		local d = math.abs( def.caliber * 10 - calMM )
		if not bd or d < bd then best, bd = def, d end
	end
	return best
end

--- Clamps raw parameters to the def's limits and normalizes them onto the
-- matching grid the ammo menu uses (0.1mm caliber, integer calibers of length).
-- @return number calMM
-- @return number len
function GunScale.Normalize( id, calMM, len )
	local lim = GunScale.Limits( id )
	if not lim then return end

	calMM = calMM and math.Clamp( math.Round( calMM, 1 ), lim.calmin * 10, lim.calmax * 10 )
		or lim.basecal * 10
	len = len and math.Clamp( math.Round( len ), lim.lenmin, lim.lenmax ) or lim.baselen

	return calMM, len
end

--- Clamps a caliber (mm) to the def's caliber envelope. Used on ammo keys so a
-- hand-edited dupe cannot smuggle an out-of-range round.
-- @return number calMM
function GunScale.ClampCalMM( id, calMM )
	local lim = GunScale.Limits( id )
	if not lim then
		local def = GunScale.ResolveDef( id )
		return def and def.caliber * 10 or calMM
	end

	return math.Clamp( calMM, lim.calmin * 10, lim.calmax * 10 )
end

--- Computes the effective stats of a def at the given caliber/length.
-- calCM in centimeters, len in calibers; both default to the base spec.
-- @return table {mass, mvmod, chamberLen, propLimit, scale(Vector),
--   calscale, lenscale, caliber(cm), borelen}
function GunScale.Stats( def, calCM, len )
	if not istable( def ) then return end

	local lim = GunScale.Limits( def.id )
	local basecal = ( lim and lim.basecal ) or def.caliber
	local baselen = ( lim and lim.baselen ) or GunScale.DefBoreLength
	local tubeFrac = ( lim and lim.tubefrac ) or GunScale.DefTubeFrac

	calCM = calCM or basecal
	len = len or baselen

	local cs = calCM / basecal
	local ls = len / baselen

	local oh = ( lim and lim.overhead ) or 0
	local mass = def.weight * ( oh + ( 1 - oh ) * ( ( 1 - tubeFrac ) * cs ^ 3 + tubeFrac * cs ^ 2 * ls ) )
	local mvmod = math.Clamp( ls ^ GunScale.MVLengthExp, GunScale.MVMin, GunScale.MVMax )
	local round = def.round or {}

	-- On models with a barrel joint the entity itself only carries the uniform
	-- caliber scale; the extra length is applied piecewise (see MapPoint) so the
	-- breech keeps its shape and only the tube stretches.
	local split = GunScale.BarrelInfo( def.model )

	-- Cyclic-rate cap: the def/class cap is authored at base caliber. Smaller
	-- guns cycle faster; exponent 0.7 reproduces the retired ladder's shape
	-- (37mm cap ~42 and 50mm ~32 fall out of the 120mm base cap of 19).
	-- Drum autoloader mag reload scales with the same exponent: bigger shells
	-- take longer to re-cage, but the mechanism size is fixed overhead.
	local rofexp = 0.7
	local maxrof = def.maxrof and ( def.maxrof / cs ^ rofexp ) or nil
	local magreload = def.magreload and ( def.magreload * cs ^ rofexp ) or nil
	local magsize = def.magsize and math.max( 1, math.floor( def.magsize / cs ^ 0.5 + 0.5 ) ) or nil

	return {
		mass       = mass,
		mvmod      = mvmod,
		chamberLen = ( round.maxlength or 0 ) * cs,
		propLimit  = ( round.propweight or 0 ) * cs ^ 3,
		scale      = split and Vector( cs, cs, cs ) or Vector( cs * ls, cs, cs ),
		split      = split,
		calscale   = cs,
		lenscale   = ls,
		caliber    = calCM,
		borelen    = len,
		maxrof     = maxrof,
		magreload  = magreload,
		magsize    = magsize,
	}
end

--- Returns the barrel-split registry entry for a model, or nil.
-- @return table|nil {joint = Vector, bore = Vector, tubelen = number, mdir = Vector}
function GunScale.BarrelInfo( model )
	return model and GunScale.BarrelJoints[model]
end

--- Maps a bind-space point through the breech/tube split. The point's distance
-- from `joint` along `bore` is stretched by lenScale, but the stretch
-- contribution caps at `tubelen`: geometry past the tube end (muzzle
-- attachments, and the muzzledev bone skin) slides rigidly instead of
-- over-stretching. The uniform scale applies last. With no split entry this
-- reduces to `pos * scale`.
-- @return Vector
function GunScale.MapPoint( pos, scale, split, lenScale )
	if not split then
		return Vector( pos.x * scale.x, pos.y * scale.y, pos.z * scale.z )
	end

	local t = ( pos - split.joint ):Dot( split.bore )
	local out = pos + split.bore * ( ( lenScale - 1 ) * math.Clamp( t, 0, split.tubelen ) )

	return Vector( out.x * scale.x, out.y * scale.y, out.z * scale.z )
end

--- Stretches the tube of a rebuilt rig (tools/modelrig). Every rebuilt model
-- carries a `tube` bone whose origin sits exactly on the breech/tube joint,
-- so a plain (lenScale, 1, 1) bone scale pivots there with no compensation,
-- and a `muzzledev` bone at the tube end that slides along `mdir` so brakes
-- and evacuators translate rigidly instead of stretching. Breech geometry is
-- skinned to the barrel bone and untouched.
-- ManipulateBonePosition is an offset from the bind position, not an absolute
-- set. Idempotent and safe at lenScale 1 (it resets the bones), which the menu
-- preview relies on when the slider returns to base. Works server-side (the
-- manipulation networks to clients).
function GunScale.ApplyBarrelBones( ent, lenScale, split )
	if not IsValid( ent ) or not lenScale or not split then return end

	local tube = ent:LookupBone( "tube" )
	if not tube then return end -- model predates the rig rebuild: uniform scale only

	ent:ManipulateBoneScale( tube, Vector( lenScale, 1, 1 ) )

	local muzz = ent:LookupBone( "muzzledev" )
	if muzz then
		ent:ManipulateBonePosition( muzz, split.mdir * ( lenScale - 1 ) * split.tubelen )
	end
end

--- Formats the GunSpec suffix for a normalized pair, or "" when the pair is the
-- base spec (so unscaled guns produce byte-identical dupe data).
-- @param id string The id the entity stores — original alias included, since
--   the empty-string contract is defined against what pasting that id yields
-- @param calMM number Effective caliber in millimeters
-- @param len number Bore length in calibers
-- @return string
function GunScale.SpecString( id, calMM, len )
	local lim = GunScale.Limits( id )
	if not lim or not calMM or not len then return "" end

	-- The empty string must round-trip: it is only correct when the spec matches
	-- what a bare paste of the id would produce. That default is the key suffix
	-- embedded in the id, then the legacy alias spec, then the class pivot —
	-- not just the pivot. A legacy gun dialed back to the pivot (170mmC at
	-- 120mm L/45) still needs explicit options or the next paste restores the
	-- alias dimensions.
	local BaseId, KeyCal, KeyLen = GunScale.ParseKey( id )
	local _, AliasCal, AliasLen = GunScale.ResolveSpec( BaseId )
	local DefCal = ( KeyCal or AliasCal or lim.basecal * 10 )
	local DefLen = ( KeyLen or AliasLen or lim.baselen )

	if math.abs( calMM - DefCal ) < 0.05 and math.abs( len - DefLen ) < 0.5 then
		return ""
	end

	-- Caliber-only guns get a length-free suffix ("140", parses as len=nil).
	if lim.lenmin >= lim.lenmax then
		return string.format( "%g", calMM )
	end

	return string.format( "%gx%g", calMM, len )
end

--- Resolves the muzzle attachment for the gun's current barrel/bodygroup state.
-- Supports def-level `barrels`, class-level `barrels`, and the legacy
-- class-level `longbarrel` table.
-- @return string attachment name
-- @return table|nil matching barrel entry
function GunScale.ResolveBarrel( gun )
	local classData = ACE.Classes.GunClass[ gun.Class or gun.GunClass ]
	local def = gun.Id and ACE.Weapons.Guns[ gun.Id ]
	local barrels = ( def and def.barrels ) or ( classData and classData.barrels )

	if barrels then
		local fallback = barrels[1]
		for _, b in ipairs( barrels ) do
			if b.index and gun:GetBodygroup( b.index ) == b.submodel then
				return b.muzzle or "muzzle", b
			end
		end
		return "muzzle", fallback
	end

	local lb = classData and classData.longbarrel
	if lb and gun:GetBodygroup( lb.index ) == lb.submodel then
		return lb.newpos or "muzzle", lb
	end

	return "muzzle"
end

--- Whether an ammo crate's BulletData can feed this gun. Non-scalable guns
-- keep the legacy exact-id rule; scalable guns accept any round of the same
-- gun class whose caliber matches, and whose length/propellant fit the
-- effective chamber.
-- @return boolean ok
-- @return string reason Rejection message when ok is false.
function GunScale.AmmoFits( gun, bdata )
	if not istable( bdata ) then return false, "Wrong ammo type!" end

	local bulletDef = GunScale.ResolveDef( bdata.Id )
	if not bulletDef then return false, "Wrong ammo type!" end

	if not gun.ScalableSpec then
		return bdata.Id == gun.Id, "Wrong ammo type!"
	end

	local bclass = ACE.Classes.GunClass[ bulletDef.gunclass ]
	local gclass = ACE.Classes.GunClass[ gun.Class ]
	local bfam = bulletDef.ammofamily or ( bclass and bclass.ammofamily ) or bulletDef.gunclass
	local gfam = ( gclass and gclass.ammofamily ) or gun.Class
	if bfam ~= gfam then
		return false, "Wrong ammo type!"
	end

	local cal = bdata.Caliber or bulletDef.caliber
	if math.abs( cal - gun.Caliber ) > GunScale.CalEpsilon then
		return false, "Wrong caliber!"
	end

	local roundLen = ( bdata.ProjLength or 0 ) + ( bdata.PropLength or 0 )
	if gun.ChamberLen and roundLen > gun.ChamberLen + GunScale.LenEpsilon then
		return false, "Round too long for the chamber!"
	end

	if gun.PropLimit and ( bdata.PropMass or 0 ) > gun.PropLimit * GunScale.PropSlack then
		return false, "Propellant charge too large for this gun!"
	end

	return true
end

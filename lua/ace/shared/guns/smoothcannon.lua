-- Unified scalable gun class. A single definition covers the whole caliber
-- (and, where present, barrel-length) envelope — the spawn menu shows sliders
-- instead of the old fixed per-caliber list. Legacy ids like the retired
-- per-caliber defs resolve to this class through
-- lua/ace/shared/ace_legacy_gun_aliases.lua, and the scaling math lives in
-- lua/ace/shared/sh_ace_gunpack.lua. When adding a new gun class, copy this
-- pattern: pick pivot values from a real reference gun.
-- Pivot spec: 120mmSBC (12.0cm, 2286kg). Scaling is relative to these base values.
ACE.DefineGunClass("SBC", {
	type = "Gun",
	spread = 0.12,
	name = "Smooth-Bore Cannon",
	desc = ACE.Translation.GunClasses[15],
	muzzleflash = "C",
	rofmod = 1.7,
	maxrof = 20, -- maximum rounds per minute
	sound = "ace_weapons/multi_sound/120mm_multi.mp3",
	year = 1960,

		-- Scaling envelope: the caliber/length slider ranges in the spawn menu.
	-- caliber is in cm; length is in L/d (calibers — barrel length as a
	-- multiple of bore diameter, so L/45 on a 120mm gun is a 5.4m tube);
	-- mass in kg at the pivot spec. tubefrac is the fraction of mass in the
	-- barrel tube (tube mass scales with bore area x length, everything else
	-- with volume); massoverhead is the fixed mechanism floor that never
	-- scales. The full mass law is documented in sh_ace_gunpack.lua.
	model        = "models/tankgun_new/tankgun_120mm.mdl",
	caliber      = { base = 12, min = 5, max = 20 }, -- cm
	length       = { base = 48, min = 30, max = 70 }, -- L/d
	mass         = 2286, -- kg at base caliber + base length
	tubefrac     = 0.44, -- fraction of total mass in the barrel tube; tube mass scales with bore area x length, the rest with volume (Rh-120 L/44->L/55 calibrated)
	massoverhead = 0.08, -- fraction of mass that never scales (mechanism floor, calibrated vs real KwK 36/39/40 weights)
	round        = { maxlength = 115, propweight = 30 }, -- at base caliber
} )

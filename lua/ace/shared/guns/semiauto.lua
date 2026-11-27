-- Unified scalable gun class. A single definition covers the whole caliber
-- (and, where present, barrel-length) envelope — the spawn menu shows sliders
-- instead of the old fixed per-caliber list. Legacy ids like the retired
-- per-caliber defs resolve to this class through
-- lua/ace/shared/ace_legacy_gun_aliases.lua, and the scaling math lives in
-- lua/ace/shared/sh_ace_gunpack.lua. When adding a new gun class, copy this
-- pattern: pick pivot values from a real reference gun.
-- Pivot spec: 57mmSA (5.7cm, 780kg). Scaling is relative to these base values.
ACE.DefineGunClass("SA", {
	type = "Gun",
	spread = 0.15,
	name = "Semiautomatic Cannon",
	desc = ACE.Translation.GunClasses[12],
	muzzleflash = "AC",
	rofmod = 0.5,
	year = 1935,
	sound = "ace_weapons/multi_sound/20mm_multi.mp3",
	noloader = true,
	magsize = 12, -- rounds at base caliber; scales inverse-sqrt with caliber
	magreload = 9, -- seconds at base caliber; scales with caliber^0.7

		-- Scaling envelope: the caliber/length slider ranges in the spawn menu.
	-- caliber is in cm; length is in L/d (calibers — barrel length as a
	-- multiple of bore diameter, so L/45 on a 120mm gun is a 5.4m tube);
	-- mass in kg at the pivot spec. tubefrac is the fraction of mass in the
	-- barrel tube (tube mass scales with bore area x length, everything else
	-- with volume); massoverhead is the fixed mechanism floor that never
	-- scales. The full mass law is documented in sh_ace_gunpack.lua.
	model        = "models/autocannon/semiautocannon_57mm.mdl",
	caliber      = { base = 5.7, min = 2.5, max = 7.62 }, -- cm
	length       = { base = 45, min = 30, max = 70 }, -- L/d
	mass         = 780, -- kg at base caliber + base length
	tubefrac     = 0.44, -- fraction of total mass in the barrel tube; tube mass scales with bore area x length, the rest with volume (Rh-120 L/44->L/55 calibrated)
	massoverhead = 0.08, -- fraction of mass that never scales (mechanism floor, calibrated vs real KwK 36/39/40 weights)
	round        = { maxlength = 62, propweight = 2 }, -- at base caliber
} )

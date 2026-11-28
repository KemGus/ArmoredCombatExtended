-- Unified scalable gun class. A single definition covers the whole caliber
-- (and, where present, barrel-length) envelope — the spawn menu shows sliders
-- instead of the old fixed per-caliber list. Legacy ids like the retired
-- per-caliber defs resolve to this class through
-- lua/ace/shared/ace_legacy_gun_aliases.lua, and the scaling math lives in
-- lua/ace/shared/sh_ace_gunpack.lua. When adding a new gun class, copy this
-- pattern: pick pivot values from a real reference gun.
-- Pivot spec: 30mmHMG (3.0cm, 150kg). Scaling is relative to these base values.
ACE.DefineGunClass("HMG", {
	type = "Gun",
	spread = 0.17,
	name = "Heavy Machinegun",
	desc = ACE.Translation.GunClasses[7],
	muzzleflash = "MG",
	rofmod = 0.16,
	year = 1935,
	sound = "ace_weapons/multi_sound/30mm_hmg_multi.mp3",
	noloader = true,

	longbarrel = {
		index = 2,
		submodel = 4,
		newpos = "muzzle2"
	},
	magsize = 50, -- rounds at base caliber; scales inverse-sqrt with caliber
	magreload = 6, -- seconds at base caliber; scales with caliber^0.7

		-- Scaling envelope: the caliber/length slider ranges in the spawn menu.
	-- caliber is in cm; length is in L/d (calibers — barrel length as a
	-- multiple of bore diameter, so L/45 on a 120mm gun is a 5.4m tube);
	-- mass in kg at the pivot spec. tubefrac is the fraction of mass in the
	-- barrel tube (tube mass scales with bore area x length, everything else
	-- with volume); massoverhead is the fixed mechanism floor that never
	-- scales. The full mass law is documented in sh_ace_gunpack.lua.
	model        = "models/machinegun/machinegun_30mm_compact.mdl",
	caliber      = { base = 3, min = 2, max = 4 }, -- cm
	mass         = 150, -- kg at base caliber + base length
	tubefrac     = 0.44, -- fraction of total mass in the barrel tube; tube mass scales with bore area x length, the rest with volume (Rh-120 L/44->L/55 calibrated)
	massoverhead = 0.08, -- fraction of mass that never scales (mechanism floor, calibrated vs real KwK 36/39/40 weights)
	round        = { maxlength = 39, propweight = 0.35 }, -- at base caliber
} )

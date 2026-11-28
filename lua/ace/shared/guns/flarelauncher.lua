-- Unified scalable gun class. A single definition covers the whole caliber
-- (and, where present, barrel-length) envelope — the spawn menu shows sliders
-- instead of the old fixed per-caliber list. Legacy ids like the retired
-- per-caliber defs resolve to this class through
-- lua/ace/shared/ace_legacy_gun_aliases.lua, and the scaling math lives in
-- lua/ace/shared/sh_ace_gunpack.lua. When adding a new gun class, copy this
-- pattern: pick pivot values from a real reference gun.
-- Pivot spec: 40mmFGL (4.0cm, 75kg). Scaling is relative to these base values.
ACE.DefineGunClass("FGL", {
	type = "Gun",
	spread = 3,
	name = "Flare Launcher",
	desc = ACE.Translation.GunClasses[5],
	muzzleflash = "MO",
	rofmod = 0.6,
	year = 1970,
	sound = "acf_new/weapons/skyfire/close/close (1).wav",

	ammoBlacklist	= {"AP", "APHE", "FL", "HE", "HEAT", "HP", "SM"}, -- ok fun's over
	magsize = 30, -- rounds at base caliber; scales inverse-sqrt with caliber
	magreload = 30, -- seconds at base caliber; scales with caliber^0.7

		-- Scaling envelope: the caliber/length slider ranges in the spawn menu.
	-- caliber is in cm; length is in L/d (calibers — barrel length as a
	-- multiple of bore diameter, so L/45 on a 120mm gun is a 5.4m tube);
	-- mass in kg at the pivot spec. tubefrac is the fraction of mass in the
	-- barrel tube (tube mass scales with bore area x length, everything else
	-- with volume); massoverhead is the fixed mechanism floor that never
	-- scales. The full mass law is documented in sh_ace_gunpack.lua.
	model        = "models/missiles/blackjellypod.mdl",
	caliber      = { base = 4, min = 4, max = 7.5 }, -- cm. Scaling example: at
		-- the 7.5cm maximum the caliber scale is 7.5/4 = 1.875, so mass grows by
		-- the mass law (roughly cubed on the non-tube fraction) and round
		-- dimensions multiply by 1.875 linearly. Only the base caliber scales
		-- here — flare launchers have no length slider because their barrels
		-- are fixed short tubes, so the envelope omits the length table
		-- entirely.
	mass         = 75, -- kg at base caliber + base length
	tubefrac     = 0.44, -- fraction of total mass in the barrel tube; tube mass scales with bore area x length, the rest with volume (Rh-120 L/44->L/55 calibrated)
	massoverhead = 0.08, -- fraction of mass that never scales (mechanism floor, calibrated vs real KwK 36/39/40 weights)
	round        = { maxlength = 9, propweight = 0.007 }, -- at base caliber
} )

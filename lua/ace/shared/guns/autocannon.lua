-- Unified scalable gun class. A single definition covers the whole caliber
-- (and, where present, barrel-length) envelope — the spawn menu shows sliders
-- instead of the old fixed per-caliber list. Legacy ids like the retired
-- per-caliber defs resolve to this class through
-- lua/ace/shared/ace_legacy_gun_aliases.lua, and the scaling math lives in
-- lua/ace/shared/sh_ace_gunpack.lua. When adding a new gun class, copy this
-- pattern: pick pivot values from a real reference gun.
-- Pivot spec: 40mmAC (4.0cm, 425kg). Scaling is relative to these base values.
ACE.DefineGunClass("AC", {
		type = "Gun",
		spread = 0.15,
		name = "Autocannon",
		desc = ACE.Translation.GunClasses[2],
		muzzleflash = "AC",
		rofmod = 0.35,
		year = 1930,
		sound = "ace_weapons/multi_sound/30mm_multi.mp3",
		noloader = true,

		-- Scaling envelope: the caliber/length slider ranges in the spawn menu.
	-- caliber is in cm; length is in L/d (calibers — barrel length as a
	-- multiple of bore diameter, so L/45 on a 120mm gun is a 5.4m tube);
	-- mass in kg at the pivot spec. tubefrac is the fraction of mass in the
	-- barrel tube (tube mass scales with bore area x length, everything else
	-- with volume); massoverhead is the fixed mechanism floor that never
	-- scales. The full mass law is documented in sh_ace_gunpack.lua.
	-- Worked example for this envelope: dialing the 40mm autocannon to its
	-- 5cm maximum gives caliber scale cs = 5/4 = 1.25. At pivot length the
	-- non-tube mass scales cs^3 = 1.95x, the tube mass cs^2 = 1.56x (the
	-- length term only enters when the length slider moves). Weighted by
	-- tubefrac/massoverhead that lands near 1.72x overall — a 50mm version
	-- is roughly 730kg, not the naive 425kg.
	model        = "models/autocannon/autocannon_40mm.mdl",
	caliber      = { base = 4, min = 2, max = 5 }, -- cm
	mass         = 425, -- kg at base caliber + base length
	tubefrac     = 0.44, -- fraction of total mass in the barrel tube; tube mass scales with bore area x length, the rest with volume (Rh-120 L/44->L/55 calibrated)
	massoverhead = 0.08, -- fraction of mass that never scales (mechanism floor, calibrated vs real KwK 36/39/40 weights)
	round        = { maxlength = 45, propweight = 0.9 }, -- at base caliber
} )

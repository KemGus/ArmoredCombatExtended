-- Unified scalable gun class. Breech autoloaders split from the drum
-- autoloader class: consistent cyclic fire instead of a burst drum, heavier
-- mechanism. Shares the autoloader ammo family so drums and breeches feed
-- from the same rounds. See lua/ace/shared/sh_ace_gunpack.lua for the
-- scaling math and ace_legacy_gun_aliases.lua for legacy id resolution.
-- Pivot spec: 120mmBAL (12.0cm, 4700kg). Scaling is relative to these base values.
ACE.DefineGunClass("BAL", {
	type = "Gun",
	spread = 0.12,
	desc = ACE.Translation.GunClasses[3],
	muzzleflash = "C", -- muzzle-flash effect preset, matched by class tag in the
		-- ace_muzzleflash effect. Cannon-class tag "C" gives the big gunflash+smoke
		-- burst; the other presets are "AC" (autocannon, smaller rapid flash),
		-- "MG" (machine gun, small flash), "MO" (mortar, minimal), "RAC"
		-- (rotary, rapid small flashes). Example: a small 20mm autocannon uses
		-- "AC" because the full cannon flash would swallow the model; this class
		-- keeps "C" even at small calibers because a breech autoloader is always
		-- a heavy tank gun — scale the caliber down and the effect scales with
		-- the gun caliber automatically.
	rofmod = 1.2,
	sound = "ace_weapons/multi_sound/120mm_multi.mp3",
	autosound = "acf_extra/tankfx/reload.wav",
	noloader = true,
	name = "Breech Autoloader",
	ammofamily = "AL", -- cross-feeds with drum autoloaders

		-- Scaling envelope: the caliber/length slider ranges in the spawn menu.
	-- caliber is in cm; length is in L/d (calibers — barrel length as a
	-- multiple of bore diameter, so L/45 on a 120mm gun is a 5.4m tube);
	-- mass in kg at the pivot spec. tubefrac is the fraction of mass in the
	-- barrel tube (tube mass scales with bore area x length, everything else
	-- with volume); massoverhead is the fixed mechanism floor that never
	-- scales. The full mass law is documented in sh_ace_gunpack.lua.
	model        = "models/tankgun_new/tankgun_120mm.mdl",
	caliber      = { base = 12, min = 5, max = 20 }, -- cm
	length       = { base = 45, min = 30, max = 70 }, -- L/d
	mass         = 4700, -- kg at base caliber + base length
	tubefrac     = 0.44, -- fraction of total mass in the barrel tube; tube mass scales with bore area x length, the rest with volume (Rh-120 L/44->L/55 calibrated)
	massoverhead = 0.08, -- fraction of mass that never scales (mechanism floor, calibrated vs real KwK 36/39/40 weights)
	round        = { maxlength = 115, propweight = 30 }, -- at base caliber
} )

-- Stage-2 unified scalable class. Breech autoloaders split from the drum
-- autoloader class: consistent cyclic fire instead of a burst drum, heavier
-- mechanism. Shares the autoloader ammo family so drums and breeches feed
-- from the same rounds.
-- Base spec: 120mmBAL (12.0cm, 4700kg).
ACE.DefineGunClass("BAL", {
	type = "Gun",
	spread = 0.12,
	desc = ACE.Translation.GunClasses[3],
	muzzleflash = "C",
	rofmod = 1.2,
	autosound = "acf_extra/tankfx/reload.wav",
	noloader = true,
	name = "Breech Autoloader",
	ammofamily = "AL", -- cross-feeds with drum autoloaders

	-- scaling envelope (stage 2)
	model        = "models/tankgun_new/tankgun_120mm.mdl",
	caliber      = { base = 12, min = 5, max = 20 }, -- cm
	length       = { base = 45, min = 30, max = 70 }, -- L/d
	mass         = 4700, -- kg at base caliber + base length
	tubefrac     = 0.44, -- barrel mass fraction (Rh-120 L/44->L/55 calibrated)
	massoverhead = 0.08, -- fraction of mass that never scales (mechanism floor, calibrated vs real KwK 36/39/40 weights)
	round        = { maxlength = 115, propweight = 30 }, -- at base caliber
} )

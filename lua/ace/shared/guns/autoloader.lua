-- Stage-2 unified scalable class. One definition covers the whole caliber
-- and length envelope; legacy per-caliber ids resolve through ACE.LegacyGunAliases.
-- Base spec: 120mmAL (12.0cm, 2700kg).
ACE.DefineGunClass("AL", {
	type = "Gun",
	spread = 0.12,
	desc = ACE.Translation.GunClasses[3],
	muzzleflash = "C",
	rofmod = 0.64,
	year = 1946,
	sound = "ace_weapons/multi_sound/100mm_multi.mp3",
	autosound = "acf_extra/tankfx/reload.wav",
	noloader = true,
	name = "Drum Autoloader",
	magsize = 12, -- rounds at base caliber; scales inverse-sqrt with caliber
	magreload = 35, -- seconds at base caliber; scales with caliber^0.7

	-- scaling envelope (stage 2)
	model        = "models/tankgun/tankgun_al_120mm.mdl",
	caliber      = { base = 12, min = 5, max = 20 }, -- cm
	length       = { base = 45, min = 30, max = 70 }, -- L/d
	mass         = 2700, -- kg at base caliber + base length
	tubefrac     = 0.44, -- barrel mass fraction (Rh-120 L/44->L/55 calibrated)
	massoverhead = 0.08, -- fraction of mass that never scales (mechanism floor, calibrated vs real KwK 36/39/40 weights)
	round        = { maxlength = 115, propweight = 30 }, -- at base caliber
} )

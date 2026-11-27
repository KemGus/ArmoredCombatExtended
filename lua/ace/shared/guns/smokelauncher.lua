-- Stage-2 unified scalable class. One definition covers the whole caliber
-- and length envelope; legacy per-caliber ids resolve through ACE.LegacyGunAliases.
-- Base spec: 40mmSL (4.0cm, 1kg).
ACE.DefineGunClass("SL", {
	type		= "Gun",
	spread		= 0.2,
	name		= "Smoke Launcher",
	desc		= ACE.Translation.GunClasses[14],
	muzzleflash = "MO",
	rofmod		= 50,
	year		= 1941,
	sound		= "ace_weapons/multi_sound/smoke_multi.mp3",
	nolights	= true,

	-- scaling envelope (stage 2)
	model        = "models/launcher/40mmsl.mdl",
	caliber      = { base = 4, min = 2, max = 5 }, -- cm
	mass         = 1, -- kg at base caliber + base length
	tubefrac     = 0.44, -- barrel mass fraction (Rh-120 L/44->L/55 calibrated)
	massoverhead = 0.08, -- fraction of mass that never scales (mechanism floor, calibrated vs real KwK 36/39/40 weights)
	round        = { maxlength = 17.5, propweight = 0.007 }, -- at base caliber
} )

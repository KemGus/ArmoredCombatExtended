-- Stage-2 unified scalable class. One definition covers the whole caliber
-- and length envelope; legacy per-caliber ids resolve through ACE.LegacyGunAliases.
-- Base spec: 40mmGL (4.0cm, 55kg).
ACE.DefineGunClass("GL", {
	type = "Gun",
	spread = 0.4,
	name = "Grenade Launcher",
	desc = ACE.Translation.GunClasses[6],
	muzzleflash = "MO",
	rofmod = 1,
	year = 1970,
	sound = "ace_weapons/multi_sound/12_7mm_multi.mp3",
	nolights	= true,
	noloader = true,
	magsize = 48, -- rounds at base caliber; scales inverse-sqrt with caliber
	magreload = 7.5, -- seconds at base caliber; scales with caliber^0.7

	-- scaling envelope (stage 2)
	model        = "models/launcher/40mmgl.mdl",
	caliber      = { base = 4, min = 3.01, max = 5 }, -- cm
	mass         = 55, -- kg at base caliber + base length
	tubefrac     = 0.44, -- barrel mass fraction (Rh-120 L/44->L/55 calibrated)
	massoverhead = 0.08, -- fraction of mass that never scales (mechanism floor, calibrated vs real KwK 36/39/40 weights)
	round        = { maxlength = 7.5, propweight = 0.01 }, -- at base caliber
} )

-- Stage-2 unified scalable class. One definition covers the whole caliber
-- and length envelope; legacy per-caliber ids resolve through ACE.LegacyGunAliases.
-- Base spec: 40mmAC (4.0cm, 425kg).
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

	-- scaling envelope (stage 2)
	model        = "models/autocannon/autocannon_40mm.mdl",
	caliber      = { base = 4, min = 2, max = 5 }, -- cm
	mass         = 425, -- kg at base caliber + base length
	tubefrac     = 0.44, -- barrel mass fraction (Rh-120 L/44->L/55 calibrated)
	massoverhead = 0.08, -- fraction of mass that never scales (mechanism floor, calibrated vs real KwK 36/39/40 weights)
	round        = { maxlength = 45, propweight = 0.9 }, -- at base caliber
} )

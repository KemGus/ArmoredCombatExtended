-- Stage-2 unified scalable class. One definition covers the whole caliber
-- and length envelope; legacy per-caliber ids resolve through ACE.LegacyGunAliases.
-- Base spec: 20mmRAC (2.0cm, 1220kg).
ACE.DefineGunClass("RAC", {
		type = "Gun",
		spread = 0.2,
		name = "Rotary Autocannon",
		desc = ACE.Translation.GunClasses[11],
		muzzleflash = "RAC",
		rofmod = 0.07,
		year = 1962,
		sound = "weapons/acf_gun/mg_fire2.wav",
		noloader = true,

		color = {135, 135, 135},

	-- scaling envelope (stage 2)
	model        = "models/rotarycannon/kw/20mmrac.mdl",
	caliber      = { base = 2, min = 1.45, max = 3 }, -- cm
	mass         = 1220, -- kg at base caliber + base length
	tubefrac     = 0.44, -- barrel mass fraction (Rh-120 L/44->L/55 calibrated)
	massoverhead = 0.08, -- fraction of mass that never scales (mechanism floor, calibrated vs real KwK 36/39/40 weights)
	round        = { maxlength = 36, propweight = 0.12 }, -- at base caliber
} )

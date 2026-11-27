-- Stage-2 unified scalable class. One definition covers the whole caliber
-- and length envelope; legacy per-caliber ids resolve through ACE.LegacyGunAliases.
-- Base spec: 57mmSA (5.7cm, 780kg).
ACE.DefineGunClass("SA", {
	type = "Gun",
	spread = 0.15,
	name = "Semiautomatic Cannon",
	desc = ACE.Translation.GunClasses[12],
	muzzleflash = "AC",
	rofmod = 0.5,
	year = 1935,
	sound = "ace_weapons/multi_sound/20mm_multi.mp3",
	noloader = true,
	magsize = 12, -- rounds at base caliber; scales inverse-sqrt with caliber
	magreload = 9, -- seconds at base caliber; scales with caliber^0.7

	-- scaling envelope (stage 2)
	model        = "models/autocannon/semiautocannon_57mm.mdl",
	caliber      = { base = 5.7, min = 2.5, max = 7.62 }, -- cm
	length       = { base = 45, min = 30, max = 70 }, -- L/d
	mass         = 780, -- kg at base caliber + base length
	tubefrac     = 0.44, -- barrel mass fraction (Rh-120 L/44->L/55 calibrated)
	massoverhead = 0.08, -- fraction of mass that never scales (mechanism floor, calibrated vs real KwK 36/39/40 weights)
	round        = { maxlength = 62, propweight = 2 }, -- at base caliber
} )

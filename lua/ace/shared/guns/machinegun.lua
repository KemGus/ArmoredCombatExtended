-- Stage-2 unified scalable class. One definition covers the whole caliber
-- and length envelope; legacy per-caliber ids resolve through ACE.LegacyGunAliases.
-- Base spec: 12.7mmMG (1.3cm, 20kg).
ACE.DefineGunClass("MG", {
	type = "Gun",
	spread = 0.13,
	name = "Machinegun",
	desc = ACE.Translation.GunClasses[9],
	muzzleflash = "MG",
	rofmod = 0.9,
	year = 1910,
	sound = "ace_weapons/multi_sound/7_62mm_multi.mp3",
	noloader = true,

	-- scaling envelope (stage 2)
	model        = "models/machinegun/machinegun_127mm.mdl",
	caliber      = { base = 1.27, min = 0.762, max = 2.5 }, -- cm
	mass         = 20, -- kg at base caliber + base length
	tubefrac     = 0.44, -- barrel mass fraction (Rh-120 L/44->L/55 calibrated)
	massoverhead = 0.08, -- fraction of mass that never scales (mechanism floor, calibrated vs real KwK 36/39/40 weights)
	round        = { maxlength = 24, propweight = 0.1 }, -- at base caliber
} )

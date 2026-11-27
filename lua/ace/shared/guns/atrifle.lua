-- Stage-2 unified scalable class. One definition covers the whole caliber
-- and length envelope; legacy per-caliber ids resolve through ACE.LegacyGunAliases.
-- Base spec: 14.5mmATR (1.4cm, 15kg).
ACE.DefineGunClass("ATR", {
	type = "Gun",
	spread = 0.01,
	name = "Anti-Tank Rifle",
	desc = ACE.Translation.GunClasses[1],
	muzzleflash = "MG",
	rofmod = 10,
	year = 1917,
	sound = "ace_weapons/multi_sound/7_62mm_multi.mp3",

	-- scaling envelope (stage 2)
	model        = "models/machinegun/machinegun_145mm.mdl",
	caliber      = { base = 1.45, min = 0.792, max = 2 }, -- cm
	mass         = 15, -- kg at base caliber + base length
	tubefrac     = 0.44, -- barrel mass fraction (Rh-120 L/44->L/55 calibrated)
	massoverhead = 0.08, -- fraction of mass that never scales (mechanism floor, calibrated vs real KwK 36/39/40 weights)
	round        = { maxlength = 21, propweight = 3.8 }, -- at base caliber
} )

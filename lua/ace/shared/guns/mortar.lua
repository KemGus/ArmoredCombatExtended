-- Stage-2 unified scalable class. One definition covers the whole caliber
-- and length envelope; legacy per-caliber ids resolve through ACE.LegacyGunAliases.
-- Base spec: 120mmM (12.0cm, 440kg).
ACE.DefineGunClass("MO", {
	type = "Gun",
	spread = 0.5,
	name = "Mortar",
	desc = ACE.Translation.GunClasses[10],
	muzzleflash = "MO",
	rofmod = 2,
	maxrof = 35, -- maximum rounds per minute
	year = 1915,
	sound = "ace_weapons/multi_sound/40mm_multi.mp3",

	-- scaling envelope (stage 2)
	model        = "models/mortar/mortar_120mm.mdl",
	caliber      = { base = 12, min = 5, max = 38 }, -- cm
	mass         = 440, -- kg at base caliber + base length
	tubefrac     = 0.44, -- barrel mass fraction (Rh-120 L/44->L/55 calibrated)
	massoverhead = 0.08, -- fraction of mass that never scales (mechanism floor, calibrated vs real KwK 36/39/40 weights)
	round        = { maxlength = 180, propweight = 0.9 }, -- at base caliber
} )

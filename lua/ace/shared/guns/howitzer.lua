-- Stage-2 unified scalable class. One definition covers the whole caliber
-- and length envelope; legacy per-caliber ids resolve through ACE.LegacyGunAliases.
-- Base spec: 155mmHW (15.5cm, 2100kg).
ACE.DefineGunClass("HW", {
	type = "Gun",
	spread = 0.15,
	name = "Howitzer",
	desc = ACE.Translation.GunClasses[8],
	muzzleflash = "C",
	rofmod = 1.5,
	maxrof = 20, -- maximum rounds per minute
	year = 1900,
	sound = "ace_weapons/multi_sound/howitzer_multi.mp3",

	-- scaling envelope (stage 2)
	model        = "models/howitzer/howitzer_155mm.mdl",
	caliber      = { base = 15.5, min = 7.5, max = 40.6 }, -- cm
	length       = { base = 30, min = 20, max = 40 }, -- L/d
	mass         = 2100, -- kg at base caliber + base length
	tubefrac     = 0.44, -- barrel mass fraction (Rh-120 L/44->L/55 calibrated)
	massoverhead = 0.08, -- fraction of mass that never scales (mechanism floor, calibrated vs real KwK 36/39/40 weights)
	round        = { maxlength = 124, propweight = 13.5 }, -- at base caliber
} )

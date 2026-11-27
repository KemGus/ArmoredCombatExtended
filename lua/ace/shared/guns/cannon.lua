-- Stage-2 unified scalable class. One definition covers the whole caliber
-- and length envelope; legacy per-caliber ids resolve through ACE.LegacyGunAliases.
-- Base spec: 120mmC (12.0cm, 2100kg).
ACE.DefineGunClass("C", {
	type = "Gun",
	spread = 0.1,
	name = "Cannon",
	desc = ACE.Translation.GunClasses[4],
	muzzleflash = "C",
	rofmod = 1.5,
	maxrof = 19, -- maximum rounds per minute
	sound = "ace_weapons/multi_sound/100mm_multi.mp3",

	-- scaling envelope (stage 2)
	model        = "models/tankgun/tankgun_120mm.mdl",
	caliber      = { base = 12, min = 3.7, max = 20 }, -- cm
	length       = { base = 45, min = 15, max = 70 }, -- L/d; short end absorbs the retired shortcannon class
	mass         = 2100, -- kg at base caliber + base length
	tubefrac     = 0.44, -- barrel mass fraction (Rh-120 L/44->L/55 calibrated)
	massoverhead = 0.08, -- fraction of mass that never scales (mechanism floor, calibrated vs real KwK 36/39/40 weights)
	round        = { maxlength = 110, propweight = 18 }, -- at base caliber
} )

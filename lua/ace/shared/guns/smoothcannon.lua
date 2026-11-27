-- Stage-2 unified scalable class. One definition covers the whole caliber
-- and length envelope; legacy per-caliber ids resolve through ACE.LegacyGunAliases.
-- Base spec: 120mmSBC (12.0cm, 2286kg).
ACE.DefineGunClass("SBC", {
	type = "Gun",
	spread = 0.12,
	name = "Smooth-Bore Cannon",
	desc = ACE.Translation.GunClasses[15],
	muzzleflash = "C",
	rofmod = 1.7,
	maxrof = 20, -- maximum rounds per minute
	sound = "ace_weapons/multi_sound/120mm_multi.mp3",
	year = 1960,

	-- scaling envelope (stage 2)
	model        = "models/tankgun_new/tankgun_120mm.mdl",
	caliber      = { base = 12, min = 10, max = 20 }, -- cm
	length       = { base = 48, min = 30, max = 70 }, -- L/d
	mass         = 2286, -- kg at base caliber + base length
	tubefrac     = 0.44, -- barrel mass fraction (Rh-120 L/44->L/55 calibrated)
	massoverhead = 0.08, -- fraction of mass that never scales (mechanism floor, calibrated vs real KwK 36/39/40 weights)
	round        = { maxlength = 115, propweight = 30 }, -- at base caliber
} )

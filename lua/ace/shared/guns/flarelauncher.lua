-- Stage-2 unified scalable class. One definition covers the whole caliber
-- and length envelope; legacy per-caliber ids resolve through ACE.LegacyGunAliases.
-- Base spec: 40mmFGL (4.0cm, 75kg).
ACE.DefineGunClass("FGL", {
	type = "Gun",
	spread = 3,
	name = "Flare Launcher",
	desc = ACE.Translation.GunClasses[5],
	muzzleflash = "MO",
	rofmod = 0.6,
	year = 1970,
	sound = "acf_new/weapons/skyfire/close/close (1).wav",

	ammoBlacklist	= {"AP", "APHE", "FL", "HE", "HEAT", "HP", "SM"}, -- ok fun's over
	magsize = 30, -- rounds at base caliber; scales inverse-sqrt with caliber
	magreload = 30, -- seconds at base caliber; scales with caliber^0.7

	-- scaling envelope (stage 2)
	model        = "models/missiles/blackjellypod.mdl",
	caliber      = { base = 4, min = 4, max = 7.5 }, -- cm
	mass         = 75, -- kg at base caliber + base length
	tubefrac     = 0.44, -- barrel mass fraction (Rh-120 L/44->L/55 calibrated)
	massoverhead = 0.08, -- fraction of mass that never scales (mechanism floor, calibrated vs real KwK 36/39/40 weights)
	round        = { maxlength = 9, propweight = 0.007 }, -- at base caliber
} )

-- Stage-2 unified scalable class. One definition covers the whole caliber
-- and length envelope; legacy per-caliber ids resolve through ACE.LegacyGunAliases.
-- Base spec: 30mmHMG (3.0cm, 150kg).
ACE.DefineGunClass("HMG", {
	type = "Gun",
	spread = 0.17,
	name = "Heavy Machinegun",
	desc = ACE.Translation.GunClasses[7],
	muzzleflash = "MG",
	rofmod = 0.16,
	year = 1935,
	sound = "ace_weapons/multi_sound/30mm_hmg_multi.mp3",
	noloader = true,

	longbarrel = {
		index = 2,
		submodel = 4,
		newpos = "muzzle2"
	},
	magsize = 50, -- rounds at base caliber; scales inverse-sqrt with caliber
	magreload = 6, -- seconds at base caliber; scales with caliber^0.7

	-- scaling envelope (stage 2)
	model        = "models/machinegun/machinegun_30mm_compact.mdl",
	caliber      = { base = 3, min = 2, max = 4 }, -- cm
	mass         = 150, -- kg at base caliber + base length
	tubefrac     = 0.44, -- barrel mass fraction (Rh-120 L/44->L/55 calibrated)
	massoverhead = 0.08, -- fraction of mass that never scales (mechanism floor, calibrated vs real KwK 36/39/40 weights)
	round        = { maxlength = 39, propweight = 0.35 }, -- at base caliber
} )

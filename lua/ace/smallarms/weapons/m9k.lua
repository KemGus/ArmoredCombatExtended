-- M9K Assault Rifles, Heavy Weapons and Small Arms packs (Workshop 128089118, 128091208, 128093075).
-- Class names from the packs' lua/weapons. M9K fires through Owner:FireBullets and does its penetration
-- and ricochet in the bullet callback, which never runs once the shot is replaced, so no patch is needed.
-- Specialties (explosives, melee) are left out.
local SetWeaponRound = ACE.SmallArms.SetWeaponRound

local Rounds = {
	-- Assault Rifles
	m9k_acr = "5.56x45", m9k_ak47 = "7.62x39", m9k_ak74 = "5.45x39", m9k_amd65 = "7.62x39",
	m9k_an94 = "5.45x39", m9k_auga3 = "5.56x45", m9k_f2000 = "5.56x45", m9k_fal = "7.62x51",
	m9k_famas = "5.56x45", m9k_g36 = "5.56x45", m9k_g3a3 = "7.62x51", m9k_l85 = "5.56x45",
	m9k_m14sp = "7.62x51", m9k_m16a4_acog = "5.56x45", m9k_m416 = "5.56x45", m9k_m4a1 = "5.56x45",
	m9k_scar = "7.62x51", m9k_tar21 = "5.56x45", m9k_val = "9x39", m9k_vikhr = "9x39",
	m9k_winchester73 = ".44-40",

	-- Heavy Weapons
	m9k_ares_shrike = "5.56x45", m9k_aw50 = ".50BMG", m9k_barret_m82 = ".50BMG", m9k_contender = ".30-30",
	m9k_dragunov = "7.62x54R", m9k_fg42 = "7.92x57", m9k_intervention = ".408CT", m9k_m1918bar = ".30-06",
	m9k_m24 = "7.62x51", m9k_m249lmg = "5.56x45", m9k_m60 = "7.62x51", m9k_m98b = ".338LM",
	m9k_minigun = "7.62x51", m9k_pkm = "7.62x54R", m9k_psg1 = "7.62x51", m9k_remington7615p = "5.56x45",
	m9k_sl8 = "5.56x45", m9k_svt40 = "7.62x54R", m9k_svu = "7.62x54R",

	-- Shotguns (one round per pellet)
	m9k_1887winchester = "12ga_00", m9k_1897winchester = "12ga_00", m9k_browningauto5 = "12ga_00",
	m9k_dbarrel = "12ga_00", m9k_ithacam37 = "12ga_00", m9k_jackhammer = "12ga_00", m9k_m3 = "12ga_00",
	m9k_mossberg590 = "12ga_00", m9k_remington870 = "12ga_00", m9k_spas12 = "12ga_00",
	m9k_striker12 = "12ga_00", m9k_usas = "12ga_00",

	-- Small Arms
	m9k_bizonp19 = "9x18", m9k_colt1911 = ".45ACP", m9k_coltpython = ".357", m9k_deagle = ".50AE",
	m9k_glock = "9x19", m9k_hk45 = ".45ACP", m9k_honeybadger = ".300BLK", m9k_kac_pdw = "5.56x45",
	m9k_luger = "9x19", m9k_m29satan = ".44Mag", m9k_m92beretta = "9x19", m9k_magpulpdr = "5.56x45",
	m9k_model3russian = ".44Russian", m9k_model500 = ".500SW", m9k_model627 = ".357", m9k_mp40 = "9x19",
	m9k_mp5 = "9x19", m9k_mp5sd = "9x19", m9k_mp7 = "4.6x30", m9k_mp9 = "9x19", m9k_ragingbull = ".454",
	m9k_remington1858 = ".44Russian", m9k_scoped_taurus = ".454", m9k_sig_p229r = ".357",
	m9k_smgp90 = "5.7x28", m9k_sten = "9x19", m9k_tec9 = "9x19", m9k_thompson = ".45ACP",
	m9k_ump45 = ".45ACP", m9k_usc = ".45ACP", m9k_usp = "9x19", m9k_uzi = "9x19", m9k_vector = ".45ACP",
}

for Class, Round in pairs(Rounds) do
	SetWeaponRound(Class, Round)
end

AddCSLuaFile()

-- ACE weapons that NPCs can hold. Lock-on launchers (javelin, stinger), mines,
-- tools and utility items are left out on purpose.
local npcWeapons = {
	{ class = "weapon_ace_ak47", title = "ACE AK-47" },
	{ class = "weapon_ace_m16", title = "ACE M16" },
	{ class = "weapon_ace_m249saw", title = "ACE M249 SAW" },
	{ class = "weapon_ace_mp5", title = "ACE MP5" },
	{ class = "weapon_ace_p90", title = "ACE P90" },
	{ class = "weapon_ace_awp", title = "ACE AWP" },
	{ class = "weapon_ace_scout", title = "ACE Scout" },
	{ class = "weapon_ace_amr", title = "ACE AMR" },
	{ class = "weapon_ace_m3super90", title = "ACE M3 Super 90" },
	{ class = "weapon_ace_xm1014", title = "ACE XM1014" },
	{ class = "weapon_ace_xm25", title = "ACE XM25" },
	{ class = "weapon_ace_deagle", title = "ACE Desert Eagle" },
	{ class = "weapon_ace_glock", title = "ACE Glock" },
	{ class = "weapon_ace_usp", title = "ACE USP" },
	{ class = "weapon_ace_p228", title = "ACE P228" },
	{ class = "weapon_ace_fiveseven", title = "ACE Five-SeveN" },
	{ class = "weapon_ace_elite", title = "ACE Dual Elites" },
	{ class = "weapon_ace_tmp", title = "ACE TMP" },
	{ class = "weapon_ace_mac10", title = "ACE MAC-10" },
	{ class = "weapon_ace_ump45", title = "ACE UMP45" },
	{ class = "weapon_ace_aug", title = "ACE AUG" },
	{ class = "weapon_ace_famas", title = "ACE FAMAS" },
	{ class = "weapon_ace_galil", title = "ACE Galil" },
	{ class = "weapon_ace_sg552", title = "ACE SG552" },
	{ class = "weapon_ace_at4", title = "ACE AT4" },
	{ class = "weapon_ace_grenade", title = "ACE HE Grenade" },
}

for _, entry in ipairs(npcWeapons) do
	list.Add("NPCUsableWeapons", entry)
end

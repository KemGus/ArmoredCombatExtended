-- Half-Life 2 weapons. NPCs carrying these (Combine soldiers, metrocops, rebels) fire ACE bullets too.
-- The crossbow, RPG and grenades aren't bullets and are left alone.
local SetWeaponRound = ACE.SmallArms.SetWeaponRound

SetWeaponRound("weapon_pistol",  "9x19")
SetWeaponRound("weapon_357",     ".357")
SetWeaponRound("weapon_smg1",    "4.6x30")
SetWeaponRound("weapon_ar2",     "5.56x45") -- the pulse rifle has no real-world round
SetWeaponRound("weapon_shotgun", "12ga_00")

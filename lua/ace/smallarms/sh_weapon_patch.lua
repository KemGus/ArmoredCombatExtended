-- Turns off each base's own bullet simulation on opted-in weapons, so every shot goes through
-- Entity:FireBullets, where sh_firebullets.lua replaces it with an ACE bullet.
local SmallArms = ACE.SmallArms

local Patch = {
	NeverPhysBullet  = true,  -- ArcCW (sh_firing.lua DoPrimaryFire) and ARC9 (sh_shoot.lua DoProjectileAttack)
	AlwaysPhysBullet = false, -- ARC9
	CanPenetrate     = false, -- CW 2.0 re-fires FireBullets for its own penetration
	CanRicochet      = false, -- CW 2.0 ricochet re-fire
	UseBallistics    = false, -- TFA (tfa_ballistics.lua ShouldUse)
}

--- Applies the bullet patch to one weapon class if it has opted in.
-- @tparam string class Weapon class.
-- @realm shared
function SmallArms.PatchWeaponClass(class)
	local Stored = weapons.GetStored(class)
	if not Stored or not SmallArms.GetClassRound(class) then return end

	for Key, Value in pairs(Patch) do
		Stored[Key] = Value
	end
end

hook.Add("Initialize", "ACE_SmallArms_PatchWeapons", function()
	for _, Swep in ipairs(weapons.GetList()) do
		SmallArms.PatchWeaponClass(Swep.ClassName)
	end
end)

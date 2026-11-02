-- One hook for every base: opted-in weapons have their FireBullets call replaced by ACE bullets.
-- Runs in both realms so the client doesn't draw the base's hitscan tracers and impacts.
local SmallArms = ACE.SmallArms

local function GetFiringWeapon(Ent, Data)
	local Inflictor = Data.Inflictor
	if IsValid(Inflictor) and Inflictor:IsWeapon() then return Inflictor end
	if Ent:IsWeapon() then return Ent end
	if Ent.GetActiveWeapon then return Ent:GetActiveWeapon() end
end

--- Returns the damage the weapon pack would have dealt with this shot.
-- @tparam Weapon wep The weapon firing.
-- @tparam table data The FireBullets table.
-- @treturn number The pack damage.
-- @realm server
function SmallArms.GetPackDamage(wep, data)
	-- ARC9 and ArcCW set the real damage in their bullet callback, not in the table.
	if wep.ARC9 and wep.GetProcessedValue then return wep:GetProcessedValue("DamageMax", true) end
	if wep.ArcCW and wep.GetDamage then return wep:GetDamage(0) end

	-- Engine weapons (HL2) leave Damage at 0 and take it from the ammo type.
	local Damage = data.Damage or 0
	if Damage == 0 and data.AmmoType then
		local AmmoID = game.GetAmmoID(data.AmmoType)
		if AmmoID > 0 then
			local Owner = wep:GetOwner()
			Damage = IsValid(Owner) and Owner:IsNPC() and game.GetAmmoNPCDamage(AmmoID) or game.GetAmmoPlayerDamage(AmmoID)
		end
	end

	return Damage
end

-- Hooks that only listen for shots (gunshot sounds, reverb). Returning false stops every hook after
-- ours, so these are handed the shot before it's cancelled.
local ShotListeners = {
	"dwr_EntityFireBullets", -- Dynamic Weapon Reverb
}

local function NotifyListeners(Ent, Data)
	local Hooks = hook.GetTable().EntityFireBullets
	if not Hooks then return end

	for _, Name in ipairs(ShotListeners) do
		local Listener = Hooks[Name]
		if Listener then Listener(Ent, Data) end
	end
end

hook.Add("EntityFireBullets", "ACE_SmallArms", function(Ent, Data)
	if not SmallArms.Enabled:GetBool() then return end

	local Wep = GetFiringWeapon(Ent, Data)
	local Round = SmallArms.GetWeaponRound(Wep)
	if not Round then return end

	if CLIENT then return false end

	NotifyListeners(Ent, Data)

	local Owner = Ent:IsWeapon() and Wep:GetOwner() or Ent
	local Damage = SmallArms.GetPackDamage(Wep, Data)

	local Dir = Data.Dir:GetNormalized()
	local Ang = Dir:Angle()
	local Right, Up = Ang:Right(), Ang:Up()
	local Spread = Data.Spread or vector_origin

	for _ = 1, math.max(Data.Num or 1, 1) do
		local ShotDir = Dir + Right * (Spread.x * math.Rand(-1, 1)) + Up * (Spread.y * math.Rand(-1, 1))
		ShotDir:Normalize()

		SmallArms.Fire(Wep, Owner, Data.Src, ShotDir, Round, Damage)
	end

	return false
end)

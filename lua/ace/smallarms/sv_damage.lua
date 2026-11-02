-- Damage to players and NPCs. ACE always decides whether the round gets through armor and cover.
-- ace_smallarms_damage "pack" (default): the HP taken is the weapon pack's own damage times a hitgroup multiplier,
-- scaled by the share of the round's energy that got through body armor. A round the armor stopped keeps ACE's
-- blunt damage.
-- ace_smallarms_damage "ace": pure ACE damage from caliber and energy (ACE.SquishyDamage as is).
local DamageMode = ACE.SmallArms.DamageMode

-- Matches the hitgroup weighting in ACE.SquishyDamage.
local HitgroupMul = {
	[HITGROUP_HEAD]     = 2.5,
	[HITGROUP_LEFTARM]  = 0.5,
	[HITGROUP_RIGHTARM] = 0.5,
	[HITGROUP_LEFTLEG]  = 0.7,
	[HITGROUP_RIGHTLEG] = 0.7,
	[HITGROUP_GEAR]     = 0.7,
}

local PendingDamage, PendingDir
local PendingThrough -- Share of the round's energy body armor let through, 1 with no armor
local PendingArmored -- True when a non-suit layer took the hit, for the ace_bodyarmor_min_damage floor

hook.Add("Initialize", "ACE_SmallArms_DamageMode", function()
	local SquishyDamage = ACE.SquishyDamage
	if not SquishyDamage then
		ErrorNoHalt("[ACE Small Arms] ACE.SquishyDamage not found, pack damage mode is disabled.\n")
		return
	end

	function ACE.SquishyDamage(Entity, Energy, FrArea, Angle, Inflictor, Bone, Gun, Type, ...)
		if not IsValid(Gun) or not Gun.ACE_SmallArms_Damage then
			return SquishyDamage(Entity, Energy, FrArea, Angle, Inflictor, Bone, Gun, Type, ...)
		end

		-- TakeDamage carries no force, which spams AddMultiDamage warnings and leaves ragdolls still.
		PendingDir = (Entity:WorldSpaceCenter() - Gun:GetPos()):GetNormalized()
		PendingDamage = DamageMode:GetString() ~= "ace" and Gun.ACE_SmallArms_Damage * (HitgroupMul[Bone] or 1) or nil
		PendingThrough = 1
		local HitRes = SquishyDamage(Entity, Energy, FrArea, Angle, Inflictor, Bone, Gun, Type, ...)
		PendingDamage, PendingDir, PendingThrough, PendingArmored = nil, nil, nil, nil

		return HitRes
	end

	-- ACE builds without body armor have no ResolveBodyArmor, and every round gets through
	local ResolveBodyArmor = ACE.ResolveBodyArmor
	if not ResolveBodyArmor then return end

	function ACE.ResolveBodyArmor(Entity, Hitgroup, Energy, ...)
		local Left, BluntJ, Layer = ResolveBodyArmor(Entity, Hitgroup, Energy, ...)

		if PendingThrough then
			local Kinetic = Energy.Kinetic or 0
			PendingThrough = not Left and 0 or (Kinetic > 0 and Left.Kinetic / Kinetic or 1)
			-- Same test ACE.FleshDamage makes for the ace_bodyarmor_min_damage floor.
			PendingArmored = (Left and Left.Armored) or (Layer and not Layer.Suit) and true or nil
		end

		return Left, BluntJ, Layer
	end
end)

-- SquishyDamage applies its damage with Entity:TakeDamage; swap in the pack value when armor didn't stop it.
hook.Add("EntityTakeDamage", "ACE_SmallArms_PackDamage", function(_, DmgInfo)
	if not PendingDir then return end

	if PendingDamage and PendingThrough > 0 and DmgInfo:GetDamage() > 0 then
		-- Lazy: an older ACE has no ace_bodyarmor_min_damage, and then armored hits keep no floor.
		local ConVar = GetConVar and GetConVar("ace_bodyarmor_min_damage")
		local Damage = PendingDamage * PendingThrough

		if PendingArmored and ConVar and Damage < ConVar:GetFloat() then Damage = 0 end
		DmgInfo:SetDamage(Damage)
	end

	DmgInfo:SetDamageForce(PendingDir * DmgInfo:GetDamage() * 300) -- about what a hitscan bullet pushes
	PendingDamage, PendingDir, PendingArmored = nil, nil, nil
end)

-- Shows the round's caliber, muzzle velocity and penetration when an opted-in gun is drawn, like the
-- ACE SWEPs do. Client-only and off by default.
local SmallArms = ACE.SmallArms

SmallArms.ShowStats = CreateClientConVar("ace_smallarms_showstats", "0", true, false,
	"Show caliber, muzzle velocity and penetration when drawing a gun that fires ACE bullets", 0, 1)

local function GetStatText(Round)
	-- The round's name (7.62x39), not its caliber field, which is the real bullet diameter (7.9mm).
	local Name = Round.id or string.format("%smm", Round.caliber)

	return string.format("%s AP ammo: %im/s speed, %.1fmm pen", Name, Round.muzzleVel, SmallArms.GetMaxPen(Round))
end

local LastWeapon

hook.Add("Think", "ACE_SmallArms_ShowStats", function()
	if not SmallArms.ShowStats:GetBool() or not SmallArms.Enabled:GetBool() then
		LastWeapon = nil
		return
	end

	local Ply = LocalPlayer()
	if not IsValid(Ply) then return end

	local Wep = Ply:GetActiveWeapon()
	if Wep == LastWeapon then return end
	LastWeapon = Wep

	local Round = SmallArms.GetWeaponRound(Wep)
	if Round then notification.AddLegacy(GetStatText(Round), NOTIFY_GENERIC, 10) end
end)

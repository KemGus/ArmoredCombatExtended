SWEP.Base = weapons.Get("homigrad_base") and "homigrad_base" or "weapon_ace_base"
SWEP.PrintName = "ACE-Homigrad Hybrid Base"
SWEP.Category = "ACE - Special"
SWEP.Purpose = "Z-City UX layer over ACE ballistics: homigrad handling (aim gates, fake bodies, reloads) with ACE.CreateBullet doing the shooting."
SWEP.Author = "\n Kemgus"
SWEP.Spawnable = false
SWEP.WorkWithFake = true

-- Scope/zoom support. On homigrad, IsZoom (hold-RMB ADS) is the zoom state and
-- their optics render picks up ZoomFOV/FOVScoped automatically for ishgwep
-- weapons. On the ace_base fallback, GetZoomState drives it instead.
SWEP.HasScope = false
SWEP.ZoomFOV = 60

function SWEP:AdjustMouseSensitivity()
	local zoomed = (self.GetZoomState and self:GetZoomState()) or (self.IsZoom and self:IsZoom())
	if not zoomed then return end

	local cvar = self.HasScope and GetConVar("ace_sens_scopes") or GetConVar("ace_sens_irons")
	return cvar and cvar:GetFloat()
end

function SWEP:InitBulletData()
	self.BulletData = {}
end

function SWEP:Initialize()
	-- ACE ballistics state first: it must exist even if upstream init aborts
	self:InitBulletData()

	-- self.BaseClass is the entity's direct base (this file on derived guns),
	-- so hop one link further via baseclass to reach homigrad_base/ace_base
	local myBase = baseclass.Get("weapon_ace_hg_base")
	local upstream = myBase and myBase.BaseClass
	if upstream and upstream.Initialize then upstream.Initialize(self) end

	if SERVER and not IsValid(self.FakeCrate) then
		self.FakeCrate = ents.Create("acf_fakecrate2")

		if IsValid(self.FakeCrate) then
			self.FakeCrate:RegisterTo(self)
			self.BulletData.Crate = self.FakeCrate:EntIndex()
		end
	end
end

-- Replaces homigrad's SWEP:FireBullet (which simulates lua bullets) with an ACE
-- ballistic round. The muzzle still comes from homigrad's trace so shots leave
-- from the fake ragdoll's gun, not the downed player's eye position.
function SWEP:FireBullet()
	if not SERVER then return end
	if not self.BulletData then return end
	if not GetConVar("ace_gunfire"):GetBool() then return end

	local owner = self:GetOwner()
	local ShooterEnt = IsValid(owner) and owner or self
	local pos, dir

	if self.GetTrace then
		self:WorldModel_Transform()
		local _, p, a = self:GetTrace(true)
		pos, dir = p, a and a:Forward()
	else
		pos = ShooterEnt:IsPlayer() and ShooterEnt:GetShootPos() or self:GetPos()
		dir = ShooterEnt:IsPlayer() and ShooterEnt:GetAimVector() or self:GetForward()
	end

	if not pos or not dir then return end

	-- Primary.Spread is a Vector on zcity weapons, a number on ours
	local spread = (self.Primary and self.Primary.Spread) or 0
	if isvector and isvector(spread) then spread = spread.x end
	if spread > 0 then
		dir = (dir:Angle() + AngleRand(-spread, spread)):Forward()
	end

	self.BulletData.Pos = pos
	self.BulletData.Flight = dir * self.BulletData.MuzzleVel * 39.37
	self.BulletData.Owner = ShooterEnt
	self.BulletData.Gun = self
	self.BulletData.Filter = {ShooterEnt}

	-- The bullet leaves from the fake body's muzzle: don't let it hit the body itself
	if hg and hg.GetCurrentCharacter then
		local char = hg.GetCurrentCharacter(ShooterEnt)
		if IsValid(char) then table.insert(self.BulletData.Filter, char) end
	end

	-- Z-City's organism hook prefers inflictor.bullet.*; the squishy damage
	-- path makes this weapon the inflictor, so publish the round's real ACE
	-- numbers (their Penetration scale is ~mm RHA: 7.62x39 PS = 12.9).
	local data = self.BulletData
	if ACE.CalcPenetration and data.PenArea and data.ProjMass then
		local energy = ACE.Kinetic(data.Flight:Length(), data.ProjMass, data.LimitVel)
		-- Homigrad-shaped too: sv_input re-fires inflictor.bullet through
		-- inf:FireLuaBullets on through-body hits, so Force and friends must exist
		local ammo = hg and hg.ammotypeshuy and self.Primary and hg.ammotypeshuy[self.Primary.Ammo]
		local ammoBullet = ammo and ammo.BulletSettings
		self.bullet = {
			Penetration = ACE.CalcPenetration(energy, data.PenArea),
			Diameter = (data.Caliber or 0) * 10,
			ShockMultiplier = self.ShockMultiplier,
			BleedMultiplier = self.BleedMultiplier,
			Damage = ammoBullet and ammoBullet.Damage or (self.Primary and self.Primary.Damage) or 25,
			Force = (ammoBullet and ammoBullet.Force and ammoBullet.Force / 1.5) or (self.Primary and self.Primary.Force) or 0,
			Speed = ammoBullet and ammoBullet.Speed or data.MuzzleVel,
			Src = pos,
			Dir = dir,
			Attacker = ShooterEnt,
			Num = 1,
			AmmoType = self.Primary and self.Primary.Ammo,
			TracerName = "nil",
			dmgtype = DMG_BULLET,
			penetrated = 0,
			limit_ricochet = 0,
		}
	end

	if self.BeforeFire then self:BeforeFire() end

	hook.Run("ACE_SWEPFired", self, ShooterEnt, self.BulletData)

	ACE.CreateBullet(self.BulletData)
end

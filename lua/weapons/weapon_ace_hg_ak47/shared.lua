SWEP.Base = "weapon_ace_hg_base"
SWEP.PrintName = "AK-47 (ACE-ZC)"
SWEP.Category = "ACE Weapons"
SWEP.SubCategory = "Assault Rifles"
SWEP.Purpose = "Z-City-handled AK firing ACE 7.62 AP ballistics"
SWEP.Spawnable = true
SWEP.Slot = 2

SWEP.WorldModel = "models/weapons/w_rif_ak47.mdl"
SWEP.ViewModel = "models/weapons/v_rif_ak47.mdl"
SWEP.HoldType = "ar2"

-- Muzzle + worldmodel offsets copied from zcity's weapon_akm (same rifle geometry)
SWEP.LocalMuzzlePos = Vector(26.986, -0.2, 2.741)
SWEP.LocalMuzzleAng = Angle(-0.4, 0, 0)
SWEP.WorldPos = Vector(4, -1, -1.5)
SWEP.WorldAng = Angle(0, 0, 0)

-- Homigrad UX block (mirrors zcity's weapon_akm stat card)
SWEP.Primary = SWEP.Primary or {}
SWEP.Primary.ClipSize = 30
SWEP.Primary.DefaultClip = 30
SWEP.Primary.Automatic = true
SWEP.Primary.Ammo = "7.62x39 mm"
SWEP.Primary.Cone = 0
SWEP.Primary.Damage = 50
SWEP.Primary.Spread = 0
SWEP.Primary.Force = 50
SWEP.Primary.Wait = 0.095
SWEP.ShockMultiplier = 2

-- String form: acf_fakecrate2:RegisterTo networks Primary.Sound via SetNWString
SWEP.Primary.Sound = "weapons/newakm/akmm_tp.wav"
SWEP.Primary.SoundFP = {"weapons/newakm/akmm_fp.wav", 85, 90, 100}
SWEP.Primary.SoundEmpty = {"weapons/newakm/akmm_empty.wav", 75, 100, 105, CHAN_WEAPON, 2}
SWEP.DistSound = "weapons/newakm/akmm_dist.wav"

-- homigrad_base reads these in shared/server init (Ergonomics is client-only
-- upstream); values mirrored from zcity's weapon_akm
SWEP.Ergonomics = 0.8
SWEP.Penetration = 15
SWEP.CustomShell = "762x39"
SWEP.RHandPos = Vector(-12, -1, 4)
SWEP.LHandPos = Vector(7, -3, -2)
SWEP.Spray = {}
for i = 1, 30 do
	SWEP.Spray[i] = Angle(-0.02 - math.cos(i) * 0.03, math.cos(i * i) * 0.02, 0) * 2
end

-- ACE ballistics (same BulletData as weapon_ace_ak47)
function SWEP:InitBulletData()
	self.BulletData = {}

	self.BulletData.Id = "7.62mmMG"
	self.BulletData.Type = "AP"
	self.BulletData.Id = 1
	self.BulletData.Caliber = 0.762
	self.BulletData.PropLength = 6
	self.BulletData.ProjLength = 4
	self.BulletData.Data5 = 0
	self.BulletData.Data6 = 0
	self.BulletData.Data7 = 0
	self.BulletData.Data8 = 0
	self.BulletData.Data9 = 0
	self.BulletData.Data10 = 1
	self.BulletData.Colour = Color(0, 255, 0)

	self.BulletData.Data13 = 0
	self.BulletData.Data14 = 0
	self.BulletData.Data15 = 0

	self.BulletData.AmmoType = self.BulletData.Type
	self.BulletData.FrArea = 3.1416 * (self.BulletData.Caliber / 2) ^ 2
	self.BulletData.ProjMass = self.BulletData.FrArea * (self.BulletData.ProjLength * 7.9 / 1000)
	self.BulletData.PropMass = self.BulletData.FrArea * (self.BulletData.PropLength * ACE.PDensity / 1000)
	self.BulletData.DragCoef  = ((self.BulletData.FrArea / 10000) / self.BulletData.ProjMass) / 3

	self.BulletData.MuzzleVel = ACE.MuzzleVelocity(self.BulletData.PropMass, self.BulletData.ProjMass, self.BulletData.Caliber)
	self.BulletData.ShovePower = 0.2
	self.BulletData.KETransfert = 0.3
	self.BulletData.PenArea = self.BulletData.FrArea ^ ACE.PenAreaMod * 1.5
	self.BulletData.Pos = Vector(0, 0, 0)
	self.BulletData.LimitVel = 800
	self.BulletData.Ricochet = 60
	self.BulletData.Flight = Vector(0, 0, 0)
	self.BulletData.BoomPower = self.BulletData.PropMass

	self.Type = self.BulletData.Type
	self.BulletData.Tracer = self.BulletData.Data10
	self.Tracer = self.BulletData.Tracer
	self.Caliber = self.BulletData.Caliber
	self.ProjMass = self.BulletData.ProjMass
	self.FillerMass = self.BulletData.Data5
	self.DragCoef = self.BulletData.DragCoef
	self.Colour = self.BulletData.Colour
end

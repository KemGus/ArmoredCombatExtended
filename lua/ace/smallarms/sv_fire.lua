local SmallArms = ACE.SmallArms

local Templates = {}
local Crates    = {}

-- Builds ACE BulletData once per round, the same way weapon_ace_base InitBulletData does.
local function GetTemplate(Round)
	local Template = Templates[Round]
	if Template then return Template end

	local Caliber  = Round.caliber / 10 -- ACE uses cm
	local FrArea   = math.pi * (Caliber / 2) ^ 2
	local ProjMass = Round.projMass / 1000

	Template = {
		Id          = Round.id or "SmallArms",
		Type        = "AP",
		AmmoType    = "AP",
		Caliber     = Caliber,
		FrArea      = FrArea,
		ProjMass    = ProjMass,
		PropMass    = 0,
		FillerMass  = 0,
		BoomPower   = 0,
		MuzzleVel   = Round.muzzleVel,
		DragCoef    = Round.dragCoef or (FrArea / 10000) / ProjMass,
		LimitVel    = Round.limitVel or 800,
		Ricochet    = Round.ricochet or 60,
		ShovePower  = 0.2,
		KETransfert = 0.3,
		Tracer      = Round.tracer or 0,
		Colour      = Round.colour or Color(255, 200, 120),
	}

	Templates[Round] = Template
	return Template
end

-- One shared fake crate per round drives the client bullet effect.
local function GetCrate(Round, Template)
	local Crate = Crates[Round]
	if IsValid(Crate) then return Crate end

	Crate = ents.Create("acf_fakecrate2")
	Crate:RegisterTo(Template)
	-- RegisterTo stores these as ints; the bullet effect needs the real sub-1 values.
	Crate:SetNWFloat("Caliber", Template.Caliber)
	Crate:SetNWFloat("ProjMass", Template.ProjMass)
	Crate:SetNWFloat("DragCoef", Template.DragCoef)

	Crates[Round] = Crate
	return Crate
end

-- The client bullet effect reads its size from the crate's networked values. A crate made on the first
-- shot hasn't reached the client yet, so that bullet drew at the 100mm default. Make it when the gun is picked up.
hook.Add("WeaponEquip", "ACE_SmallArms_PrepareCrate", function(Wep)
	local Round = SmallArms.GetWeaponRound(Wep)
	if Round then GetCrate(Round, GetTemplate(Round)) end
end)

--- Fires one ACE small-arms bullet.
-- @tparam Weapon wep The weapon firing. Credited as the inflictor.
-- @tparam Entity owner The player or NPC shooting. Credited as the attacker.
-- @tparam Vector pos Start position.
-- @tparam Vector dir Normalized direction.
-- @tparam table round Round definition (see ACE.SmallArms.RegisterRound).
-- @tparam number damage The pack's own damage for this shot, used by the "pack" damage mode.
-- @realm server
function SmallArms.Fire(wep, owner, pos, dir, round, damage)
	if not GetConVar("ace_gunfire"):GetBool() then return end

	local Template = GetTemplate(round)

	-- ACE.CreateBullet copies the table, so the template is reused.
	Template.PenArea = SmallArms.GetPenArea(round) -- not cached: ace_smallarms_penmul can change
	Template.Pos    = pos
	Template.Flight = dir * Template.MuzzleVel * 39.37
	Template.Owner  = owner
	Template.Gun    = wep
	Template.Crate  = GetCrate(round, Template):EntIndex()
	Template.Filter = { owner }

	--- Fires before an ACE small-arms bullet is created.
	-- @tparam Weapon wep The weapon firing.
	-- @tparam Entity owner The shooter.
	-- @tparam table bulletData The ACE bullet data. Pos is the start, Flight the velocity.
	-- @treturn bool|nil Return false to cancel the bullet.
	-- @realm server
	if hook.Run("ACE_SmallArms_PreFire", wep, owner, Template) == false then return end

	wep.ACE_SmallArms_Damage = damage

	ACE.CreateBullet(Template)
end

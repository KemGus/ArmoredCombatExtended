local SmallArms = ACE.SmallArms

SmallArms.Rounds       = SmallArms.Rounds or {}
SmallArms.WeaponRounds = SmallArms.WeaponRounds or {}

--- Registers a small-arms round that weapons can fire through ACE.
-- @tparam string id Unique round name, e.g. "5.56x45".
-- @tparam table def Round definition:
--   caliber (number, mm), projMass (number, grams), muzzleVel (number, m/s),
--   optional dragCoef (ACE units, derived from caliber and mass when omitted),
--   limitVel (m/s, default 800), ricochet (degrees, default 60),
--   tracer (0 or 1, default 0), colour (Color, tracer colour),
--   penMul (number, default 1, multiplies armor penetration only).
-- @realm shared
function SmallArms.RegisterRound(id, def)
	assert(isstring(id), "ACE.SmallArms.RegisterRound: id must be a string")
	assert(istable(def), "ACE.SmallArms.RegisterRound: def must be a table")
	assert(isnumber(def.caliber) and isnumber(def.projMass) and isnumber(def.muzzleVel),
		"ACE.SmallArms.RegisterRound: caliber, projMass and muzzleVel are required")

	def.id = id
	SmallArms.Rounds[id] = def
end

--- Resolves a round id or inline round table to a round definition.
-- @tparam string|table round Round id or inline definition.
-- @treturn table|nil The round definition, or nil when unknown.
-- @realm shared
function SmallArms.GetRound(round)
	if isstring(round) then return SmallArms.Rounds[round] end
	if istable(round) then return round end
end

--- Assigns a round to a weapon class, for packs that don't set SWEP.ACE_Round themselves.
-- @tparam string class Weapon class, e.g. "arccw_ak47".
-- @tparam string|table round Round id or inline definition. nil removes the assignment.
-- @realm shared
function SmallArms.SetWeaponRound(class, round)
	SmallArms.WeaponRounds[class] = round
	SmallArms.PatchWeaponClass(class)
end

--- Returns the round a weapon class fires, or nil when the class has not opted in.
-- @tparam string class Weapon class.
-- @treturn table|nil The round definition.
-- @realm shared
function SmallArms.GetClassRound(class)
	local Swep = weapons.Get(class)
	if Swep and Swep.ACE_Enabled == false then return end

	local Round = Swep and Swep.ACE_Round or SmallArms.WeaponRounds[class]
	return SmallArms.GetRound(Round)
end

--- Returns the round a weapon entity fires, or nil when it has not opted in.
-- @tparam Weapon wep The weapon.
-- @treturn table|nil The round definition.
-- @realm shared
function SmallArms.GetWeaponRound(wep)
	if not IsValid(wep) or wep.ACE_Enabled == false then return end

	local Round = wep.ACE_Round or SmallArms.WeaponRounds[wep:GetClass()]
	return SmallArms.GetRound(Round)
end

--- Returns the area ACE divides a round's energy by. Smaller means more penetration.
-- Includes the round's penMul and the server-wide ace_smallarms_penmul.
-- @tparam table round Round definition.
-- @treturn number The PenArea for ACE BulletData.
-- @realm shared
function SmallArms.GetPenArea(round)
	local Caliber = round.caliber / 10
	local FrArea  = math.pi * (Caliber / 2) ^ 2

	return FrArea ^ ACE.PenAreaMod * 1.1 / ((round.penMul or 1) * SmallArms.PenMul:GetFloat())
end

--- Returns a round's armor penetration at the muzzle, in mm of RHA.
-- @tparam table round Round definition.
-- @treturn number Penetration in mm.
-- @realm shared
function SmallArms.GetMaxPen(round)
	local Energy = ACE.Kinetic(round.muzzleVel * 39.37, round.projMass / 1000, round.limitVel or 800)

	return Energy.Penetration / SmallArms.GetPenArea(round) * ACE.KEtoRHA
end

AddCSLuaFile("shared.lua")
AddCSLuaFile("cl_init.lua")

include("shared.lua")

DEFINE_BASECLASS("ace_scalability")

CreateConVar("sbox_max_ace_era", 64, FCVAR_NOTIFY, "Maximum number of ACE ERA bricks a player can spawn.")

-- Scalable ERA box. Reactive behavior lives in the ERA armor material
-- (lua/acf/shared/armor/era*.lua + sh_ace_era.lua); this entity is just a
-- box-shaped, scalable carrier with a fixed casing thickness, a chosen
-- generation, and a forward (reactive) face. Model concept by Delectros.

local ValidGen = { ERA = true, ERA2 = true, ERA3 = true }
local ValidAxis = { Up = true, Down = true, Forward = true, Back = true, Left = true, Right = true }

function ENT:Initialize()
	self.SpecialHealth = true   -- use our ACF_Activate for HP/armor
	self.SpecialDamage = true   -- route damage through ACF_PropDamage -> ERA material
	self.IsExplosive   = true   -- ERA bricks cook off / damage nearby things
	self.IsScalable    = true
	self.Exploding     = false

	self.GenId          = self.GenId or "ERA"
	self.ERAForwardAxis = self.ERAForwardAxis or "Up"

	self.Outputs = WireLib.CreateOutputs(self, { "Entity [ENTITY]" })
	Wire_TriggerOutput(self, "Entity", self)
end

-- "L:W:H" (inches) -> clamped Vector.
local function ParseSize(str)
	local mn = 2 -- ERA bricks can be thin (a real Kontakt-1 element is ~3in deep)
	local mx = ACF.CrateMaximumSize or 200

	local L, W, H
	if isstring(str) then
		local p = string.Explode(":", str)
		L, W, H = tonumber(p[1]), tonumber(p[2]), tonumber(p[3])
	end

	L = math.Clamp(L or 12, mn, mx)
	W = math.Clamp(W or 12, mn, mx)
	H = math.Clamp(H or 4,  mn, mx)

	return Vector(L, W, H)
end

function MakeACE_ERA(Owner, Pos, Angle, GenId, SizeStr, ForwardAxis)
	if IsValid(Owner) and not Owner:CheckLimit("_ace_era") then return false end

	if not ValidGen[GenId] then GenId = "ERA" end
	if not ValidAxis[ForwardAxis] then ForwardAxis = "Up" end

	local Gen = ACE.ERA.Generations[GenId]
	if not Gen then return false end

	local Ent = ents.Create("ace_era")
	if not IsValid(Ent) then return false end

	if IsValid(Owner) then Ent:CPPISetOwner(Owner) end
	Ent:SetAngles(Angle)
	Ent:SetPos(Pos)

	Ent.GenId          = GenId
	Ent.ERAForwardAxis = ForwardAxis
	Ent.SizeStr        = SizeStr

	Ent:Spawn()

	-- Build the scalable box (mirrors acf_ammo's scalable crate path).
	local Size      = ParseSize(SizeStr)
	local ModelData = ACE.ModelData["Box"]
	local Default   = ModelData.DefaultSize

	Ent.Dimensions = Size
	Ent:SetMaterial("sprops/sprops_grid_12x12") -- plain reactive-block look, not an ammo crate
	Ent:SetModel(ModelData.Model)
	Ent:PhysicsInit(SOLID_VPHYSICS)
	Ent:SetMoveType(MOVETYPE_VPHYSICS)
	Ent:SetSolid(SOLID_VPHYSICS)

	Ent.ScaleData = {
		Mesh     = ModelData.CustomMesh,
		Scale    = Vector(Size.x / Default, Size.y / Default, Size.z / Default),
		Size     = Default,
		Material = ModelData.physMaterial,
	}
	Ent:ACE_SetScale(Ent.ScaleData)
	Ent.ACE_ERAVolume = nil -- recomputed by ERA.GetBrickVolume after scaling

	-- Mass: thin steel casing + flyer plates + explosive filler. Real ERA bricks
	-- run ~2.4-3.0 kg per litre of brick volume (Gen.Density), e.g. a Kontakt-1
	-- container ~2.3 L weighs ~5.5 kg. NOT scaled by massMod (that is the armor
	-- point/cost multiplier, not a physical density).
	local volCuIn = Size.x * Size.y * Size.z
	local liters  = volCuIn * 16.387064 / 1000
	Ent.Mass      = math.Clamp(liters * (Gen.Density or 2.5), 1, 5000)

	Ent:ACF_Activate()

	local phys = Ent:GetPhysicsObject()
	if IsValid(phys) then phys:SetMass(Ent.Mass) end

	Ent:UpdateOverlayText()

	if IsValid(Owner) then
		Owner:AddCount("_ace_era", Ent)
		Owner:AddCleanup("acfmenu", Ent)
	end

	return Ent
end

list.Set("ACFCvars", "ace_era", { "id", "data1", "data2" })
duplicator.RegisterEntityClass("ace_era", MakeACE_ERA, "Pos", "Angle", "GenId", "SizeStr", "ERAForwardAxis")

-- ACF health/armor setup. Armor is the FIXED casing thickness for this
-- generation (box size only changes coverage, volume and cost), so ERA can
-- never be abused as thick base armor. Reactive behavior is the material's job.
function ENT:ACF_Activate(Recalc)
	self.ACF = self.ACF or {}

	local phys = self:GetPhysicsObject()
	if not IsValid(phys) then return end

	local Gen = ACE.ERA.Generations[self.GenId] or ACE.ERA.Generations.ERA

	self.ACF.Area   = self.ACF.Area or (phys:GetSurfaceArea() * 6.45)
	self.ACF.Volume = self.ACF.Volume or (phys:GetVolume() * 16.38)

	local Health  = (self.ACF.Volume / ACF.Threshold) * 0.5
	local Percent = 1
	if Recalc and self.ACF.Health and self.ACF.MaxHealth then
		Percent = self.ACF.Health / self.ACF.MaxHealth
	end

	self.ACF.Health    = Health * Percent
	self.ACF.MaxHealth = Health
	self.ACF.Armour    = Gen.CasingMM * (0.5 + Percent / 2)
	self.ACF.MaxArmour = Gen.CasingMM
	self.ACF.Ductility = 0
	self.ACF.Type      = "Prop"
	self.ACF.Mass      = self.Mass
	self.ACF.Material  = self.GenId
end

-- Route hits through the standard prop damage path, which dispatches to the ERA
-- material's ArmorResolution (trigger / inert casing / volume-scaled blast).
function ENT:ACF_OnDamage(Entity, Energy, FrArea, Angle, Inflictor, Bone, Type)
	if IsValid(Inflictor) and Inflictor:IsPlayer() then self.Inflictor = Inflictor end
	return ACF_PropDamage(Entity, Energy, FrArea, Angle, Inflictor, Bone, Type)
end

function ENT:UpdateOverlayText()
	local Gen = ACE.ERA.Generations[self.GenId] or ACE.ERA.Generations.ERA
	local d   = self.Dimensions or vector_origin

	local txt = Gen.name
	txt = txt .. "\nCasing: " .. (Gen.CasingMM or 0) .. " mm RHA (fixed)"
	txt = txt .. "\nForward face: " .. (self.ERAForwardAxis or "Up")
	txt = txt .. "\nSize: " .. math.Round(d.x, 1) .. " x " .. math.Round(d.y, 1) .. " x " .. math.Round(d.z, 1) .. " in"
	txt = txt .. "\nMass: " .. math.Round(self.Mass or 0, 1) .. " kg"
	txt = txt .. "\nEffective: ~" .. ACE.ERA.EstimateEffectiveArmor(Gen, "KE") .. " mm vs KE / ~" .. ACE.ERA.EstimateEffectiveArmor(Gen, "HEAT") .. " mm vs HEAT"
	txt = txt .. "\nReacts on the FORWARD face only."

	self:SetOverlayText(txt)
end

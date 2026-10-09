AddCSLuaFile("cl_init.lua")
AddCSLuaFile("shared.lua")

include("shared.lua")

DEFINE_BASECLASS( "base_wire_entity" )

--[[
	Engine heater: a fuel-fired coolant heater linked to one engine (ENT:LinkHeater on the
	engine). While switched on and below its cut-in temperature it burns fuel from the engine's
	liquid fuel tanks, draws its fan, pump and glow pin power from the engine's starter battery,
	and puts its heat into the engine's coolant (ACE.EngineThermalThink sums HeatW over the
	engine's HeaterLink). Definitions in lua/ace/shared/tools/engine_heaters.lua.

	Control: runs until the coolant reaches OffC, restarts below OnC, as parking heaters cycle
	on their own thermostat. OnC 65 °C, OffC 75 °C (estimated).
]]
local OnC, OffC = 65, 75
local ThinkDelay = 0.5
-- Burner efficiency of the rapid preheater, from the Thermo E+ 320's 32 kW on 3.2 kg/h, and the
-- fuel's lower heating value (diesel, 42.8 MJ/kg).
local RapidEff, FuelLHV = 0.84, 42.8e6

function ENT:Initialize()
	self.Master    = {}  -- the engine it heats (at most one)
	self.Active    = true
	self.Burning   = false
	self.HeatW      = 0 -- into the coolant, W
	self.HeatBlockW = 0 -- into the metal (rapid preheater), W
	self.HeatOilW   = 0 -- into the oil (rapid preheater), W
	self.Status     = "Not linked"
	self.LastThink = CurTime()

	self.Inputs = WireLib.CreateInputs(self, {
		"Active (Switches the heater on or off. On by default.)",
	})
	self.Outputs = WireLib.CreateOutputs(self, {
		"Burning (1 while the heater is burning fuel)",
		"Heat Output (Heat put into the engine, kW)",
		"Fuel Use (Fuel burned, litres per hour)",
		"Coolant Temp (The linked engine's coolant temperature, °C)",
	})
end

function ENT:ACF_Activate( _ )
	ACE.GetEntityState(self, true)

	local PhysObj = self:GetPhysicsObject()
	local Area = IsValid(PhysObj) and PhysObj:GetSurfaceArea() or 1000
	local Volume = IsValid(PhysObj) and PhysObj:GetVolume() or 1000

	self.ACE.Area      = Area
	self.ACE.Volume    = Volume
	self.ACE.Health    = Area / 30
	self.ACE.MaxHealth = self.ACE.Health
	self.ACE.Armour    = 1
	self.ACE.MaxArmour = self.ACE.Armour
	self.ACE.Mass      = self.Weight
	self.ACE.Density   = (self.Weight * 1000) / math.max(Volume, 1)
	self.ACE.Type      = "Prop"
end

--- Spawns an engine heater (also the duplicator factory).
-- @param Owner Player The owner.
-- @param Pos Vector Position.
-- @param Angle Angle Angles.
-- @param Id string Heater id (lua/ace/shared/tools/engine_heaters.lua).
-- @return Entity|false The heater, or false when it could not be made.
function ACE.MakeEngineHeater(Owner, Pos, Angle, Id)
	if IsValid(Owner) and not Owner:CheckLimit("_ace_misc") then return false end

	local Heaters = ACE.Weapons.EngineHeaters
	local Def = Heaters[Id] or Heaters["Heater_Small"]
	if not Def then return false end

	local Heater = ents.Create("ace_engine_heater")
	if not IsValid(Heater) then return false end

	Heater:SetAngles(Angle)
	Heater:SetPos(Pos)
	Heater:Spawn()
	if IsValid(Owner) then Heater:CPPISetOwner(Owner) end

	Heater.Id        = Def.id
	Heater.Def       = Def
	Heater.Weight    = Def.weight
	Heater.AcfName   = Def.name
	Heater.ACEPoints = Def.acepoints

	Heater:SetModel(Def.model)
	Heater:PhysicsInit(SOLID_VPHYSICS)
	Heater:SetMoveType(MOVETYPE_VPHYSICS)
	Heater:SetSolid(SOLID_VPHYSICS)
	local Phys = Heater:GetPhysicsObject()
	if IsValid(Phys) then Phys:SetMass(Def.weight) end

	Heater:SetNWString("WireName", Def.name)
	Heater:UpdateOverlayText()

	if IsValid(Owner) then
		Owner:AddCount("_ace_misc", Heater)
		Owner:AddCleanup("acemenu", Heater)
	end

	return Heater
end

list.Set( "ACFCvars", "ace_engine_heater", {"id"} )
duplicator.RegisterEntityClass("ace_engine_heater", ACE.MakeEngineHeater, "Pos", "Angle", "Id")

function ENT:TriggerInput(Name, Value)
	if Name == "Active" then
		self.Active = Value ~= 0
		self:UpdateOverlayText()
	end
end

-- The engine's first liquid fuel tank that can feed the heater.
local function HeaterTank(Engine)
	for _, Tank in ipairs(Engine.FuelLink or {}) do
		if IsValid(Tank) and not Tank.BatteryState and Tank.FuelType ~= "Electric"
			and Tank.Fuel > 0 and Tank.Active and Tank.Legal then
			return Tank
		end
	end
end

function ENT:Think()
	local Now = CurTime()
	local Dt = math.Clamp(Now - self.LastThink, 0, 1)
	self.LastThink = Now
	self:NextThink(Now + ThinkDelay)

	local Def = self.Def
	local Engine = self.Master[1]
	local Coolant
	local HeatW, BlockW, OilW, FuelLph = 0, 0, 0, 0

	if not IsValid(Engine) then
		self.Burning = false
		self.Status = "Not linked"
	else
		Coolant = Engine.Heat or ACE.AmbientTemp
		if not self.Active then
			self.Burning = false
			self.Status = "Off"
		elseif self.Burning and Coolant >= OffC then
			self.Burning = false
			self.Status = "Warm - waiting"
		elseif not self.Burning and Coolant >= OnC then
			self.Status = "Warm - waiting"
		else
			local Tank = HeaterTank(Engine)
			if not Tank then
				self.Burning = false
				self.Status = "No fuel"
			elseif not Engine:DrawAuxPower(Def.elecw * Dt, Dt) then
				self.Burning = false
				self.Status = "No power - starter battery flat"
			else
				self.Burning = true
				self.Status = "Heating"
				local FuelKgh = Def.fuelkgh
				HeatW = Def.heatw
				local TS = Def.rapidk and ACE.EngineThermalSpec(Engine)
				if TS then
					-- Shared by heat capacity so metal, coolant and oil warm together.
					local Co = TS.Co or 0
					local Ct = TS.Cb + TS.Cc + Co
					local P = Ct * Def.rapidk / math.max(ACE.ThermalTimeScale or 1, 0.01)
					HeatW, BlockW, OilW = P * TS.Cc / Ct, P * TS.Cb / Ct, P * Co / Ct
					FuelKgh = P / (RapidEff * FuelLHV) * 3600
				end
				local Density = ACE.FuelDensity[Tank.FuelType] or 0.84
				Tank.Fuel = math.max(Tank.Fuel - FuelKgh / 3600 * Dt / Density, 0)
				FuelLph = FuelKgh / Density
			end
		end
	end

	self.HeatW, self.HeatBlockW, self.HeatOilW = HeatW, BlockW, OilW
	self.HeatTotalW = HeatW + BlockW + OilW
	WireLib.TriggerOutput(self, "Burning", self.Burning and 1 or 0)
	WireLib.TriggerOutput(self, "Heat Output", self.HeatTotalW / 1000)
	WireLib.TriggerOutput(self, "Fuel Use", FuelLph)
	WireLib.TriggerOutput(self, "Coolant Temp", Coolant or 0)
	self.Coolant = Coolant
	self:UpdateOverlayText()

	return true
end

function ENT:UpdateOverlayText()
	local Def = self.Def
	local Text = (Def and Def.name or "Engine heater") .. "\nStatus: " .. (self.Status or "")
	if self.Burning then
		Text = Text .. "\nHeat: " .. math.Round((self.HeatTotalW or 0) / 1000, 1) .. " kW"
	end
	if self.Coolant then
		Text = Text .. "\nCoolant: " .. math.Round(self.Coolant) .. " °C"
	end
	self:SetOverlayText(Text)
end

function ENT:OnRemove()
	-- A copy: unlinking removes the engine from self.Master.
	for _, Engine in ipairs(table.Copy(self.Master)) do
		if IsValid(Engine) then Engine:Unlink(self) end
	end
end

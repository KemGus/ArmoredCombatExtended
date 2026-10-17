-- sv_engine_spawn.lua
-- Spawning an engine from its definition, updating one in place, the built-in cooler, ACE armour and
-- damage hooks, start-up and removal.
-- Included by init.lua; ENT is the acf_engine entity table.

local EngineTable = ACE.Weapons.Engines

do

	local BackComp = {
		["Induction motor, Tiny"]                 = "Electric-Tiny-NoBatt",
		["Induction motor, Small, Standalone"]    = "Electric-Small-NoBatt",
		["Induction motor, Medium, Standalone"]   = "Electric-Medium-NoBatt",
		["Induction motor, Large, Standalone"]    = "Electric-Large-NoBatt",

		["AVDS-1790-9A"]                          = "24.8-V12",
		["AVDS-1790-1500"]                        = "27.0-V12"
	}

	--[[
		Sets an engine up from its definition: stats, torque curve, fuel use, wire inputs, output
		point and mass. With Rebuild it also sets the model and builds the physics object.
		Spawning and updating a placed engine (ENT:Update) both go through here.
	]]
	local function ApplyEngine( Engine, Id, Rebuild )
		local Lookup = EngineTable[Id]

		Engine.Id = Id
		Engine.Model            = Lookup.model
		Engine.Weight           = Lookup.weight
		Engine.BaseTorque		= Lookup.torque
		Engine.PeakTorque       = Lookup.torque
		Engine.peakkw           = Lookup.peakpower
		Engine.PeakKwRPM        = Lookup.peakpowerrpm
		Engine.PeakTqRPM        = math.max(Lookup.peaktqrpm, Lookup.idlerpm)
		Engine.IdleRPM          = Lookup.idlerpm
		Engine.PeakMinRPM       = Lookup.peakminrpm
		Engine.PeakMaxRPM       = Lookup.peakmaxrpm
		Engine.LimitRPM         = Lookup.limitrpm
		Engine.Inertia          = Lookup.flywheelmass * 3.1416 ^ 2
		Engine.iselec           = Lookup.iselec
		Engine.FlywheelOverride = Lookup.flywheeloverride
		Engine.IsTrans          = Lookup.istrans -- driveshaft outputs to the side
		Engine.FuelType         = Lookup.fuel or "Petrol"
		Engine.EngineType       = Lookup.enginetype or "GenericPetrol"
		Engine.Efficiency     = 1-(ACE.Efficiency[Engine.EngineType] or ACE.Efficiency["GenericPetrol"])  * (1 + (Engine.peakkw * 1.34 / 2000) * 0.1) -- Energy not transformed into kinetic energy and instead into thermal
		Engine.EfficiencyMod	= Engine.Efficiency
		Engine.TorqueCurve	= ACE.GetEngineTorqueCurve(Lookup)
		Engine.ModTorqueCurve      = table.Copy(Engine.TorqueCurve)
		Engine.SoundPath        = Lookup.sound
		Engine.DefaultSound     = Engine.SoundPath
		Engine.SoundPitch       = Lookup.pitch or 100
		--Engine.SpecialHealth    = true
		Engine.SpecialDamage    = true
		Engine.FuelTank         = 0
		Engine.ThermalSurfaceArea = Lookup.CoolingArea or 0.1

		local EngineHorsepower = Engine.peakkw / 0.7457 --Converts KW to HP, 74.57 / 100

		Engine.TorqueScale	= ACE.TorqueScale[Engine.EngineType]

		Engine.MaxDB = 70 + 60 * (EngineHorsepower / 2400) --Base volume of 70DB. Plus 60 * The ratio of the engine hp to 2400.

		--If the engine has more than 100 hp it requires a driver. A linked driver seat takes the place of a seated driver.
		Engine.RequiresDriver = EngineHorsepower > ACE.LargeEngineThreshold and ACE.LargeEnginesRequireDrivers ~= 0
		Engine.CanUseSeatDriver = Engine.RequiresDriver and not Engine.HasDriver

		--calculate base fuel usage
		if Engine.EngineType == "Electric" then
			Engine.FuelUse = ACE.ElecRate / (ACE.Efficiency[Engine.EngineType] * 60 * 60) --elecs use current power output, not max

			Engine.MaxDB = Engine.MaxDB * 0.15 --Electrics generate hardly any sound by themselves.
		else
			Engine.FuelUse = ACE.FuelRate * ACE.Efficiency[Engine.EngineType] * Engine.peakkw / (60 * 60)
		end

		if Rebuild then
			Engine:SetModel( Engine.Model )

			Engine:PhysicsInit( SOLID_VPHYSICS )
			Engine:SetMoveType( MOVETYPE_VPHYSICS )
			Engine:SetSolid( SOLID_VPHYSICS )
		end

		Engine.Out = ACE.LocalAttachment( Engine, "driveshaft" )

		local phys = Engine:GetPhysicsObject()
		if IsValid( phys ) then
			phys:SetMass( Engine.Weight )
			Engine.ModelInertia = 0.99 * phys:GetInertia() / phys:GetMass() -- giving a little wiggle room
		end

		-- Electric motors add Reverse; adjusting keeps the wires on the other inputs.
		WireLib.AdjustSpecialInputs( Engine, ACE.EngineInputs( Engine.FuelType == "Electric" ) )
		Engine:UpdateBuiltinCooler( Lookup )

		Engine:SetNWString( "WireName", Lookup.name )
	end

	function ACE.MakeEngine(Owner, Pos, Angle, Id)

		if not Owner:CheckLimit("_ace_misc") then return false end

		local Engine = ents.Create( "acf_engine" )
		if not IsValid( Engine ) then return false end

		if not ACE.CheckEngine( Id ) then
			Id = BackComp[Id] or "5.7-V8"
		end

		Engine:SetAngles(Angle)
		Engine:SetPos(Pos)
		Engine:Spawn()
		Engine:CPPISetOwner(Owner)

		Engine.TorqueMult       = 1
		Engine.Heat             = ACE.AmbientTemp
		Engine.FlyRPM = 0
		Engine.Sound = nil
		Engine.RPM = {}

		ApplyEngine( Engine, Id, true )

		Engine:UpdateOverlayText()

		Owner:AddCount("_ace_misc", Engine)
		Owner:AddCleanup( "acemenu", Engine )

		ACE.Activate( Engine, 0 )

		return Engine
	end
	list.Set( "ACFCvars", "acf_engine", {"id"} )
	duplicator.RegisterEntityClass("acf_engine", ACE.MakeEngine, "Pos", "Angle", "Id")

	--- Updates a placed engine in place to the engine the menu tool has selected. Any engine can
	-- become any other: a new model rebuilds its physics, keeping its constraints
	-- (ACE.SaveEntity), its gearbox links are redrawn to the new output, and its fuel tanks,
	-- batteries and heaters are linked again under the new engine's rules.
	-- @param ArgsTable table The menu's values (ACFCvars order) after the player, trace position
	-- and angle: [4] is the engine id.
	-- @return boolean Success.
	-- @return string Message for the player.
	function ENT:Update( ArgsTable )
		if self.Active then
			return false, "Turn off the engine before updating it!"
		end

		local Id = ArgsTable[4]
		if not ACE.CheckEngine( Id ) then
			return false, "Unknown engine!"
		end

		local NewEngine = Id ~= self.Id
		local Rebuild = EngineTable[Id].model ~= self.Model

		if Rebuild then ACE.SaveEntity( self ) end
		ApplyEngine( self, Id, Rebuild )

		local Lost = 0
		if Rebuild then
			local _, Failed = ACE.RestoreEntity( self )
			Lost = Failed
			-- The armour model caches the old hull's area.
			if self.ACE then self.ACE.Area = nil end
		end

		local Broken = self:RefreshLinks()
		local Dropped = self:RelinkSupplies()

		-- The drivetrain and cooling models are rebuilt for the new engine, which starts cold.
		self.MobSpec, self.ThermalSpec = nil, nil
		if NewEngine then
			self.MobState, self.ThermalState = nil, nil
			self.Heat = ACE.AmbientTemp
		end

		-- The starter's extra mass goes back on top of the new engine's (ENT:SetStarterSetup).
		self.StarterExtraKg = 0
		self:SetStarterSetup( self.StarterSetup )
		self:UpdateOverlayText()

		ACE.Activate( self, 1 )
		if ACE.PointsInputChanged then ACE.PointsInputChanged( self, "engine-updated" ) end

		local Msg = "Engine updated successfully!"
		if Broken > 0 then
			Msg = Msg .. " " .. Broken .. " gearbox link(s) were at too steep an angle and were unlinked."
		end
		if #Dropped > 0 then
			Msg = Msg .. " Unlinked: " .. table.concat( Dropped, ", " ) .. "."
		end
		if Lost > 0 then
			Msg = Msg .. " " .. Lost .. " constraint(s) could not be restored."
		end
		return true, Msg
	end

end


--[[
	Built-in cooler. Some motor models are a housing much larger than the motor itself (the old
	"integrated battery" motors). That space holds a radiator core: its volume is the housing's
	collision volume less the bare motor's (definition field motorvolume, in³), its depth along the
	airflow the housing's thinnest side, and its face whatever area that leaves. The core cools
	the motor's coolant through the same heat exchanger model as a radiator entity
	(ACE.EngineThermalThink), with a fan that runs off the battery.
]]

--- Works out the built-in radiator core of a motor whose housing has room for one.
-- @param Lookup table Engine definition.
function ENT:UpdateBuiltinCooler( Lookup )
	self.BuiltinCoreFrontM2, self.BuiltinCoreDepthM, self.BuiltinCoreFanW = nil, nil, nil
	if not Lookup or not Lookup.motorvolume then return end

	local PhysObj = self:GetPhysicsObject()
	if not IsValid( PhysObj ) then return end

	local CoreIn3 = ( PhysObj:GetVolume() or 0 ) - Lookup.motorvolume
	if CoreIn3 <= 0 then return end

	local Size = self:OBBMaxs() - self:OBBMins()
	local DepthIn = math.max( math.min( Size.x, Size.y, Size.z ), 1 )
	self.BuiltinCoreDepthM = DepthIn * 0.0254
	self.BuiltinCoreFrontM2 = CoreIn3 / DepthIn * 0.00064516
	-- Fan power as the radiator entity sizes it: 30 W per litre of core.
	self.BuiltinCoreFanW = CoreIn3 * ACE.CuIToLiter * 30
end

function ENT:ACF_Activate()
	--Density of steel = 7.8g cm3 so 7.8kg for a 1mx1m plate 1m thick
	local Entity = self
	ACE.GetEntityState(Entity, true)

	local Count
	local PhysObj = Entity:GetPhysicsObject()
	if PhysObj:GetMesh() then Count = #PhysObj:GetMesh() end
	if PhysObj:IsValid() and Count and Count > 100 then

		if not Entity.ACE.Area then
			Entity.ACE.Area = (PhysObj:GetSurfaceArea() * 6.45) * 0.52505066107
		end

	else
		local Size = Entity.OBBMaxs(Entity) - Entity.OBBMins(Entity)
		if not Entity.ACE.Area then
			Entity.ACE.Area = ((Size.x * Size.y) + (Size.x * Size.z) + (Size.y * Size.z)) * 6.45
		end

	end

	Entity.ACE.Ductility = Entity.ACE.Ductility or 0

	local Area = Entity.ACE.Area
	local Armour = (Entity:GetPhysicsObject():GetMass() * 1000 / Area / 0.78)
	local Health = Area / ACE.Threshold

	local Percent = 1

	if Recalc and Entity.ACE.Health and Entity.ACE.MaxHealth then
		Percent = Entity.ACE.Health / Entity.ACE.MaxHealth
	end

	Entity.ACE.Health    = Health * Percent * ACE.EngineHPMult[self.EngineType]
	Entity.ACE.MaxHealth = Health * ACE.EngineHPMult[self.EngineType]
	Entity.ACE.Armour    = Armour * (0.5 + Percent / 2)
	Entity.ACE.MaxArmour = Armour * ACE.ArmorMod
	Entity.ACE.Type      = nil
	Entity.ACE.Mass      = PhysObj:GetMass()
	Entity.ACE.Type      = "Prop"

	Entity.ACE.Material	= not isstring(Entity.ACE.Material) and ACE.BackCompMat[Entity.ACE.Material] or Entity.ACE.Material or "RHA"

end

function ENT:ACF_OnDamage( Entity, Energy, FrArea, Angle, Inflictor, _, Type )	--This function needs to return HitRes

	local Mul = (((Type == "HEAT" or Type == "THEAT" or Type == "HEATFS" or Type == "THEATFS") and ACE.HEATMulEngine) or 1) --Heat penetrators deal bonus damage to engines
	local HitRes = ACE.PropDamage( Entity, Energy, FrArea * Mul, Angle, Inflictor ) --Calling the standard damage prop function

	return HitRes --This function needs to return HitRes
end

function ENT:ACFInit()

	self:CalcMassRatio()

	self.LastThink = CurTime()
	self.Stalled = false
	Wire_TriggerOutput(self, "Stalled", 0)
	local Spec = ACE.Mobility.EngineSpec(self, self.FuelType)
	-- Preheat is decided from the temperatures at the moment the start is requested.
	self:StarterModelInputs(Spec, self.MobState)
	ACE.Mobility.Engine.Start(self.MobState)

end

function ENT:OnRemove()
	ACE.EngineSound.Stop( self, true )
end

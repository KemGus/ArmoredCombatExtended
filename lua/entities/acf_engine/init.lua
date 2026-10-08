-- init.lua

AddCSLuaFile( "shared.lua" )
AddCSLuaFile( "cl_init.lua" )

include("shared.lua")

local EngineTable = ACE.Weapons.Engines
local FuelLinkDistBase = 512
local FeedRescan = 0.5 -- s; how often the fuel feed's tanks and shares are rebuilt (ENT:ScanFeed)
local FeedFlush = 0.1 -- s; how often the fuel burned is taken from the tanks (ENT:FlushFeed)

do

	local EngineWireDescs = {
		--Inputs
		["Throttle"]    = "Controls the amount of fuel which will be displaced to the engine.\n Increasing it will also increase RPM, Power and fuel consumption. Values go from 0-100.\n Electric motors also take -100 to 0: regenerative braking strength, 0 is none and -100 is full.",
		["Exhaust"]     = "Optional exhaust entity: sound banks marked 'Play at exhaust' play from it, and exhaust smoke comes out along its forward axis.",
		["Reverse"]     = "Electric motors only: 1 drives the motor backwards, so a vehicle can reverse without a reverse gear. Switched while moving, the motor is braked to a stop first, charging the battery, and then driven the other way.",

		--Outputs
		["RPM"]         = "Returns the current RPM.",
		["Torque"]      = "Returns the current Torque.",
		["Power"]       = "Returns the current power of this engine.",
		["Fuel Use"]    = "Gives the actual fuel consumption of the engine.",
		["EngineHeat"]  = "Coolant temperature in °C. The thermostat opens at about 82 °C and the coolant boils at 120 °C. Air-cooled engines: the oil.",
		["Oil Temp"]    = "Sump oil temperature in °C, 0 for electric motors. Cold oil raises friction; past about 150 °C it wears the engine.",
		["Block Temp"]  = "Engine metal temperature, block and head, in °C. Hot metal costs torque and past about 200 °C wears the engine. Air-cooled engines: cylinder heads, limit 260 °C.",
		["Stalled"]     = "1 when the engine has stalled. Cycle Active to crank it again."
	}

	function ENT:Initialize()

		self.Throttle       = 0
		self.Active         = false
		self.IsMaster       = true
		self.GearLink       = {} -- a "Link" has these components: Ent, Rope, RopeLen, ReqTq
		self.FuelLink       = {}
		self.RadLink       = {}
		self.BatteryLink    = {} -- batteries feeding a combustion engine's starter
		self.StarterSize    = 1  -- starter setup (ENT:SetStarterSetup)
		self.StarterExtraKg = 0
		self.OTWarnings		= {} --Used to remember all the one time warnings.

		self.NextUpdate     = 0
		self.LastThink      = 0
		self.MassRatio      = 1
		self.FuelTank       = 0
		self.Heat           = ACE.AmbientTemp
		self.TotalFuel      = 0
		self.Legal          = true
		self.CanUpdate      = true
		self.RequiresDriver = false
		self.NextLegalCheck = ACE.CurTime + math.random(ACE.Legal.Min, ACE.Legal.Max) -- give any spawning issues time to iron themselves out
		self.Legal          = true
		self.LegalIssues    = ""
		self.LockOnActive   = false --used to turn on the engine in case of being lockdown by not legal
		self.CrewLink       = {}
		self.HasDriver      = false
		self.HasFuel		= false
		self.HasSeatDriver = false
		self.CanUseSeatDriver = false
		self.SeatDriverEnt = nil

		self.HeatGeneration = 0 --Heat generated per second

		self.LastFuel = nil

		self.ThermalSurfaceArea = 0.1 --In m^2

		self.LastDamageTime = CurTime()

		self.Inputs = WireLib.CreateSpecialInputs( self, ACE.EngineInputs(false) )
		self.Outputs = WireLib.CreateSpecialOutputs( self,  { "RPM (" .. EngineWireDescs["RPM"] .. ")", "Torque (" .. EngineWireDescs["Torque"] .. ")", "Power (" .. EngineWireDescs["Power"] .. ")", "Fuel Use (" .. EngineWireDescs["Fuel Use"] .. ")", "Total Fuel" , "Entity", "Mass", "Physical Mass" , "EngineHeat (" .. EngineWireDescs["EngineHeat"] .. ")", "Stalled (" .. EngineWireDescs["Stalled"] .. ")",
														"Oil Temp (" .. EngineWireDescs["Oil Temp"] .. ")", "Block Temp (" .. EngineWireDescs["Block Temp"] .. ")" },
														{ "NORMAL","NORMAL","NORMAL", "NORMAL", "NORMAL", "ENTITY", "NORMAL", "NORMAL", "NORMAL", "NORMAL", "NORMAL", "NORMAL", "NORMAL" } )

		Wire_TriggerOutput( self, "Entity", self )
		Wire_TriggerOutput(self, "EngineHeat", self.Heat)
		Wire_TriggerOutput(self, "Block Temp", self.Heat)

		self.WireDebugName = "ACF Engine"

		self.CanLegalCheck = true

	end

	--- Wire inputs of an engine; electric motors add Reverse.
	-- @param Electric boolean Whether the engine is an electric motor.
	-- @return table Names, table Types.
	function ACE.EngineInputs(Electric)
		local Names = { "Active", "Throttle (" .. EngineWireDescs["Throttle"] .. ")", "Exhaust (" .. EngineWireDescs["Exhaust"] .. ")" }
		local Types = { "NORMAL", "NORMAL", "ENTITY" }
		if Electric then
			Names[#Names + 1] = "Reverse (" .. EngineWireDescs["Reverse"] .. ")"
			Types[#Types + 1] = "NORMAL"
		end
		return Names, Types
	end

end

do

	local BackComp = {
		["Induction motor, Tiny"]                 = "Electric-Tiny-NoBatt",
		["Induction motor, Small, Standalone"]    = "Electric-Small-NoBatt",
		["Induction motor, Medium, Standalone"]   = "Electric-Medium-NoBatt",
		["Induction motor, Large, Standalone"]    = "Electric-Large-NoBatt",

		["AVDS-1790-9A"]                          = "24.8-V12",
		["AVDS-1790-1500"]                        = "27.0-V12"
	}

	function ACE.MakeEngine(Owner, Pos, Angle, Id)

		if not Owner:CheckLimit("_ace_misc") then return false end

		local Engine = ents.Create( "acf_engine" )
		if not IsValid( Engine ) then return false end

		if not ACE.CheckEngine( Id ) then
			Id = BackComp[Id] or "5.7-V8"
		end

		local Lookup = EngineTable[Id]

		Engine:SetAngles(Angle)
		Engine:SetPos(Pos)
		Engine:Spawn()
		Engine:CPPISetOwner(Owner)
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
		Engine.RequiresDriver   = false
		Engine.SoundPath        = Lookup.sound
		Engine.DefaultSound     = Engine.SoundPath
		Engine.SoundPitch       = Lookup.pitch or 100
		--Engine.SpecialHealth    = true
		Engine.SpecialDamage    = true
		Engine.TorqueMult       = 1
		Engine.FuelTank         = 0
		Engine.Heat             = ACE.AmbientTemp
		Engine.ThermalSurfaceArea = Lookup.CoolingArea or 0.1

		local EngineHorsepower = Engine.peakkw / 0.7457 --Converts KW to HP, 74.57 / 100

		Engine.TorqueScale	= ACE.TorqueScale[Engine.EngineType]

		Engine.MaxDB = 70 + 60 * (EngineHorsepower / 2400) --Base volume of 70DB. Plus 60 * The ratio of the engine hp to 2400.

		if EngineHorsepower > ACE.LargeEngineThreshold and ACE.LargeEnginesRequireDrivers ~= 0 then --If the engine has more than 100 hp it requires a driver.
			Engine.RequiresDriver = true
			Engine.CanUseSeatDriver = true
		end

		--calculate base fuel usage
		if Engine.EngineType == "Electric" then
			Engine.FuelUse = ACE.ElecRate / (ACE.Efficiency[Engine.EngineType] * 60 * 60) --elecs use current power output, not max

			Engine.MaxDB = Engine.MaxDB * 0.15 --Electrics generate hardly any sound by themselves.
		else
			Engine.FuelUse = ACE.FuelRate * ACE.Efficiency[Engine.EngineType] * Engine.peakkw / (60 * 60)
		end

		Engine.FlyRPM = 0
		Engine:SetModel( Engine.Model )
		Engine.Sound = nil
		Engine.RPM = {}

		Engine:PhysicsInit( SOLID_VPHYSICS )
		Engine:SetMoveType( MOVETYPE_VPHYSICS )
		Engine:SetSolid( SOLID_VPHYSICS )

		Engine.Out = Engine:WorldToLocal(Engine:GetAttachment(Engine:LookupAttachment( "driveshaft" )).Pos)

		local phys = Engine:GetPhysicsObject()
		if IsValid( phys ) then
			phys:SetMass( Engine.Weight )
			Engine.ModelInertia = 0.99 * phys:GetInertia() / phys:GetMass() -- giving a little wiggle room
		end

		if Engine.FuelType == "Electric" then
			WireLib.AdjustSpecialInputs( Engine, ACE.EngineInputs(true) )
		end
		Engine:UpdateBuiltinCooler( Lookup )

		Engine:SetNWString( "WireName", Lookup.name )
		Engine:UpdateOverlayText()

		Owner:AddCount("_ace_misc", Engine)
		Owner:AddCleanup( "acemenu", Engine )

		ACE.Activate( Engine, 0 )

		return Engine
	end
	list.Set( "ACFCvars", "acf_engine", {"id"} )
	duplicator.RegisterEntityClass("acf_engine", ACE.MakeEngine, "Pos", "Angle", "Id")

end

function ENT:Update( ArgsTable )
	-- That table is the player data, as sorted in the ACFCvars above, with player who shot,
	-- and pos and angle of the tool trace inserted at the start

	if self.Active then
		return false, "Turn off the engine before updating it!"
	end

	local Id = ArgsTable[4] -- Argtable[4] is the engine ID
	local Lookup = EngineTable[Id]

	if Lookup.model ~= self.Model then
		return false, "The new engine must have the same model!"
	end

	local Feedback = ""
	if Lookup.fuel ~= self.FuelType then
		Feedback = " Fuel type changed, fuel tanks unlinked."
		for Key in pairs(self.FuelLink) do
			table.remove(self.FuelLink,Key)
			self:UpdateOverlayText()
			--need to remove from tank master?
		end
	end

	self.Id                = Id
	self.Weight            = Lookup.weight
	self.BaseTorque		   = Lookup.torque
	self.PeakTorque        = Lookup.torque
	self.peakkw            = Lookup.peakpower
	self.PeakKwRPM         = Lookup.peakpowerrpm
	self.PeakTqRPM         = math.max(Lookup.peaktqrpm, Lookup.idlerpm)
	self.IdleRPM           = Lookup.idlerpm
	self.PeakMinRPM        = Lookup.peakminrpm
	self.PeakMaxRPM        = Lookup.peakmaxrpm
	self.LimitRPM          = Lookup.limitrpm
	self.Inertia           = Lookup.flywheelmass * 3.1416 ^ 2
	self.iselec            = Lookup.iselec -- is the engine electric?
	self.FlywheelOverride  = Lookup.flywheeloverride -- modifies rpm drag on iselec==true
	self.IsTrans           = Lookup.istrans
	self.FuelType          = Lookup.fuel
	self.EngineType        = Lookup.enginetype
	self.SoundPath         = Lookup.sound
	self.DefaultSound      = self.SoundPath
	self.SoundPitch        = Lookup.pitch or 100
	self.SpecialHealth     = false
	self.SpecialDamage     = true
	self.TorqueMult        = self.TorqueMult or 1
	self.FuelTank          = 0
	self.TorqueScale		= ACE.TorqueScale[self.EngineType]

	--calculate base fuel usage
	if self.EngineType == "Electric" then
		self.FuelUse = ACE.ElecRate / (ACE.Efficiency[self.EngineType] * 60 * 60) --elecs use current power output, not max
	else
		self.FuelUse = ACE.FuelRate * ACE.Efficiency[self.EngineType] * self.peakkw / (60 * 60)
	end

	self:SetModel( self.Model )
	self:SetSolid( SOLID_VPHYSICS )
	self.Out = self:WorldToLocal(self:GetAttachment(self:LookupAttachment( "driveshaft" )).Pos)

	local phys = self:GetPhysicsObject()
	if IsValid( phys ) then
		phys:SetMass( self.Weight )
	end
	self:UpdateBuiltinCooler( Lookup )

	self:SetNWString( "WireName", Lookup.name )
	-- The starter's extra mass goes back on top of the new engine's (ENT:SetStarterSetup), and
	-- the drivetrain model is rebuilt for the new engine.
	self.StarterExtraKg = 0
	self.MobSpec = nil
	self:SetStarterSetup( self.StarterSetup )
	self:UpdateOverlayText()

	ACE.Activate( self, 1 )
	if ACE.PointsInputChanged then ACE.PointsInputChanged( self, "engine-updated" ) end

	return true, "Engine updated successfully!" .. Feedback
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

function ENT:UpdateOverlayText()

	local pbmin = self.PeakMinRPM
	local pbmax = self.PeakMaxRPM

	local DriverBoost = self.HasDriver and ACE.DriverTorqueBoost or 1

	local PowerKW = math.Round( self.peakkw * DriverBoost )
	local PowerHP = math.Round( self.peakkw * DriverBoost * 1.34 )
	local TorqueNm = math.Round( self.BaseTorque * DriverBoost )
	local TorqueFtLb = math.Round( self.BaseTorque * DriverBoost * 0.73 )

	local text = "Power: " .. PowerKW .. " kW / " .. PowerHP .. " hp at " .. math.Round(self.PeakKwRPM) .. " RPM\n"
	text = text .. "Torque: " .. TorqueNm .. " Nm / " .. TorqueFtLb .. " ft-lb at " .. math.Round(self.PeakTqRPM) .. " RPM\n"
	text = text .. "Powerband: " .. (math.Round(pbmin / 10) * 10) .. " - " .. (math.Round(pbmax / 10) * 10) .. " RPM\n"
	text = text .. "Redline: " .. self.LimitRPM .. " RPM\n\n"
	-- The three parts the cooling model tracks (ACE.EngineThermalThink).
	local function temp(C) return math.Round(C) .. " °C / " .. math.Round(C * (9 / 5) + 32) .. " °F" end
	if self.AirCooled then
		-- Finned cylinders: no coolant, the oil is the only liquid.
		text = text .. "Air-cooled\n"
		text = text .. "Cylinder heads: " .. temp(self.BlockHeat or self.Heat) .. "\n"
		text = text .. "Oil: " .. temp(self.Heat) .. "\n"
		text = text .. "Air through the fins: " .. math.Round((self.FinAirSpeed or 0) * 3.6) .. " km/h\n"
	else
		text = text .. "Coolant: " .. temp(self.Heat) .. "\n"
		if self.OilHeat then
			text = text .. "Oil: " .. temp(self.OilHeat) .. "\n"
		end
		text = text .. "Block: " .. temp(self.BlockHeat or self.Heat) .. "\n"
	end
	if self.BuiltinCoreFrontM2 then
		text = text .. "Built-in radiator: " .. math.Round(self.BuiltinCoreFrontM2, 2) .. " m^2 face, " .. math.Round(self.BuiltinCoreDepthM * 100) .. " cm deep\n"
	end
	if self.ReverseInput and self.FuelType == "Electric" then
		text = text .. "Direction: reverse\n"
	end
	if self.CoolantBoiling then
		text = text .. "Coolant boiling - block at " .. math.Round(self.BlockHeat or self.Heat) .. " °C\n"
	end
	if self.OilOverheating and self.OilHeat then
		text = text .. "Oil overheating - " .. math.Round(self.OilHeat) .. " °C\n"
	end

	--if self.FuelLink and #self.FuelLink > 0 then
	if self.HasFuel then
		text = text .. "\nSupplied with " .. (self.EngineType == "Electric" and "Batteries" or "Fuel")
	end
	-- Starter: which battery feeds it, and why it is not cranking when it is not.
	if next(self.BatteryLink or {}) then
		text = text .. "\nStarter: linked battery"
	elseif self.StarterPack then
		text = text .. "\nStarter battery: " .. math.Round(ACE.Mobility.Battery.StarterPackSOC(self.StarterPack) * 100) .. "%"
	end
	if self.StarterWasCut then
		text = text .. "\nStarter overheated - cooling down"
	elseif self.StarterWasFlat then
		text = text .. "\nStarter battery flat"
	elseif self.StarterWasPreheating then
		text = text .. "\nPreheating (glow plugs)"
	end

	if self.HasDriver then
		text = text .. "\nDriver Provided (" .. (ACE.DriverTorqueBoost * 100 - 100) .. "% boost)"
	end

	if not self.Legal then
		text = text .. "\nNot legal, disabled for " .. math.ceil(self.NextLegalCheck - ACE.CurTime) .. "s\nIssues: " .. self.LegalIssues
	end

	self:SetOverlayText( text )

end

function ENT:FindSeatForDriver()

	local MaxDist = 348749.3 --Max distance to link driver seats. (15 meters * 39.37)^2 = 348749.3
	local closestDist = math.huge
	local SeatEnt = nil

	local EngContraption = self:CFW_GetContraption()

	for _, ent in pairs( ACE.critEnts ) do


		local eclass = ent:GetClass()

		if eclass ~= "prop_vehicle_prisoner_pod" then continue end

		local epos = ent:GetPos()
		local spos = self:GetPos()
		local SqDist = spos:DistToSqr( epos )

		if SqDist > MaxDist then continue end --Outside link range. Continue.

		if EngContraption ~= ent:CFW_GetContraption() then continue end --Seatent isn't on the same contraption as the engine. Ignore it.

		if SqDist < closestDist then
			SeatEnt = ent
			closestDist = SqDist
		end
	end

	if SeatEnt then
		self.HasSeatDriver = true
		self.LinkedDriver = SeatEnt
	end

end

function ENT:TestDriverDistance()

	if not IsValid(self.LinkedDriver) then
		--print("DRIVER ENT NOT VALID")
		self.HasSeatDriver = false
		self.HasDriver = false
		self.LinkedDriver = nil
		return
	end

	local epos = self.LinkedDriver:GetPos()
	local spos = self:GetPos()
	local SqDist = spos:DistToSqr( epos )

	local MaxDist = 348749.3 --Max distance to link driver seats. (15 meters * 39.37)^2 = 348749.3
	if SqDist > MaxDist then

		--local sqrtMaxDist = math.sqrt(MaxDist)
		--local sqrtDist = math.sqrt(SqDist)
		--print("Unlinked due to exceeding maxdist")
		--print("SquaredDist: " .. SqDist)
		--print("Dist: " .. sqrtDist)
		--print("MaxDistance: " .. sqrtMaxDist)
		--print("Exceeded by: " .. (sqrtDist-sqrtMaxDist))
		--print(self.LinkedDriver)


		self.HasDriver = false
		self.HasSeatDriver = false
		self.LinkedDriver = nil
		local soundstr =  "physics/metal/metal_box_impact_bullet" .. tostring(math.random(1, 3)) .. ".wav"
		self:EmitSound(soundstr,500,100)
	end


end

function ENT:TriggerInput( iname, value )

	if iname == "Exhaust" then
		ACE.EngineSound.SetExhaust( self, value )
		return
	end

	if iname == "Reverse" then
		-- Selects the direction the motor controller drives in; ENT:MobilityDesc hands it to the
		-- motor model, which brakes a motor still turning the old way before driving it.
		self.ReverseInput = value ~= 0
		self:UpdateOverlayText()
		return
	end

	if (iname == "Throttle") then
		self.Throttle = math.Clamp(value,0,100) / 100
		-- Electric motors take -100..0 as a regenerative braking command.
		self.RegenCommand = math.Clamp(-value, 0, 100) / 100
	elseif (iname == "Active") then
		if (value > 0 and not self.Active and self.Legal) then
			--make sure we have fuel
			local HasFuel
			local HasDriver

			for _,fueltank in pairs(self.FuelLink) do
				if fueltank.Fuel > 0 and fueltank.Active and fueltank.Legal then HasFuel = true break end
			end

			self.HasFuel = HasFuel == true
			if not self.RequiresDriver then
				HasDriver = true
			else
				if self.HasDriver or self.HasSeatDriver then
					HasDriver = true
				elseif self.CanUseSeatDriver then
					self:FindSeatForDriver()
					if IsValid(self.LinkedDriver) then
						HasDriver = true
					end
				end
			end
			--RequiresDriver
			if (HasFuel or ACE.EnginesRequireFuel == 0) and HasDriver then
				self.Active = true
				ACE.EngineSound.Start( self )
				self:ACFInit()
			else

				if not HasFuel then
					local HasWarned = self.OTWarnings.WarnedFuel or false
					--self.OTWarnings
					if not HasWarned then
						ACE.SendEngineHint( self:CPPIGetOwner() , "[ACE] Your engine requires fuel to work and that it be activated BEFORE the engine.", Color( 255, 0, 0 ))
						self.OTWarnings.WarnedFuel = true
					end
				end

				if not HasDriver then
					local HasWarned = self.OTWarnings.WarnedDriver or false
					--self.OTWarnings
					if not HasWarned then
						ACE.SendEngineHint( self:CPPIGetOwner() , "[ACE] Your engine is above [" .. ACE.LargeEngineThreshold .. " hp] requiring a driver to work.", Color( 255, 0, 0 ))
						self.OTWarnings.WarnedDriver = true
					end
				end

			end
			ACE.DoContraptionLegalCheck(self)
		elseif (value <= 0 and self.Active) then
			self.Active = false
			if self.MobState then ACE.Mobility.Engine.Stop(self.MobState) end
			ACE.EngineSound.Stop( self )
			Wire_TriggerOutput( self, "Torque", 0 )
			Wire_TriggerOutput( self, "Power", 0 )
			Wire_TriggerOutput( self, "Fuel Use", 0 )
		end
	end
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

function ENT:IllegalCrewSeatRemove(crewEntities)
	for _, crewEnt in ipairs(crewEntities) do
		if not crewEnt.Legal then
			self:Unlink(crewEnt)
		end
	end
end

function ENT:Think()

	if ACE.HasDefaultActiveInputState(self) and not ACE.IsDefaultActiveInputWired(self) then
		local active = ACE.GetDefaultActiveInputState(self)

		if self.Active ~= active then
			self:TriggerInput("Active", active and 1 or 0)
		end
	end

	if ACE.CurTime > self.NextLegalCheck then
		self.Legal, self.LegalIssues = ACE.CheckLegal(self, self.Model, math.Round(self.Weight,2), self.ModelInertia, true, true)
		self.NextLegalCheck = ACE.Legal.NextCheck(self.legal)
		self:CheckRopes()
		self:CheckFuel()
		self:CalcMassRatio()

		self:UpdateOverlayText()
		self.NextUpdate = ACE.CurTime + 1

		self:IllegalCrewSeatRemove(self.CrewLink)

		if not self.Legal and self.Active then
			self:TriggerInput("Active",0) -- disable if not legal and active
			self.LockOnActive = true
		else
			-- Restore the requested state after a legality lockdown.
			if self.LockOnActive then
				self.LockOnActive = false
				self:TriggerInput("Active", ACE.GetDefaultActiveInputState(self) and 1 or 0)
			end
		end
	end

	-- when not legal, update overlay displaying lockout and issues
	if not self.Legal and ACE.CurTime > self.NextUpdate then
		self:UpdateOverlayText()
		self.NextUpdate = ACE.CurTime + 1
	end

	Wire_TriggerOutput(self, "EngineHeat", self.Heat)
	Wire_TriggerOutput(self, "Oil Temp", self.OilHeat or 0)
	Wire_TriggerOutput(self, "Block Temp", self.BlockHeat or self.Heat)

	if ACE.CurTime >= (self.NextFeedFlush or 0) then
		self:FlushFeed(ACE.CurTime - (self.LastFeedFlush or ACE.CurTime))
		self.LastFeedFlush = ACE.CurTime
		self.NextFeedFlush = ACE.CurTime + FeedFlush
	end

	if ACE.CurTime > self.NextUpdate then

		self.TotalFuel = self:GetMaxFuel()
		self.HasFuel = self.TotalFuel > 0
		Wire_TriggerOutput(self, "Total Fuel", self.TotalFuel)

		self:UpdateOverlayText()
		self.NextUpdate = ACE.CurTime + 0.5
	end

	if self.Active then
		self:CalcRPM()
	end

	-- The drivetrain keeps running with the engine off so brakes, engine braking and a stopped
	-- engine holding the car in gear all still work.
	if next(self.GearLink) then
		self.MobDt = math.Clamp(CurTime() - self.LastThink, engine.TickInterval() * 0.5, 0.1)
		ACE.Mobility.Tick(self, self.MobDt)
	elseif self.MobCtrlStarted then
		-- Unlinked: stop driving the wheels it used to.
		ACE.Mobility.StopController(self)
	end

	-- Cooling runs whether or not the engine is on: a stopped engine still cools down.
	ACE.EngineThermalThink(self)

	self.LastThink = ACE.CurTime
	self:NextThink( ACE.CurTime )
	return true

end

-- specialized calcmassratio for engines
function ENT:CalcMassRatio()

	local Mass = 0
	local PhysMass = 0
	local Check = nil

	-- get the shit that is physically attached to the vehicle
	local PhysEnts = ACE.GetAllPhysicalConstraints( self )

	-- get the wheels directly connected to the drivetrain
	local Wheels = ACE.GetLinkedWheels(self)

	-- check if any wheels aren't in the physicalconstraint tree
	for _,Ent in pairs( Wheels ) do
		if not PhysEnts[Ent] then -- WE GOT EM BOIS
			Check = Ent
			Wheels[Ent] = nil -- manual removal, idk how table.remove would handle indexing by ent. probably not well. indexing by entity sucks, please use ent id.
			break
		end
	end

	-- if there's a wheel that's not in the engine constraint tree, use it as a start for getting physical constraints
	if IsValid(Check) then -- sneaky bastards trying to get away with remote engines...  NOT ANYMORE
		table.Merge(PhysEnts, Wheels) -- I mean, they'll still be remote... but they wont get free extra power from calcmass not seeing the contraption it's powering
		ACE.GetAllPhysicalConstraints( Check, PhysEnts ) -- no need for assignment here
	end

	-- add any parented but not constrained props you sneaky bastards
	local AllEnts = table.Copy( PhysEnts )
	for _, v in pairs( PhysEnts ) do
		table.Merge( AllEnts, ACE.GetAllChildren( v ) )
	end

	for _, v in pairs( AllEnts ) do

		if not IsValid( v ) then continue end

		local phys = v:GetPhysicsObject()
		if not IsValid( phys ) then continue end

		Mass = Mass + phys:GetMass()

		if PhysEnts[ v ] then
			PhysMass = PhysMass + phys:GetMass()
		end

	end

	--phys / parented
	--total: 6000 kgs
	--5000/1000 = 5 ratio
	--1000/5000 = 0.2 ratio
	--local Tmass = PhysMass + Mass

	self.MassRatio = PhysMass / Mass
	self.PhysMass = PhysMass
	self.TotalMass = Mass
	--self.MassRatio = 1 / (Tmass/10000)
	--self.MassRatio = (PhysMass ^ 0.9225) / Mass

	Wire_TriggerOutput( self, "Mass", math.Round( Mass, 2 ) )
	Wire_TriggerOutput( self, "Physical Mass", math.Round( PhysMass, 2 ) )

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

function ENT:GetMaxFuel()
	local TFuel = 0

	for _, Tank in pairs(self.FuelLink) do
		if not IsValid(Tank) then continue end
		if not Tank.Active then continue end

		TFuel = TFuel + Tank.Fuel
	end

	return TFuel
end

--[[
	Starter setup, chosen in the engine menu and kept through duplication:
	  Size     starter size relative to the standard one, 0.5-3: torque and current scale with
	           it, and so does the built-in battery; the starter and battery's extra mass is
	           added to the engine's (StarterKgPerW of the starter's rated power per unit of
	           size: 2.2 kg/kW for a reduction-gear starter plus 12.5 kg/kW of lead-acid battery
	           at 0.5 Wh/W and 40 Wh/kg; estimated from Bosch / Delco Remy catalogue masses and
	           typical flooded battery energy density).
	  Preheat  glow plug preheat at -20 °C in seconds, 0-60 (diesels; 0 = no glow plugs; nil =
	           ACE.Mobility.Engine.DefaultPreheat).
	The starter sound is set with the engine's sound banks (sound replacer tool, ace_enginestartersound).
]]
local StarterKgPerW = ( 2.2 + 12.5 ) / 1000

-- Rated (most) power of this engine's standard starter, W.
local function StarterBaseRatedW( Ent )
	local Model = ACE.Mobility and ACE.Mobility.Engine
	local Def = EngineTable[Ent.Id]
	if not Model or not Def then return 0 end
	local Spec = Model.Build( Def, ACE.GetEngineTorqueCurve( Def ) )
	if Spec.Kind == "electric" or Spec.Kind == "turbine" then return 0 end
	local _, StallW = Model.StarterRating( Spec )
	return StallW / 4
end

--- Applies an engine's starter and cooling setup and stores it so it survives duplication.
-- @param Setup table|nil { Size = number (0.5-3), Preheat = number|nil (s, 0-60),
-- Cooling = "air"|"liquid"|nil (nil = as the engine was built) }.
function ENT:SetStarterSetup( Setup )
	Setup = istable( Setup ) and Setup or {}
	local Size = math.Clamp( tonumber( Setup.Size ) or 1, 0.5, 3 )
	local Preheat = tonumber( Setup.Preheat )
	if Preheat then Preheat = math.Clamp( Preheat, 0, 60 ) end
	if Preheat == ACE.Mobility.Engine.DefaultPreheat then Preheat = nil end
	self.StarterSize, self.StarterPreheat = Size, Preheat
	-- Air or liquid cooling in place of the engine's own (ACE.Mobility.EngineSpec reads it).
	local Cooling = ( Setup.Cooling == "air" or Setup.Cooling == "liquid" ) and Setup.Cooling or nil
	if Cooling ~= self.CoolingChoice then
		self.CoolingChoice = Cooling
		self.MobSpec, self.ThermalSpec = nil, nil
	end
	self.StarterSetup = { Size = Size, Preheat = Preheat, Cooling = Cooling }
	-- Setups saved while the sound lived here carry it; it now belongs with the sound banks.
	if isstring( Setup.Sound ) and Setup.Sound ~= "" and ACE.EngineSound and ACE.EngineSound.SetStarterSound then
		ACE.EngineSound.SetStarterSound( self, Setup.Sound )
	end

	-- The bigger (or smaller) starter and battery weigh more (or less).
	local Extra = ( Size - 1 ) * StarterBaseRatedW( self ) * StarterKgPerW
	if math.abs( Extra - ( self.StarterExtraKg or 0 ) ) > 0.01 then
		self.Weight = math.max( self.Weight - ( self.StarterExtraKg or 0 ) + Extra, 1 )
		self.StarterExtraKg = Extra
		local Phys = self:GetPhysicsObject()
		if IsValid( Phys ) then Phys:SetMass( self.Weight ) end
	end

	if Size == 1 and not Preheat and not Cooling then
		duplicator.ClearEntityModifier( self, "ACE_EngineStarter" )
	else
		duplicator.StoreEntityModifier( self, "ACE_EngineStarter", self.StarterSetup )
	end
	self:UpdateOverlayText()
end

duplicator.RegisterEntityModifier( "ACE_EngineStarter", function( _, Ent, Data )
	if IsValid( Ent ) and Ent.SetStarterSetup then Ent:SetStarterSetup( Data ) end
end )

--- Hands the starter setup and the temperatures that decide a start to the engine model.
-- @param Spec table Engine spec (gets StarterMul and PreheatMax).
-- @param State table|nil Engine state (gets AirC, CoolantC and BlockC, °C).
function ENT:StarterModelInputs( Spec, State )
	Spec.StarterMul = self.StarterSize or 1
	Spec.PreheatMax = self.StarterPreheat
	if State then
		State.AirC = ACE.AmbientTemp
		State.CoolantC = self.Heat
		State.BlockC = self.BlockHeat or self.Heat
	end
end

--- The engine's own lead-acid starter battery (ACE.Mobility.Battery.StarterPack), sized from
-- its starter; created full.
-- @param Spec table Engine spec.
-- @return table|nil Pack, nil for motors and turbines.
function ENT:GetStarterPack( Spec )
	if Spec.Kind == "electric" or Spec.Kind == "turbine" then return nil end
	local _, StallW = ACE.Mobility.Engine.StarterRating( Spec )
	local Pack = self.StarterPack
	if not Pack then
		Pack = ACE.Mobility.Battery.StarterPack( StallW / 4 )
		self.StarterPack = Pack
	elseif Pack.RatedW ~= StallW / 4 then
		ACE.Mobility.Battery.StarterPackResize( Pack, StallW / 4 )
	end
	Pack.RatedW = StallW / 4
	return Pack
end

--- What the starter motor runs on this tick. The first linked starter battery that is on, legal
-- and holds charge feeds it (ENT:LinkStarterBattery). With no battery linked the engine cranks
-- on its own lead-acid battery (ENT:GetStarterPack), which its alternator recharges. With
-- batteries linked but all flat, off or illegal, the starter gets nothing.
-- @param Spec table Engine spec.
-- @return table { Volt, Sag, EnergyJ } as the engine model's State.StarterSupply.
function ENT:StarterSupply( Spec )
	for I = #self.BatteryLink, 1, -1 do
		if not IsValid( self.BatteryLink[I] ) then table.remove( self.BatteryLink, I ) end
	end
	self.StarterBattery = nil

	local Supply = self.MobStarterSupply or {}
	self.MobStarterSupply = Supply
	Supply.Volt, Supply.Sag, Supply.EnergyJ = 0, 0, 0
	if not next( self.BatteryLink ) then
		local Pack = self:GetStarterPack( Spec )
		if Pack then
			Supply.Volt, Supply.Sag, Supply.EnergyJ = ACE.Mobility.Battery.StarterPackSupply( Pack, ACE.AmbientTemp )
		end
		return Supply
	end

	for _, Bat in ipairs( self.BatteryLink ) do
		if Bat.Fuel > 0 and Bat.Active and Bat.Legal and Bat.BatteryState then
			local _, StallW = ACE.Mobility.Engine.StarterRating( Spec )
			Supply.Volt, Supply.Sag = ACE.Mobility.Battery.StarterSupply( Bat.BatterySpec, Bat.BatteryState,
				Bat.Fuel / math.max( Bat.Capacity, 1e-6 ), StallW )
			Supply.EnergyJ = Bat.Fuel * 3.6e6
			self.StarterBattery = Bat
			break
		end
	end
	return Supply
end

--[[
	Alternator. While the engine runs it recharges the starter battery (the built-in one, or a
	linked ACE battery) and loads the crank with the power that takes over its efficiency.
	AlternatorEff: 0.55, claw-pole alternators convert 50-65 % (Bosch Automotive Handbook,
	  alternators; estimated midpoint).
	AlternatorPerW: most charging power per watt of the starter's rated power, 1.5 (car: a 1.4 kW
	  starter and a 1.5-2 kW alternator, of which part feeds the vehicle's own loads, which are
	  not modelled; estimated). Below idle the alternator gives proportionally less.
]]
local AlternatorEff  = 0.55
local AlternatorPerW = 1.5

--- Charging power the alternator delivers this tick: as much as the starter battery accepts,
-- up to the alternator's output at the present crank speed.
-- @param Spec table Engine spec.
-- @param State table Engine state.
-- @return number Watts at the battery terminals (0 while the engine is not running).
-- @return table|Entity|nil The built-in pack or the linked battery it goes to.
function ENT:AlternatorCharge( Spec, State )
	if not State.Running or ( State.W or 0 ) <= 0 then return 0 end
	local _, StallW = ACE.Mobility.Engine.StarterRating( Spec )
	local Most = AlternatorPerW * StallW / 4 * math.Clamp( State.W / Spec.IdleW, 0, 1 )
	local Bat = self.BatteryLink[1]
	if IsValid( Bat ) then
		if not Bat.ChargeAcceptW or not Bat.Active or not Bat.Legal then return 0 end
		return math.min( Most, Bat:ChargeAcceptW() ), Bat
	end
	local Pack = self.StarterPack
	if not Pack then return 0 end
	return math.min( Most, ACE.Mobility.Battery.StarterPackAcceptW( Pack ) ), Pack
end

--- Load torque of the alternator on the crank at its charging power.
-- @param Spec table Engine spec.
-- @param State table Engine state.
-- @return number N·m.
function ENT:AlternatorTorque( Spec, State )
	local ChargeW = self:AlternatorCharge( Spec, State )
	self.MobAltW = ChargeW
	if ChargeW <= 0 then return 0 end
	return ChargeW / AlternatorEff / math.max( State.W, 0.5 * Spec.IdleW )
end

--- Bills the starter's (and glow plugs') electricity to its battery, charges it from the
-- alternator, and tells the owner when the starter cuts out on heat or its battery is flat.
-- @param State table Engine state.
-- @param Dt number Tick length, s.
function ENT:StarterApply( State, Dt )
	local Battery = ACE.Mobility.Battery
	local Pack = self.StarterPack
	local Joules = State.StarterJ or 0
	if Joules > 0 then
		State.StarterJ = 0
		local Bat = self.StarterBattery
		if IsValid( Bat ) and Bat.DrawEnergy then
			Bat:DrawEnergy( Joules / 3.6e6, Dt )
		elseif Pack and not next( self.BatteryLink ) then
			Battery.StarterPackDraw( Pack, Joules )
		end
	end

	local Spec = self.MobSpec
	if Spec and ( self.MobAltW or 0 ) > 0 then
		local ChargeW, Target = self:AlternatorCharge( Spec, State )
		ChargeW = math.min( ChargeW, self.MobAltW )
		if Target == Pack and Pack then
			Battery.StarterPackCharge( Pack, ChargeW * Dt )
		elseif IsValid( Target ) and Target.StoreEnergy then
			Target:StoreEnergy( ChargeW * Dt / 3.6e6, Dt )
		end
	end
	if Pack then Battery.StarterPackStep( Pack, Dt ) end

	local Cut = State.StarterOn and State.StarterCut or false
	local Supply = State.StarterSupply
	local Flat = State.StarterOn and Supply ~= nil and Supply.Volt <= 0 or false
	local Preheating = State.StarterOn and State.Preheating or false
	if Cut ~= (self.StarterWasCut or false) or Flat ~= (self.StarterWasFlat or false) or Preheating ~= (self.StarterWasPreheating or false) then
		self.StarterWasCut, self.StarterWasFlat, self.StarterWasPreheating = Cut, Flat, Preheating
		self:UpdateOverlayText()
		if (Cut or Flat) and ACE.CurTime > (self.NextStarterHint or 0) then
			self.NextStarterHint = ACE.CurTime + 15
			local Msg = "[ACE] Starter overheated - it cranks again once it cools down."
			if Flat then
				Msg = next( self.BatteryLink ) and "[ACE] Starter battery is flat or switched off."
					or "[ACE] Engine starter battery is flat - rest it a few minutes, link a charged battery to the engine, or push start in gear."
			end
			ACE.SendEngineHint( self:CPPIGetOwner(), Msg, Color( 255, 160, 0 ) )
		end
	end
end

-- Checks if the fuel tank is valid, has fuel, is active and was not marked as illegal.
local function IsValidfueltank( Tank )
	return IsValid(Tank) and Tank.Fuel > 0 and Tank.Active and Tank.Legal
end

--[[
	Fuel feed. All linked tanks feed the engine together, as a crossfeed system does: liquid fuel
	is drawn from each in proportion to what it holds, so they run dry together and the weight
	stays balanced. Batteries are wired in parallel: each gives current in proportion to its
	conductance (capacity over internal resistance, held back by its BMS derate) and to how far
	its open-circuit voltage stands above an empty cell's, so fuller and larger packs give more
	and the packs even out (an estimated stand-in for solving the parallel circuit). Regenerative
	braking charges every battery in proportion to the charge it accepts.

	The tank list and the shares are rebuilt every FeedRescan seconds, and the fuel burned is
	added up and taken from the tanks every FeedFlush seconds (constants at the top of the file),
	so the per-tick cost does not grow with the number of tanks.
]]

-- Rebuilds the tanks feeding the engine and their shares.
function ENT:ScanFeed()
	local Battery = ACE.Mobility.Battery
	local EmptyV = Battery.OCV(0)
	local Feed, Charge = self.Feed or {}, self.ChargeFeed or {}
	local NFeed, NCharge = 0, 0
	local DerateSum, CapSum, AcceptSum = 0, 0, 0
	for _, Tank in ipairs(self.FuelLink) do
		if IsValid(Tank) then
			local State = Tank.BatteryState
			if IsValidfueltank(Tank) then
				local Share = Tank.Fuel
				if State then
					local SOC = Tank.Fuel / math.max(Tank.Capacity, 1e-6)
					local Derate = Battery.DischargeDerate(State)
					local Cap = Tank.NominalCapacity * Battery.Health(State)
					Share = Cap / Battery.Resistance(State) * Derate * math.max(Battery.OCV(SOC) - EmptyV, 0.01)
					DerateSum = DerateSum + Cap * Derate
					CapSum = CapSum + Cap
				end
				NFeed = NFeed + 1
				Feed[NFeed] = Tank
				Tank.FeedShare = Share
			end
			if State and Tank.ChargeAcceptW then
				local Accept = Tank:ChargeAcceptW()
				if Accept > 0 then
					NCharge = NCharge + 1
					Charge[NCharge] = Tank
					Tank.ChargeShare = Accept
					AcceptSum = AcceptSum + Accept
				end
			end
		end
	end
	for I = NFeed + 1, #Feed do Feed[I] = nil end
	for I = NCharge + 1, #Charge do Charge[I] = nil end
	self.Feed, self.ChargeFeed = Feed, Charge
	-- The packs' BMS limits add up: the bank gives the capacity-weighted share of full power.
	self.FeedDerate = CapSum > 0 and DerateSum / CapSum or 1
	self.ChargeAcceptSum = AcceptSum
	self.NextFeedScan = ACE.CurTime + FeedRescan
end

--- Burns fuel from the engine's tanks (all of them together, see ScanFeed).
-- @param Amount number Litres of fuel, or kWh for batteries.
function ENT:DrawFuel(Amount)
	self.FeedPending = (self.FeedPending or 0) + Amount
end

--- Stores regenerated energy in the engine's batteries, shared by their charge acceptance.
-- @param KWh number Energy at the terminals, kWh.
function ENT:ChargeFuel(KWh)
	self.ChargePending = (self.ChargePending or 0) + KWh
end

-- Takes the fuel added up since the last flush (Dt seconds ago) from the tanks.
function ENT:FlushFeed(Dt)
	local Draw, Store = self.FeedPending or 0, self.ChargePending or 0
	self.FeedPending, self.ChargePending = 0, 0
	if Dt <= 0 then return end

	local Feed = self.Feed
	if Draw > 0 and Feed then
		local Sum = 0
		for I = 1, #Feed do
			local Tank = Feed[I]
			if IsValid(Tank) and Tank.Fuel > 0 then Sum = Sum + Tank.FeedShare end
		end
		if Sum > 0 then
			for I = 1, #Feed do
				local Tank = Feed[I]
				if IsValid(Tank) and Tank.Fuel > 0 then
					local Part = Draw * Tank.FeedShare / Sum
					if Tank.BatteryState then
						Tank:DrawEnergy(Part, Dt) -- the battery also loses its resistive heat
					else
						Tank.Fuel = math.max(Tank.Fuel - Part, 0)
						if Tank.Fuel <= 0 then self.NextFeedScan = 0 end
					end
				end
			end
		end
	end

	local Charge = self.ChargeFeed
	local AcceptSum = self.ChargeAcceptSum or 0
	if Store > 0 and Charge and AcceptSum > 0 then
		for I = 1, #Charge do
			local Tank = Charge[I]
			if IsValid(Tank) then Tank:StoreEnergy(Store * Tank.ChargeShare / AcceptSum, Dt) end
		end
	end
end

-- Per-tick checks that decide whether the engine may run: fuel, driver, legality, heat and
-- damage. Torque and RPM come from the drivetrain solve in ace/server/sv_mobility.lua.
function ENT:CalcRPM()

	if ACE.CurTime >= (self.NextFeedScan or 0) then self:ScanFeed() end
	-- The first feeding tank stands for the fuel type the engine burns.
	local Tank = self.Feed[1]
	if Tank ~= nil and not IsValidfueltank(Tank) then
		self:ScanFeed()
		Tank = self.Feed[1]
	end
	self.MobTank = Tank

	if IsValid(Tank) then
		self.HasFuel = true
	else
		self.HasFuel = false
		Wire_TriggerOutput(self, "Fuel Use", 0)

		if ACE.EnginesRequireFuel == 1 then
			self:TriggerInput( "Active", 0 ) --shut off if no fuel and requires it
			return
		end
	end

	ACE.DoContraptionLegalCheck(self)

	if self.RequiresDriver and not (self.HasDriver or self.HasSeatDriver) then
		self:TriggerInput( "Active", 0 ) --shut off if no driver and requires it
		return
	end

	-- Damage lowers the torque an engine can make; a driver boosts it. TorqueScale sets how
	-- quickly damage bites for this engine type.
	local DriverBoost = self.HasDriver and ACE.DriverTorqueBoost or 1 --Seat drivers dont give hp boost.
	self.TorqueMult = math.Clamp(((1 - self.TorqueScale) / 0.5) * ((self.ACE.Health / self.ACE.MaxHealth) - 1) + 1, self.TorqueScale, 1)
	-- An overheated engine also loses torque (ACE.EngineThermalThink).
	self.PeakTorque = self.BaseTorque * self.TorqueMult * DriverBoost * (self.ThermalDerate or 1)
	-- A hot battery pack is held back by its management system (battery_model.lua).
	if self.FuelType == "Electric" and IsValid(Tank) then
		self.PeakTorque = self.PeakTorque * (self.FeedDerate or 1)
	end

	local HealthRatio = self.ACE.Health / self.ACE.MaxHealth
	if HealthRatio < 0.995 then
		if HealthRatio > 0.025 then
			local PhysObj = self:GetPhysicsObject()
			local Mass = PhysObj:GetMass()
			ACE.Damage(self, {
				Kinetic = (1 + math.max(Mass / 2, 20) / 2.5) * 5 * self.Throttle / 100,
				Momentum = 0,
				Penetration = (1 + math.max(Mass / 2, 20) / 2.5) * 5 * self.Throttle / 100
			}, 2, 0, self:CPPIGetOwner())

			if math.Rand(0,1) > 0.99 * HealthRatio * 1.2 then
				self:EmitSound( "ambient/materials/door_hit1.wav", 120, math.random(45,100)  ) --npc/strider/strider_step4.wav
			end

		else
			--Turns Off due to massive damage
			self:TriggerInput("Active", 0)
		end
	end
end

-- Builds this engine's part of the drivetrain description. Called by ACE.Mobility.Tick.
function ENT:MobilityDesc(Ctx)
	local Tank = self.Active and self.MobTank or nil
	local Spec = ACE.Mobility.EngineSpec(self, IsValid(Tank) and Tank.FuelType or nil)

	local Gearboxes = {}
	local Assisted = false
	for _, Link in pairs(self.GearLink) do
		local Box = Link.Ent
		if IsValid(Box) and Box.Legal then
			Gearboxes[#Gearboxes + 1] = ACE.Mobility.GearboxDesc(Box, Ctx)
			Assisted = Assisted or ACE.Mobility.IsAssisted(Box)
		end
	end

	local Running = self.Active and self.Legal

	local Desc = self.MobDesc or {}
	self.MobDesc = Desc
	Desc.Spec, Desc.State = Spec, self.MobState
	Desc.Throttle = Running and self.Throttle or 0
	if self.FuelType == "Electric" and (self.RegenCommand or 0) > 0 then
		Desc.Throttle = Running and -self.RegenCommand or 0
	end
	Desc.HasFuel = Running and (IsValid(Tank) or ACE.EnginesRequireFuel == 0)
	Desc.NoStall = Assisted
	-- Damage and the driver boost. Parented mass is handled at the road by ACE.Mobility.Tick.
	Desc.TorqueMul = self.PeakTorque / self.BaseTorque
	Desc.Gearboxes = Gearboxes
	if self.FuelType == "Electric" and self.MobState then
		-- Regenerative braking needs somewhere to put the charge, and a battery only takes as
		-- much as its CC-CV charge acceptance allows: nothing once every linked battery is full.
		if not self.ChargeFeed then self:ScanFeed() end
		self.MobState.RegenLimitW = self.ChargeAcceptSum or 0
		self.MobState.Direction = self.ReverseInput and -1 or 1
	end
	-- Belt-driven accessories such as a radiator fan.
	-- Radiators add their fan load between Thinks; MobilityApply holds it for every physics step
	-- until the next.
	Desc.AccessoryTorque = self.MobAccessory or self.AccessoryTorque or 0
	if self.MobState and Spec.Kind ~= "electric" and Spec.Kind ~= "turbine" then
		-- The starter setup, the temperatures a start depends on, what the starter motor runs on
		-- this tick (engine_model.lua, starter) and the alternator recharging its battery.
		self:StarterModelInputs(Spec, self.MobState)
		self.MobState.StarterSupply = self:StarterSupply(Spec)
		Desc.AccessoryTorque = Desc.AccessoryTorque + self:AlternatorTorque(Spec, self.MobState)
	end
	return Desc
end

-- The in-step drivetrain: the physics engine calls this inside every step for the wheels this
-- engine's motion controller holds (see ACE.Mobility.PhysicsStep).
function ENT:PhysicsSimulate(Phys, Dt)
	ACE.Mobility.PhysicsStep(self, Phys, Dt)
	return vector_origin, vector_origin, SIM_NOTHING
end

-- Reads back the solve: fuel burned, heat made, RPM and torque outputs, and stalls.
function ENT:MobilityApply()
	local Desc = self.MobDesc
	local State = self.MobState
	if not Desc or not State then return end
	self.MobAccessory = self.AccessoryTorque or 0
	self.AccessoryTorque = 0

	local RPM = State.W * 30 / math.pi
	-- Only electric motors turn backwards; RPM and sound follow the speed either way.
	self.FlyRPM = self.FuelType == "Electric" and math.abs(RPM) or math.max(RPM, 0)
	self.Torque = Desc.AvgTorque or 0

	local Dt = self.MobDt or engine.TickInterval()
	local Tank = self.MobTank
	local FuelKg = Desc.FuelKg or 0
	if self.Active and IsValid(Tank) and FuelKg > 0 then
		local Used
		if self.FuelType == "Electric" then
			Used = FuelKg / 3.6e6 -- electric "fuel" is energy: J to kWh
		else
			Used = FuelKg / (ACE.FuelDensity[Tank.FuelType] or 0.745) -- kg to litres
		end
		self:DrawFuel(Used)
		Wire_TriggerOutput(self, "Fuel Use", math.Round(60 * Used / Dt, 3))
	elseif self.Active and FuelKg < 0 and self.FuelType == "Electric" then
		-- Regenerative braking: the motor returned energy, which charges a battery with room.
		local Charged = -FuelKg / 3.6e6
		self:ChargeFuel(Charged)
		Wire_TriggerOutput(self, "Fuel Use", -math.Round(60 * Charged / Dt, 3))
	end
	if self.FuelType ~= "Electric" then self:StarterApply(State, Dt) end

	if (Desc.HeatJ or 0) > 0 then
		self.HeatGeneration = Desc.HeatJ / 1000 / Dt -- kJ/s, shown in the menu
		ACE.EngineThermalInput(self, Desc)
	end

	-- Over-revving: the limiter only cuts fuel, so a missed downshift can still drag the engine
	-- far past redline through the wheels. Past ~110% valves float and hit pistons.
	local Over = self.FlyRPM / self.LimitRPM - 1.1
	if Over > 0 and self.ACE and self.ACE.Health then
		self.ACE.Health = math.max(self.ACE.Health - self.ACE.MaxHealth * Over * Dt, 0)
		if self.ACE.Health <= 0 and self.Active then self:TriggerInput("Active", 0) end
	end

	if self.Active and State.Stalled then
		State.Stalled = false
		self.Active = false
		self.Stalled = true
		Wire_TriggerOutput(self, "Stalled", 1)
		ACE.EngineSound.Stop( self )
	end

	-- Signed: a motor driving backwards has negative torque and speed, positive power.
	local Power = self.Torque * (self.FuelType == "Electric" and RPM or self.FlyRPM) / 9548.8
	Wire_TriggerOutput(self, "Torque", math.Round(self.Torque))
	Wire_TriggerOutput(self, "Power", math.Round(Power))
	Wire_TriggerOutput(self, "RPM", math.Round(self.FlyRPM))

	-- Also called while off: the sound follows the crank as it spins down, and the starter is heard.
	ACE.EngineSound.Update( self, self.FlyRPM, self.Active and self.Throttle or 0 )
end

-------------------------- Periodic Link Engine checks --------------------------
do
	-- Checks the current ropes linked to this engine complies with the requirements to be valid.
	function ENT:CheckRopes()

		for _, Link in pairs( self.GearLink ) do

			local Ent = Link.Ent
			local OutPos = self:LocalToWorld( self.Out )
			local InPos = Ent:LocalToWorld( Ent.In )

			-- make sure it is not stretched too far
			if OutPos:Distance( InPos ) > Link.RopeLen * 1.5 then
				self:Unlink( Ent )
			end

			-- make sure the angle is not excessive
			if not self:Checkdriveshaft( Ent ) then
				self:Unlink( Ent )
				local soundstr =  "physics/metal/metal_box_impact_bullet" .. tostring(math.random(1, 3)) .. ".wav"
				self:EmitSound(soundstr,500,100)
			end
		end

	end

	-- Check fueltanks are within the range with the engine.
	function ENT:CheckFuel()
		for _,tank in pairs(self.FuelLink) do
			if self:GetPos():Distance(tank:GetPos()) > FuelLinkDistBase then
				self:Unlink( tank )
				local soundstr =  "physics/metal/metal_box_impact_bullet" .. tostring(math.random(1, 3)) .. ".wav"
				self:EmitSound(soundstr,500,100)
				self:UpdateOverlayText()
			end
		end

		self:TestDriverDistance()

	end


	--[[
	--HARDCODED. USE MODELDEFINITION INSTEAD
	local TransAxialGearboxes = {
		["models/engines/transaxial_l.mdl"] = true,
		["models/engines/transaxial_m.mdl"] = true,
		["models/engines/transaxial_s.mdl"] = true,
		["models/engines/transaxial_t.mdl"] = true --mhm acf extras invading...
	}
	]]

	-- make sure the angle is not excessive
	function ENT:Checkdriveshaft( NextEnt )
		local InPos = NextEnt:LocalToWorld( NextEnt.In ) 	--gearbox to connect to engine
		local OutPos = self:LocalToWorld( self.Out ) 		--the engine output

		local MaxAngle = 0.7 --magic number to define the max tolerance of link between gearboxes
		local Direction = self.IsTrans and -self:GetRight() or self:GetForward() --transaxial like turbines. Forward is for conventional engines like a V8
		local DrvAngle 	= ( OutPos - InPos ):GetNormalized():Dot( Direction )

		--Check if the link is right from engine's perspective
		if DrvAngle < MaxAngle then
			return false
		--else
			--[[ --Disabled since this could break several builds. When we have more junctions, this could be enforced.
			--Now, do the same, but from gearbox's perspective this time.
			Direction 	= TransAxialGearboxes[ NextEnt:GetModel() ] and -NextEnt:GetForward() or -NextEnt:GetRight()
			DrvAngle 	= ( InPos - OutPos ):GetNormalized():Dot( Direction )

			if DrvAngle < MaxAngle then
				return false
			end
			]]
		end

		return true
	end
end

-------------------------- Link Logic --------------------------
do

	local AllowedEnts = {
		acf_gearbox = true,
		acf_fueltank = true,
		ace_radiator = true,
		ace_crewseat_driver = true,
	}

	function ENT:Link( Target )

		if not IsValid( Target ) or not AllowedEnts[Target:GetClass()] then
			print(Target:GetClass())
			return false, "You can only link gearboxes, fueltanks or crewseats!"
		end

		-- Gear links
		if Target:GetClass() == "acf_gearbox" then
			return self:LinkGearbox( Target )
		end
		-- Fuel links
		if Target:GetClass() == "acf_fueltank" then
			return self:LinkFuel( Target )
		end
		-- Radiator links
		if Target:GetClass() == "ace_radiator" then
			return self:LinkRadiator( Target )
		end
		-- Crew links
		if Target:GetClass() == "ace_crewseat_driver" then
			return self:LinkCrew( Target )
		end
	end

	function ENT:Unlink( Target )

		if not IsValid( Target ) or not AllowedEnts[Target:GetClass()] then
			return false, "You can only unlink gearboxes, fueltanks, radiators, or crewseats!"
		end

		-- Gear links
		if Target:GetClass() == "acf_gearbox" then
			return self:UnlinkGearbox( Target )
		end
		-- Fuel links
		if Target:GetClass() == "acf_fueltank" then
			return self:UnlinkFuel( Target )
		end
		-- Radiator links
		if Target:GetClass() == "ace_radiator" then
			return self:UnlinkRadiator( Target )
		end
		-- Crew links
		if Target:GetClass() == "ace_crewseat_driver" then
			return self:UnlinkCrew( Target )
		end
	end

	function ENT:LinkGearbox( Target )

		-- Check if target is already linked
		for _, Link in pairs( self.GearLink ) do
			if Link.Ent == Target then
				return false, "This gearbox is already linked to this engine!"
			end
		end

		-- make sure the angle is not excessive
		if not self:Checkdriveshaft( Target ) then
			return false, "Cannot link due to excessive driveshaft angle!"
		end

		local InPos = Target:LocalToWorld( Target.In ) 	--gearbox to connect to engine
		local OutPos = self:LocalToWorld( self.Out ) 	--the engine output

		local Rope = nil
		if self:CPPIGetOwner():GetInfoNum( "ace_mobility_rope_links", 1) == 1 then
			Rope = ACE.CreateLinkRope( OutPos, self, self.Out, Target, Target.In )
		end

		local Link = {
			Ent 	= Target, 						-- Linked Gearbox
			Rope 	= Rope, 						-- Rope
			RopeLen = ( OutPos - InPos ):Length(), 	-- The length between the Engine Point to the Gearbox Point
			ReqTq 	= 0 							-- Possibly the requested torque from the gearbox to the engine?
		}

		table.insert( self.GearLink, Link )
		table.insert( Target.Master, self )

		return true, "Link successful!"
	end

	function ENT:UnlinkGearbox( Target )

		for Key, Link in pairs( self.GearLink ) do

			if Link.Ent == Target then

				-- Remove any old physical ropes leftover from dupes
				for _, Rope in pairs( constraint.FindConstraints( Link.Ent, "Rope" ) ) do
					if Rope.Ent1 == self or Rope.Ent2 == self then
						Rope.Constraint:Remove()
					end
				end

				if IsValid( Link.Rope ) then
					Link.Rope:Remove()
				end

				table.remove( self.GearLink,Key )

				return true, "Unlink successful!"
			end
		end

		return false, "That gearbox is not linked to this engine!"
	end

	function ENT:LinkCrew( Target )

		if not Target.Legal then
			return false, "The driver seat is illegal!"
		end

		if self.HasDriver then
			return false, "The engine already has a driver!"
		end

		table.insert( self.CrewLink, Target )
		table.insert( Target.Master, self )

		Target.LinkedEngine = self
		self.LinkedDriver = Target
		self.HasDriver = true
		self.CanUseSeatDriver = false --Driver specified. Seat can no longer be used as driver.
		self:UpdateOverlayText()

		return true, "Link successful!"
	end

	function ENT:UnlinkCrew( Target )

		self.HasDriver = false
		self:UpdateOverlayText()

		for Key,Value in pairs(self.CrewLink) do
			if Value == Target then
				Target.LinkedEngine = nil
				table.remove(self.CrewLink,Key)
				return true, "Unlink successful!"
			end
		end
	end

	function ENT:LinkFuel( Target )

		-- A battery linked to a piston or rotary engine feeds its starter.
		if Target.FuelType == "Electric" and self.FuelType ~= "Electric" then
			return self:LinkStarterBattery( Target )
		end

		if not (self.FuelType == "Multifuel" and Target.FuelType ~= "Electric") and self.FuelType ~= Target.FuelType then
			return false, "Cannot link because fuel type is incompatible."
		end

		if Target.NoLinks then
			return false, "This fuel tank doesn\'t allow linking."
		end

		for _, Value in pairs(self.FuelLink) do
			if Value == Target then
				return false, "That fuel tank is already linked to this engine!"
			end
		end

		if self:GetPos():Distance( Target:GetPos() ) > FuelLinkDistBase then
			return false, "The fuel tank is too far away."
		end

		table.insert( self.FuelLink, Target )
		table.insert( Target.Master, self )
		self.NextFeedScan = 0

		return true, "Link successful!"
	end

	function ENT:UnlinkFuel( Target )

		for Key, Value in pairs( self.FuelLink ) do
			if Value == Target then
				table.remove( self.FuelLink, Key )
				self.NextFeedScan = 0
				return true, "Unlink successful!"
			end
		end

		if table.HasValue( self.BatteryLink, Target ) then
			table.RemoveByValue( self.BatteryLink, Target )
			table.RemoveByValue( Target.Master, self )
			self:UpdateOverlayText()
			return true, "Starter battery unlinked."
		end

		return false, "That fuel tank is not linked to this engine!"
	end

	--- Links a battery to feed this engine's starter motor. Piston and rotary engines only:
	-- turbines and electric motors start without one.
	-- @param Target acf_fueltank holding Electric fuel.
	-- @return boolean, string Success and message.
	function ENT:LinkStarterBattery( Target )
		if self.EngineType == "Turbine" or self.EngineType == "GroundTurbine" then
			return false, "Turbines start without a starter battery."
		end
		if Target.NoLinks then
			return false, "This battery doesn\'t allow linking."
		end
		if table.HasValue( self.BatteryLink, Target ) then
			return false, "That battery already feeds this engine's starter!"
		end
		if self:GetPos():Distance( Target:GetPos() ) > FuelLinkDistBase then
			return false, "The battery is too far away."
		end

		table.insert( self.BatteryLink, Target )
		table.insert( Target.Master, self )
		self:UpdateOverlayText()

		return true, "Battery linked to the starter."
	end
end

function ENT:LinkRadiator( Target )

	for _, Value in pairs(self.RadLink) do
		if Value == Target then
			return false, "That radiator is already linked to this engine!"
		end
	end

	if self:GetPos():Distance( Target:GetPos() ) > FuelLinkDistBase then
		return false, "The radiator is too far away."
	end

	table.insert( self.RadLink, Target )
	table.insert( Target.Master, self )

	return true, "Link successful!"
end

function ENT:UnlinkRadiator( Target )

	for Key, Value in pairs( self.RadLink ) do
		if Value == Target then
			table.remove( self.RadLink, Key )
			-- The radiator must forget this engine too, or it keeps sharing its cooling with it.
			table.RemoveByValue( Target.Master, self )
			return true, "Unlink successful!"
		end
	end

	return false, "That radiator is not linked to this engine!"
end

-------------------------- Duplicator related stuff --------------------------
do
	function ENT:PreEntityCopy()

		--Link Saving
		local info = {}
		local entids = {}
		for Key, Link in pairs( self.GearLink ) do				--First clean the table of any invalid entities
			if not IsValid( Link.Ent ) then
				table.remove( self.GearLink, Key )
			end
		end
		for _, Link in pairs( self.GearLink ) do				--Then save it
			table.insert( entids, Link.Ent:EntIndex() )
		end

		info.entities = entids
		if info.entities then
			duplicator.StoreEntityModifier( self, "GearLink", info )
		end

		--fuel tank link saving
		local fuel_info = {}
		local fuel_entids = {}
		for _, Value in pairs(self.FuelLink) do				--First clean the table of any invalid entities
			if not Value:IsValid() then
				table.remove(self.FuelLink, Value)
			end
		end
		for _, Value in pairs(self.FuelLink) do				--Then save it
			table.insert(fuel_entids, Value:EntIndex())
		end
		-- Starter batteries are saved with the fuel tanks; pasting relinks them through
		-- ENT:LinkFuel, which sends batteries to the starter.
		for _, Value in ipairs(self.BatteryLink) do
			if IsValid(Value) then table.insert(fuel_entids, Value:EntIndex()) end
		end

		fuel_info.entities = fuel_entids
		if fuel_info.entities then
			duplicator.StoreEntityModifier( self, "FuelLink", fuel_info )
		end

		--fuel tank link saving
		local rad_info = {}
		local rad_entids = {}
		for _, Value in pairs(self.RadLink) do				--First clean the table of any invalid entities
			if not Value:IsValid() then
				table.remove(self.RadLink, Value)
			end
		end
		for _, Value in pairs(self.RadLink) do				--Then save it
			table.insert(rad_entids, Value:EntIndex())
		end

		rad_info.entities = rad_entids
		if rad_info.entities then
			duplicator.StoreEntityModifier( self, "RadLink", rad_info )
		end

		--driver seat link saving
		for _, Value in pairs(self.CrewLink) do				--First clean the table of any invalid entities
			if not Value:IsValid() then
				table.remove(self.CrewLink, Value)
			end
		end
		for _, Value in pairs(self.CrewLink) do				--Then save it
			table.insert(entids, Value:EntIndex())
		end

		info.entities = entids
		if info.entities then
			duplicator.StoreEntityModifier( self, "CrewLink", info )
		end

		--Wire dupe info
		self.BaseClass.PreEntityCopy( self )

	end

	function ENT:PostEntityPaste( Player, Ent, CreatedEntities )

		--Link Pasting
		if Ent.EntityMods and Ent.EntityMods.GearLink and Ent.EntityMods.GearLink.entities then
			local GearLink = Ent.EntityMods.GearLink
			if GearLink.entities and next(GearLink.entities) then
				timer.Simple( 0, function() -- this timer is a workaround for an ad2/makespherical issue https://github.com/nrlulz/ACF/issues/14#issuecomment-22844064
					for _,ID in pairs(GearLink.entities) do
						local Linked = CreatedEntities[ ID ]
						if IsValid( Linked ) then
							self:Link( Linked )
						end
					end
				end )
			end
			Ent.EntityMods.GearLink = nil
		end
		--fuel tank link Pasting
		if Ent.EntityMods and Ent.EntityMods.FuelLink and Ent.EntityMods.FuelLink.entities then
			local FuelLink = Ent.EntityMods.FuelLink
			if FuelLink.entities and next(FuelLink.entities) then
				for _,ID in pairs(FuelLink.entities) do
					local Linked = CreatedEntities[ ID ]
					if IsValid( Linked ) then
						self:Link( Linked )
					end
				end
			end
			Ent.EntityMods.FuelLink = nil
		end
		--radiator link Pasting
		if Ent.EntityMods and Ent.EntityMods.RadLink and Ent.EntityMods.RadLink.entities then
			local RadLink = Ent.EntityMods.RadLink
			if RadLink.entities and next(RadLink.entities) then
				for _,ID in pairs(RadLink.entities) do
					local Linked = CreatedEntities[ ID ]
					if IsValid( Linked ) then
						self:Link( Linked )
					end
				end
			end
			Ent.EntityMods.RadLink = nil
		end
		--ace_crewseat_gunner
		if Ent.EntityMods and Ent.EntityMods.CrewLink and Ent.EntityMods.CrewLink.entities then
			local CrewLink = Ent.EntityMods.CrewLink
			if CrewLink.entities and next(CrewLink.entities) then
				for _,ID in pairs(CrewLink.entities) do
					local Linked = CreatedEntities[ ID ]
					if IsValid( Linked ) then
						self:Link( Linked )
					end
				end
			end
			Ent.EntityMods.CrewLink = nil
		end
		--Wire dupe info
		self.BaseClass.PostEntityPaste( self, Player, Ent, CreatedEntities )
	end
end
function ENT:OnRemove()
	ACE.EngineSound.Stop( self, true )
end

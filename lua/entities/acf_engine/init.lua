-- init.lua

AddCSLuaFile( "shared.lua" )
AddCSLuaFile( "cl_init.lua" )

include("shared.lua")

local EngineTable = ACE.Weapons.Engines
local FuelLinkDistBase = 512

do

	local EngineWireDescs = {
		--Inputs
		["Throttle"]    = "Controls the amount of fuel which will be displaced to the engine.\n Increasing it will also increase RPM, Power and fuel consumption. Values go from 0-100.",
		["Exhaust"]     = "Entity that sound banks marked 'Play at exhaust' play from.",

		--Outputs
		["RPM"]         = "Returns the current RPM.",
		["Torque"]      = "Returns the current Torque.",
		["Power"]       = "Returns the current power of this engine.",
		["Fuel Use"]    = "Gives the actual fuel consumption of the engine.",
		["EngineHeat"]  = "Returns the engine's temperature.",
		["Stalled"]     = "1 when the engine has stalled. Cycle Active to crank it again."
	}

	function ENT:Initialize()

		self.Throttle       = 0
		self.Active         = false
		self.IsMaster       = true
		self.GearLink       = {} -- a "Link" has these components: Ent, Rope, RopeLen, ReqTq
		self.FuelLink       = {}
		self.RadLink       = {}
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

		self.Inputs = WireLib.CreateSpecialInputs( self, { "Active", "Throttle (" .. EngineWireDescs["Throttle"] .. ")", "Exhaust (" .. EngineWireDescs["Exhaust"] .. ")" }, { "NORMAL", "NORMAL", "ENTITY" } ) --use fuel input?
		self.Outputs = WireLib.CreateSpecialOutputs( self,  { "RPM (" .. EngineWireDescs["RPM"] .. ")", "Torque (" .. EngineWireDescs["Torque"] .. ")", "Power (" .. EngineWireDescs["Power"] .. ")", "Fuel Use (" .. EngineWireDescs["Fuel Use"] .. ")", "Total Fuel" , "Entity", "Mass", "Physical Mass" , "EngineHeat (" .. EngineWireDescs["EngineHeat"] .. ")", "Stalled (" .. EngineWireDescs["Stalled"] .. ")"},
														{ "NORMAL","NORMAL","NORMAL", "NORMAL", "NORMAL", "ENTITY", "NORMAL", "NORMAL", "NORMAL", "NORMAL" } )

		Wire_TriggerOutput( self, "Entity", self )
		Wire_TriggerOutput(self, "EngineHeat", self.Heat)

		self.WireDebugName = "ACF Engine"

		self.CanLegalCheck = true

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
		Engine.Efficiency     = 1-(ACE.Efficiency[Engine.EngineType] or ACE.Efficiency["GenericPetrol"])  * (1 + (Engine.peakkw * 1.34/2000)*0.1) -- Energy not transformed into kinetic energy and instead into thermal
		Engine.EfficiencyMod	= Engine.Efficiency
		Engine.TorqueCurve	= Lookup.torquecurve or ACE.GenericTorqueCurves[Engine.EngineType]
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

	self:SetNWString( "WireName", Lookup.name )
	self:UpdateOverlayText()

	ACE.Activate( self, 1 )
	if ACE.PointsInputChanged then ACE.PointsInputChanged( self, "engine-updated" ) end

	return true, "Engine updated successfully!" .. Feedback
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
	text = text .. "Temp: " .. math.Round(self.Heat) .. " °C / " .. math.Round((self.Heat * (9 / 5)) + 32) .. " °F\n"

	--if self.FuelLink and #self.FuelLink > 0 then
	if self.HasFuel then
		text = text .. "\nSupplied with " .. (self.EngineType == "Electric" and "Batteries" or "Fuel")
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

	if (iname == "Throttle") then
		self.Throttle = math.Clamp(value,0,100) / 100
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
						ACE.ChatMessagePly( self:CPPIGetOwner() , "[ACE] Your engine requires fuel to work and that it be activated BEFORE the engine.", Color( 255, 0, 0 ))
						self.OTWarnings.WarnedFuel = true
					end
				end

				if not HasDriver then
					local HasWarned = self.OTWarnings.WarnedDriver or false
					--self.OTWarnings
					if not HasWarned then
						ACE.ChatMessagePly( self:CPPIGetOwner() , "[ACE] Your engine is above [" .. ACE.LargeEngineThreshold .. " hp] requiring a driver to work.", Color( 255, 0, 0 ))
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
	end

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
	ACE.Mobility.EngineSpec(self, self.FuelType)
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

-- Checks if the fuel tank is valid, has fuel, is active and was not marked as illegal.
local function IsValidfueltank( Tank )
	return IsValid(Tank) and Tank.Fuel > 0 and Tank.Active and Tank.Legal
end

-- Per-tick checks that decide whether the engine may run: fuel, driver, legality, heat and
-- damage. Torque and RPM come from the drivetrain solve in ace/server/sv_mobility.lua.
function ENT:CalcRPM()

	local DeltaTime = math.min(CurTime() - self.LastThink, 0.1)

	-- First active fuel tank among the linked ones.
	local Tank
	for _, FuelTank in ipairs(self.FuelLink) do
		if IsValidfueltank( FuelTank ) then
			Tank = FuelTank
			break
		end
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

	-- Air cooling improves with speed: it doubles every 40 mph.
	local Speed = math.min(ACE.GetPhysicalParent(self):GetVelocity():Length() / 17.6, 141)
	local CoolingMult = 2 ^ (Speed / 40)
	ACE.AtmosphericHeatDissipation(self, CoolingMult, DeltaTime)

	ACE.DoContraptionLegalCheck(self)

	if self.RequiresDriver and not (self.HasDriver or self.HasSeatDriver) then
		self:TriggerInput( "Active", 0 ) --shut off if no driver and requires it
		return
	end

	-- Damage lowers the torque an engine can make; a driver boosts it. TorqueScale sets how
	-- quickly damage bites for this engine type.
	local DriverBoost = self.HasDriver and ACE.DriverTorqueBoost or 1 --Seat drivers dont give hp boost.
	self.TorqueMult = math.Clamp(((1 - self.TorqueScale) / 0.5) * ((self.ACE.Health / self.ACE.MaxHealth) - 1) + 1, self.TorqueScale, 1)
	self.PeakTorque = self.BaseTorque * self.TorqueMult * DriverBoost

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
	Desc.HasFuel = Running and (IsValid(Tank) or ACE.EnginesRequireFuel == 0)
	Desc.NoStall = Assisted
	-- Mass parented onto a contraption has no weight in Source's physics, so engines lose torque
	-- in proportion to it (MassRatio). This is a balance rule kept from the old drivetrain.
	Desc.TorqueMul = (self.PeakTorque / self.BaseTorque) * (self.MassRatio or 1)
	Desc.Gearboxes = Gearboxes
	-- Belt-driven accessories such as a radiator fan.
	Desc.AccessoryTorque = self.AccessoryTorque or 0
	self.AccessoryTorque = 0
	return Desc
end

-- Reads back the solve: fuel burned, heat made, RPM and torque outputs, and stalls.
function ENT:MobilityApply()
	local Desc = self.MobDesc
	local State = self.MobState
	if not Desc or not State then return end

	local RPM = State.W * 30 / math.pi
	self.FlyRPM = math.max(RPM, 0)
	self.Torque = Desc.AvgTorque or 0

	local Dt = self.MobDt or engine.TickInterval()
	local Tank = self.MobTank
	if self.Active and IsValid(Tank) and (Desc.FuelKg or 0) > 0 then
		local Used
		if self.FuelType == "Electric" then
			Used = Desc.FuelKg / 3.6e6 -- electric "fuel" is energy: J to kWh
		else
			Used = Desc.FuelKg / (ACE.FuelDensity[Tank.FuelType] or 0.745) -- kg to litres
		end
		Tank.Fuel = math.max(Tank.Fuel - Used, 0)
		Wire_TriggerOutput(self, "Fuel Use", math.Round(60 * Used / Dt, 3))
	end

	if (Desc.HeatJ or 0) > 0 then
		self.HeatGeneration = Desc.HeatJ / 1000 / Dt -- kJ/s, shown in the menu
		ACE.AddThermalEnergy(self, Desc.HeatJ / 1000 * ACE.ThermalTimeScale)
	end

	if self.Active and State.Stalled then
		State.Stalled = false
		self.Active = false
		self.Stalled = true
		Wire_TriggerOutput(self, "Stalled", 1)
		ACE.EngineSound.Stop( self )
	end

	local Power = self.Torque * self.FlyRPM / 9548.8
	Wire_TriggerOutput(self, "Torque", math.Round(self.Torque))
	Wire_TriggerOutput(self, "Power", math.Round(Power))
	Wire_TriggerOutput(self, "RPM", math.Round(self.FlyRPM))

	if self.Active then
		ACE.EngineSound.Update( self, self.FlyRPM, self.Throttle )
	end
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

		return true, "Link successful!"
	end

	function ENT:UnlinkFuel( Target )

		for Key, Value in pairs( self.FuelLink ) do
			if Value == Target then
				table.remove( self.FuelLink, Key )
				return true, "Unlink successful!"
			end
		end

		return false, "That fuel tank is not linked to this engine!"
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
	ACE.EngineSound.Stop( self )
end

AddCSLuaFile("shared.lua")
AddCSLuaFile("cl_init.lua")

include("shared.lua")

--don't forget:
--armored tanks

do

	local RadiatorWireDescs = {
		--Inputs
		["ActiveCooling"]	= "Active uses engine power to cool the radiator. Pushes an additional 20mph of airflow through the radiator.",

		--Outputs
		["Coolant"]        = "Returns the current coolant level.",
		["Capacity"]    = "Returns the max capacity of the radiator.",
		["Leaking"]     = "Is the radiator leaking?",
		["Temperature"]     = "How hot is the radiator"
	}

	function ENT:Initialize()

		self.CanUpdate        = true

		self.Size             = 0	--outer dimensions
		self.Volume           = 0	--total internal volume in cubic inches
		self.Capacity         = 0	--max coolant capacity in liters
		self.Coolant          = 0	--coolant in liters
		self.Leaking          = 0
		self.EmptyMass        = 0	--mass of tank only

		self.ThermalSurfaceArea = 1 	--total surface area of the radiator fins
		self.AirflowRestrictiveness = 1 --Ratio for airflow passing through the radiator.

		self.NextMassUpdate   = 0
		self.NextGUIUpdate    = 0
		self.Id               = nil	--model id
		self.Active           = false
		self.FanRunning		  = 0
		self.NextLegalCheck   = ACE.CurTime + math.random(ACE.Legal.Min, ACE.Legal.Max) -- give any spawning issues time to iron themselves out
		self.Legal            = true
		self.LegalIssues      = ""

		self.RadiatorEfficacy = 1
		self.ActiveTorqueDemand = 1

		self.FanSpeed = 0

		self.Sound = nil
		self.SoundPath = "acf_extra/ACE/miscellaneous/fans/BuzzingCoolingFan.wav"
		self.SoundPitch = 100

		self.RadiatorStats    = "" --Used to cache radiator stats. No reason to recalculate these constantly.
		self.Heat = ACE.AmbientTemp

		self.Inputs = Wire_CreateInputs( self, { "ActiveCooling (" .. RadiatorWireDescs["ActiveCooling"] .. ")" } )
		self.Outputs = WireLib.CreateSpecialOutputs( self,
			{  "Temperature (" .. RadiatorWireDescs["Temperature"] .. ")", "Coolant (" .. RadiatorWireDescs["Coolant"] .. ")", "Capacity (" .. RadiatorWireDescs["Capacity"] .. ")", "Leaking (" .. RadiatorWireDescs["Leaking"] .. ")", "FanRunning", "Entity" },
			{ "NORMAL", "NORMAL", "NORMAL", "NORMAL", "NORMAL", "ENTITY" }
		)
		Wire_TriggerOutput( self, "Leaking", 0 )
		Wire_TriggerOutput( self, "Entity", self )

		self.Master = {} --engines linked to this tank

		self.LastThink = 0

		self.NextFanLogic = 0
		self.NextHeatLogic = 0
		self.LastThink2 = 0 --Used for the core heat logic running less frequently
		self.NextThink = ACE.CurTime +  1

	end

end

function ENT:ACF_Activate( Recalc )

	ACE.GetEntityState(self, true)

	local PhysObj = self:GetPhysicsObject()
	if not self.ACE.Area then
		self.ACE.Area = PhysObj:GetSurfaceArea() * 6.45
	end
	if not self.ACE.Volume then
		self.ACE.Volume = PhysObj:GetVolume() * 1
	end

	local Armour = self.EmptyMass * 1000 / self.ACE.Area / 0.78 --So we get the equivalent thickness of that prop in mm if all it's weight was a steel plate
	local Health = self.ACE.Volume / ACE.Threshold							--Setting the threshold of the prop Area gone

	local Percent = 1
	if Recalc and self.ACE.Health and self.ACE.MaxHealth then
		Percent = self.ACE.Health / self.ACE.MaxHealth
	end

	self.ACE.Health    = Health * Percent
	self.ACE.MaxHealth = Health
	self.ACE.Armour    = Armour * (0.5 + Percent / 2)
	self.ACE.MaxArmour = Armour
	self.ACE.Type      = nil
	self.ACE.Mass      = self.Mass
	self.ACE.Density   = (PhysObj:GetMass() * 1000) / self.ACE.Volume
	self.ACE.Type      = "Prop"

	self.ACE.Material	= not isstring(self.ACE.Material) and ACE.BackCompMat[self.ACE.Material] or self.ACE.Material or "RHA"

	--Forces an update of mass
	self.LastMass = 1
	self:UpdateRadiatorMass()

end

do

	-- Checks if the provided string vector matches the desired format.
	-- Define a pattern to match the format
	local pattern = "^%d+%.?%d*:%d+%.?%d*:%d+%.?%d*$"
	local function IsValidStringScale( Id )
		if not isstring( Id ) then return false end
		if not string.match(Id, pattern) then return false end
		return true
	end

	-- Converts an already verified string vector into a valid vector scale.
	local function ParseToVector( ScaleId )
		if not isstring(ScaleId) then return end

		local Result = string.Explode( ":", ScaleId )

		local X = tonumber(Result[1])
		local Y = tonumber(Result[2])
		local Z = tonumber(Result[3])

		return Vector(X, Y, Z)
	end

	-- Clamps the already converted scale so its within the size limits, defined on globals.
	local function ClampScale( Scale )
		if not isvector( Scale ) then return end

		local MinSize = ACE.CrateMinimumSize
		local MaxSize = ACE.CrateMaximumSize

		Scale.x = math.Clamp( math.Round(Scale.x, 1), MinSize, MaxSize)
		Scale.y = math.Clamp( math.Round(Scale.y, 1), MinSize, MaxSize)
		Scale.z = math.Clamp( math.Round(Scale.z, 1), MinSize, MaxSize)

		return Scale
	end

	-- Tries to convert a scale id, having a string format, to a vector scale. If its already a vector, skip the process.
	local function ConvertStringScale( ScaleId )
		if isvector( ScaleId ) then return ScaleId end
		if not IsValidStringScale( ScaleId ) then return end

		local Scale = ParseToVector( ScaleId )
		Scale = ClampScale( Vector(Scale.y, Scale.x, Scale.z) )

		return Scale
	end

	function ACE.MakeRadiator(Owner, Pos, Angle, Id, Data1)

		if IsValid(Owner) and not Owner:CheckLimit("_ace_misc") then return false end
		-- A radiator is defined by its size ("L:W:H" or a vector); anything else cannot be built.
		if not ConvertStringScale(Data1) then return false end

		local Tank = ents.Create("ace_radiator")
		if IsValid(Tank) then

			local Model
			local Dimensions

			Tank:CPPISetOwner(Owner)
			Tank:SetAngles(Angle)
			Tank:SetPos(Pos)
			Tank:Spawn()

			local Scale = ConvertStringScale(Data1)

			if isvector(Scale) then

				local ModelData = ACE.ModelData["Radiator"]

				Data1 = Scale
				Model = ModelData.Model
				Dimensions = Scale

				local DefaultSize    = ModelData.DefaultSize
				local Mesh           = ModelData.CustomMesh
				local PhysMaterial   = ModelData.physMaterial
				--Width is X
				--Thickness is y
				--Height is Z
				local RadScale = Vector(1 / 35.775, 1 / 4.5, 1 / 22.5)
				--local EntityScale    = Vector(Scale.x / DefaultSize, Scale.y / DefaultSize, Scale.z / DefaultSize) --Defaultsize does not support 3d vectors.
				local EntityScale    = Vector(Scale.x, Scale.y, Scale.z) * RadScale


				Tank.ScaleData = {
					Mesh = Mesh,
					Scale = EntityScale,
					Size = DefaultSize,
					Material = PhysMaterial,
				}

				--Tank:SetMaterial("phoenix_storms/gear")
				Tank:SetModel( Model ) --Sending the model to client
				Tank:PhysicsInit( SOLID_VPHYSICS )
				Tank:SetMoveType( MOVETYPE_VPHYSICS )
				Tank:SetSolid( SOLID_VPHYSICS )

				Tank.IsScalable = true
				Tank:ACE_SetScale( Tank.ScaleData )

			end

			Tank.Id           = Id
			Tank.SizeId       = Data1
			Tank.Shape 		  = "Radiator"
			Tank.Model        = Model
			Tank.Dimensions   = Dimensions

			Tank.LastMass = 1
			Tank:UpdateRadiator(Id, Data1)

			if IsValid(Owner) then
				Owner:AddCount( "_ace_misc", Tank )
				Owner:AddCleanup( "acemenu", Tank )
			end

			--table.insert(ACE.FuelTanks, Tank)

			return Tank
		end

		return Tank
	end
end

list.Set( "ACFCvars", "ace_radiator", {"id", "data1"} )
duplicator.RegisterEntityClass("ace_radiator", ACE.MakeRadiator, "Pos", "Angle", "Id", "SizeId")


local Wall = 0.75 -- wall thickness in inches
local FanOnTemp = 85 -- deg C; coolant thermostats open at about 82-90 °C and switch the fan on above it

function ENT:UpdateRadiator(_, _)

	local pct = 1 --how full is the tank?
	self.Leaking = 0


	local ModelData = ACE.ModelData[self.Shape]
	local Volumefunc = ModelData.volumefunction

	local Dimensions = self.Dimensions

	--We love rotated models.
	--Width is X
	--Thickness is y
	--Height is Z

	local Length = Dimensions.y
	local Width = Dimensions.x
	local Height = Dimensions.z

	local Volume = Volumefunc( Length, Width, Height)
	local IVolume = math.max(Volumefunc( Length, Width - (Wall * 2), Height - (Wall * 2)) * 0.7,0) --Assume 2/3rds volume radiator fins, 1/3rd water (roughly 0.7x)

	self.Volume        = IVolume-- total volume of tank (cu in), reduced by wall thickness
	self.Capacity      = IVolume * ACE.CuIToLiter * ACE.TankVolumeMul * 0.4774 --internal volume available for coolant in liters, with magic realism number
	self.EmptyMass     = (Volume - IVolume) * 16.387 * ( 2.6 / 1000 )    -- total wall volume * cu in to cc * density of aluminum (kg/cc)
	self.Coolant	= pct * self.Capacity
	self.Mass = self.EmptyMass + self.Coolant --* 1   Conversion Ommited    -- weight of tank + weight of contained water. Water is 1kg/Liter

	self:UpdateRadiatorMass()

	local x = math.Round(Length, 1) / 10
	local y = math.Round(Width, 1) / 10
	local z = math.Round(Height, 1) / 10

	-- Fan shaft power in W: 30 W per liter of radiator core. ActiveTorqueDemand keeps its old
	-- name for dupes and chips that read it, but it is a power, not a torque.
	self.ActiveTorqueDemand = self.Volume / 61.02 * 30

	-- Core geometry for the heat exchanger model (ace/shared/mobility/thermal_model.lua): the
	-- face the air passes through, inside the walls, and the depth it passes along.
	self.CoreFrontM2 = math.max(Width - Wall * 2, 0) * math.max(Height - Wall * 2, 0) * 0.00064516
	self.CoreDepthM = Length * 0.0254

	--Infotext moved from the overlay update. No need to recalculate this.
	local Thermal = ACE.Mobility.Thermal
	local function Rating(Face)
		return Thermal.RadiatorRating(self.CoreFrontM2, self.CoreDepthM, Face, 80) / 1000
	end

	local text = "\nCore: " .. math.Round(self.CoreFrontM2, 2) .. " m^2 face, " .. math.Round(self.CoreDepthM * 100, 1) .. " cm deep\n"
	text = text .. "\nCooling with coolant at 100 °C, air at 20 °C:"
	text = text .. "\n- Standing, fan off: " .. math.Round(Rating(Thermal.FaceVelocity(self.CoreDepthM, 0, 0)), 1) .. " kW"
	text = text .. "\n- Standing, fan on: " .. math.Round(Rating(Thermal.FaceVelocity(self.CoreDepthM, 0, 1)), 1) .. " kW"
	text = text .. "\n- 40 km/h, fan on: " .. math.Round(Rating(Thermal.FaceVelocity(self.CoreDepthM, 40 / 3.6, 1)), 1) .. " kW"
	text = text .. "\nFan uses " .. math.Round(self.ActiveTorqueDemand / 745.7, 2) .. " hp when needed\n"

	self.RadiatorStats = text




	local dims = x .. "x" .. y .. "x" .. z

	local rad	= " " .. dims .. " Radiator"

	self:SetNWString( "WireName", rad )

	Wire_TriggerOutput( self, "Capacity", math.Round(self.Capacity,2) )
	self:UpdateOverlayText()

end

function ENT:UpdateOverlayText()


	local Stats

	if self.FanRunning > 0 then
		Stats = "Cooling Actively - Fan using engine power"
	else
		Stats = "Cooling Passively"
	end

	local text = "- " .. Stats .. " -\n"

	--Slot in infotext

	text = text .. self.RadiatorStats

	text = text .. "\nTemp: " .. math.Round(self.Heat or ACE.AmbientTemp or 20) .. " °C / " .. math.Round(((self.Heat or ACE.AmbientTemp or 20) * (9 / 5)) + 32) .. " °F\n"
	text = text .. "Rejecting: " .. math.Round((self.HeatRejected or 0) / 1000, 1) .. " kW\n"

	text = text .. "\nCurrent Coolant Remaining:"
	text = text .. "\n-  " .. math.Round( self.Coolant, 1 ) .. " / " .. math.Round( self.Capacity, 1 ) .. " liters"
	text = text .. "\n-  " .. math.Round( self.Coolant * 0.264172, 1 ) .. " / " .. math.Round( self.Capacity * 0.264172, 1 ) .. " gallons"

	if self.Leaking > 0 then
		text = text .. "\n- Leaking: " .. math.Round(self.Leaking, 1) .. " liters per second"
	end


	if not self.Legal then
		text = text .. "\nNot legal, disabled for " .. math.ceil(self.NextLegalCheck - ACE.CurTime) .. "s\nIssues: " .. self.LegalIssues
	end

	self:SetOverlayText( text )

end

function ENT:UpdateRadiatorMass()

	self.Mass = self.EmptyMass + self.Coolant -- * 1 --Water weighs 1kg/L

	--reduce superflous engine calls, update fuel tank mass every 5 kgs change or every 10s-15s
	if math.abs(self.LastMass - self.Mass) > 5 or ACE.CurTime > self.NextMassUpdate then
		self.LastMass = self.Mass
		self.NextMassUpdate = ACE.CurTime + math.Rand(10, 15)
		local phys = self:GetPhysicsObject()
		if (phys:IsValid()) then
			phys:SetMass( self.Mass )
		end
	end

	self:UpdateOverlayText()

end

function ENT:Update( ArgsTable )

	local Feedback = ""

	self:UpdateRadiator(ArgsTable[4], ArgsTable[5]) --Id, SizeId, FuelType

	return true, "Radiator successfully updated." .. Feedback
end

function ENT:TriggerInput( iname, value )

	if (iname == "ActiveCooling") then
		if value >	 0 then
			self.Active = true
		else
			self.Active = false
		end
	end

end

function ENT:Think()

	local CT = ACE.CurTime

	local ECount = #self.Master

	--[[
		Active cooling: a fan driven from the engines, switched on by the ActiveCooling input and
		run by its thermostat only while the coolant is above the thermostat's opening point
		(the thermostatic fan clutch of real cooling systems). The fan's power is taken from the
		crank as a torque, P / omega, at no less than idle speed.
	]]
	local FanWanted = self.Active and (self.Heat or 0) > FanOnTemp
	self.FanRunning = 0

	for Key in pairs(self.Master) do
		local Ent = self.Master[Key]
		if FanWanted and IsValid( Ent ) and Ent.Active then
			local Spec, State = Ent.MobSpec, Ent.MobState
			-- Electric motors idle at 0 rpm and can turn backwards: their fan load is taken at no
			-- less than 80 rad/s.
			local Idle = Spec and Spec.IdleW or 0
			local Omega = math.max(math.abs(State and State.W or 0), Idle > 0 and Idle or 80)
			-- The fan is a load on the crank; the drivetrain solve takes it from the engine.
			Ent.AccessoryTorque = (Ent.AccessoryTorque or 0) + self.ActiveTorqueDemand / math.max(ECount, 1) / Omega

			self.FanRunning = 1
		end
	end

	--[[
		A radiator cooling only batteries (no engine turning its fan) runs an electric fan off the
		battery while the cells are warm (acf_fueltank batteryLoop sets BatteryFanWanted).
	]]
	local Battery = self.FanBattery
	if self.FanRunning == 0 and self.Active and self.BatteryFanWanted and IsValid(Battery) and Battery.DrawEnergy then
		local Dt = CT - (self.LastThink or CT)
		if Dt > 0 then Battery:DrawEnergy(self.ActiveTorqueDemand * Dt / 3.6e6, Dt) end
		self.FanRunning = 1
	end



	if CT > self.NextFanLogic then

		if self.FanRunning == 1 then --The Fan is running


			if self.FanSpeed > 0 then --Fan is ramping up
				self.FanSpeed = math.min(self.FanSpeed + 0.03,1)
				if self.Sound then
					self.Sound:ChangePitch( self.SoundPitch * self.FanSpeed )
				end
			elseif self.FanSpeed == 0 then --Fan just started
				--stupid workaround for the engine sound. THANK YOU garry
				local Filter = RecipientFilter(true)
				Filter:AddAllPlayers()

				if self.SoundPath ~= "" then
					self.Sound = CreateSound(self, self.SoundPath , Filter)
					local Horsepower = self.ActiveTorqueDemand / 745.7

					local DB = math.min(40 + Horsepower * 10, 90)
					self.Sound:SetSoundLevel( DB ) --Has to be adjusted before being played sadly. No dynamic DB levels.
					self.Sound:PlayEx(1.0,0)
				end

				self.FanSpeed = self.FanSpeed + 0.01
			end

		else --The cooling fan is no longer running

			if self.FanSpeed > 0 then --Fan is slowing down
				self.FanSpeed = math.max(self.FanSpeed - 0.03,0)
				if self.Sound then
					self.Sound:ChangePitch( self.SoundPitch * self.FanSpeed )
				end
			elseif self.FanSpeed == 0 then --Fan has stopped
				if self.Sound then
					self.Sound:Stop()
				end
				self.Sound = nil
			end

		end




		--Maybe later once a workaround is found
		--local sequence = self:LookupSequence("idle")
		--self:ResetSequence(sequence)
		--self:SetPlaybackRate(0)

		self.NextFanLogic = CT + 0.05
	end

	if CT > self.NextHeatLogic then
		local DeltaTime2 = CT - self.LastThink2

		--Obligatory legality Check
		if CT > self.NextLegalCheck then
			--local minmass = math.floor(self.Mass-6)  -- water is light, may as well save complexity and just check it's above empty mass
			self.Legal, self.LegalIssues = ACE.CheckLegal(self, self.Model, math.Round(self.EmptyMass,2), nil, true, true) -- mass-6, as mass update is granular to 5 kg
			self.NextLegalCheck = ACE.Legal.NextCheck(self.legal)
			--make sure it's not made spherical
			if self.EntityMods and self.EntityMods.MakeSphericalCollisions then self.Coolant = 0 end
			self:UpdateOverlayText()
		end

		--Update the UI
			self:UpdateOverlayText()

		--[[
			Air side of the heat exchanger. The linked engines solve the coolant circuit
			(ACE.EngineThermalThink) and write back this radiator's Heat; here the radiator only
			says how well air gets through it: ram air from the vehicle's speed plus the fan.
		]]
		local Thermal = ACE.Mobility.Thermal
		local SpeedMS = ACE.GetPhysicalParent(self):GetVelocity():Length() * 0.01905 -- units/s to m/s
		local Face = Thermal.FaceVelocity(self.CoreDepthM or 0.05, SpeedMS, self.FanRunning == 1 and self.FanSpeed or 0)
		if self.Legal and (self.Coolant or 0) > 0 then
			self.ThermalUA, self.ThermalCair = Thermal.RadiatorAir(self.CoreFrontM2 or 0, self.CoreDepthM or 0, Face)
		else
			self.ThermalUA, self.ThermalCair = 0, 0
		end

		-- With no running circuit through it, the radiator drifts back to the air temperature.
		local Linked = false
		for _, Ent in pairs(self.Master) do
			if IsValid(Ent) then Linked = true break end
		end
		for _, Ent in pairs(self.Batteries or {}) do
			if IsValid(Ent) then Linked = true break end
		end
		if not Linked then
			self.HeatRejected = 0
			self.Heat = ACE.AmbientTemp + ((self.Heat or ACE.AmbientTemp) - ACE.AmbientTemp) * math.exp(-DeltaTime2 * ACE.GetHeatRate() / 60)
		end

		Wire_TriggerOutput( self, "Temperature", self.Heat )
		Wire_TriggerOutput( self, "FanRunning", self.FanRunning )

		self.LastThink2 = CT --Used for heat deltatime
		self.NextHeatLogic = CT + 0.25 --Executes heat logic every 0.5 seconds.
	end



	self.LastThink = CT

	self:NextThink( CT )
	return true

end

function ENT:OnRemove()

	-- A copy: unlinking removes each engine from self.Master.
	for _, Engine in ipairs(table.Copy(self.Master)) do
		if IsValid( Engine ) then
			Engine:Unlink( self )
		end
	end

	for _, Battery in ipairs(table.Copy(self.Batteries or {})) do
		if IsValid( Battery ) then
			Battery:Unlink( self )
		end
	end

	if self.Sound then
		self.Sound:Stop()
	end
end
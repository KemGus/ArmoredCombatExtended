AddCSLuaFile("shared.lua")
AddCSLuaFile("cl_init.lua")

include("shared.lua")

local GearboxTable = ACE.Weapons.Gearboxes

do

	local GearboxWireDescs = {
		["Gear"]		= "Sets the gear of this gearbox.",
		["GearUp"]		= "Increases one gear above the current one.",
		["GearDown"]	= "Decreases one gear below the current one.",
		["Clutch"]		= "Applies Clutch to gearbox. Values from 0 to 1.",
		["Brake"]		= "Applies Brake to gearbox. The value you put, the strenght of the brake."
	}

	function ENT:Initialize()

		self.IsGeartrain	= true
		self.Master			= {}
		self.IsMaster		= true

		self.WheelLink		= {} -- a "Link" has these components: Ent, Side, Axis, Rope, RopeLen, Output, ReqTq, Vel

		self.TotalReqTq		= 0
		self.RClutch		= 0
		self.LClutch		= 0
		self.LBrake			= 0
		self.RBrake			= 0
		self.SteerRate		= 0

		self.Gear			= 0
		self.GearRatio		= 0
		self.ChangeFinished = 0

		self.LegalThink		= 0

		self.RPM			= {}
		self.CurRPM			= 0
		self.CVT			= false
		self.DoubleDiff		= false
		self.Auto			= false
		self.InGear			= false
		self.CanUpdate		= true
		self.LastActive		= 0
		self.Legal			= true
		self.Parentable		= false
		self.RootParent		= nil
		self.NextLegalCheck = ACE.CurTime + math.random(ACE.Legal.Min, ACE.Legal.Max) -- give any spawning issues time to iron themselves out
		self.LegalIssues	= ""

		--self.Heat		= ACE.AmbientTemp

	end

	function ACE.MakeGearbox(Owner, Pos, Angle, Id, Data1, Data2, Data3, Data4, Data5, Data6, Data7, Data8, Data9, Data10)

		if not Owner:CheckLimit("_ace_misc") then return false end

		local Gearbox	= ents.Create("acf_gearbox")

		if not IsValid( Gearbox ) then return false end

		if not ACE.CheckGearbox( Id ) then
			Id = "1Gear-T-S" --deal with it
			Data1	= 0.1 --gear1
			Data10  = 0.5 --gear2
		end

		local GearboxData = GearboxTable[Id]

		Gearbox:SetAngles(Angle)
		Gearbox:SetPos(Pos)
		Gearbox:Spawn()

		Gearbox:CPPISetOwner(Owner)
		Gearbox.Id		= Id
		Gearbox.Model	= GearboxData.model
		Gearbox.Mass		= GearboxData.weight		or 1
		Gearbox.SwitchTime  = GearboxData.switch
		Gearbox.MaxTorque	= GearboxData.maxtq		or 0
		Gearbox.Gears	= GearboxData.gears		or 2 --hmmmmmm ok? just if everything fails
		Gearbox.Dual		= GearboxData.doubleclutch	or false
		Gearbox.CVT		= GearboxData.cvt			or false
		Gearbox.DoubleDiff  = GearboxData.doublediff	or false
		Gearbox.Auto		= GearboxData.auto			or false
		Gearbox.Parentable  = GearboxData.parentable	or false
		Gearbox.ACEPoints		= GearboxData.acepoints or 0.9
		Gearbox.Category	= GearboxData.category

		if Gearbox.CVT then
			Gearbox.TargetMinRPM = Data3
			Gearbox.TargetMaxRPM = math.max(Data4,Data3 + 100)
			Gearbox.CVTRatio = nil
		end

		Gearbox.GearTable = table.Copy(GearboxData.geartable)
			Gearbox.GearTable.Final = Data10
			Gearbox.GearTable[1] = Data1
			Gearbox.GearTable[2] = Data2
			Gearbox.GearTable[3] = Data3
			Gearbox.GearTable[4] = Data4
			Gearbox.GearTable[5] = Data5
			Gearbox.GearTable[6] = Data6
			Gearbox.GearTable[7] = Data7
			Gearbox.GearTable[8] = Data8
			Gearbox.GearTable[9] = Data9
			Gearbox.GearTable[0] = GearboxData.geartable[0]

			Gearbox.Gear0 = Data10
			Gearbox.Gear1 = Data1
			Gearbox.Gear2 = Data2
			Gearbox.Gear3 = Data3
			Gearbox.Gear4 = Data4
			Gearbox.Gear5 = Data5
			Gearbox.Gear6 = Data6
			Gearbox.Gear7 = Data7
			Gearbox.Gear8 = Data8
			Gearbox.Gear9 = Data9

		Gearbox.GearRatio = (Gearbox.GearTable[0] or 0) * Gearbox.GearTable.Final

		if Gearbox.Auto then
			Gearbox.ShiftPoints = {}
			for part in string.gmatch(Data9, "[^,]+") do Gearbox.ShiftPoints[#Gearbox.ShiftPoints + 1] = tonumber(part) end
			Gearbox.ShiftPoints[0] = -1
			Gearbox.Reverse = Gearbox.Gears + 1
			Gearbox.GearTable[Gearbox.Reverse] = Data8
			Gearbox.Drive = 1
			Gearbox.ShiftScale = 1
		end

		Gearbox:SetModel( Gearbox.Model )

		local Inputs = {"Gear (" .. GearboxWireDescs["Gear"] .. ")","Gear Up (" .. GearboxWireDescs["GearUp"] .. ")","Gear Down (" .. GearboxWireDescs["GearDown"] .. ")"}
		if Gearbox.CVT then
			table.insert(Inputs,"CVT Ratio")
		elseif Gearbox.DoubleDiff then
			table.insert(Inputs, "Steer Rate")
		elseif Gearbox.Auto then
			table.insert(Inputs, "Hold Gear")
			table.insert(Inputs, "Shift Speed Scale")
			Gearbox.Hold = false
		end

		table.insert(Inputs, "Assisted (1 = automatic clutch and rev matching, if the server allows it)")
		table.insert(Inputs, "Diff Lock")

		if Gearbox.Dual then
			table.insert(Inputs, "Left Clutch")
			table.insert(Inputs, "Right Clutch")
			table.insert(Inputs, "Left Brake")
			table.insert(Inputs, "Right Brake")
		else
			table.insert(Inputs, "Clutch (" .. GearboxWireDescs["Clutch"] .. ")")
			table.insert(Inputs, "Brake (" .. GearboxWireDescs["Brake"] .. ")")
		end

		local Outputs = { "Ratio", "Entity", "Current Gear", "Input RPM", "Clutch Slip", "Clutch Temp", "Output Torque" }
		local OutputTypes = { "NORMAL", "ENTITY", "NORMAL", "NORMAL", "NORMAL", "NORMAL", "NORMAL" }
		if Gearbox.CVT then
			table.insert(Outputs,"Min Target RPM")
			table.insert(Outputs,"Max Target RPM")
			table.insert(OutputTypes,"NORMAL")
		end

		Gearbox.Inputs = Wire_CreateInputs( Gearbox, Inputs )
		Gearbox.Outputs = WireLib.CreateSpecialOutputs( Gearbox, Outputs, OutputTypes )
		Wire_TriggerOutput(Gearbox, "Entity", Gearbox)

		if Gearbox.CVT then
			Wire_TriggerOutput(Gearbox, "Min Target RPM", Gearbox.TargetMinRPM)
			Wire_TriggerOutput(Gearbox, "Max Target RPM", Gearbox.TargetMaxRPM)
		end

		Gearbox.LClutch = Gearbox.MaxTorque
		Gearbox.RClutch = Gearbox.MaxTorque

		Gearbox:PhysicsInit( SOLID_VPHYSICS )
		Gearbox:SetMoveType( MOVETYPE_VPHYSICS )
		Gearbox:SetSolid( SOLID_VPHYSICS )

		local phys = Gearbox:GetPhysicsObject()
		if IsValid( phys ) then
			phys:SetMass( Gearbox.Mass )
			Gearbox.ModelInertia = 0.99 * phys:GetInertia() / phys:GetMass() -- giving a little wiggle room
		end

		Gearbox.In = Gearbox:WorldToLocal(Gearbox:GetAttachment(Gearbox:LookupAttachment( "input" )).Pos)
		Gearbox.OutL = Gearbox:WorldToLocal(Gearbox:GetAttachment(Gearbox:LookupAttachment( "driveshaftL" )).Pos)
		Gearbox.OutR = Gearbox:WorldToLocal(Gearbox:GetAttachment(Gearbox:LookupAttachment( "driveshaftR" )).Pos)

		Owner:AddCount("_ace_misc", Gearbox)
		Owner:AddCleanup( "acemenu", Gearbox )

		Gearbox:ChangeGear(1)

		if Gearbox.Dual or Gearbox.DoubleDiff then
			Gearbox:SetBodygroup(1, 1)
		else
			Gearbox:SetBodygroup(1, 0)
		end

		Gearbox:SetNWString( "WireName", GearboxData.name )
		Gearbox:UpdateOverlayText()

		ACE.Activate( Gearbox, 0 )

		return Gearbox
	end
	list.Set( "ACFCvars", "acf_gearbox", {"id", "data1", "data2", "data3", "data4", "data5", "data6", "data7", "data8", "data9", "data10", "data11", "data12", "data13", "data14", "data15"} )
	duplicator.RegisterEntityClass("acf_gearbox", ACE.MakeGearbox, "Pos", "Angle", "Id", "Gear1", "Gear2", "Gear3", "Gear4", "Gear5", "Gear6", "Gear7", "Gear8", "Gear9", "Gear0" )

end

function ENT:Update( ArgsTable )
	-- That table is the player data, as sorted in the ACFCvars above, with player who shot,
	-- and pos and angle of the tool trace inserted at the start

	local Id = ArgsTable[4] -- Argtable[4] is the engine ID
	local GearboxData = GearboxTable[Id]

	if GearboxData.model ~= self.Model then
		return false, "The new gearbox must have the same model!"
	end

	if self.Id ~= Id then

		self.Id		= Id
		self.Mass	= GearboxData.weight		or 1
		self.SwitchTime = GearboxData.switch
		self.MaxTorque  = GearboxData.maxtq		or 0
		self.Gears	= GearboxData.gears		or 2
		self.Dual	= GearboxData.doubleclutch	or false
		self.CVT		= GearboxData.cvt			or false
		self.DoubleDiff = GearboxData.doublediff	or false
		self.Auto	= GearboxData.auto			or false
		self.Parentable = GearboxData.parentable	or false
		self.Category	= GearboxData.category

		local Inputs = {"Gear","Gear Up","Gear Down"}
		if self.CVT then
			table.insert(Inputs,"CVT Ratio")
		elseif self.DoubleDiff then
			table.insert(Inputs, "Steer Rate")
		elseif self.Auto then
			table.insert(Inputs, "Hold Gear")
			table.insert(Inputs, "Shift Speed Scale")
			self.Hold = false
		end

		table.insert(Inputs, "Assisted")
		table.insert(Inputs, "Diff Lock")

		if self.Dual then
			table.insert(Inputs, "Left Clutch")
			table.insert(Inputs, "Right Clutch")
			table.insert(Inputs, "Left Brake")
			table.insert(Inputs, "Right Brake")
		else
			table.insert(Inputs, "Clutch")
			table.insert(Inputs, "Brake")
		end

		local Outputs = { "Ratio", "Entity", "Current Gear", "Input RPM", "Clutch Slip", "Clutch Temp", "Output Torque" }
		local OutputTypes = { "NORMAL", "ENTITY", "NORMAL", "NORMAL", "NORMAL", "NORMAL", "NORMAL" }
		if self.CVT then
			table.insert(Outputs,"Min Target RPM")
			table.insert(Outputs,"Max Target RPM")
			table.insert(OutputTypes,"NORMAL")
		end

		local phys = self:GetPhysicsObject()
		if IsValid( phys ) then
			phys:SetMass( self.Mass )
		end

		self.Inputs = Wire_CreateInputs( self, Inputs )
		self.Outputs = WireLib.CreateSpecialOutputs( self, Outputs, OutputTypes )
		Wire_TriggerOutput( self, "Entity", self )
	end

	if self.CVT then
		self.TargetMinRPM = ArgsTable[7]
		self.TargetMaxRPM = math.max(ArgsTable[8],ArgsTable[7] + 100)
		self.CVTRatio = nil
		Wire_TriggerOutput(self, "Min Target RPM", self.TargetMinRPM)
		Wire_TriggerOutput(self, "Max Target RPM", self.TargetMaxRPM)
	end

	self.GearTable.Final = ArgsTable[14]
	self.GearTable[1] = ArgsTable[5]
	self.GearTable[2] = ArgsTable[6]
	self.GearTable[3] = ArgsTable[7]
	self.GearTable[4] = ArgsTable[8]
	self.GearTable[5] = ArgsTable[9]
	self.GearTable[6] = ArgsTable[10]
	self.GearTable[7] = ArgsTable[11]
	self.GearTable[8] = ArgsTable[12]
	self.GearTable[9] = ArgsTable[13]
	self.GearTable[0] = GearboxData.geartable[0]

	self.Gear0 = ArgsTable[14]
	self.Gear1 = ArgsTable[5]
	self.Gear2 = ArgsTable[6]
	self.Gear3 = ArgsTable[7]
	self.Gear4 = ArgsTable[8]
	self.Gear5 = ArgsTable[9]
	self.Gear6 = ArgsTable[10]
	self.Gear7 = ArgsTable[11]
	self.Gear8 = ArgsTable[12]
	self.Gear9 = ArgsTable[13]

	self.GearRatio = (self.GearTable[0] or 0) * self.GearTable.Final

	if self.Auto then
		self.ShiftPoints = {}
		for part in string.gmatch(ArgsTable[13], "[^,]+") do self.ShiftPoints[#self.ShiftPoints + 1] = tonumber(part) end
		self.ShiftPoints[0] = -1
		self.Reverse = self.Gears + 1
		self.GearTable[self.Reverse] = ArgsTable[12]
		self.Drive = 1
		self.ShiftScale = 1
	end

	--self:ChangeGear(1) -- fails on updating because func exits on detecting same gear
	self.Gear = 1
	self.GearRatio = (self.GearTable[self.Gear] or 0) * self.GearTable.Final
	self.ChangeFinished = CurTime() + self.SwitchTime
	self.InGear = false

	if self.Dual or self.DoubleDiff then
		self:SetBodygroup(1, 1)
	else
		self:SetBodygroup(1, 0)
	end

	self:SetNWString( "WireName", GearboxData.name )
	self:UpdateOverlayText()

	ACE.Activate( self, 1 )

	return true, "Gearbox updated successfully!"
end

function ENT:UpdateOverlayText()

	local text = ""

	if self.CVT then
		text = "Reverse Gear: " .. math.Round( self.GearTable[ 2 ], 2 ) -- maybe a better name than "gear 2"...?
		text = text .. "\nTarget: " .. math.Round( self.TargetMinRPM ) .. " - " .. math.Round( self.TargetMaxRPM ) .. " RPM\n"
	elseif self.Auto then
		for i = 1, self.Gears do
			text = text .. "Gear " .. i .. ": " .. math.Round( self.GearTable[ i ], 2 ) .. ", Upshift @ " .. math.Round( self.ShiftPoints[i] / 10.936, 1 ) .. " kph / " .. math.Round( self.ShiftPoints[i] / 17.6 ,1 ) .. " mph\n"
		end
	else
		for i = 1, self.Gears do
			text = text .. "Gear " .. i .. ": " .. math.Round( self.GearTable[ i ], 2 ) .. "\n"
		end
	end
	if self.Auto then
		text = text .. "Reverse gear: " .. math.Round( self.GearTable[ self.Reverse ], 2 ) .. "\n"
	end

	text = text .. "Final Drive: " .. math.Round( self.Gear0, 2 ) .. "\n"
	text = text .. "Torque Rating: " .. self.MaxTorque .. " Nm / " .. math.Round( self.MaxTorque * 0.73 ) .. " ft-lb"

	if not self.Legal then
		text = text .. "\nNot legal, disabled for " .. math.ceil(self.NextLegalCheck - ACE.CurTime) .. "s\nIssues: " .. self.LegalIssues
	end

	self:SetOverlayText( text )

end


-- prevent people from changing bodygroup
function ENT:CanProperty( _, property )

	return property ~= "bodygroups"

end

function ENT:TriggerInput( iname, value )

	if ( iname == "Gear" ) then
		if self.Auto then
			self:ChangeDrive(value)
		else
			self:ChangeGear(value)
		end
	elseif ( iname == "Gear Up" ) and value ~= 0 then
		if self.Auto then
			self:ChangeDrive(self.Drive + 1)
		else
			self:ChangeGear(self.Gear + 1)
		end
	elseif ( iname == "Gear Down" ) and value ~= 0 then
		if self.Auto then
			self:ChangeDrive(self.Drive - 1)
		else
			self:ChangeGear(self.Gear - 1)
		end
	elseif ( iname == "Clutch" ) then
		self.LClutch = math.Clamp(1-value,0,1) * self.MaxTorque
		self.RClutch = math.Clamp(1-value,0,1) * self.MaxTorque
	elseif ( iname == "Brake" ) then
		self.LBrake = math.Clamp(value,0,100)
		self.RBrake = math.Clamp(value,0,100)
	elseif ( iname == "Left Brake" ) then
		self.LBrake = math.Clamp(value,0,100)
	elseif ( iname == "Right Brake" ) then
		self.RBrake = math.Clamp(value,0,100)
	elseif ( iname == "Left Clutch" ) then
		self.LClutch = math.Clamp(1-value,0,1) * self.MaxTorque
	elseif ( iname == "Right Clutch" ) then
		self.RClutch = math.Clamp(1-value,0,1) * self.MaxTorque
	elseif ( iname == "CVT Ratio" ) then
		self.CVTRatio = math.Clamp(value,0,1)
	elseif ( iname == "Steer Rate" ) then
		self.SteerRate = math.Clamp(value,-1,1)
	elseif ( iname == "Hold Gear" ) then
		self.Hold = value ~= 0
	elseif ( iname == "Shift Speed Scale" ) then
		self.ShiftScale = math.Clamp(value,0.1,1.5)
	elseif ( iname == "Assisted" ) then
		self.AssistedInput = value ~= 0
	elseif ( iname == "Diff Lock" ) then
		self.DiffLockInput = value ~= 0
	end

end

function ENT:Think()

	if ACE.CurTime > self.NextLegalCheck then
		self.Legal, self.LegalIssues = ACE.CheckLegal(self, self.Model, math.Round(self.Mass,2), self.ModelInertia, true, true) -- requiresweld overrides parentable, need to set it false for parent-only gearboxes
		self.NextLegalCheck = ACE.Legal.NextCheck(self.legal)
		self:UpdateOverlayText()

		if self.Legal and self.Parentable then self.RootParent = ACE.GetPhysicalParent(self) end
	end

	local Time = CurTime()

	if self.LastActive + 2 > Time then
		self:CheckRopes()
	end

	self:NextThink( Time + math.random( 5, 10 ) )
	return true

end

function ENT:CheckRopes()

	for _, Link in pairs( self.WheelLink ) do

		local Ent = Link.Ent

		--skips any invalid entity and remove from list
		if not IsValid(Ent) then continue end

		local OutPos = self:LocalToWorld( Link.Output )
		local InPos = Ent:GetPos()
		if Ent.IsGeartrain then
			InPos = Ent:LocalToWorld( Ent.In )
		end

		-- make sure it is not stretched too far
		if OutPos:Distance( InPos ) > Link.RopeLen * 1.5 then
			self:Unlink( Ent )
			local soundstr =  "physics/metal/metal_box_impact_bullet" .. tostring(math.random(1, 3)) .. ".wav"
			self:EmitSound(soundstr,500,100)
		end

		-- make sure the angle is not excessive
		if not self:Checkdriveshaft( Ent ) then
			self:Unlink( Ent )
			local soundstr =  "physics/metal/metal_box_impact_bullet" .. tostring(math.random(1, 3)) .. ".wav"
			self:EmitSound(soundstr,500,100)
		end
	end
end

-- Check if every entity we are linked to still actually exists
-- and remove any links that are invalid.
function ENT:CheckEnts()

	for Key, Link in pairs( self.WheelLink ) do

		if not IsValid( Link.Ent ) then
			table.remove( self.WheelLink, Key )
		continue end

		local Phys = Link.Ent:GetPhysicsObject()
		if not IsValid( Phys ) then
			Link.Ent:Remove()
			table.remove( self.WheelLink, Key )
		end

	end

end

--[[
	Drivetrain control for this gearbox. The physics (shafts, clutches, differential, brakes)
	is solved by ACE.Mobility.Tick; this part decides what the gearbox is doing this tick:
	which ratio is engaged, how much its clutch can carry, what the differential is set to,
	and for automatics the converter, lock-up and shift schedule.
]]

local RPMToRad = math.pi / 30

-- Clutch heat: a dry clutch pack of a few kg of steel and friction material. Its size scales
-- with the gearbox torque rating. Organic facings fade from ~250 °C and are destroyed near
-- 350-400 °C (Shigley §16-8, and SAE J1916-style clutch-temperature practice).
local ClutchSpecificHeat = 460       -- J/(kg·K), steel
local ClutchFadeStart = 250           -- °C
local ClutchFadeEnd = 450             -- °C, capacity down to the fade floor
local ClutchFadeFloor = 0.35
local ClutchDamageTemp = 350          -- °C

-- The engine driving this gearbox, directly or through parent gearboxes.
local function masterEngine(Box, Depth)
	Depth = Depth or 0
	if Depth > 8 then return nil end
	for _, Master in pairs(Box.Master or {}) do
		if IsValid(Master) then
			if Master:GetClass() == "acf_engine" then return Master end
			local Found = masterEngine(Master, Depth + 1)
			if Found then return Found end
		end
	end
	return Box.ParentBox and IsValid(Box.ParentBox) and masterEngine(Box.ParentBox, Depth + 1) or nil
end

-- Average output shaft speed (rad/s) seen at the last solve, from wheels and child gearboxes.
local function outputSpeed(Box)
	local Desc = Box.Mob
	if not Desc or not Desc.Outputs then return 0 end
	local Sum, Count = 0, 0
	for _, Out in ipairs(Desc.Outputs) do
		if Out.Wheel and Out.Wheel.WOut then
			Sum, Count = Sum + Out.Wheel.WOut, Count + 1
		elseif Out.Gearbox and Out.Gearbox.InputW then
			Sum, Count = Sum + Out.Gearbox.InputW, Count + 1
		end
	end
	return Count > 0 and Sum / Count or 0
end

function ENT:ClutchCapacityScale()
	local T = self.ClutchTemp or ACE.AmbientTemp
	if T <= ClutchFadeStart then return 1 end
	local F = math.Clamp((T - ClutchFadeStart) / (ClutchFadeEnd - ClutchFadeStart), 0, 1)
	return 1 - F * (1 - ClutchFadeFloor)
end

-- Decides the engaged ratio and clutch capacity for this tick. Called by ACE.Mobility.Tick
-- before the gearbox description is built.
function ENT:MobilityControl(Dt)
	local Now = CurTime()
	local Max = self.MaxTorque or 0
	local Mob = self.Mob or {}
	local Engine = masterEngine(self)
	local Throttle = IsValid(Engine) and Engine.Throttle or 0
	local Assisted = ACE.Mobility.IsAssisted(self)
	local Fade = self:ClutchCapacityScale()

	self.MobDriveCap = nil
	self.MobEfficiency = self.Auto and 0.94 or (self.CVT and 0.9 or 0.97)

	-- Differential. Transfer cases are locked; everything else is an open diff unless the Diff
	-- Lock input or a limited-slip preload is set.
	if self.DiffLockInput then
		self.MobDiff = "locked"
	elseif (self.LSDPreload or 0) > 0 or (self.LSDRamp or 0) > 0 then
		self.MobDiff = "lsd"
	elseif self.Category == "Transfer" then
		self.MobDiff = "locked"
	else
		self.MobDiff = "open"
	end

	local Shifting = self.ChangeFinished > Now
	local Target = (self.GearTable[self.Gear] or 0) * (self.GearTable.Final or 1)
	local TargetR = math.abs(Target) > 1e-6 and 1 / Target or 0

	------------------------------------------------ automatic
	if self.Auto then
		if IsValid(Engine) and Engine.MobSpec then
			-- Size the converter once so the engine stalls the converter near 2.2x idle,
			-- a typical passenger-car stall speed (and never past 60% of redline).
			if not self.MobConverter or self.MobConverterFor ~= Engine.MobSpec then
				local Spec = Engine.MobSpec
				local Stall = math.min(Spec.IdleRPM * 2.2, Spec.LimitRPM * 0.6)
				self.MobConverter = ACE.Mobility.TorqueConverter.New(Stall, Spec.BrakeWOT(Stall * RPMToRad), 2.0)
				self.MobConverterFor = Spec
			end
		end

		-- Shift schedule: the builder's speed points, pushed up by throttle (kickdown).
		if self.Drive == 1 and not Shifting and not self.Hold then
			local Base = ACE.GetPhysicalParent(self)
			local Vel = IsValid(Base) and Base:GetVelocity():Length() or 0
			local Scale = self.ShiftScale * (1 + 0.35 * math.max(Throttle - 0.5, 0) / 0.5)
			if self.Gear < self.Gears and Vel > self.ShiftPoints[self.Gear] * Scale then
				self:ChangeGear(self.Gear + 1)
			elseif self.Gear > 1 and Vel < self.ShiftPoints[self.Gear - 1] * Scale * 0.85 then
				self:ChangeGear(self.Gear - 1)
			end
			Shifting = self.ChangeFinished > Now
		end

		-- Clutch-to-clutch shift: the new ratio is engaged at once, its clutch pack picks up the
		-- torque over the shift time while the old one releases.
		self.MobRatio = TargetR
		if Shifting then
			local Frac = 1 - math.Clamp((self.ChangeFinished - Now) / math.max(self.SwitchTime, 0.05), 0, 1)
			self.MobDriveCap = Max * (0.25 + 0.75 * Frac)
		end

		-- Lock-up clutch above the coupling point in the upper gears.
		local SR = 0
		if IsValid(Engine) and Engine.MobState and Engine.MobState.W > 1 then
			SR = (Mob.InputW or 0) / Engine.MobState.W
		end
		local Lock = self.Gear >= 2 and not Shifting and SR > 0.85 and Throttle < 0.9
		self.MobLockupCap = Lock and Max or 0
		-- Until the converter is sized (no engine spec yet) the box is coupled by a plain clutch.
		self.MobClutchCap = self.MobConverter and nil or Max
		self.MobSideScale = 1
		return
	end

	------------------------------------------------ CVT
	if self.CVT and self.Gear == 1 then
		local Want
		if self.CVTRatio and self.CVTRatio > 0 then
			Want = math.Clamp(self.CVTRatio, 0.01, 1)
		else
			local InRPM = (Mob.InputW or 0) / RPMToRad
			Want = math.Clamp((InRPM - self.TargetMinRPM) / ((self.TargetMaxRPM - self.TargetMinRPM) or 1), 0.05, 1)
		end
		-- The sheaves move hydraulically; the ratio follows with a ~0.3 s time constant.
		local Cur = self.GearTable[1] or Want
		self.GearTable[1] = Cur + (Want - Cur) * (1 - math.exp(-Dt / 0.3))
		self.GearRatio = self.GearTable[1] * self.GearTable.Final
		Target = self.GearRatio
		TargetR = 1 / Target
	end

	------------------------------------------------ manual (and CVT, clutch, diffs)
	local Pedal = Max > 0 and 1 - (self.LClutch or Max) / Max or 0

	if Shifting then
		self.MobRatio = 0
		self.PendingEngage = true
	elseif self.PendingEngage then
		-- Synchromesh: the gear only goes in once the input shaft is near the output speed,
		-- which needs the clutch pressed (or a rev-matched blip). Assisted boxes rev-match.
		local Out = outputSpeed(self)
		local Need = Out * TargetR
		local Mismatch = math.abs((Mob.InputW or 0) - Need)
		if Assisted or Pedal > 0.85 or Mismatch < 250 * RPMToRad or TargetR == 0 then
			self.PendingEngage = false
			Mob.InputW = Need
			self.EngagedAt = Now
		elseif Now > (self.NextGrind or 0) then
			self.NextGrind = Now + 0.4
			self:EmitSound("physics/metal/metal_solid_strain" .. math.random(1, 5) .. ".wav", 70, math.random(140, 170), 0.7)
		end
		self.MobRatio = self.PendingEngage and 0 or TargetR
	else
		self.MobRatio = TargetR
	end

	local Cap = (self.LClutch or Max) * Fade
	self.MobSideScale = Fade
	if Assisted and IsValid(Engine) and Engine.MobState and Engine.MobSpec then
		-- Automatic clutch: fully out while shifting, eased back in afterwards, and slipped
		-- like a centrifugal clutch at launch so the engine cannot stall.
		local Launch = ACE.Mobility.Vehicle.AssistedClutch(Engine.MobState, Engine.MobSpec, Max, Pedal, Throttle)
		local Since = Now - (self.EngagedAt or 0)
		local Ease = math.Clamp(Since / 0.3, 0, 1)
		Cap = (Shifting or self.PendingEngage) and 0 or math.min(Launch, Max * Ease) * Fade
		-- Dual-clutch (steering) boxes have no main clutch; their side clutches do the launch.
		self.MobSideScale = Max > 0 and Cap / Max or 0
	end
	self.MobClutchCap = Cap
	self.MobConverter = nil
end

-- Reads back the solve: outputs and clutch heat.
function ENT:MobilityApply()
	local Mob = self.Mob
	if not Mob then return end
	local Dt = engine.TickInterval()

	-- Clutch temperature: slip heat in, convection out (~20 s time constant at ambient air).
	local Mass = 2 + (self.MaxTorque or 0) / 250
	local T = self.ClutchTemp or ACE.AmbientTemp
	T = T + (Mob.ClutchHeatJ or 0) / (ClutchSpecificHeat * Mass)
	T = T - (T - ACE.AmbientTemp) * (1 - math.exp(-Dt / 20))
	self.ClutchTemp = T

	if T > ClutchDamageTemp and self.ACE and self.ACE.Health then
		-- A cooked clutch wears its facings away: lose health in proportion to the overheat.
		local Wear = (T - ClutchDamageTemp) / 100 * Dt * 0.01 * self.ACE.MaxHealth
		self.ACE.Health = math.max(self.ACE.Health - Wear, self.ACE.MaxHealth * 0.05)
	end

	if self.CVT then Wire_TriggerOutput(self, "Ratio", self.GearRatio) end
	Wire_TriggerOutput(self, "Input RPM", math.Round((Mob.InputW or 0) * 30 / math.pi))
	Wire_TriggerOutput(self, "Clutch Slip", math.Round(math.abs(Mob.ClutchSlip or 0) * 30 / math.pi))
	Wire_TriggerOutput(self, "Clutch Temp", math.Round(T))
	Wire_TriggerOutput(self, "Output Torque", math.Round(Mob.OutputTorque or 0))

	-- Kept for E2/Starfall acfTorqueOut, which divides by GearRatio.
	self.TotalReqTq = math.abs((Mob.OutputTorque or 0) * (self.GearRatio or 0))
end

function ENT:ChangeGear(value)

	local new = math.Clamp(math.floor(value),0,self.Gears)
	if self.Gear == new then return end

	self.Gear = new
	self.GearRatio = (self.GearTable[self.Gear] or 0) * self.GearTable.Final
	self.ChangeFinished = CurTime() + self.SwitchTime
	self.InGear = false

	Wire_TriggerOutput(self, "Current Gear", self.Gear)
	self:EmitSound("buttons/lever7.wav",250,100)
	Wire_TriggerOutput(self, "Ratio", self.GearRatio)

end

--handles gearing for automatics; 0=neutral, 1=forward autogearing, 2=reverse
function ENT:ChangeDrive(value)

	local new = math.Clamp(math.floor(value),0,2)
	if self.Drive == new then return end

	self.Drive = new
	if self.Drive == 2 then
		self.Gear = self.Reverse
		self.GearRatio = (self.GearTable[self.Gear] or 0) * self.GearTable.Final
		self.ChangeFinished = CurTime() + self.SwitchTime
		self.InGear = false

		Wire_TriggerOutput(self, "Current Gear", self.Gear)
		self:EmitSound("buttons/lever7.wav",250,100)
		Wire_TriggerOutput(self, "Ratio", self.GearRatio)
	else
		self:ChangeGear(self.Drive) --autogearing in :calc will set correct gear
	end

end

do

	--[[
	--HARDCODED. USE MODELDEFINITION INSTEAD
	local TransAxialGearboxes = {
		["models/engines/transaxial_l.mdl"] = true,
		["models/engines/transaxial_m.mdl"] = true,
		["models/engines/transaxial_s.mdl"] = true,
		["models/engines/transaxial_t.mdl"] = true --mhm acf extras invading...
	}
	]]

	function ENT:Checkdriveshaft( NextEnt )

		local InPos = vector_origin
		if NextEnt.IsGeartrain then
			InPos = NextEnt.In
		end
		local InPosWorld = NextEnt:LocalToWorld( InPos )

		local OutPos	= self.OutR
		if self:WorldToLocal( InPosWorld ).y < 0 then
			OutPos  = self.OutL
		end
		local OutPosWorld = self:LocalToWorld( OutPos )

		local MaxAngle = 0.7 --magic number to define the max tolerance of link between gearboxes
		local Direction = ( self:GetRight() * OutPos.y ):GetNormalized()
		local DrvAngle = ( OutPosWorld - InPosWorld ):GetNormalized():Dot( Direction )

		if DrvAngle < MaxAngle then
			return false
		--else
			--[[ --Disabled since this could break several builds. When we have more junctions, this could be enforced.
			--Now, do the same, but from gearbox's point this time.
			Direction 	= TransAxialGearboxes[ NextEnt:GetModel() ] and -NextEnt:GetForward() or -NextEnt:GetRight() --transaxial like those T junctions. Forward is for Straight like gearboxes.
			DrvAngle 	= ( InPosWorld - OutPosWorld ):GetNormalized():Dot( Direction )

			if DrvAngle < MaxAngle then
				return false
			end
			]]
		end

		return true
	end

end

function ENT:Link( Target )

	if not IsValid( Target ) or not table.HasValue( { "prop_physics", "acf_gearbox", "tire" }, Target:GetClass() ) then
		return false, "Can only link props or gearboxes!"
	end

	-- Check if target is already linked
	for _, Link in pairs( self.WheelLink ) do
		if Link.Ent == Target then
			return false, "That is already linked to this gearbox!"
		end
	end

	-- make sure the angle is not excessive
	if not self:Checkdriveshaft( Target ) then
		return false, "Cannot link due to excessive driveshaft angle!"
	end

	local InPos = Vector( 0, 0, 0 )
	if Target.IsGeartrain then
		InPos = Target.In
	end
	local InPosWorld = Target:LocalToWorld( InPos )

	local OutPos	= self.OutR
	local Side	= 1
	if self:WorldToLocal( InPosWorld ).y < 0 then
		OutPos  = self.OutL
		Side	= 0
	end
	local OutPosWorld = self:LocalToWorld( OutPos )

	local Rope = nil
	if self:CPPIGetOwner():GetInfoNum( "ace_mobility_rope_links", 1) == 1 then
		Rope = ACE.CreateLinkRope( OutPosWorld, self, OutPos, Target, InPos )
	end

	local Phys	= Target:GetPhysicsObject()
	local Axis	= Phys:WorldToLocalVector( self:GetRight() )
	local Inertia	= ( Axis * Phys:GetInertia() ):Length()

	local Link = {
		Ent			= Target,
		Side		= Side,
		Axis		= Axis,
		Inertia		= Inertia,
		Rope		= Rope,
		RopeLen		= ( OutPosWorld - InPosWorld ):Length(),
		Output		= OutPos,
		ReqTq		= 0,
		Vel			= 0
	}
	table.insert( self.WheelLink, Link )

	return true, "Link successful!"

end

function ENT:Unlink( Target )

	for Key, Link in pairs( self.WheelLink ) do

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

			table.remove( self.WheelLink, Key )

			return true, "Unlink successful!"

		end

	end

	return false, "That entity is not linked to this gearbox!"

end

function ENT:PreEntityCopy()

	-- Link Saving
	local info = {}
	local entids = {}

	-- Clean the table of any invalid entities
	for Key, Link in pairs( self.WheelLink ) do
		if not IsValid( Link.Ent ) then
			table.remove( self.WheelLink, Key )
		end
	end

	-- Then save it
	for _, Link in pairs( self.WheelLink ) do
		table.insert( entids, Link.Ent:EntIndex() )
	end

	info.entities = entids
	if info.entities then
		duplicator.StoreEntityModifier( self, "WheelLink", info )
	end

	--Wire dupe info
	self.BaseClass.PreEntityCopy( self )

end

function ENT:PostEntityPaste( Player, Ent, CreatedEntities )

	-- Link Pasting
	if Ent.EntityMods and Ent.EntityMods.WheelLink and Ent.EntityMods.WheelLink.entities then
		local WheelLink = Ent.EntityMods.WheelLink
		if WheelLink.entities and next( WheelLink.entities ) then
			timer.Simple( 0, function() -- this timer is a workaround for an ad2/makespherical issue https://github.com/nrlulz/ACF/issues/14#issuecomment-22844064
				for _, ID in pairs( WheelLink.entities ) do
					local Linked = CreatedEntities[ ID ]
					if IsValid( Linked ) then
						self:Link( Linked )
					end
				end
			end )
		end
		Ent.EntityMods.WheelLink = nil
	end

	--Wire dupe info
	self.BaseClass.PostEntityPaste( self, Player, Ent, CreatedEntities )

end

function ENT:OnRemove()

	for Key in pairs(self.Master) do	--Let's unlink ourselves from the engines properly
		if IsValid( self.Master[Key] ) then
			self.Master[Key]:Unlink( self )
		end
	end

end

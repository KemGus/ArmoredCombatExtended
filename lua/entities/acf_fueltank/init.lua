AddCSLuaFile("shared.lua")
AddCSLuaFile("cl_init.lua")

include("shared.lua")

local BaseClass = baseclass.Get("ace_scalability")

--don't forget:
--armored tanks

local TankTable = ACE.Weapons.FuelTanksSize

do

	local FueltankWireDescs = {
		--Inputs
		["Refuel"]	= "Allows to this tank to supply other fuel tanks.\n Fuel type must be equal to the tank which you want to supply.",

		--Outputs
		["Fuel"]        = "Returns the current fuel level.",
		["Capacity"]    = "Returns the max capacity of this fuel tank. Batteries: the capacity left after wear, in kWh.",
		["Leaking"]     = "Is the fuel tank leaking?",
		["Temperature"] = "Batteries only: cell temperature in °C. Charging stops at 50 °C, discharging at 60 °C.",
		["Health"]      = "Batteries only: capacity left, in % of a new battery's.",
		["Power"]       = "Batteries only: power the battery is giving out now, in kW (negative while it charges), averaged over about a second."
	}

	local Names = { "Fuel", "Capacity", "Leaking" }

	--- Wire outputs of a fuel tank; batteries add their temperature and health.
	-- @param Electric boolean Whether the tank is a battery.
	-- @return table Names, table Types.
	function ACE.FuelTankOutputs(Electric)
		local Out, Types = {}, {}
		for _, Name in ipairs(Names) do
			Out[#Out + 1] = Name .. " (" .. FueltankWireDescs[Name] .. ")"
			Types[#Types + 1] = "NORMAL"
		end
		Out[#Out + 1], Types[#Types + 1] = "Entity", "ENTITY"
		if Electric then
			for _, Name in ipairs({ "Temperature", "Health", "Power" }) do
				Out[#Out + 1] = Name .. " (" .. FueltankWireDescs[Name] .. ")"
				Types[#Types + 1] = "NORMAL"
			end
		end
		return Out, Types
	end

	function ENT:Initialize()

		self.CanUpdate        = true
		self.SpecialHealth    = true  --If true, use the ACE_Activate function defined by this ent
		self.SpecialDamage    = true  --If true, use the ACE_OnDamage function defined by this ent
		self.IsExplosive      = true
		self.Exploding        = false

		self.Size             = 0	--outer dimensions
		self.Volume           = 0	--total internal volume in cubic inches
		self.Capacity         = 0	--max fuel capacity in liters
		self.Fuel             = 0	--current fuel level in liters
		self.FuelType         = nil
		self.EmptyMass        = 0	--mass of tank only
		self.NextMassUpdate   = 0
		self.Id               = nil	--model id
		self.Active           = true
		self.SupplyFuel       = false
		self.Leaking          = 0
		self.NextLegalCheck   = ACE.CurTime + math.random(ACE.Legal.Min, ACE.Legal.Max) -- give any spawning issues time to iron themselves out
		self.Legal            = true
		self.LegalIssues      = ""

		self.Inputs = Wire_CreateInputs( self, { "Active", "Refuel Duty (" .. FueltankWireDescs["Refuel"] .. ")" } )
		self.Outputs = WireLib.CreateSpecialOutputs( self, ACE.FuelTankOutputs(false) )
		ACE.GetDefaultActiveInputState(self)
		Wire_TriggerOutput( self, "Leaking", 0 )
		Wire_TriggerOutput( self, "Entity", self )

		self.Master = {} --engines linked to this tank
		self.RadLink = {} --radiators cooling this battery
		self.IsMaster = true --so the link tool asks the battery to link a radiator
		ACE.FuelTanks = ACE.FuelTanks or {} --master list of acf fuel tanks

		self.LastThink = 0
		self.NextThink = CurTime() +  1

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
	local Health = (self.ACE.Volume / ACE.Threshold) * 0.5					--Setting the threshold of the prop Area gone

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
	self:UpdateFuelMass()

end

function ENT:ACF_OnDamage( Entity, Energy, FrArea, Angle, Inflictor, _, Type )	--This function needs to return HitRes

	local Mul = (((Type == "HEAT" or Type == "THEAT" or Type == "HEATFS" or Type == "THEATFS") and ACE.HEATMulFuel) or 1) --Heat penetrators deal bonus damage to fuel
	local HitRes = ACE.PropDamage( Entity, Energy, FrArea * Mul, Angle, Inflictor ) --Calling the standard damage prop function

	local NoExplode = self.FuelType == "Diesel" and not (Type == "HE" or Type == "HEAT" or Type == "THEAT" or Type == "HEATFS" or Type == "THEATFS")
	if self.Exploding or NoExplode or not self.IsExplosive then return HitRes end

	if HitRes.Kill then

	if hook.Run( "ACE_FuelExplode", self ) == false then return HitRes end

		self.Exploding = true

		if IsValid(Inflictor) and Inflictor:IsPlayer() then
			self.Inflictor = Inflictor
		end

		ACE.ScaledExplosion( self , true )

		return HitRes
	end

	local Ratio = (HitRes.Damage / self.ACE.Health) ^ 0.75 --chance to explode from sheer damage, small shots = small chance
	local ExplodeChance = (1-(self.Fuel / self.Capacity)) ^ 0.75 --chance to explode from fumes in tank, less fuel = more explodey

	--it's gonna blow
	if math.Rand(0, 1.2) < (ExplodeChance + Ratio) then

	if hook.Run( "ACE_FuelExplode", self ) == false then return HitRes end

		self.Inflictor = Inflictor
		self.Exploding = true

		timer.Simple(math.Rand(0.1, 1), function()
			if IsValid(self) then
				ACE.ScaledExplosion( self , true )
			end
		end )

	else												--spray some fuel around
		self:NextThink( CurTime() + 0.1 )
		if self.FuelType ~= "Electric" then
			self.Leaking = self.Leaking + self.Fuel * ((HitRes.Damage / self.ACE.Health) ^ 1.5) * 0.25
		end
	end

	return HitRes

end

do

	-- Parses + clamps an "L:W:H" string into a Vector. Shared with ammo crates and
	-- scalable explosives (see ACE.Scalable.ParseScale); fuel tanks pass the crate
	-- size limits as their bounds.
	local function ConvertStringScale( ScaleId )
		return ACE.Scalable.ParseScale( ScaleId, { min = ACE.CrateMinimumSize, max = ACE.CrateMaximumSize } )
	end

	function ACE.MakeFuelTank(Owner, Pos, Angle, Id, Data1, Data2, Data3)

		if IsValid(Owner) and not Owner:CheckLimit("_ace_misc") then return false end

		local Tank = ents.Create("acf_fueltank")
		if IsValid(Tank) then

			local Model
			local Dimensions

			Tank:CPPISetOwner(Owner)
			Tank:SetAngles(Angle)
			Tank:SetPos(Pos)
			Tank:Spawn()

			-- If the crate is not valid in the system, but it could be scalable.
			if not ACE.CheckFuelTank( Data1 ) then

				-- Reminder: When the legacy fueltanks get deleted. Do the same as ammo crates.
				local Scale = ConvertStringScale(Data1)

				if isvector(Scale) then

					local ModelData = ACE.ModelData[Data3]

					Data1 = Scale
					Model = ModelData.Model
					Weight = (Scale.x * Scale.y * Scale.z) / 200
					Dimensions = Scale

					local DefaultSize    = ModelData.DefaultSize
					local Mesh           = ModelData.CustomMesh
					local PhysMaterial   = ModelData.physMaterial
					local EntityScale    = Vector(Scale.x / DefaultSize, Scale.y / DefaultSize, Scale.z / DefaultSize)

					Tank.ScaleData = {
						Mesh = Mesh,
						Scale = EntityScale,
						Size = DefaultSize,
						Material = PhysMaterial,
					}

					Tank:SetMaterial("phoenix_storms/gear")
					Tank:SetModel( Model ) --Sending the model to client
					Tank:PhysicsInit( SOLID_VPHYSICS )
					Tank:SetMoveType( MOVETYPE_VPHYSICS )
					Tank:SetSolid( SOLID_VPHYSICS )

					Tank.IsScalable = true
					Tank:ACE_SetScale( Tank.ScaleData )

				else
					Data1 = "Tank_4x4x2"
				end
			end

			if ACE.CheckFuelTank( Data1 ) then

				local TankData = TankTable[Data1]

				Model = TankData.model
				Weight = TankData.weight

				Tank:SetModel( Model )
				Tank:PhysicsInit( SOLID_VPHYSICS )
				Tank:SetMoveType( MOVETYPE_VPHYSICS )
				Tank:SetSolid( SOLID_VPHYSICS )

			end

			Tank.Id           = Id
			Tank.SizeId       = Data1
			Tank.Shape 		  = Data3
			Tank.Model        = Model
			Tank.Dimensions   = Dimensions

			Tank.LastMass = 1
			Tank:UpdateFuelTank(Id, Data1, Data2)

			Owner:AddCount( "_ace_misc", Tank )
			Owner:AddCleanup( "acemenu", Tank )

			table.insert(ACE.FuelTanks, Tank)

			return Tank
		end

		return Tank
	end
end

list.Set( "ACFCvars", "acf_fueltank", {"id", "data1", "data2", "data3"} )
duplicator.RegisterEntityClass("acf_fueltank", ACE.MakeFuelTank, "Pos", "Angle", "Id", "SizeId", "FuelType", "Shape" )


local Wall = 0.03937 --wall thickness in inches (1mm)

function ENT:UpdateFuelTank(_, _, Data2)

	local electric = "ups"
	local gas = "ups"
	local TankData = TankTable[self.SizeId]
	local pct = 1 --how full is the tank?

	if self.Capacity and self.Capacity ~= 0 then --if updating existing tank, keep fuel level
		pct = self.Fuel / self.Capacity
	end

	if self.IsScalable then

		local ModelData = ACE.ModelData[self.Shape]
		local Volumefunc = ModelData.volumefunction

		local Dimensions = self.Dimensions

		local Length = Dimensions.x
		local Width = Dimensions.y
		local Height = Dimensions.z

		local Volume = Volumefunc( Length, Width, Height)
		local IVolume = Volumefunc( Length - (Wall * 2), Width - (Wall * 2), Height - (Wall * 2))

		self.Volume        = IVolume-- total volume of tank (cu in), reduced by wall thickness
		self.Capacity      = IVolume * ACE.CuIToLiter * ACE.TankVolumeMul * 0.4774 --internal volume available for fuel in liters, with magic realism number
		self.EmptyMass     = (Volume - IVolume) * 16.387 * ( 7.9 / 1000 )    -- total wall volume * cu in to cc * density of steel (kg/cc)

		local x = math.Round(Length, 1) / 10
		local y = math.Round(Width, 1) / 10
		local z = math.Round(Height, 1) / 10

		local dims = x .. "x" .. y .. "x" .. z

		electric = (Data2 == "Electric") and dims .. " Li-Ion Battery"
		gas	= Data2 .. " " .. dims .. " Fuel Tank"

	else
		local PhysObj    = self:GetPhysicsObject()
		local Area       = PhysObj:GetSurfaceArea()
		local Volume     = PhysObj:GetVolume()

		self.Volume        = Volume - (Area * Wall) -- total volume of tank (cu in), reduced by wall thickness
		self.Capacity      = self.Volume * ACE.CuIToLiter * ACE.TankVolumeMul * 0.4774 --internal volume available for fuel in liters, with magic realism number
		self.EmptyMass     = (Area * Wall) * 16.387 * (7.9 / 1000)  -- total wall volume * cu in to cc * density of steel (kg/cc)

		electric = (Data2 == "Electric") and TankData.name .. " Li-Ion Battery"
		gas	= Data2 .. " " .. TankData.name .. ( not TankData.notitle and " Fuel Tank" or "")
	end

	local WasElectric = self.FuelType == "Electric"
	self.FuelType      = Data2
	self.IsExplosive   = self.FuelType ~= "Electric" and false or true
	self.NoLinks       = TankData and (TankData.nolinks == true) or false

	if self.FuelType == "Electric" then
		self.Liters   = self.Capacity --batteries capacity is different from internal volume
		self.NominalCapacity = self.Capacity * ACE.LiIonED
		self:UpdateBatterySpec()
		self.Capacity = self.NominalCapacity * ACE.Mobility.Battery.Health(self.BatteryState)
		self.Fuel     = pct * self.Capacity
	else
		self.BatterySpec, self.BatteryState, self.NominalCapacity = nil, nil, nil
		self.Fuel	= pct * self.Capacity
	end

	if WasElectric ~= (self.FuelType == "Electric") then
		WireLib.AdjustSpecialOutputs( self, ACE.FuelTankOutputs(self.FuelType == "Electric") )
		Wire_TriggerOutput( self, "Entity", self )
	end

	self:UpdateFuelMass()

	local name = "ACE " .. (electric or gas)

	self:SetNWString( "WireName", name )

	Wire_TriggerOutput( self, "Capacity", math.Round(self.Capacity,2) )
	self:UpdateOverlayText()

end

function ENT:UpdateOverlayText()


	local Stats

	if self.Active then
		Stats = "In use"
	else
		Stats = "Not In use"
	end

	local text = "- " .. Stats .. " -\n"

	if self.FuelType == "Electric" then

		text = text .. "\nCurrent Charge Level:"
		text = text .. "\n-  " .. math.Round( self.Fuel, 1 ) .. " / " .. math.Round( self.Capacity, 1 ) .. " kWh"
		text = text .. "\n-  " .. math.Round( self.Fuel * 3.6, 1 ) .. " / " .. math.Round( self.Capacity * 3.6, 1) .. " MJ"

		local State = self.BatteryState
		if State then
			local Battery = ACE.Mobility.Battery
			local Power = self.PowerKW or 0
			text = text .. "\n\n" .. ( Power < 0 and "Charging: " or "Output: " ) .. math.Round( math.abs( Power ), 1 ) .. " kW"
			text = text .. "\nTemperature: " .. math.Round( State.T, 1 ) .. " °C"
			if #(self.RadLink or {}) > 0 then
				text = text .. "\nLiquid cooled by " .. #self.RadLink .. (#self.RadLink == 1 and " radiator" or " radiators")
			end
			text = text .. "\nHealth: " .. math.Round( Battery.Health(State) * 100, 2 ) .. " % of new capacity"
			if State.T > Battery.DischargeTmax - Battery.TaperK then
				text = text .. "\n- Too hot: output limited"
			elseif State.T > Battery.ChargeTmax - Battery.TaperK then
				text = text .. "\n- Too hot to charge"
			end
		end

	else

		text = text .. "\nCurrent Fuel Remaining:"
		text = text .. "\n-  " .. math.Round( self.Fuel, 1 ) .. " / " .. math.Round( self.Capacity, 1 ) .. " liters"
		text = text .. "\n-  " .. math.Round( self.Fuel * 0.264172, 1 ) .. " / " .. math.Round( self.Capacity * 0.264172, 1 ) .. " gallons"

		--text = text .. "\nFuel Remaining: " .. math.Round( self.Fuel, 1 ) .. " liters / " .. math.Round( self.Fuel * 0.264172, 1 ) .. " gallons"

		if self.Leaking > 0 then
			text = text .. "\n- Leaking: " .. math.Round(self.Leaking, 1) .. " liters per second"
		end
	end

	if not self.Legal then
		text = text .. "\nNot legal, disabled for " .. math.ceil(self.NextLegalCheck - ACE.CurTime) .. "s\nIssues: " .. self.LegalIssues
	end

	self:SetOverlayText( text )

end

function ENT:UpdateFuelMass()

	if self.FuelType == "Electric" then
		self.Mass = self.EmptyMass + self.Liters * ACE.FuelDensity[self.FuelType]
	else
		local FuelMass = self.Fuel * ACE.FuelDensity[self.FuelType]
		self.Mass = self.EmptyMass + FuelMass
	end

	--reduce superflous engine calls, update fuel tank mass every 5 kgs change or every 10s-15s
	if math.abs(self.LastMass - self.Mass) > 5 or CurTime() > self.NextMassUpdate then
		self.LastMass = self.Mass
		self.NextMassUpdate = CurTime() + math.Rand(10, 15)
		local phys = self:GetPhysicsObject()
		if (phys:IsValid()) then
			phys:SetMass( self.Mass )
		end
	end

	self:UpdateOverlayText()

end

--[[
	Batteries. The cells are modelled in ace/shared/mobility/battery_model.lua: resistive losses
	heat them, they cool to the air through the pack's skin, and they wear with time, heat,
	charge level and cycling. The wear lives only on the entity: a duplicated battery is
	pasted new.
]]

--- Rebuilds a battery's thermal description from its size, keeping its wear and temperature.
function ENT:UpdateBatterySpec()
	local Battery = ACE.Mobility.Battery

	local AreaIn2
	if self.IsScalable and self.Dimensions then
		local D = self.Dimensions
		AreaIn2 = 2 * (D.x * D.y + D.y * D.z + D.x * D.z)
	else
		local PhysObj = self:GetPhysicsObject()
		AreaIn2 = IsValid(PhysObj) and PhysObj:GetSurfaceArea() or 0
	end

	local CellKg = (self.Liters or 0) * ACE.FuelDensity.Electric
	self.BatterySpec = Battery.Build(self.NominalCapacity * 1000, CellKg, self.EmptyMass or 0, AreaIn2 * 0.00064516)
	self.BatteryState = self.BatteryState or Battery.NewState(ACE.AmbientTemp)
end

--- Charging power this battery accepts right now (CC-CV and the charge temperature limit).
-- @return number Watts; 0 for fuel tanks, and for batteries that are full, off or too hot.
function ENT:ChargeAcceptW()
	if self.FuelType ~= "Electric" or not self.BatteryState or not self.Active or not self.Legal then return 0 end
	return ACE.Mobility.Battery.ChargeAcceptW(self.BatterySpec, self.BatteryState, self.Fuel / math.max(self.Capacity, 1e-6))
end

--- Share of full output the battery management allows at the cells' temperature.
-- @return number 0..1; always 1 for fuel tanks.
function ENT:DischargeDerate()
	if not self.BatteryState then return 1 end
	return ACE.Mobility.Battery.DischargeDerate(self.BatteryState)
end

-- Moves TerminalKWh through a battery's terminals (positive charges) over Dt seconds.
local function batteryTransfer(Tank, TerminalKWh, Dt)
	local Battery = ACE.Mobility.Battery
	local State = Tank.BatteryState
	local Stored = Battery.Transfer(Tank.BatterySpec, State, TerminalKWh * 1000, Dt) / 1000
	local Before = Tank.Fuel
	Tank.Fuel = math.Clamp(Tank.Fuel + Stored, 0, Tank.Capacity)
	local Moved = Tank.Fuel - Before
	Battery.AddThroughput(State, Moved / math.max(Tank.NominalCapacity, 1e-6), Tank.Fuel / math.max(Tank.Capacity, 1e-6))
	-- Terminal energy since the last think, for the Power output.
	Tank.TerminalKWh = (Tank.TerminalKWh or 0) + TerminalKWh
	return Moved
end

--- Takes energy out of a tank. Batteries also lose their internal resistance loss (heat) on top.
-- @param KWh number Energy delivered, kWh (fuel tanks: litres).
-- @param Dt number Time it took, s.
function ENT:DrawEnergy(KWh, Dt)
	if KWh <= 0 then return end
	if not self.BatteryState then
		self.Fuel = math.max(self.Fuel - KWh, 0)
		return
	end
	batteryTransfer(self, -KWh, Dt)
end

--- Charges a battery. Only the input less the resistive loss is stored.
-- @param KWh number Energy put in at the terminals, kWh.
-- @param Dt number Time it took, s.
function ENT:StoreEnergy(KWh, Dt)
	if KWh <= 0 then return end
	if not self.BatteryState then
		self.Fuel = math.min(self.Fuel + KWh, self.Capacity)
		return
	end
	batteryTransfer(self, KWh, Dt)
end

--[[
	Battery cooling loop. Real packs sit on liquid cold plates whose coolant runs through a
	radiator; a battery linked to radiators gets that loop (Battery.LoopG). A radiator shared
	with engines or other batteries gives each an equal share, as engines share them. Returns
	the loop's conductance and writes the coolant temperature back to radiators no engine uses.
]]
local LoopFanOnTemp = 30 -- °C; battery loops run their fan far cooler than an engine's thermostat

local function batteryLoop(Tank, CellT)
	if not Tank.RadLink then return 0 end
	local Rads = {}
	for I = #Tank.RadLink, 1, -1 do
		local Rad = Tank.RadLink[I]
		if not IsValid(Rad) then
			table.remove(Tank.RadLink, I)
		elseif Rad.ThermalUA then
			local Share = 1 / math.max(#Rad.Master + #(Rad.Batteries or {}), 1)
			Rads[#Rads + 1] = { UA = Rad.ThermalUA * Share, Cair = Rad.ThermalCair * Share, Rad = Rad }
			Rad.BatteryFanWanted = Tank.Active and CellT > LoopFanOnTemp or nil
			Rad.FanBattery = Tank
		end
	end
	if #Rads == 0 then return 0 end
	local G, Gr = ACE.Mobility.Battery.LoopG(Tank.BatterySpec, Rads)
	local Ambient = ACE.AmbientTemp
	local Q = G * (CellT - Ambient)
	for _, R in ipairs(Rads) do
		-- Engines sharing the radiator write their own coolant temperature; batteries only fill in.
		if #R.Rad.Master == 0 then
			R.Rad.Heat = Gr > 0 and Ambient + Q / Gr or Ambient
			R.Rad.HeatRejected = Q / #Rads
		end
	end
	return G
end

--- Links a radiator to cool this battery.
-- @param Target ace_radiator entity.
-- @return boolean, string Success and message.
function ENT:Link( Target )
	if not IsValid( Target ) or Target:GetClass() ~= "ace_radiator" then
		return false, "Batteries can only be linked to radiators!"
	end
	if self.FuelType ~= "Electric" then
		return false, "Only batteries can be cooled by a radiator!"
	end
	self.RadLink = self.RadLink or {}
	if table.HasValue( self.RadLink, Target ) then
		return false, "That radiator is already linked to this battery!"
	end
	if self:GetPos():Distance( Target:GetPos() ) > 512 then
		return false, "The radiator is too far away."
	end
	table.insert( self.RadLink, Target )
	Target.Batteries = Target.Batteries or {}
	table.insert( Target.Batteries, self )
	self:UpdateOverlayText()
	return true, "Link successful!"
end

--- Unlinks a radiator from this battery.
-- @param Target ace_radiator entity.
-- @return boolean, string Success and message.
function ENT:Unlink( Target )
	if not table.HasValue( self.RadLink or {}, Target ) then
		return false, "That radiator is not linked to this battery!"
	end
	table.RemoveByValue( self.RadLink, Target )
	if IsValid( Target ) and Target.Batteries then table.RemoveByValue( Target.Batteries, self ) end
	self:UpdateOverlayText()
	return true, "Unlink successful!"
end

function ENT:PreEntityCopy()
	local Ids = {}
	for _, Rad in ipairs( self.RadLink or {} ) do
		if IsValid( Rad ) then Ids[#Ids + 1] = Rad:EntIndex() end
	end
	duplicator.StoreEntityModifier( self, "RadLink", { entities = Ids } )
	if BaseClass.PreEntityCopy then BaseClass.PreEntityCopy( self ) end
end

function ENT:PostEntityPaste( Player, Ent, CreatedEntities )
	local Mod = Ent.EntityMods and Ent.EntityMods.RadLink
	if Mod and Mod.entities then
		for _, Id in pairs( Mod.entities ) do
			local Rad = CreatedEntities[Id]
			if IsValid( Rad ) then self:Link( Rad ) end
		end
		Ent.EntityMods.RadLink = nil
	end
	if BaseClass.PostEntityPaste then BaseClass.PostEntityPaste( self, Player, Ent, CreatedEntities ) end
end

-- Heat, cooling and wear, every think. Heat follows ace_heat_timescale like the engines' coolant;
-- calendar wear runs on real time.
local function batteryThink(Tank, Dt)
	local Battery = ACE.Mobility.Battery
	local State = Tank.BatteryState
	if not State or Dt <= 0 then return end
	-- The first think after spawning measures from 0; tanks think about once a second.
	Dt = math.min(Dt, 5)

	Battery.ThermalStep(Tank.BatterySpec, State, Dt, ACE.AmbientTemp, ACE.ThermalTimeScale, batteryLoop(Tank, State.T))
	Battery.CalendarAge(State, Tank.Fuel / math.max(Tank.Capacity, 1e-6), Dt / 86400)

	local Capacity = Tank.NominalCapacity * Battery.Health(State)
	if math.abs(Capacity - Tank.Capacity) > 1e-6 then
		Tank.Capacity = Capacity
		Tank.Fuel = math.min(Tank.Fuel, Capacity)
		Wire_TriggerOutput( Tank, "Capacity", math.Round(Capacity, 2) )
	end
	Wire_TriggerOutput( Tank, "Temperature", State.T )
	Wire_TriggerOutput( Tank, "Health", Battery.Health(State) * 100 )
	-- kWh over Dt seconds to kW; positive while the battery gives power out.
	Tank.PowerKW = -(Tank.TerminalKWh or 0) * 3600 / Dt
	Tank.TerminalKWh = 0
	Wire_TriggerOutput( Tank, "Power", math.Round(Tank.PowerKW, 2) )
end

function ENT:Update( ArgsTable )

	local Feedback = ""

	if ( ArgsTable[6] ~= self.FuelType ) then
		for _, Engine in pairs( self.Master ) do
			if Engine:IsValid() then
				Engine:Unlink( self )
			end
		end
		Feedback = " New fuel type loaded, fuel tank unlinked."
	end

	self:UpdateFuelTank(ArgsTable[4], ArgsTable[5], ArgsTable[6]) --Id, SizeId, FuelType

	return true, "Fuel tank successfully updated." .. Feedback
end

function ENT:TriggerInput( iname, value )

	if (iname == "Active") then
		self.Active = ACE.GetDefaultActiveInputState(self, value)

		self:UpdateOverlayText()
	elseif iname == "Refuel Duty" then
		if value ~= 0 then
			self.SupplyFuel = true
		else
			self.SupplyFuel = false
		end
	end

end

function ENT:Think()

	if not ACE.IsDefaultActiveInputWired(self) then
		self.Active = ACE.GetDefaultActiveInputState(self)
	end

	if ACE.CurTime > self.NextLegalCheck then
		--local minmass = math.floor(self.Mass-6)  -- fuel is light, may as well save complexity and just check it's above empty mass
		self.Legal, self.LegalIssues = ACE.CheckLegal(self, self.Model, math.Round(self.EmptyMass,2), nil, true, true) -- mass-6, as mass update is granular to 5 kg
		self.NextLegalCheck = ACE.Legal.NextCheck(self.legal)
		self:UpdateOverlayText()
	end

	--make sure it's not made spherical
	if self.EntityMods and self.EntityMods.MakeSphericalCollisions then self.Fuel = 0 end

	if self.Leaking > 0 then
		self:NextThink( CurTime() + 0.25 )
		self.Fuel = math.max(self.Fuel - self.Leaking,0)
		self.Leaking = math.Clamp(self.Leaking - (1 / math.max(self.Fuel,1)) ^ 0.5, 0, self.Fuel) --fuel tanks are self healing
		Wire_TriggerOutput(self, "Leaking", (self.Leaking > 0) and 1 or 0)
	else
		self:NextThink( CurTime() + 1 )
	end

	--refuelling
	if self.Active and self.SupplyFuel and self.Fuel > 0 and self.Legal then
		self:NextThink(CurTime())
		for _,Tank in pairs(ACE.FuelTanks) do

			if self.FuelType == Tank.FuelType and not Tank.SupplyFuel and Tank.Legal then --don't refuel the refuellers, otherwise it'll be one big circlejerk
				local dist = self:GetPos():Distance(Tank:GetPos())

				if dist < ACE.RefillDistance and (Tank.Capacity - Tank.Fuel > 0.1) then
					local exchange = ((self.FuelType == "Electric") and 1 or 15) / 200
					exchange = math.min(exchange, self.Fuel, Tank.Capacity - Tank.Fuel)
					if self.FuelType == "Electric" then
						-- A charger follows the receiving pack's CC-CV acceptance and the supplying
						-- pack's own temperature limit.
						local Dt = math.max(CurTime() - self.LastThink, engine.TickInterval())
						exchange = math.min(exchange, Tank:ChargeAcceptW() * Dt / 3.6e6 * self:DischargeDerate())
						if exchange > 0 then
							self:DrawEnergy(exchange, Dt)
							Tank:StoreEnergy(exchange, Dt)
						end
					else
						self.Fuel = self.Fuel - exchange
						Tank.Fuel = Tank.Fuel + exchange
					end

					if Tank.FuelType == "Electric" then
						if not Tank.PlayedSound and CurTime() > (Tank.NextSoundTime or 0) then
							sound.Play("ambient/energy/newspark04.wav", Tank:GetPos(), 75, 100, 0.5)
							Tank.PlayedSound = true
							Tank.NextSoundTime = CurTime() + 1 -- Adjust the delay time (in seconds) as needed
						end
					else
						if CurTime() > (Tank.NextSoundTime or 0) then
							sound.Play("vehicles/jetski/jetski_no_gas_start.wav", Tank:GetPos(), 75, 120, 0.5)
							Tank.NextSoundTime = CurTime() + 1 -- Adjust the delay time (in seconds) as needed
						end
					end
				end
			end
		end
	end

	batteryThink(self, CurTime() - self.LastThink)

	self:UpdateFuelMass()

	Wire_TriggerOutput(self, "Fuel", self.Fuel)

	self.LastThink = CurTime()

	return true

end

function ENT:OnRemove()

	for _, Rad in ipairs(table.Copy(self.RadLink or {})) do
		self:Unlink(Rad)
	end

	for Key in pairs(self.Master) do
		if IsValid( self.Master[Key] ) then
			self.Master[Key]:Unlink( self )
		end
	end

	if #ACE.FuelTanks > 0 then
		for k,v in pairs(ACE.FuelTanks) do
			if v == self then
				table.remove(ACE.FuelTanks,k)
			end
		end
	end

end

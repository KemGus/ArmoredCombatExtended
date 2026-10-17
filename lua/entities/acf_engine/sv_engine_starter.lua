-- sv_engine_starter.lua
-- Starter motor, alternator and the accessory power drawn from the starter battery.
-- Included by init.lua; ENT is the acf_engine entity table.

local EngineTable = ACE.Weapons.Engines

--[[
	Starter setup, chosen in the engine menu and kept through duplication:
	  Size     starter size relative to the standard one, 0.5-3: torque and current scale with
	           it, and so does the built-in battery; the starter and battery's extra mass is
	           added to the engine's (StarterKgPerW of the starter's rated power per unit of
	           size: 2.2 kg/kW for a reduction-gear starter plus 12.5 kg/kW of lead-acid battery
	           at 0.5 Wh/W and 40 Wh/kg; estimated).
	Glow plugs always preheat for ACE.Mobility.Engine.DefaultPreheat; the Preheat setting older
	dupes carry is ignored.
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
-- @param Setup table|nil { Size = number (0.5-3), Cooling = "air"|"liquid"|nil (nil = as the
-- engine was built) }.
function ENT:SetStarterSetup( Setup )
	Setup = istable( Setup ) and Setup or {}
	local Size = math.Clamp( tonumber( Setup.Size ) or 1, 0.5, 3 )
	self.StarterSize = Size
	-- Air or liquid cooling in place of the engine's own (ACE.Mobility.EngineSpec reads it).
	local Cooling = ( Setup.Cooling == "air" or Setup.Cooling == "liquid" ) and Setup.Cooling or nil
	if Cooling ~= self.CoolingChoice then
		self.CoolingChoice = Cooling
		self.MobSpec, self.ThermalSpec = nil, nil
	end
	self.StarterSetup = { Size = Size, Cooling = Cooling }
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

	if Size == 1 and not Cooling then
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
-- @param Spec table Engine spec (gets StarterMul).
-- @param State table|nil Engine state (gets AirC, CoolantC and BlockC, °C).
function ENT:StarterModelInputs( Spec, State )
	Spec.StarterMul = self.StarterSize or 1
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
	AlternatorEff: 0.55 (estimated; claw-pole alternators are about 50 % efficient, Motor
	  magazine, May 2000, motor.com/magazine/pdfs/052000_04.pdf).
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

--- Draws power for an engine's accessories (coolant heaters) from its starter battery: the first
-- linked starter battery that is on, legal and charged, else the engine's own lead-acid battery.
-- @param Joules number Energy wanted [J].
-- @param Dt number Seconds the draw covers.
-- @return boolean Whether the battery could supply it.
function ENT:DrawAuxPower( Joules, Dt )
	if next( self.BatteryLink ) then
		for _, Bat in ipairs( self.BatteryLink ) do
			if IsValid( Bat ) and Bat.Fuel > 0 and Bat.Active and Bat.Legal and Bat.DrawEnergy then
				Bat:DrawEnergy( Joules / 3.6e6, Dt )
				return true
			end
		end
		return false
	end

	local Spec = self.MobSpec or ACE.Mobility.EngineSpec( self )
	local Pack = Spec and self:GetStarterPack( Spec )
	if not Pack then return false end
	local Battery = ACE.Mobility.Battery
	local _, _, EnergyJ = Battery.StarterPackSupply( Pack, ACE.AmbientTemp )
	if EnergyJ < Joules then return false end
	Battery.StarterPackDraw( Pack, Joules )
	-- The pack's wells settle in StarterApply, which runs only with a drivetrain linked.
	if not next( self.GearLink ) then Battery.StarterPackStep( Pack, Dt ) end
	return true
end

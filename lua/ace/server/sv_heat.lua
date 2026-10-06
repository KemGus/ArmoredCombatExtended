--Every funciton will return Heat. The only difference is how the Heat is created from
--VERY IMPORTANT: If ACF3 changed some of their functions/value names, then it would be required to check this code below too.

-----------------------------------[ HEAT PARAMETERS ]-----------------------------------


------Ambient Temperature. Engine Heat will not be lower than this. In Celcius.
	ACE.AmbientTemp = 20

------How much the distance affects Heat detection for IR seeker? Higher => Less Heat detected at distant targets - Def: 1
	ACE.HeatDistanceLoss = 0.5

--[[-------------------------------------------------------------------------------------
	Global heat settings. Each one is a server convar (the server-wide default, set from the
	console or server.cfg) that a map can override. Map overrides are set by admins from the
	ACE menu (Server settings > Heat) and saved to data/ace/heat/<map>.txt, the same way the
	default damage permission mode is saved per map in data/ace/permissions/.

	ace_heat_timescale is how many times faster than real time heat moves. Engine coolant, oil
	and metal run at exactly this; the older, game-tuned heat models (gun barrels, clutches, missile radars,
	idle radiators) keep their tuning at the default and speed up or slow down in proportion.
]]---------------------------------------------------------------------------------------
do
	local MapHeatDir = "ace/heat/"
	local DefaultTimeScale = 2

	-- Order here is the order the menu lists them in.
	ACE.HeatSettings = {
		{ Name = "ace_ambient_temp", Default = 20, Min = -50, Max = 55,
			Help = "Air temperature on the map in °C. Engines, radiators, batteries, clutches and guns start at it and cool towards it; IR seekers look for heat above it. 15 is the standard atmosphere." },
		{ Name = "ace_heat_timescale", Default = DefaultTimeScale, Min = 0.1, Max = 60,
			Help = "How many times faster than real time everything that heats up (engines, radiators, guns, clutches, radars) heats and cools. 1 is real time." },
		{ Name = "ace_engine_builtin_cooling", Default = 0.5, Min = 0, Max = 4,
			Help = "Cooling every engine has without a radiator entity, as a share of its full-power heat. 0 - none, 1 - enough for full power." },
		{ Name = "ace_engine_overheat_damage", Default = 1, Min = 0, Max = 1,
			Help = "1 - engines lose health when their block metal or oil overheats, 0 - they only lose power." },
	}

	local ByName = {}
	for _, Setting in ipairs(ACE.HeatSettings) do
		Setting.CVar = CreateConVar(Setting.Name, Setting.Default, FCVAR_ARCHIVE, Setting.Help, Setting.Min, Setting.Max)
		ByName[Setting.Name] = Setting
	end

	local MapOverrides = {}

	--- Returns the value of a global heat setting on this map: the map's saved value if it has
	-- one, otherwise the server convar.
	-- @param Name string Convar name, one of ACE.HeatSettings.
	-- @return number
	function ACE.GetHeatSetting(Name)
		local Value = MapOverrides[Name]
		if Value ~= nil then return Value end
		return ByName[Name].CVar:GetFloat()
	end

	--- Returns how much faster than its default tuning heat moves right now: 1 at the default
	-- ace_heat_timescale. For heat models tuned by hand rather than in real time.
	-- @return number
	function ACE.GetHeatRate()
		return ACE.ThermalTimeScale / DefaultTimeScale
	end

	-- ACE.ThermalTimeScale is read every think, so it holds the live value instead of a lookup.
	local function applyHeatSettings()
		ACE.ThermalTimeScale = ACE.GetHeatSetting("ace_heat_timescale")
		ACE.AmbientTemp = ACE.GetHeatSetting("ace_ambient_temp")
	end

	local function getMapHeatFile()
		local MapName = string.gsub(game.GetMap(), "[^%a%d-_]", "_")
		return MapHeatDir .. MapName .. ".txt"
	end

	local function saveMapHeatSettings()
		local Path = getMapHeatFile()
		if next(MapOverrides) == nil then
			if file.Exists(Path, "DATA") then file.Delete(Path) end
			return
		end

		file.CreateDir(MapHeatDir)
		file.Write(Path, util.TableToJSON(MapOverrides, true))
	end

	local function loadMapHeatSettings()
		MapOverrides = {}

		local Saved = util.JSONToTable(file.Read(getMapHeatFile(), "DATA") or "")
		if istable(Saved) then
			for Name, Value in pairs(Saved) do
				local Setting = ByName[Name]
				if Setting and isnumber(Value) then
					MapOverrides[Name] = math.Clamp(Value, Setting.Min, Setting.Max)
				end
			end
		end

		if next(MapOverrides) ~= nil then
			print("[ACE | INFO]- Loaded heat settings for " .. game.GetMap() .. " from data/" .. getMapHeatFile())
		end

		applyHeatSettings()
	end

	-- The convars stay live as the server default: a console change applies at once unless
	-- this map overrides that setting.
	for _, Setting in ipairs(ACE.HeatSettings) do
		cvars.AddChangeCallback(Setting.Name, applyHeatSettings, "ACE_HeatSettings")
	end

	loadMapHeatSettings()

	--- Sends the heat settings (value on this map, server default, whether the map overrides it)
	-- to a player's ACE menu.
	-- @param Ply Player
	function ACE.SendHeatSettings(Ply)
		local State = {}
		for I, Setting in ipairs(ACE.HeatSettings) do
			State[I] = {
				Name = Setting.Name,
				Value = ACE.GetHeatSetting(Setting.Name),
				ServerDefault = Setting.CVar:GetFloat(),
				MapSaved = MapOverrides[Setting.Name] ~= nil,
			}
		end

		net.Start("ACE_HeatSettings")
			net.WriteString(game.GetMap())
			net.WriteTable(State)
		net.Send(Ply)
	end

	local function resendHeatSettings()
		for _, Ply in ipairs(player.GetAll()) do
			if Ply:IsAdmin() then ACE.SendHeatSettings(Ply) end
		end
	end

	local function tellAdmins(Text)
		for _, Ply in ipairs(player.GetAll()) do
			if Ply:IsAdmin() then ACE.SendMsg(Ply, Color(255, 0, 0), Text) end
		end
	end

	net.Receive("ACE_HeatSettings", function(_, Ply)
		if not IsValid(Ply) or not Ply:IsAdmin() then return end
		ACE.SendHeatSettings(Ply)
	end)

	local function msgtoconsole(_, Msg) print(Msg) end

	concommand.Add("ACE_SetMapHeatSetting", function(Ply, _, Args)
		local ValidPly = IsValid(Ply)
		local PrintMsg = ValidPly and function(Hud, Msg) Ply:PrintMessage(Hud, Msg) end or msgtoconsole

		local Setting = ByName[string.lower(Args[1] or "")]
		local Value = tonumber(Args[2] or "")
		if not Setting or not Value then
			local Names = {}
			for _, S in ipairs(ACE.HeatSettings) do Names[#Names + 1] = S.Name end
			PrintMsg(HUD_PRINTCONSOLE,
				" - Set a heat setting for this map and save it. Usage: ACE_SetMapHeatSetting <setting> <value>" ..
				"\n	Settings: " .. table.concat(Names, " "))
			return false
		end

		if ValidPly and not Ply:IsAdmin() then
			PrintMsg(HUD_PRINTCONSOLE, "You can't use this because you are not an admin.")
			return false
		end

		Value = math.Clamp(Value, Setting.Min, Setting.Max)
		if MapOverrides[Setting.Name] == Value then return true end

		MapOverrides[Setting.Name] = Value
		saveMapHeatSettings()
		applyHeatSettings()

		PrintMsg(HUD_PRINTCONSOLE, "Command SUCCESSFUL: " .. Setting.Name .. " for " .. game.GetMap() .. " set to " .. Value)
		tellAdmins(Setting.Name .. " for " .. game.GetMap() .. " has been set to " .. Value .. "!")
		hook.Run("ACE_HeatSettingsChanged", Setting.Name, Value)

		resendHeatSettings()
		return true
	end)

	concommand.Add("ACE_ClearMapHeatSettings", function(Ply)
		local ValidPly = IsValid(Ply)
		local PrintMsg = ValidPly and function(Hud, Msg) Ply:PrintMessage(Hud, Msg) end or msgtoconsole

		if ValidPly and not Ply:IsAdmin() then
			PrintMsg(HUD_PRINTCONSOLE, "You can't use this because you are not an admin.")
			return false
		end

		MapOverrides = {}
		saveMapHeatSettings()
		applyHeatSettings()

		PrintMsg(HUD_PRINTCONSOLE, "Command SUCCESSFUL: " .. game.GetMap() .. " now uses the server's heat settings.")
		tellAdmins(game.GetMap() .. " now uses the server's heat settings.")
		hook.Run("ACE_HeatSettingsChanged")

		resendHeatSettings()
		return true
	end)
end

----------------------------------------------------------------------------------------/
----------------------------------------------------------------------------------------/
------------------------------------/FUNCTIONS BELOW------------------------------------/
----------------------------------------------------------------------------------------/

--[[-------------------------------------------------------------------------------------
	ACE_InfraredHeatFromProp( self, Target , dist )  --used mostly by infrared guidance

->  Input information:

	guidance - infrared guidance
	Target - Ent Target to track Heat
	dist - distance between the missile and the Target

]]---------------------------------------------------------------------------------------
function ACE.InfraredHeatFromProp( Target, dist )

	if not IsValid(Target) then print("[ACE | WARN]- Unable to track Heat. Target Entity not valid!") return 0 end
	if not dist then print("[ACE | WARN]- Unable to track Heat. dist not valid!") return end

	local entpos = Target:GetPos()
	local GroundTr = util.TraceHull( {
		start = entpos,
		endpos = entpos + Vector(0,0,-500) , --12 meters off ground
		collisiongroup  = COLLISION_GROUP_WORLD,
		mins = Vector( 0, 0, 0 ),
		maxs = Vector( 0, 0, 0 ),
		filter = function( ent ) if ( ent:GetClass() ~= "worldspawn" ) then return false end end
	}) --Hits anything in the world.

	local Speed = Target:GetVelocity():Length()
	local Heat = 0 --Heat will be added to this.
	Heat = Heat + (Speed / 35.2 ) --35.2 is 150 heat from 300 mph. 17.6 formula. 300mph / 2 mph per heat / 17.6 units/mph
	if not GroundTr.Hit then Heat = Heat + 150 end --Add 150C if the target is above the ground

	--A tank going 60mph will generate 30 extra heat plus engine heat
	--An aircraft going 200 mph will generate 100 heat plus 150
	--An aircraft going 300 mph will generate 150 heat plus 150

	return Heat
end

--[[-------------------------------------------------------------------------------------
	ACE_HeatFromGun( Gun, Heat, DeltaTime )  --used by Guns

->  Input information:

	Gun - The Gun Entity
	Heat - Current Heat of this gun
	DeltaTime - Delta time of this gun

]]---------------------------------------------------------------------------------------
function ACE.HeatFromGun( Gun , Heat, DeltaTime )

	local phys = Gun:GetPhysicsObject()
	local Mass = phys:GetMass()

--Decided to keep this code as note

	--local Energyloss = ((42500 * (-Heat))) * (1 + (Mass ^ 0.5) * 2/75) * DeltaTime * 0.03
	--Heat = math.max(Heat +(Energyloss/(Mass ^ 0.5) * 2/743.2),0)

	-- The global heat time scale speeds up heating and cooling alike (1 at the default scale).
	local Rate = ACE.GetHeatRate()

	--Creates Heat when firing. Just as note, IK last shot will not create Heat, not really relevant though
	if Gun.HeatFire then

		Heat = Heat + (((0.2 + Gun.BulletData.PropMass) ^ 1.05 * 150000) / (Mass ^ 0.5) / 743.2) * Rate
		Gun.HeatFire = false
	--Dissipates when not firing
	else

		local Diff = Heat - ACE.AmbientTemp
		Heat = Heat - Diff * math.min(DeltaTime * 0.1 * Rate, 1) --* 0.35

	end


	return Heat
end

--[[-------------------------------------------------------------------------------------
	ACE_HeatFromEngine( Engine , Radiator )  --used mostly by engines

->  Input information:

	Engine - The Engine Entity

]]---------------------------------------------------------------------------------------
function ACE.HeatFromEngine( Engine )

	--bullshiet code below, better using tables next time

	if Engine.NAE then return end
	if not Engine.FlyRPM then print("[ACE | WARN]- RPM not found in this ent. Heat will not create this time!")  Engine.NAE = true return end

	local ExTemp = 0			--> Defines how hot is the engine when it is active? DONT TOUCH
	local Temp = Engine.Heat	--> Current Temperature


	if Engine.Active then

		local RPM  = Engine.FlyRPM  --> RPM of said engin
		local Heat = 0			--> Heat from engine

		---Highly uneffective code below. Guaranteed to get cancer once you read this---

		--Diesel Engines are cooler tbh
		if Engine.FuelType == "Diesel" then
			--print("Diesel Engine")
			Heat = RPM / 90000
			ExTemp = 50

		--Petrol Engines are oof of heat
		elseif Engine.FuelType == "Petrol" then
			--print("Petrol Engine")
			Heat = RPM / 100000
			ExTemp = 60

		--Electric engines are more efficient, so they will make less heat than oil based engines
		elseif Engine.FuelType == "Electric" then
			--print("Electric Engine")
			Heat = RPM / 60000
			ExTemp = 5

		--completely messy code, i hate it. ACF3 will cover this better
		elseif Engine.FuelType == "Multifuel" then
			--print("MultiFuel Category")

			--Ground Gas turbines. This is going crazy at this point
			if Engine.EngineType == "Radial" then
				--print("Ground Gas Turbine")
				Heat = RPM / 100000
				ExTemp = 60

			--Aero-turbines. deal with that temperature. AGT 1500 is cooler though
			elseif Engine.EngineType == "Turbine" then
				--print("Aero Turbine")
				Heat = RPM / 30000
				ExTemp = 350

			--Any multifuel Engine that is not a gas turbine.
			--Since they can use both petrol or diesel that i´ll leave a average of them
			else
				--print("MutiFuel Engine")
				Heat = RPM / 100000
				ExTemp = 55

			end
		end

		Temp = Temp + Heat

	end

	local Diff = Temp - (ACE.AmbientTemp + ExTemp )
	Temp = Temp - Diff / 750

	return Temp

end

function ACE.HeatFromRadar(Radar, Delta)
	Delta = Delta * ACE.GetHeatRate() -- The global heat time scale (1 at the default scale).
	local CurHeat = Radar.Heat
	local AmbientTemp = ACE.AmbientTemp

	local HeatWhileActive = 7 -- Degrees increase per second while active
	local CoolingCoefficient = 0.1 -- Degrees decrease per second per degree above ambient

	local CoolingRate = (CurHeat - AmbientTemp) * CoolingCoefficient * Delta
	local HeatingRate = 0

	if Radar.Active then
		HeatingRate = HeatWhileActive * Delta
	end

	local NewHeat = CurHeat + HeatingRate - CoolingRate

	return NewHeat
end






--[[-------------------------------------------------------------------------------------
	ACE_HeatFromGearbox( Gearbox )  --used mostly by gearboxes. Not used atm

->  Input information:

	Gearbox - The Gearbox Entity

]]---------------------------------------------------------------------------------------
--NOTE: disabled until i compile more information about gearbox code. the code works though
function ACE.HeatFromGearbox( Gearbox , InputRPM )

	if not Gearbox:IsValid() then
		print("Missing Gearbox")
		Temp = 0
		return Temp
	end
	if not InputRPM then
		print("Missing RPM")
		Temp = 0
		return Temp
	end

	local ExTemp = 5

	local Temp = Gearbox.Heat

	Temp = Temp + math.abs(Gearbox.GearRatio) * InputRPM * 0.0005

	local Diff = Temp - (ACE.AmbientTemp + ExTemp)

	Temp = Temp - Diff / 100

	return Temp
end


--THIS CODE NEEDS A REWRITE, USELESS ATM BUT I WILL KEEP IT HERE
--[[
function ACE_HeatFromEngine( Engine , Radiator )  --radiator?!? woooo

	--print(Engine.EngineType)

	local RPM  = 0

	if Engine.Active then
		RPM = Engine.FlyRPM
	end


	--Diesel Engines are cooler tbh
	local Heat = 0.003 * RPM / 2500

	--Petrol Engines are oof of heat
	if Engine.EngineType == 'GenericPetrol' then
		Heat = 0.005 * RPM / 2500

	--Electric engines are more efficient, so they will make less heat than oil based engines
	elseif Engine.EngineType == 'Electric' then
		Heat = 0.00125 * RPM / 2500

	--Turbines are the hottest engine for now
	elseif Engine.EngineType == 'Turbine' then
		Heat = 0.0025 * RPM / 2500

	end
	Engine.Heat = Engine.Heat + Heat * RPM * 0.01

-----------------------------------------------------------------------------------------
	--These parts need rewrite, since we dont have radiators yet
	local Phys = Engine:GetPhysicsObject()

	local Area = Phys:GetVolume() * 2--3452 * 2 --+ 10000  --engine + radiator
	local Volume = Phys:GetVolume() * 2 --+ 7000 --engine + radiator

	local Mul = Area / Volume
-----------------------------------------------------------------------------------------

	local Diff = Engine.Heat - ACE.AmbientTemp

	Engine.Heat = Engine.Heat - Diff * Mul * 0.0025

	return Engine.Heat

end
]]--

--ACE.AmbientTemp

--The following functions require any entity involved to:
--Have a specific heat defined
--Have a thermal transfer coefficient defined
--Surface area

function ACE.GetThermalMass(Ent)

	local Mass = Ent.ThermalMass or -1

	if Mass == -1 then
		local Phys = Ent:GetPhysicsObject()
		if Phys:IsValid() then
			Mass = Phys:GetMass()
			Ent.ThermalMass = Mass
		else
			Mass = 1000
		end
	end

	return Mass
end

function ACE.AddThermalEnergy(Ent, KJ) --Used to add or remove thermal energy

	local SpecificHeat = Ent.ACESpecificHeat or 0.9211 --Uses specific heat of aluminum if unavailable
	local Mass = ACE.GetThermalMass(Ent)

	local DeltaTemp = KJ / SpecificHeat / Mass

	Ent.Heat = (Ent.Heat or ACE.AmbientTemp) + DeltaTemp
end

function ACE.EqualizeThermalEnergy(Ent1, Ent2) --Instantly balances the thermal energy of 2 objects. Useful for radiators or things one doesn't care for heat transfer rates with.

	local SpecificHeat1 = Ent1.ACESpecificHeat or 0.9211 --Uses specific heat of aluminum if unavailable
	local SpecificHeat2 = Ent2.ACESpecificHeat or 0.9211

	local TMass1 = ACE.GetThermalMass(Ent1)
	local TMass2 = ACE.GetThermalMass(Ent2)
	local TotalMass = TMass1 + TMass2

	local Ratio1 = TMass1 / TotalMass
	local Ratio2 = TMass2 / TotalMass

	local AvgSpecificHeat = SpecificHeat1 * Ratio1 + SpecificHeat2 * Ratio2

	--I LOVE KELVIN AND HAVING TO RECONVERT EVERYTHING 4 TIMES!!!!!!!! :)

	local ThermalEnergy1 = Ent1.Heat * SpecificHeat1 * TMass1
	local ThermalEnergy2 = Ent2.Heat * SpecificHeat2 * TMass2
	local TotalEnergy = ThermalEnergy1 + ThermalEnergy2

	local FinalTemp = TotalEnergy / AvgSpecificHeat / TotalMass

	Ent1.Heat = FinalTemp
	Ent2.Heat = FinalTemp
end

function ACE.AtmosphericHeatDissipation(Ent, CoolingMultiplier, DeltaTime) --Could be optimized by breaking into more functions. The rate doesn't need to be calculated every iteration riiiiiiiigt?
	local ThermalTransferCoefficient = Ent.AtmosphericCoefficient or 5 --5 W / M^2 * K, the thermal transfer coefficient of aluminum to air
	local SurfaceArea = Ent.ThermalSurfaceArea --Area in meters squared

	local TempDif = ACE.AmbientTemp - Ent.Heat

	local TransferRate = ThermalTransferCoefficient * SurfaceArea * TempDif * CoolingMultiplier

	--print(TransferRate * DeltaTime * ACE.ThermalTimeScale)
	--print(TransferRate * ACE.ThermalTimeScale / DeltaTime / ACE.ThermalTimeScale) --1 Second cooling
	ACE.AddThermalEnergy(Ent, TransferRate * DeltaTime * ACE.ThermalTimeScale)
end


--AtmosphericHeatExchange with speed--

--[[-------------------------------------------------------------------------------------
	Engine cooling. The physics is in ace/shared/mobility/thermal_model.lua: engine metal,
	coolant and sump oil as three thermal masses, a thermostat, a water pump, an oil cooler and
	radiators as cross-flow heat exchangers. Engine.Heat is the coolant temperature (the
	EngineHeat wire output, and what IR sensors see); Engine.BlockHeat is the
	engine metal and Engine.OilHeat the oil. The oil's temperature sets the engine's friction
	through Spec.FrictionMul. Radiators take their air-side conductance from ENT:Think in
	entities/ace_radiator.
]]---------------------------------------------------------------------------------------
do
	local Thermal = ACE.Mobility.Thermal
	-- Coolant temperature above which a motor's built-in radiator fan runs [°C] (estimated).
	local BuiltinFanOnTemp = 50

	--- Returns (building when needed) an engine's thermal spec.
	-- @param Engine acf_engine entity.
	-- @return table|nil Thermal spec, or nil when the engine has no mobility spec yet.
	function ACE.EngineThermalSpec(Engine)
		local Spec = Engine.MobSpec
		if not Spec and ACE.Mobility.EngineSpec then Spec = ACE.Mobility.EngineSpec(Engine) end
		if not Spec then return end

		local Builtin = ACE.GetHeatSetting("ace_engine_builtin_cooling")
		local TS = Engine.ThermalSpec
		if TS and TS.EngineSpec == Spec and Engine.ThermalBuiltin == Builtin then return TS end

		local Phys = Engine:GetPhysicsObject()
		local Mass = Engine.Weight or (IsValid(Phys) and Phys:GetMass()) or 100
		TS = Thermal.Build(Spec, Mass, Builtin)
		Engine.ThermalSpec, Engine.ThermalBuiltin = TS, Builtin
		return TS
	end

	--- Collects the heat one drivetrain solve put into an engine. Called from ENT:MobilityApply.
	-- @param Engine acf_engine entity.
	-- @param Desc table The engine's drivetrain description after the solve (HeatJ, FuelKg).
	function ACE.EngineThermalInput(Engine, Desc)
		local HeatJ = Desc.HeatJ or 0
		if HeatJ <= 0 then return end
		local TS = ACE.EngineThermalSpec(Engine)
		local State = Engine.MobState
		if TS and State then
			HeatJ = Thermal.CoolantHeat(TS, HeatJ, Desc.FuelKg or 0, State.Load, State.W)
		end
		Engine.ThermalHeatJ = (Engine.ThermalHeatJ or 0) + HeatJ
	end

	--- Advances an engine's cooling system by the time since its last call. Call every think.
	-- Sets Engine.Heat (coolant, °C), Engine.BlockHeat (metal, °C), Engine.OilHeat (oil, °C;
	-- nil for motors), Engine.ThermalDerate (torque multiplier), Engine.CoolantBoiling,
	-- Engine.OilOverheating and the engine spec's FrictionMul, updates linked radiators' Heat,
	-- and applies overheat damage.
	-- @param Engine acf_engine entity.
	function ACE.EngineThermalThink(Engine)
		local Now = CurTime()
		local Dt = math.Clamp(Now - (Engine.ThermalLast or Now), 0, 0.5)
		Engine.ThermalLast = Now
		if Dt <= 0 then return end

		local TS = ACE.EngineThermalSpec(Engine)
		if not TS then return end

		local Ambient = ACE.AmbientTemp
		local T = Engine.ThermalState
		if not T then
			T = Thermal.NewState(Engine.Heat or Ambient)
			Engine.ThermalState = T
		end

		local HeatW = (Engine.ThermalHeatJ or 0) / Dt
		Engine.ThermalHeatJ = 0

		-- Linked radiators: a radiator shared by several engines gives each an equal share.
		local Exchangers, ExtraC = Engine.ThermalExchangers or {}, 0
		Engine.ThermalExchangers = Exchangers
		for I = #Exchangers, 1, -1 do Exchangers[I] = nil end
		for _, Rad in pairs(Engine.RadLink or {}) do
			if IsValid(Rad) and Rad.ThermalUA then
				local Share = 1 / math.max(#Rad.Master + #(Rad.Batteries or {}), 1)
				Exchangers[#Exchangers + 1] = { UA = Rad.ThermalUA * Share, Cair = Rad.ThermalCair * Share, Rad = Rad }
				ExtraC = ExtraC + (Rad.Coolant or 0) * Thermal.CoolantCPerLitre * Share
			end
		end

		--[[
			A motor housing with a built-in radiator core (ENT:UpdateBuiltinCooler): ram air from
			the vehicle's speed plus a fan that runs off the battery while the motor is on and its
			coolant is warm.
		]]
		if Engine.BuiltinCoreFrontM2 then
			local Fan = Engine.Active and T.Tc > BuiltinFanOnTemp
			Engine.BuiltinFanOn = Fan
			local Parent = ACE.GetPhysicalParent and ACE.GetPhysicalParent(Engine) or Engine
			local SpeedMS = IsValid(Parent) and Parent:GetVelocity():Length() * 0.01905 or 0 -- units/s to m/s
			local Face = Thermal.FaceVelocity(Engine.BuiltinCoreDepthM, SpeedMS, Fan and 1 or 0)
			local UA, Cair = Thermal.RadiatorAir(Engine.BuiltinCoreFrontM2, Engine.BuiltinCoreDepthM, Face)
			Exchangers[#Exchangers + 1] = { UA = UA, Cair = Cair }
			local Tank = Engine.MobTank
			if Fan and IsValid(Tank) and Tank.DrawEnergy then
				Tank:DrawEnergy(Engine.BuiltinCoreFanW * Dt / 3.6e6, Dt)
			end
		end

		local Scale = ACE.ThermalTimeScale
		local MobState = Engine.MobState
		local W = MobState and MobState.W or 0
		-- Air-cooled fins also take ram air from the vehicle's or aircraft's speed.
		local AirSpeed = 0
		if TS.K.AirCooled then
			local Parent = ACE.GetPhysicalParent and ACE.GetPhysicalParent(Engine) or Engine
			AirSpeed = IsValid(Parent) and Parent:GetVelocity():Length() * 0.01905 or 0 -- units/s to m/s
		end
		Thermal.Step(T, TS, HeatW, W, Dt * Scale, {
			Ambient = Ambient, Running = Engine.Active, Exchangers = Exchangers, ExtraC = ExtraC,
			Load = MobState and MobState.Load or 0, AirSpeed = AirSpeed,
		})

		Engine.Heat = T.Tc
		Engine.BlockHeat = T.Tb
		Engine.OilHeat = T.To
		Engine.CoolantBoiling = T.Boiling
		Engine.OilOverheating = (TS.Co ~= nil or TS.K.AirCooled == true) and T.To ~= nil and T.To > TS.K.OilHot
		Engine.AirCooled = TS.K.AirCooled or nil
		Engine.FinAirSpeed = T.FinV
		Engine.ThermalDerate = Thermal.Derate(TS, T.Tb)
		Engine.ThermalHeatW = HeatW
		-- Cold oil is viscous: the engine's rubbing friction follows the oil temperature.
		TS.EngineSpec.FrictionMul = Thermal.FrictionMul(TS, T.To)

		for _, X in ipairs(Exchangers) do
			if X.Rad then
				X.Rad.Heat = T.Tc
				X.Rad.HeatRejected = (X.G or 0) * (T.Tc - Ambient)
			end
		end

		-- Overheating: past its damage temperature the engine wears itself out (scuffed liners,
		-- a warped head, bearings running on thinned oil), on the same accelerated clock as the heat.
		local Rate = Thermal.DamageRate(TS, T.Tb, T.To)
		Engine.ThermalDamageRate = Rate
		if Rate > 0 and ACE.GetHeatSetting("ace_engine_overheat_damage") ~= 0 and Engine.ACE and Engine.ACE.Health then
			Engine.ACE.Health = math.max(Engine.ACE.Health - Engine.ACE.MaxHealth * Rate * Dt * Scale, 0)
			if Engine.ACE.Health <= 0 and Engine.Active then Engine:TriggerInput("Active", 0) end
		end
	end

	--[[
		Engine debug readout for E2 (acfEngineDebug) and Starfall (acfEngineDebug): everything
		the drivetrain and cooling models know about one engine, as plain numbers and booleans.
		Units: RPM; torques in N·m (positive opposes rotation for Friction/Pumping, positive turns
		the crank forward for Gas/Starter/Crank); temperatures in °C; heat flows in kW; FuelRate
		in kg/s (electric motors: battery power in W); DamageRate in % of maximum health per real
		second; Thermostat, Load, Derate, Health and fractions 0..1.
	]]
	local RadToRPM = 30 / math.pi

	--- Collects an engine's full drivetrain and thermal state for debugging.
	-- @param Engine acf_engine entity.
	-- @return table Key-value table of numbers and booleans (see the comment above for units).
	function ACE.EngineDebugInfo(Engine)
		local St = Engine.MobState or {}
		local Spec = Engine.MobSpec
		local T = Engine.ThermalState or {}
		local TS = Engine.ThermalSpec
		local Model = ACE.Mobility.Engine
		local W = St.W or 0
		local Load = St.Load or 0

		local Fans = Engine.BuiltinFanOn and 1 or 0
		for _, Rad in pairs(Engine.RadLink or {}) do
			if IsValid(Rad) and Rad.FanRunning == 1 then Fans = Fans + 1 end
		end

		-- Damage only counts while ace_engine_overheat_damage is on.
		local DamageRate = (Engine.ThermalDamageRate or 0) * ACE.ThermalTimeScale * 100
		if ACE.GetHeatSetting("ace_engine_overheat_damage") == 0 then DamageRate = 0 end

		local Health = 1
		if Engine.ACE and Engine.ACE.Health and (Engine.ACE.MaxHealth or 0) > 0 then
			Health = Engine.ACE.Health / Engine.ACE.MaxHealth
		end

		return {
			RPM = W * RadToRPM,
			Load = Load,
			Active = Engine.Active == true,
			Running = St.Running == true,
			Stalled = Engine.Stalled == true or St.Stalled == true,
			Cranking = (St.Cranking or 0) > 0 and not St.Running,
			Torque = Engine.Torque or 0,
			CrankTorque = St.Torque or 0,
			FrictionTorque = Spec and Model.FrictionTorque(Spec, W, Load) or 0,
			PumpingTorque = Spec and Model.PumpingTorque(Spec, Load, W) or 0,
			GasTorque = St.GasTorque or 0,
			StarterTorque = St.StarterTorque or 0,
			-- Starting (engine_model.lua): glow plug preheat left [s], glow plug heat and the
			-- share of cycles firing (0-1), and the built-in starter battery's charge (0-1; -1
			-- with a battery linked to the starter or no starter).
			Preheat = St.StarterOn and St.PreheatLeft or 0,
			Glow = St.Glow or 0,
			Firing = St.Fire or 0,
			StarterCharge = (Engine.StarterPack and not next(Engine.BatteryLink or {}))
				and ACE.Mobility.Battery.StarterPackSOC(Engine.StarterPack) or -1,
			FrictionMul = Spec and Spec.FrictionMul or 1,
			CoolantTemp = Engine.Heat or ACE.AmbientTemp,
			OilTemp = Engine.OilHeat or 0,
			BlockTemp = Engine.BlockHeat or Engine.Heat or ACE.AmbientTemp,
			OilViscosity = TS and Engine.OilHeat and Thermal.OilViscosity(TS, Engine.OilHeat) or 0,
			Thermostat = T.Thermostat or 0,
			Boiling = Engine.CoolantBoiling == true,
			OilOverheating = Engine.OilOverheating == true,
			HeatInput = (Engine.ThermalHeatW or 0) / 1000,
			OilHeat = (T.OilHeat or 0) / 1000,
			OilToCoolant = (T.OilToCoolant or 0) / 1000,
			RadiatorHeat = (T.Qrad or 0) / 1000,
			FansRunning = Fans,
			Derate = Engine.ThermalDerate or 1,
			DamageRate = DamageRate,
			Health = Health,
			FuelRate = St.FuelRate or 0,
		}
	end
end

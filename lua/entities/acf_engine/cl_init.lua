-- cl_init.lua

include("shared.lua")

CreateClientConVar("ace_engine_info_while_seated", 0, true, false)

-- copied from base_wire_entity: DoNormalDraw's notip arg isn't accessible from ENT:Draw defined there.
function ENT:Draw()

	local lply = LocalPlayer()
	local hideBubble = not GetConVar("ace_engine_info_while_seated"):GetBool() and IsValid(lply) and lply:InVehicle()

	self.BaseClass.DoNormalDraw(self, false, hideBubble)
	Wire_Render(self)

	if self.GetBeamLength and (not self.GetShowBeam or self:GetShowBeam()) then
		-- Every SENT that has GetBeamLength should draw a tracer. Some of them have the GetShowBeam boolean
		Wire_DrawTracerBeam( self, 1, self.GetBeamHighlight and self:GetBeamHighlight() or false )
	end

end

do -- Torque / power graph

	local KwToHp       = 1.34
	local TorqueColor  = Color(200, 50, 50)
	local PowerColor   = Color(40, 90, 210)
	local IdleColor    = Color(120, 120, 120)
	local RedlineColor = Color(230, 0, 0)
	local BandColor    = Color(255, 200, 0, 45)

	-- Returns a function RPM -> torque in Nm for the given engine data.
	-- This is the only place that knows the torque model; swap it when the model changes.
	local function MakeTorqueSampler( Data )

		local Mobility = ACE.Mobility
		if Mobility and Mobility.EngineCurveSample and Data.def then
			return function( RPM ) return Mobility.EngineCurveSample( Data.def, RPM ) or 0 end
		end

		local Curve = Data.curve or ACE.GenericTorqueCurves.GenericPetrol

		return function( RPM )
			local Perc = math.Remap( RPM, Data.idle, Data.limit, 0, 1 )
			return Data.torque * ACE.CalcCurve( Curve, Perc )
		end
	end

	local function PowerKW( Torque, RPM )
		return Torque * RPM / 9548.8
	end

	-- Peak torque, peak power and the powerband (within 10% of peak power), measured on the sampler.
	local function Analyse( Data, Sample )
		local Steps = 200
		local From = Data.from or Data.idle
		local Result = { peakTq = 0, peakTqRPM = From, peakKw = 0, peakKwRPM = From }
		local Powers = {}

		for I = 0, Steps do
			local RPM = From + ( Data.limit - From ) * I / Steps
			local Tq = Sample( RPM )
			local Kw = PowerKW( Tq, RPM )

			Powers[I] = Kw

			if Tq > Result.peakTq then
				Result.peakTq, Result.peakTqRPM = Tq, RPM
			end

			if Kw > Result.peakKw then
				Result.peakKw, Result.peakKwRPM = Kw, RPM
			end
		end

		for I = 0, Steps do
			if Powers[I] >= Result.peakKw * 0.9 then
				local RPM = From + ( Data.limit - From ) * I / Steps

				Result.bandMin = Result.bandMin or RPM
				Result.bandMax = RPM
			end
		end

		return Result
	end

	--- Fills an ACE_Graph with an engine's torque and power curves.
	-- @param Graph Panel The ACE_Graph to draw into; it is cleared first.
	-- @param Data table { curve = table, torque = number (Nm), idle = number, limit = number, fuel = string, def = table (optional engine definition), from = number (optional first RPM plotted, default idle) }.
	function ACE.PlotEngineCurves( Graph, Data )

		if not IsValid( Graph ) or not Data or not Data.idle or not Data.limit or Data.limit <= Data.idle then return end

		local Sample = MakeTorqueSampler( Data )
		local Info = Analyse( Data, Sample )
		local PeakHp = Info.peakKw * KwToHp

		Graph:Clear()
		Graph:SetXRange( 0, math.ceil( Data.limit * 1.05 / 100 ) * 100 )
		Graph:SetYRange( 0, math.max( Info.peakTq, PeakHp, 1 ) * 1.15 )
		Graph:SetXLabel( "RPM" )
		Graph:SetYLabel( "Nm / hp" )
		Graph:SetXFormat( function( RPM ) return math.Round( RPM ) .. " RPM" end )

		if Info.bandMin and Info.bandMax then
			Graph:PlotBand( "Powerband", Info.bandMin, Info.bandMax, BandColor )
		end

		Graph:PlotLimitLine( "Idle", true, Data.idle, IdleColor )
		Graph:PlotLimitLine( "Redline", true, Data.limit, RedlineColor )

		local From = Data.from or Data.idle
		Graph:PlotLimitFunction( "Torque", From, Data.limit, TorqueColor, Sample, function( Tq )
			return math.Round( Tq ) .. " Nm / " .. math.Round( Tq * 0.73 ) .. " ft-lb"
		end )

		Graph:PlotLimitFunction( "Power", From, Data.limit, PowerColor, function( RPM )
			return PowerKW( Sample( RPM ), RPM ) * KwToHp
		end, function( Hp )
			return math.Round( Hp ) .. " hp / " .. math.Round( Hp / KwToHp ) .. " kW"
		end )

		Graph:PlotPoint( math.Round( Info.peakTq ) .. " Nm", Info.peakTqRPM, Info.peakTq, TorqueColor )
		Graph:PlotPoint( math.Round( PeakHp ) .. " hp / " .. math.Round( Info.peakKw ) .. " kW", Info.peakKwRPM, PeakHp, PowerColor )
	end
end

function ACE.EngineGUI_Update( Table )

	acemenupanel:CPanelText("Name", Table.name, "DermaDefaultBold")

	if not acemenupanel.CData.DisplayModel then

		acemenupanel.CData.DisplayModel = vgui.Create( "DModelPanel", acemenupanel.CustomDisplay )
		acemenupanel.CData.DisplayModel:SetModel( Table.model )
		acemenupanel.CData.DisplayModel:SetCamPos( Vector( 250, 500, 250 ) )
		acemenupanel.CData.DisplayModel:SetLookAt( Vector( 0, 0, 0 ) )
		acemenupanel.CData.DisplayModel:SetFOV( 20 )
		acemenupanel.CData.DisplayModel:SetSize(acemenupanel:GetWide(),acemenupanel:GetWide())
		acemenupanel.CData.DisplayModel.LayoutEntity = function() end
		acemenupanel.CustomDisplay:AddItem( acemenupanel.CData.DisplayModel )

	end

	acemenupanel.CData.DisplayModel:SetModel( Table.model )

	acemenupanel:CPanelText("Desc", Table.desc)

	local peakkw = Table.peakpower
	local peakkwrpm = Table.peakpowerrpm
	local peaktqrpm = Table.peaktqrpm
	local pbmin = Table.peakminrpm
	local pbmax = Table.peakmaxrpm

	acemenupanel:CPanelText("Power", "\nPeak Power: " .. math.floor(peakkw) .. " kW / " .. math.Round(peakkw * 1.34) .. " HP @ " .. math.Round(peakkwrpm) .. " RPM")
	acemenupanel:CPanelText("Torque", "Peak Torque: " .. Table.torque .. " n/m  / " .. math.Round(Table.torque * 0.73) .. " ft-lb @ " .. math.Round(peaktqrpm) .. " RPM")

	acemenupanel:CPanelText("RPM", "Idle: " .. Table.idlerpm .. " RPM\nPowerband : " .. (math.Round(pbmin / 10) * 10) .. "-" .. (math.Round(pbmax / 10) * 10) .. " RPM\nRedline : " .. Table.limitrpm .. " RPM")
	acemenupanel:CPanelText("Weight", "Weight: " .. Table.weight .. " kg")

	if not IsValid( acemenupanel.CData.EngineGraph ) then
		acemenupanel.CData.EngineGraph = vgui.Create( "ACE_Graph" )
		acemenupanel.CData.EngineGraph:SetTall( math.max( acemenupanel:GetWide() * 0.6, 160 ) )
		acemenupanel.CustomDisplay:AddItem( acemenupanel.CData.EngineGraph )
	end

	ACE.PlotEngineCurves( acemenupanel.CData.EngineGraph, {
		curve  = ACE.GetEngineTorqueCurve(Table),
		torque = Table.torque,
		idle   = Table.idlerpm,
		limit  = Table.limitrpm,
		fuel   = Table.fuel,
		def    = Table,
		-- A free power turbine's output shaft works down to stall, where its torque peaks.
		from   = ( Table.enginetype == "Turbine" or Table.enginetype == "GroundTurbine" ) and 0 or nil,
	} )


	acemenupanel:CPanelText("FuelType", "\nFuel Type: " .. Table.fuel)

	local EngineModel = ACE.Mobility and ACE.Mobility.Engine
	local Spec = EngineModel and EngineModel.Build( Table, ACE.GetEngineTorqueCurve( Table ) )

	if Table.fuel == "Electric" and Spec then
		-- Battery power at peak power: shaft power plus the motor and inverter losses there.
		local Torque = Spec.RatedPower / Spec.RatedW
		local Kw = ( Spec.RatedPower + EngineModel.MotorLoss( Spec, Torque ) ) / 1000
		acemenupanel:CPanelText("FuelCons", "Battery draw at peak power: " .. math.Round(Kw, 1) .. " kW / " .. math.Round(Kw / 60, 2) .. " kWh/min\nRegenerates on a negative throttle; the Reverse input drives it backwards")
	elseif Spec and Spec.Kind == "turbine" then
		-- A turbine burns fuel for its gas generator whatever the output shaft does.
		local Full = EngineModel.TurbineFuelRate( Spec, 1 ) * 60
		local Idle = EngineModel.TurbineFuelRate( Spec, Spec.K.IdleSpool ) * 60
		for _, Fuel in ipairs( { "Petrol", "Diesel" } ) do
			local Density = ACE.FuelDensity[Fuel]
			acemenupanel:CPanelText("FuelCons" .. Fuel, Fuel .. " use: " .. math.Round(Full / Density, 2) .. " liters/min at full power, " .. math.Round(Idle / Density, 2) .. " at idle")
		end
	elseif Table.fuel == "Multifuel" then
		local engineEfficiency = ACE.Efficiency[Table.enginetype] * (1 + (peakkw * 1.34 / 2000) * 0.1)
		local petrolcons = ACE.FuelRate * engineEfficiency * peakkw / (60 * ACE.FuelDensity.Petrol) * ACE.PerFuelRelativeEfficiency.Petrol
		local dieselcons = ACE.FuelRate * engineEfficiency * peakkw / (60 * ACE.FuelDensity.Diesel) * ACE.PerFuelRelativeEfficiency.Diesel
		local HeatPerLiterUsedPetrol = engineEfficiency * ACE.FuelPowerDensity["Petrol"] * 0.4 * 1000 / 60 / ACE.FuelRate --Heat generated per liter burned. Assume 60% heat lost to the air as exhaust.
		local HeatPerLiterUsedDiesel = engineEfficiency * ACE.FuelPowerDensity["Diesel"] * 0.4 * 1000 / 60 / ACE.FuelRate --Heat generated per liter burned. Assume 60% heat lost to the air as exhaust.
		acemenupanel:CPanelText("FuelConsP", "Petrol Use at " .. math.Round(peakkwrpm) .. " rpm: " .. math.Round(petrolcons,2) .. " liters/min / " .. math.Round(0.264 * petrolcons,2) .. " gallons/min")
		acemenupanel:CPanelText("EngHeatP", "Producing " .. math.Round(petrolcons * HeatPerLiterUsedPetrol,2) .. "kJ / Second of heat")
		acemenupanel:CPanelText("FuelConsD", "Diesel Use at " .. math.Round(peakkwrpm) .. " rpm: " .. math.Round(dieselcons,2) .. " liters/min / " .. math.Round(0.264 * dieselcons,2) .. " gallons/min")
		acemenupanel:CPanelText("EngHeatD", "Producing " .. math.Round(dieselcons * HeatPerLiterUsedDiesel,2) .. "kJ / Second of heat")
	else
		local engineEfficiency = ACE.Efficiency[Table.enginetype] * (1 + (peakkw * 1.34 / 2000) * 0.1)
		local fuelcons = ACE.FuelRate * engineEfficiency * peakkw / (60 * ACE.FuelDensity[Table.fuel])  * ACE.PerFuelRelativeEfficiency[Table.fuel]
		acemenupanel:CPanelText("FuelCons", Table.fuel .. " Use at " .. math.Round(peakkwrpm) .. " rpm: " .. math.Round(fuelcons,2) .. " liters/min / " .. math.Round(0.264 * fuelcons,2) .. " gallons/min")
		local HeatPerLiterUsed = engineEfficiency * ACE.FuelPowerDensity[Table.fuel] * 0.4 * 1000 / 60 / ACE.FuelRate --Heat generated per liter burned. Assume 60% heat lost to the air as exhaust.
		acemenupanel:CPanelText("EngHeat", "Producing " .. math.Round(fuelcons * HeatPerLiterUsed,2) .. "kJ / Second of heat")
	end

	ACE.EngineModelGUI( Table, Spec )

	acemenupanel.CustomDisplay:PerformLayout()

end

do -- What the drivetrain model does with an engine, and its starter setup

	local SizeVar    = "acemenu_eng_startersize"
	local PreheatVar = "acemenu_eng_preheat"
	local CoolingVar = "acemenu_eng_cooling"

	-- Plain-language summary of each kind of engine.
	local KindText = {
		si = "Spark ignition. Fires once the starter turns it past 60-100 rpm and the first fuel has reached the cylinders, slower when cold. Throttled, so it brakes hard off the throttle.",
		diesel = "Compression ignition: the squeezed air itself must get hot enough to light the fuel. Cold, it needs glow plug preheat and a fast crank; warm, it starts at once. Weak engine braking; the governor gives full fuel to hold idle, so it crawls in gear.",
		rotary = "Wankel rotary. Starts like a petrol engine and brakes like one.",
		turbine = "Gas turbine with a free power turbine: lights up without a starter battery and cannot stall; the output can sit at 0 rpm under load. The gas generator burns fuel whatever the output does.",
		electric = "Electric motor: full torque from 0 rpm, no starter and no stall. Reverse input drives it backwards; a negative throttle regenerates into the battery.",
	}

	local function Text( Name, Value, Tooltip, Font )
		acemenupanel:CPanelText( Name, Value, Font )
		local Label = acemenupanel.CData[Name .. "_text"]
		if IsValid( Label ) then
			Label:SetTooltip( Tooltip or false )
			Label:SetMouseInputEnabled( Tooltip ~= nil )
		end
	end

	local function Seconds( T, Preheat )
		if not T then return "no start" end
		local S = string.format( "%.1f s", T )
		if Preheat and Preheat > 0 then S = S .. string.format( " (%.0f s preheat)", Preheat ) end
		return S
	end

	-- Start times at three temperatures with the menu's starter setup.
	local function StartLine( Table, Spec )
		local Model = ACE.Mobility.Engine
		local Thermal = ACE.Mobility.Thermal
		Spec.StarterMul = math.Clamp( GetConVar( SizeVar ):GetFloat(), 0.5, 3 )
		Spec.PreheatMax = math.Clamp( GetConVar( PreheatVar ):GetFloat(), 0, 60 )
		local TS = Thermal and Thermal.Build( Spec, Table.weight or 100 )
		local function Try( C )
			local Mul = ( TS and C < 80 ) and Thermal.FrictionMul( TS, C ) or nil
			return Model.SimulateStart( Spec, { AirC = math.min( C, 20 ), BlockC = C, CoolantC = C, FrictionMul = Mul, MaxTime = 15 } )
		end
		local Warm, WarmP = Try( 90 )
		local Mild, MildP = Try( 20 )
		local Cold, ColdP = Try( -20 )
		return "Start: warm " .. Seconds( Warm, WarmP ) .. ", 20 °C " .. Seconds( Mild, MildP ) .. ", -20 °C " .. Seconds( Cold, ColdP )
	end

	-- The starter and its built-in battery at the menu's starter size (StartLine sets it).
	local function StarterLine( Spec )
		local Stall, StallW = ACE.Mobility.Engine.StarterRating( Spec )
		local Battery = ACE.Mobility.Battery
		local Wh = Battery and StallW / 4 * Battery.LeadWhPerW or 0
		return string.format( "Starter: %.1f kW, %.0f Nm at stall, on a built-in %.1f kWh lead-acid battery the alternator recharges.", StallW / 4000, Stall, Wh / 1000 )
	end

	local function Slider( Key, Label, Min, Max, Decimals, ConVar, Tooltip )
		local CData = acemenupanel.CData
		if IsValid( CData[Key] ) then return end
		local S = vgui.Create( "DNumSlider" )
		S:SetText( Label )
		S:SetDark( true )
		S:SetMinMax( Min, Max )
		S:SetDecimals( Decimals )
		S:SetConVar( ConVar )
		S:SetTooltip( Tooltip )
		CData[Key] = S
		acemenupanel.CustomDisplay:AddItem( S )
	end

	--- Adds what the drivetrain model does with an engine to the engine menu: a plain-language
	-- summary, cylinders and compression, the starter and expected start times, cooling, and the
	-- starter setup the menu tool applies to the engines it spawns.
	-- @param Table table Engine definition.
	-- @param Spec table|nil Engine spec (ACE.Mobility.Engine.Build).
	function ACE.EngineModelGUI( Table, Spec )
		if not Spec then return end

		Text( "MobHeader", "\nHow it is modelled", nil, "DermaDefaultBold" )
		Text( "MobKind", KindText[Spec.Kind] or "" )

		local Piston = Spec.Kind ~= "electric" and Spec.Kind ~= "turbine"
		if not Piston then return end

		local Build = string.format( "%.1f L, %d cylinder%s", Spec.DispL, Spec.Cylinders, Spec.Cylinders == 1 and "" or "s" )
		if Spec.Gas then
			Build = Build .. string.format( ", %.0f:1 compression", ( Spec.Gas.Vcyl + Spec.Gas.Vc ) / Spec.Gas.Vc )
		end
		Build = Build .. string.format( ", flywheel %.2f kg·m²", Spec.Inertia )
		Text( "MobBuild", Build, "With the engine off its cylinders act as gas springs: the trapped air holds a parked car in gear, creeps as it leaks past the rings, and rocks a stopping engine back." )

		-- The menu's cooling choice overrides the definition's (ENT:SetStarterSetup).
		local Choice = GetConVar( CoolingVar ):GetString()
		local Air = Choice == "air" or Choice ~= "liquid" and ACE.Mobility.Engine.IsAirCooled( Table )
		if Air then
			Text( "MobCooling", "Air-cooled: finned cylinders cooled by the engine's own fan or propeller wash plus the air it moves through. EngineHeat output = oil °C; Block Temp = cylinder heads, limit 260 °C.",
				"No coolant to boil, but the heads run hot: about 200 °C climbing at full power is normal for a light aircraft engine. Standing at full power, or a powerful engine with small cylinders, overheats. Linked radiators work as oil coolers." )
		else
			Text( "MobCooling", "EngineHeat output = coolant °C (thermostat 82, boils at 120). Cold oil adds friction: about 2x at 20 °C, up to 4x. Oil past 150 °C wears the engine.",
				"Coolant, oil and engine metal are tracked separately (Oil Temp and Block Temp outputs). The engine warms up slowly at idle; link radiators to keep it cool under load." )
		end

		-- StartLine first: it applies the menu's starter size to Spec.
		local Start = StartLine( Table, Spec )
		Text( "MobStarter", StarterLine( Spec ),
			"Cranking runs the battery down; a flat battery recovers some charge after a few minutes' rest. Link an ACE battery to the engine (menu tool, right click both) to start from it instead. The starter cuts out after about 30 s of cranking and cranks again once it cools." )
		Text( "MobStart", Start,
			"Engine alone in neutral, from the request (Active = 1) to running. Cold oil and a cold charge slow it; a bigger starter and glow plug preheat speed it up." )

		-- Follow the starter setup sliders.
		local Label = acemenupanel.CData["MobStart_text"]
		local StarterLabel = acemenupanel.CData["MobStarter_text"]
		if IsValid( Label ) then
			local Key, NextCheck = nil, 0
			Label.Think = function( Self )
				local Now = RealTime()
				if Now < NextCheck then return end
				NextCheck = Now + 0.3
				local New = GetConVar( SizeVar ):GetString() .. "|" .. GetConVar( PreheatVar ):GetString()
				if Key == nil then Key = New return end
				if New == Key then return end
				Key = New
				Self:SetText( StartLine( Table, Spec ) )
				if IsValid( StarterLabel ) then StarterLabel:SetText( StarterLine( Spec ) ) end
			end
		end

		Text( "MobSetup", "Engine setup:", nil, "DermaDefaultBold" )
		local CData = acemenupanel.CData
		if not IsValid( CData.CoolingChoice ) then
			local Box = vgui.Create( "DComboBox" )
			Box:SetTall( 20 )
			Box:SetTooltip( "Air-cooled engines have finned cylinders and no coolant; liquid-cooled ones have a water jacket and need radiators under load. Weight and power stay the same (estimated). Applies to engines this tool spawns or updates." )
			Box:AddChoice( "Cooling: as built (" .. ( ACE.Mobility.Engine.IsAirCooled( Table ) and "air" or "liquid" ) .. ")", "", Choice == "" )
			Box:AddChoice( "Cooling: air", "air", Choice == "air" )
			Box:AddChoice( "Cooling: liquid", "liquid", Choice == "liquid" )
			Box.OnSelect = function( _, _, _, Data )
				RunConsoleCommand( CoolingVar, Data )
				local Label = acemenupanel.CData["MobCooling_text"]
				if IsValid( Label ) then
					local Now = Data == "air" or Data ~= "liquid" and ACE.Mobility.Engine.IsAirCooled( Table )
					Label:SetText( Now and "Air-cooled: finned cylinders cooled by the engine's own fan or propeller wash plus the air it moves through. EngineHeat output = oil °C; Block Temp = cylinder heads, limit 260 °C." or "EngineHeat output = coolant °C (thermostat 82, boils at 120). Cold oil adds friction: about 2x at 20 °C, up to 4x. Oil past 150 °C wears the engine." )
				end
			end
			CData.CoolingChoice = Box
			acemenupanel.CustomDisplay:AddItem( Box )
		end
		Slider( "StarterSize", "Starter size (x)", 0.5, 3, 2, SizeVar,
			"Torque and current of the starter and its battery against the standard size. Bigger cranks faster and starts cold engines, but adds weight." )
		if Spec.Kind == "diesel" then
			Slider( "StarterPreheat", "Glow plug preheat at -20 °C (s)", 0, 30, 0, PreheatVar,
				"How long the glow plugs heat before cranking on a frozen engine. Shorter as the coolant warms, none above 60 °C. 0 = no glow plugs." )
		end
	end
end

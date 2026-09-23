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

		local Curve = table.Copy( Data.curve or ACE.GenericTorqueCurves.GenericPetrol )
		local Fuel = Data.fuel == "Multifuel" and "Diesel" or Data.fuel
		local FuelCurve = ACE.PerFuelTorqueCurveMul[Fuel or "Petrol"]

		if FuelCurve then
			ACE.ApplyEngineFuelModifierToCurve( Curve, FuelCurve )
		end

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
		local Result = { peakTq = 0, peakTqRPM = Data.idle, peakKw = 0, peakKwRPM = Data.idle }
		local Powers = {}

		for I = 0, Steps do
			local RPM = Data.idle + ( Data.limit - Data.idle ) * I / Steps
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
				local RPM = Data.idle + ( Data.limit - Data.idle ) * I / Steps

				Result.bandMin = Result.bandMin or RPM
				Result.bandMax = RPM
			end
		end

		return Result
	end

	--- Fills an ACE_Graph with an engine's torque and power curves.
	-- @param Graph Panel The ACE_Graph to draw into; it is cleared first.
	-- @param Data table { curve = table, torque = number (Nm), idle = number, limit = number, fuel = string, def = table (optional engine definition) }.
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

		Graph:PlotLimitFunction( "Torque", Data.idle, Data.limit, TorqueColor, Sample, function( Tq )
			return math.Round( Tq ) .. " Nm / " .. math.Round( Tq * 0.73 ) .. " ft-lb"
		end )

		Graph:PlotLimitFunction( "Power", Data.idle, Data.limit, PowerColor, function( RPM )
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
		curve  = Table.torquecurve or ACE.GenericTorqueCurves[Table.enginetype],
		torque = Table.torque,
		idle   = Table.idlerpm,
		limit  = Table.limitrpm,
		fuel   = Table.fuel,
		def    = Table,
	} )


	acemenupanel:CPanelText("FuelType", "\nFuel Type: " .. Table.fuel)

	if Table.fuel == "Electric" then
		local engineEfficiency = ACE.Efficiency[Table.enginetype] * (1 + (peakkw * 1.34/2000)*0.1)
		local cons = ACE.ElecRate * peakkw / engineEfficiency
		acemenupanel:CPanelText("FuelCons", "Peak energy use: " .. math.Round(cons,1) .. " kW / " .. math.Round(0.06 * cons,1) .. " MJ/min")
	elseif Table.fuel == "Multifuel" then
		local engineEfficiency = ACE.Efficiency[Table.enginetype] * (1 + (peakkw * 1.34/2000)*0.1)
		local petrolcons = ACE.FuelRate * engineEfficiency * peakkw / (60 * ACE.FuelDensity.Petrol) * ACE.PerFuelRelativeEfficiency.Petrol
		local dieselcons = ACE.FuelRate * engineEfficiency * peakkw / (60 * ACE.FuelDensity.Diesel) * ACE.PerFuelRelativeEfficiency.Diesel
		local HeatPerLiterUsedPetrol = engineEfficiency * ACE.FuelPowerDensity["Petrol"] * 0.4 * 1000 / 60 / ACE.FuelRate --Heat generated per liter burned. Assume 60% heat lost to the air as exhaust.
		local HeatPerLiterUsedDiesel = engineEfficiency * ACE.FuelPowerDensity["Diesel"] * 0.4 * 1000 / 60 / ACE.FuelRate --Heat generated per liter burned. Assume 60% heat lost to the air as exhaust.
		acemenupanel:CPanelText("FuelConsP", "Petrol Use at " .. math.Round(peakkwrpm) .. " rpm: " .. math.Round(petrolcons,2) .. " liters/min / " .. math.Round(0.264 * petrolcons,2) .. " gallons/min")
		acemenupanel:CPanelText("EngHeatP", "Producing ".. math.Round(petrolcons * HeatPerLiterUsedPetrol,2) .. "kJ / Second of heat")
		acemenupanel:CPanelText("FuelConsD", "Diesel Use at " .. math.Round(peakkwrpm) .. " rpm: " .. math.Round(dieselcons,2) .. " liters/min / " .. math.Round(0.264 * dieselcons,2) .. " gallons/min")
		acemenupanel:CPanelText("EngHeatD", "Producing ".. math.Round(dieselcons * HeatPerLiterUsedDiesel,2) .. "kJ / Second of heat")
	else
		local engineEfficiency = ACE.Efficiency[Table.enginetype] * (1 + (peakkw * 1.34/2000)*0.1)
		local fuelcons = ACE.FuelRate * engineEfficiency * peakkw / (60 * ACE.FuelDensity[Table.fuel])  * ACE.PerFuelRelativeEfficiency[Table.fuel]
		acemenupanel:CPanelText("FuelCons", Table.fuel .. " Use at " .. math.Round(peakkwrpm) .. " rpm: " .. math.Round(fuelcons,2) .. " liters/min / " .. math.Round(0.264 * fuelcons,2) .. " gallons/min")
		local HeatPerLiterUsed = engineEfficiency * ACE.FuelPowerDensity[Table.fuel] * 0.4 * 1000 / 60 / ACE.FuelRate --Heat generated per liter burned. Assume 60% heat lost to the air as exhaust.
		acemenupanel:CPanelText("EngHeat", "Producing ".. math.Round(fuelcons * HeatPerLiterUsed,2) .. "kJ / Second of heat")
	end

	acemenupanel.CustomDisplay:PerformLayout()

end

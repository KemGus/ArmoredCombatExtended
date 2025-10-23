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

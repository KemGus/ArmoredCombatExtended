
include("shared.lua")

CreateClientConVar("ace_gearbox_info_while_seated", 0, true, false)

-- copied from base_wire_entity: DoNormalDraw's notip arg isn't accessible from ENT:Draw defined there.
function ENT:Draw()

	local lply = LocalPlayer()
	local hideBubble = not GetConVar("ace_gearbox_info_while_seated"):GetBool() and IsValid(lply) and lply:InVehicle()

	self.BaseClass.DoNormalDraw(self, false, hideBubble)
	Wire_Render(self)

	if self.GetBeamLength and (not self.GetShowBeam or self:GetShowBeam()) then
		-- Every SENT that has GetBeamLength should draw a tracer. Some of them have the GetShowBeam boolean
		Wire_DrawTracerBeam( self, 1, self.GetBeamHighlight and self:GetBeamHighlight() or false )
	end

end

CreateClientConVar("ace_gearchart_wheel_diameter", 30, true, false, "Wheel diameter in inches used by the gearbox menu's gear chart.")
CreateClientConVar("ace_gearchart_rpm", 5000, true, false, "Engine RPM used as the shift point by the gearbox menu's gear chart.")

local CreateGearChart

do -- Gear chart (vehicle speed vs engine RPM)

	-- ACE gear values are currently output/input speed multipliers (0..1), and so is the final drive.
	-- Set this to true once gears are stored as real reduction ratios (>1 = reduction, real = 1 / old).
	local GEARS_ARE_REDUCTION_RATIOS = false

	-- Wheel RPM per engine RPM for one gear value and the final drive.
	local function ratioOf( GearValue, Final )
		GearValue = math.abs( tonumber( GearValue ) or 0 )
		Final = math.abs( tonumber( Final ) or 0 )

		if GEARS_ARE_REDUCTION_RATIOS then
			if GearValue == 0 or Final == 0 then return 0 end

			return 1 / ( GearValue * Final )
		end

		return GearValue * Final
	end

	-- km/h at the wheel for an engine RPM, overall ratio and wheel diameter in inches.
	local function SpeedKmh( RPM, Ratio, Diameter )
		return RPM * Ratio * math.pi * Diameter * 60 * 0.0000254
	end

	local GearColors = {
		Color(200, 50, 50), Color(220, 130, 20), Color(170, 160, 0), Color(40, 150, 40),
		Color(20, 150, 170), Color(40, 90, 210), Color(130, 60, 200), Color(200, 60, 150),
	}
	local PathColor = Color(25, 25, 25)

	-- Reads the gear sliders currently in the menu. Returns an array of { gear = N, value = V } and the final drive.
	local function ReadGears( GearCount )
		local CData = acemenupanel and acemenupanel.CData
		if not CData then return {}, 0 end

		local Gears = {}

		for I = 1, GearCount do
			local Slider = CData[I]

			if IsValid( Slider ) then
				Gears[#Gears + 1] = { gear = I, value = Slider:GetValue() }
			end
		end

		local Final = IsValid( CData[10] ) and CData[10]:GetValue() or 1

		return Gears, Final
	end

	--- Fills an ACE_Graph with a gear chart: engine RPM against road speed for every gear.
	-- @param Graph Panel The ACE_Graph to draw into; it is cleared first.
	-- @param Gears table Array of { gear = number, value = number } using the stored gear format.
	-- @param Final number Final drive value in the stored gear format.
	-- @param Diameter number Wheel diameter in inches.
	-- @param ShiftRPM number Engine RPM each gear is run up to before the next one.
	function ACE.PlotGearChart( Graph, Gears, Final, Diameter, ShiftRPM )

		if not IsValid( Graph ) then return end

		Graph:Clear()
		Graph:SetLegendVisible( false )
		Graph:SetXLabel( "km/h" )
		Graph:SetYLabel( "Engine RPM" )
		Graph:SetXFormat( function( Kmh ) return math.Round( Kmh, 1 ) .. " km/h / " .. math.Round( Kmh * 0.621371, 1 ) .. " mph" end )

		Diameter = math.max( tonumber( Diameter ) or 30, 1 )
		ShiftRPM = math.max( tonumber( ShiftRPM ) or 5000, 100 )

		local Lines = {}

		for _, Gear in ipairs( Gears ) do
			local Ratio = ratioOf( Gear.value, Final )

			if Ratio > 0 then
				Lines[#Lines + 1] = { gear = Gear.gear, top = SpeedKmh( ShiftRPM, Ratio, Diameter ) }
			end
		end

		table.sort( Lines, function( A, B ) return A.top < B.top end )

		local TopSpeed = Lines[#Lines] and Lines[#Lines].top or 100

		Graph:SetXRange( 0, TopSpeed * 1.05 )
		Graph:SetYRange( 0, ShiftRPM * 1.1 )
		Graph:PlotLimitLine( "Shift", false, ShiftRPM, Color(230, 0, 0) )

		local RPMFormat = function( RPM ) return math.Round( RPM ) .. " RPM" end
		local Path = { { x = 0, y = 0 } }

		for I, Line in ipairs( Lines ) do
			local Col = GearColors[( I - 1 ) % #GearColors + 1]

			Graph:PlotTable( "Gear " .. Line.gear, { { x = 0, y = 0 }, { x = Line.top, y = ShiftRPM } }, Col, RPMFormat )
			Graph:PlotPoint( tostring( Line.gear ), Line.top, ShiftRPM, Col )

			-- Sawtooth: run this gear up to the shift RPM, then drop to the next gear's RPM at the same speed
			Path[#Path + 1] = { x = Line.top, y = ShiftRPM }

			local Next = Lines[I + 1]

			if Next and Next.top > 0 then
				Path[#Path + 1] = { x = Line.top, y = ShiftRPM * Line.top / Next.top }
			end
		end

		if #Lines > 1 then
			Graph:PlotTable( "Shift path", Path, PathColor, RPMFormat )
		end
	end

	-- Adds the chart and its inputs to the gearbox menu, and redraws it whenever a slider moves.
	function CreateGearChart( Table )

		local CData = acemenupanel.CData
		if IsValid( CData.GearChart ) then return end

		local Inputs = vgui.Create( "DPanel" )
		Inputs:SetPaintBackground( false )
		Inputs:SetTall( 20 )

		local function AddInput( Label, ConVarName, Tooltip )
			local Text = Inputs:Add( "DLabel" )
			Text:Dock( LEFT )
			Text:SetDark( true )
			Text:SetText( Label )
			Text:SizeToContentsX( 6 )

			local Wang = Inputs:Add( "DNumberWang" )
			Wang:Dock( LEFT )
			Wang:SetWide( 60 )
			Wang:SetDecimals( 1 )
			Wang:SetMinMax( 1, 50000 )
			Wang:SetConVar( ConVarName )
			Wang:SetTooltip( Tooltip )

			return Wang
		end

		AddInput( "Wheel diameter (in):", "ace_gearchart_wheel_diameter", "For tracked vehicles use the drive wheel diameter." )
		AddInput( "  Shift RPM:", "ace_gearchart_rpm", "Engine RPM each gear is run up to." )

		CData.GearChartInputs = Inputs
		acemenupanel.CustomDisplay:AddItem( Inputs )

		local Graph = vgui.Create( "ACE_Graph" )
		Graph:SetTall( math.max( acemenupanel:GetWide() * 0.55, 150 ) )
		CData.GearChart = Graph
		acemenupanel.CustomDisplay:AddItem( Graph )

		local GearCount = Table.gears or 0
		local LastKey
		local NextCheck = 0

		Graph.Think = function( Self )
			local Now = RealTime()
			if Now < NextCheck then return end
			NextCheck = Now + 0.2

			local Gears, Final = ReadGears( GearCount )
			local Diameter = GetConVar( "ace_gearchart_wheel_diameter" ):GetFloat()
			local ShiftRPM = GetConVar( "ace_gearchart_rpm" ):GetFloat()
			local Key = Final .. "|" .. Diameter .. "|" .. ShiftRPM

			for _, Gear in ipairs( Gears ) do
				Key = Key .. "|" .. Gear.value
			end

			if Key == LastKey then return end
			LastKey = Key

			ACE.PlotGearChart( Self, Gears, Final, Diameter, ShiftRPM )
		end
	end
end

function ACE.GearboxGUICreate( Table )

	if not acemenupanel.Serialize then
		acemenupanel.Serialize = function( tbl, factor )
			local str = ""
			for i = 1,7 do
				str = str .. math.Round(tbl[i] * factor,1) .. ","
			end
			RunConsoleCommand( "acemenu_data9", str )
		end
	end

	if not acemenupanel.GearboxData then
		acemenupanel.GearboxData = {}
	end

	if not acemenupanel.GearboxData[Table.id] then
		acemenupanel.GearboxData[Table.id] = {}
		acemenupanel.GearboxData[Table.id].GearTable = Table.geartable
	end

	if Table.auto and not acemenupanel.GearboxData[Table.id].ShiftTable then
		acemenupanel.GearboxData[Table.id].ShiftTable = {10,20,30,40,50,60,70}
	end

	acemenupanel:CPanelText("Name", Table.name, "DermaDefaultBold")

	acemenupanel.CData.DisplayModel = vgui.Create( "DModelPanel", acemenupanel.CustomDisplay )
		acemenupanel.CData.DisplayModel:SetModel( Table.model )
		acemenupanel.CData.DisplayModel:SetCamPos( Vector( 250, 500, 250 ) )
		acemenupanel.CData.DisplayModel:SetLookAt( Vector( 0, 0, 0 ) )
		acemenupanel.CData.DisplayModel:SetFOV( 20 )
		acemenupanel.CData.DisplayModel:SetSize(acemenupanel:GetWide(),acemenupanel:GetWide())
		acemenupanel.CData.DisplayModel.LayoutEntity = function() end
	acemenupanel.CustomDisplay:AddItem( acemenupanel.CData.DisplayModel )

	acemenupanel:CPanelText("Desc", Table.desc) --Description (Name, Desc)

	if Table.auto and not acemenupanel.CData.UnitsInput then
		acemenupanel.CData.UnitsInput = vgui.Create( "DComboBox", acemenupanel.CustomDisplay )
			acemenupanel.CData.UnitsInput.ID = Table.id
			acemenupanel.CData.UnitsInput.Gears = Table.gears
			acemenupanel.CData.UnitsInput:SetSize( 60,22 )
			acemenupanel.CData.UnitsInput:SetTooltip( "If using the shift point generator, recalc after changing units." )
			acemenupanel.CData.UnitsInput:AddChoice( "KPH", 10.936, true )
			acemenupanel.CData.UnitsInput:AddChoice( "MPH", 17.6 )
			acemenupanel.CData.UnitsInput:AddChoice( "GMU", 1 )
			acemenupanel.CData.UnitsInput:SetDark( true )
			acemenupanel.CData.UnitsInput.OnSelect = function( panel, _, _, data )
				acemenupanel.Serialize( acemenupanel.GearboxData[panel.ID].ShiftTable, data )  --dot intentional
			end
		acemenupanel.CustomDisplay:AddItem(acemenupanel.CData.UnitsInput)
	end

	if Table.cvt then
		ACE.GearsSlider(2, acemenupanel.GearboxData[Table.id].GearTable[2], Table.id)
		ACE.GearsSlider(3, acemenupanel.GearboxData[Table.id].GearTable[-3], Table.id, "Min Target RPM",true)
		ACE.GearsSlider(4, acemenupanel.GearboxData[Table.id].GearTable[-2], Table.id, "Max Target RPM",true)
		ACE.GearsSlider(10, acemenupanel.GearboxData[Table.id].GearTable[-1], Table.id, "Final Drive")
		RunConsoleCommand( "acemenu_data1", 0.01 )
	else
		for ID,Value in pairs(acemenupanel.GearboxData[Table.id].GearTable) do
			if ID > 0 and not (Table.auto and ID == 8) then
				ACE.GearsSlider(ID, Value, Table.id)
				if Table.auto then
					ACE.ShiftPoint(ID, acemenupanel.GearboxData[Table.id].ShiftTable[ID], Table.id, "Gear " .. ID .. " upshift speed: ")
				end
			elseif Table.auto and (ID == -2 or ID == 8) then
				ACE.GearsSlider(8, Value, Table.id, "Reverse")
			elseif ID == -1 then
				ACE.GearsSlider(10, Value, Table.id, "Final Drive")
			end
		end
	end

	--
	local InvertButton = vgui.Create("DButton")
	InvertButton:SetText( "Invert Final drive" )
	InvertButton:SetIcon( "icon16/arrow_refresh.png" )
	InvertButton.DoClick = function()
		if acemenupanel.CData[10] then ---10 gear is the final drive

			local oldValue = acemenupanel.CData[10]:GetValue()
			acemenupanel.CData[10]:SetValue( oldValue * -1 )
		end
	end
	acemenupanel.CustomDisplay:AddItem(InvertButton)

	acemenupanel:CPanelText("Desc", Table.desc)
	acemenupanel:CPanelText("MaxTorque", "Clutch Maximum Torque Rating : " .. Table.maxtq .. "n-m / " .. math.Round(Table.maxtq * 0.73) .. "ft-lb")
	acemenupanel:CPanelText("Weight", "Weight : " .. Table.weight .. "kg\n")

	if not Table.cvt then
		CreateGearChart( Table )
	end

	if Table.auto then
		acemenupanel:CPanelText( "ShiftPointGen", "Shift Point Generator:", "DermaDefaultBold" )

		if not acemenupanel.CData.ShiftGenPanel then
			acemenupanel.CData.ShiftGenPanel = vgui.Create( "DPanel" )
				acemenupanel.CData.ShiftGenPanel:SetPaintBackground( false )
				acemenupanel.CData.ShiftGenPanel:DockPadding( 4, 0, 4, 0 )
				acemenupanel.CData.ShiftGenPanel:SetTall( 60 )
				acemenupanel.CData.ShiftGenPanel:SizeToContentsX()
				acemenupanel.CData.ShiftGenPanel.Gears = Table.gears

			acemenupanel.CData.ShiftGenPanel.Calc = acemenupanel.CData.ShiftGenPanel:Add( "DButton" )
				acemenupanel.CData.ShiftGenPanel.Calc:SetText( "Calculate" )
				acemenupanel.CData.ShiftGenPanel.Calc:Dock( BOTTOM )
				acemenupanel.CData.ShiftGenPanel.Calc:SetTall( 20 )

				acemenupanel.CData.ShiftGenPanel.Calc.DoClick = function()
					local _, factor = acemenupanel.CData.UnitsInput:GetSelected()
					local mul = math.pi * acemenupanel.CData.ShiftGenPanel.RPM:GetValue() * acemenupanel.CData.ShiftGenPanel.Ratio:GetValue() * acemenupanel.CData[10]:GetValue() * acemenupanel.CData.ShiftGenPanel.Wheel:GetValue() / (60 * factor)
					for i = 1,acemenupanel.CData.ShiftGenPanel.Gears do
						acemenupanel.CData[10 + i].Input:SetValue( math.Round( math.abs( mul * acemenupanel.CData[i]:GetValue() ), 2 ) )
						acemenupanel.GearboxData[acemenupanel.CData.UnitsInput.ID].ShiftTable[i] = tonumber(acemenupanel.CData[10 + i].Input:GetValue())
					end
					acemenupanel.Serialize( acemenupanel.GearboxData[acemenupanel.CData.UnitsInput.ID].ShiftTable, factor )  --dot intentional
				end

				acemenupanel.CData.WheelPanel = acemenupanel.CData.ShiftGenPanel:Add( "DPanel" )
					acemenupanel.CData.WheelPanel:SetPaintBackground( false )
					acemenupanel.CData.WheelPanel:DockMargin( 4, 0, 4, 0 )
					acemenupanel.CData.WheelPanel:Dock( RIGHT )
					acemenupanel.CData.WheelPanel:SetWide( 76 )
					acemenupanel.CData.WheelPanel:SetTooltip( "If you use default spherical settings, add 0.5 to your wheel diameter.\nFor treaded vehicles, use the diameter of road wheels, not drive wheels." )

					acemenupanel.CData.ShiftGenPanel.WheelLabel = acemenupanel.CData.WheelPanel:Add( "DLabel" )
						acemenupanel.CData.ShiftGenPanel.WheelLabel:Dock( TOP )
						acemenupanel.CData.ShiftGenPanel.WheelLabel:SetDark( true )
						acemenupanel.CData.ShiftGenPanel.WheelLabel:SetText( "Wheel Diameter:" )

					acemenupanel.CData.ShiftGenPanel.Wheel = acemenupanel.CData.WheelPanel:Add( "DNumberWang" )
						acemenupanel.CData.ShiftGenPanel.Wheel:HideWang()
						acemenupanel.CData.ShiftGenPanel.Wheel:SetDrawBorder( false )
						acemenupanel.CData.ShiftGenPanel.Wheel:Dock( BOTTOM )
						acemenupanel.CData.ShiftGenPanel.Wheel:SetDecimals( 2 )
						acemenupanel.CData.ShiftGenPanel.Wheel:SetMinMax( 0, 9999 )
						acemenupanel.CData.ShiftGenPanel.Wheel:SetValue( 30 )

				acemenupanel.CData.RatioPanel = acemenupanel.CData.ShiftGenPanel:Add( "DPanel" )
					acemenupanel.CData.RatioPanel:SetPaintBackground( false )
					acemenupanel.CData.RatioPanel:DockMargin( 4, 0, 4, 0 )
					acemenupanel.CData.RatioPanel:Dock( RIGHT )
					acemenupanel.CData.RatioPanel:SetWide( 76 )
					acemenupanel.CData.RatioPanel:SetTooltip( "Total ratio is the ratio of all gearboxes (excluding this one) multiplied together.\nFor example, if you use engine to automatic to diffs to wheels, your total ratio would be (diff gear ratio * diff final ratio)." )

					acemenupanel.CData.ShiftGenPanel.RatioLabel = acemenupanel.CData.RatioPanel:Add( "DLabel" )
						acemenupanel.CData.ShiftGenPanel.RatioLabel:Dock( TOP )
						acemenupanel.CData.ShiftGenPanel.RatioLabel:SetDark( true )
						acemenupanel.CData.ShiftGenPanel.RatioLabel:SetText( "Total ratio:" )

					acemenupanel.CData.ShiftGenPanel.Ratio = acemenupanel.CData.RatioPanel:Add( "DNumberWang" )
						acemenupanel.CData.ShiftGenPanel.Ratio:HideWang()
						acemenupanel.CData.ShiftGenPanel.Ratio:SetDrawBorder( false )
						acemenupanel.CData.ShiftGenPanel.Ratio:Dock( BOTTOM )
						acemenupanel.CData.ShiftGenPanel.Ratio:SetDecimals( 2 )
						acemenupanel.CData.ShiftGenPanel.Ratio:SetMinMax( 0, 9999 )
						acemenupanel.CData.ShiftGenPanel.Ratio:SetValue( 0.1 )

				acemenupanel.CData.RPMPanel = acemenupanel.CData.ShiftGenPanel:Add( "DPanel" )
					acemenupanel.CData.RPMPanel:SetPaintBackground( false )
					acemenupanel.CData.RPMPanel:DockMargin( 4, 0, 4, 0 )
					acemenupanel.CData.RPMPanel:Dock( RIGHT )
					acemenupanel.CData.RPMPanel:SetWide( 76 )
					acemenupanel.CData.RPMPanel:SetTooltip( "Target engine RPM to upshift at." )

					acemenupanel.CData.ShiftGenPanel.RPMLabel = acemenupanel.CData.RPMPanel:Add( "DLabel" )
						acemenupanel.CData.ShiftGenPanel.RPMLabel:Dock( TOP )
						acemenupanel.CData.ShiftGenPanel.RPMLabel:SetDark( true )
						acemenupanel.CData.ShiftGenPanel.RPMLabel:SetText( "Upshift RPM:" )

					acemenupanel.CData.ShiftGenPanel.RPM = acemenupanel.CData.RPMPanel:Add( "DNumberWang" )
						acemenupanel.CData.ShiftGenPanel.RPM:HideWang()
						acemenupanel.CData.ShiftGenPanel.RPM:SetDrawBorder( false )
						acemenupanel.CData.ShiftGenPanel.RPM:Dock( BOTTOM )
						acemenupanel.CData.ShiftGenPanel.RPM:SetDecimals( 2 )
						acemenupanel.CData.ShiftGenPanel.RPM:SetMinMax( 0, 9999 )
						acemenupanel.CData.ShiftGenPanel.RPM:SetValue( 5000 )

			acemenupanel.CustomDisplay:AddItem(acemenupanel.CData.ShiftGenPanel)
		end
	end

	acemenupanel.CustomDisplay:PerformLayout()
	maxtorque = Table.maxtq
end

function ACE.GearsSlider(Gear, Value, ID, Desc, CVT)

	if Gear and not acemenupanel.CData[Gear] then

		acemenupanel.CData[Gear] = vgui.Create( "DNumSlider", acemenupanel.CustomDisplay )
			acemenupanel.CData[Gear]:SetText( Desc or "Gear " .. Gear )
			acemenupanel.CData[Gear].Label:SizeToContents()
			acemenupanel.CData[Gear]:SetDark( true )
			acemenupanel.CData[Gear]:SetMin( CVT and 1 or -2 )
			acemenupanel.CData[Gear]:SetMax( CVT and 20000 or 2 )
			acemenupanel.CData[Gear]:SetDecimals( (not CVT) and 2 or 0 )
			acemenupanel.CData[Gear].Gear = Gear
			acemenupanel.CData[Gear].ID = ID
			acemenupanel.CData[Gear]:SetValue(Value)
			RunConsoleCommand( "acemenu_data" .. Gear, Value )
			acemenupanel.CData[Gear].OnValueChanged = function( slider, val )
				acemenupanel.GearboxData[slider.ID].GearTable[slider.Gear] = val
				RunConsoleCommand( "acemenu_data" .. Gear, val )
			end
		acemenupanel.CustomDisplay:AddItem( acemenupanel.CData[Gear] )
	end

end

function ACE.ShiftPoint(Gear, Value, ID, Desc)
	local Index = Gear + 10
	if Gear and not acemenupanel.CData[Index] then
		acemenupanel.CData[Index] = vgui.Create( "DPanel" )
			acemenupanel.CData[Index]:SetPaintBackground( false )
			acemenupanel.CData[Index]:SetTall( 20 )
			acemenupanel.CData[Index]:SizeToContentsX()

		acemenupanel.CData[Index].Input = acemenupanel.CData[Index]:Add( "DNumberWang" )
			acemenupanel.CData[Index].Input.Gear = Gear
			acemenupanel.CData[Index].Input.ID = ID
			acemenupanel.CData[Index].Input:HideWang()
			acemenupanel.CData[Index].Input:SetDrawBorder( false )
			acemenupanel.CData[Index].Input:SetDecimals( 2 )
			acemenupanel.CData[Index].Input:SetMinMax( 0, 9999 )
			acemenupanel.CData[Index].Input:SetValue( Value )
			acemenupanel.CData[Index].Input:Dock( RIGHT )
			acemenupanel.CData[Index].Input:SetWide( 45 )
			acemenupanel.CData[Index].Input.OnValueChanged = function( box, value )
				acemenupanel.GearboxData[box.ID].ShiftTable[box.Gear] = value
				local _, factor = acemenupanel.CData.UnitsInput:GetSelected()
				acemenupanel.Serialize( acemenupanel.GearboxData[acemenupanel.CData.UnitsInput.ID].ShiftTable, factor )  --dot intentional
			end
			RunConsoleCommand( "acemenu_data9", "10,20,30,40,50,60,70" )

		acemenupanel.CData[Index].Label = acemenupanel.CData[Index]:Add( "DLabel" )
			acemenupanel.CData[Index].Label:Dock( RIGHT )
			acemenupanel.CData[Index].Label:SetWide( 120 )
			acemenupanel.CData[Index].Label:SetDark( true )
			acemenupanel.CData[Index].Label:SetText( Desc )

		acemenupanel.CustomDisplay:AddItem(acemenupanel.CData[Index])
	end
end

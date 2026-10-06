
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

--[[
	Gearbox spawn menu.

	Order on the page: what the box is (name, model, description), how big it is (size, gear
	count, dual clutch, and the stats those give), its gears (ratios, final drive, and for
	automatics the upshift speeds), the gear chart, and the drivetrain setup (differential,
	clutch, assisted driving). The chart's wheel and RPM inputs are the only place those numbers
	are entered: automatics compute their upshift speeds from them.

	Tool convars: acemenu_data1-9 gears (automatics: data8 reverse, data9 upshift speeds as a
	comma list in game units; CVTs: data2 reverse, data3/4 target RPM), data10 final drive,
	data11 size, data12 gear count, data13 dual clutch.
]]

local WheelVar = CreateClientConVar( "ace_gearchart_wheel_diameter", 30, true, false, "Wheel diameter in inches used by the gearbox menu's gear chart." )
local RPMVar = CreateClientConVar( "ace_gearchart_rpm", 5000, true, false, "Engine RPM used as the shift point by the gearbox menu's gear chart." )
local AfterVar = CreateClientConVar( "ace_gearchart_after", 1, true, false, "Ratio of everything after the gearbox (differentials, transfer cases) in ACE's gear values, for the gear chart and upshift speeds." )
local SizeVar = CreateClientConVar( "acemenu_gb_size", 1, true, false, "Size of the next scalable gearbox (1 = the small model)." )
local GearsVar = CreateClientConVar( "acemenu_gb_gears", 5, true, false, "Gear count of the next scalable gearbox." )
local RealRatiosConVar = CreateClientConVar( "acemenu_gb_realratios", "0", true, false,
	"1 = the gearbox menu's gear sliders take real ratios (4.1 = 4.1:1 reduction) instead of ACE's output/input speed values." )

-- Game speed units (inches per second) in one km/h.
local InchPerSecKmh = 10.936

local GearColors = {
	Color(200, 50, 50), Color(220, 130, 20), Color(170, 160, 0), Color(40, 150, 40),
	Color(20, 150, 170), Color(40, 90, 210), Color(130, 60, 200), Color(200, 60, 150),
	Color(120, 80, 40),
}
local PathColor = Color(25, 25, 25)

-- km/h at the wheel for an engine RPM, overall output/input speed and wheel diameter in inches.
local function SpeedKmh( RPM, Ratio, Diameter )
	return RPM * Ratio * math.pi * Diameter / 60 / InchPerSecKmh
end

--- Fills an ACE_Graph with a gear chart: engine RPM against road speed for every gear.
-- @param Graph Panel The ACE_Graph to draw into; it is cleared first.
-- @param Gears table Array of { gear = number, value = number } in the stored gear format.
-- @param Final number Final drive in the stored gear format, times anything after the box.
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
		local Ratio = math.abs( Gear.value * Final )
		if Gear.value > 0 and Ratio > 0 then
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
		-- Sawtooth: run this gear up to the shift RPM, then drop to the next gear's RPM at the same speed.
		Path[#Path + 1] = { x = Line.top, y = ShiftRPM }
		local Next = Lines[I + 1]
		if Next and Next.top > 0 then
			Path[#Path + 1] = { x = Line.top, y = ShiftRPM * Line.top / Next.top }
		end
	end
	if #Lines > 1 then Graph:PlotTable( "Shift path", Path, PathColor, RPMFormat ) end
end

-- Real ratio (reduction, as a gearbox data sheet gives it) of a stored gear value.
local function RealRatioText( Value )
	if math.abs( Value ) < 1e-4 then return "neutral" end
	return string.format( "%.2f:1", 1 / Value )
end

--[[
	Gears are stored the way ACE always has, as output/input speed (0.25 = the output turns a
	quarter as fast). A real ratio is its inverse. Stored values run from -2 to 2, so real ratios
	below 0.5:1 are raised to 0.5:1.
]]
local function ToReal( Stored )
	if math.abs( Stored ) < 1e-4 then return 0 end
	return 1 / Stored
end

local function ToStored( Real )
	if math.abs( Real ) < 0.01 then return 0 end
	return ( Real < 0 and -1 or 1 ) / math.max( math.abs( Real ), 0.5 )
end

--- Stored (output/input speed) value of a gearbox menu gear slider, whichever way it is shown.
-- @param Slider Panel A gear slider.
-- @return number
function ACE.GearSliderValue( Slider )
	return Slider.Stored or Slider:GetValue()
end

-- Shows the first Count panels of a list and hides the rest, then re-lays the page out.
local function ShowFirst( Panels, Count )
	for I, Panel in pairs( Panels or {} ) do
		if IsValid( Panel ) then Panel:SetVisible( I <= Count ) end
	end
	if IsValid( acemenupanel.CustomDisplay ) then acemenupanel.CustomDisplay:InvalidateLayout() end
end

local function Rebuild()
	timer.Simple( 0, function()
		if IsValid( acemenupanel ) and acemenupanel.ActiveDisplayTable then
			acemenupanel:UpdateDisplay( acemenupanel.ActiveDisplayTable )
		end
	end )
end

local function AddItem( Panel )
	acemenupanel.CustomDisplay:AddItem( Panel )
	return Panel
end

local function Header( Name, Text )
	acemenupanel:CPanelText( Name, Text, "DermaDefaultBold" )
end

-- A labelled number box on its own row, label column the same width on every row.
local function NumberRow( Label, Value, Min, Max, Decimals, Tooltip, OnChange )
	local Row = vgui.Create( "DPanel" )
	Row:SetPaintBackground( false )
	Row:SetTall( 20 )

	local Text = Row:Add( "DLabel" )
	Text:Dock( LEFT )
	Text:SetWide( 150 )
	Text:SetDark( true )
	Text:SetText( Label )

	local Wang = Row:Add( "DNumberWang" )
	Wang:Dock( LEFT )
	Wang:SetWide( 80 )
	Wang:SetDecimals( Decimals )
	Wang:SetMinMax( Min, Max )
	Wang:SetValue( Value )
	Wang:SetTooltip( Tooltip )
	Text:SetTooltip( Tooltip )
	Wang.OnValueChanged = function( _, New ) OnChange( tonumber( New ) or Value ) end

	Row.Wang = Wang
	return AddItem( Row )
end

local function Slider( Label, Min, Max, Decimals, Value, Tooltip, OnChange )
	local S = vgui.Create( "DNumSlider" )
	S:SetText( Label )
	S:SetDark( true )
	S:SetMinMax( Min, Max )
	S:SetDecimals( Decimals )
	S:SetValue( Value )
	S:SetTooltip( Tooltip )
	S.OnValueChanged = function( _, New ) OnChange( New ) end
	return AddItem( S )
end

local function CheckBox( Label, Value, Tooltip, OnChange )
	local C = vgui.Create( "DCheckBoxLabel" )
	C:SetText( Label )
	C:SetDark( true )
	C:SetValue( Value and 1 or 0 )
	C:SetTooltip( Tooltip )
	C.OnChange = function( _, New ) OnChange( New ) end
	return AddItem( C )
end

-- Gear values the builder set per gearbox family, kept while the menu is open.
local function Store( Table, Gears, Count )
	acemenupanel.GearboxData = acemenupanel.GearboxData or {}
	local Key = Table.family or Table.id
	local S = acemenupanel.GearboxData[Key]
	if not S then
		S = { Gears = {}, Shift = {}, Final = Table.geartable and Table.geartable[-1] or 0.5, Reverse = -0.1 }
		acemenupanel.GearboxData[Key] = S
	end
	for I = 1, Gears do
		-- Defaults: evenly spaced forward gears; a manual's last gear is its reverse.
		if S.Gears[I] == nil then
			S.Gears[I] = ( not Table.auto and Count > 1 and I == Count ) and -0.1 or 0.1 * I
		end
		if S.Shift[I] == nil then S.Shift[I] = 10 * I end
	end
	return S
end

-- One gear slider. Slot is the acemenu_data slot it writes.
local function GearSlider( Slot, Label, Stored, OnStored )
	local Real = RealRatiosConVar:GetBool()
	local S = vgui.Create( "DNumSlider" )
	S:SetDark( true )
	S:SetMinMax( Real and -20 or -2, Real and 20 or 2 )
	S:SetDecimals( 2 )
	S.RealRatio = Real
	S.Stored = Stored
	S:SetValue( Real and ToReal( Stored ) or Stored )
	local function Caption( V ) S:SetText( Real and Label or ( Label .. "  = " .. RealRatioText( V ) ) ) end
	Caption( Stored )
	S.OnValueChanged = function( Self, V )
		local New = Real and ToStored( V ) or V
		Self.Stored = New
		OnStored( New )
		if Slot then RunConsoleCommand( "acemenu_data" .. Slot, New ) end
		Caption( V )
	end
	if Slot then RunConsoleCommand( "acemenu_data" .. Slot, Stored ) end
	return AddItem( S )
end

local function SerializeShift( S )
	local Parts = {}
	for I = 1, math.max( #S.Shift, 7 ) do
		Parts[I] = math.Round( ( S.Shift[I] or 0 ) * InchPerSecKmh, 1 )
	end
	RunConsoleCommand( "acemenu_data9", table.concat( Parts, "," ) .. "," )
end

-- The size block: size, gear count, dual clutch, and what they give.
local function CreateSizePanel( Table, Family, View )
	local Size = ACE.GearboxSize
	local Scale = Size.ClampScale( SizeVar:GetFloat() )
	local Gears = Size.ClampGears( Family, GearsVar:GetInt() )
	-- Dual clutch is remembered per family: transfer cases default to it, gearboxes do not.
	acemenupanel.GearboxDual = acemenupanel.GearboxDual or {}
	local Remembered = acemenupanel.GearboxDual[Table.family]
	if Remembered == nil then Remembered = Family.DualDefault or false end
	local Dual = Family.DualForced or ( Family.CanDual and Remembered ) or false

	RunConsoleCommand( "acemenu_data11", Scale )
	RunConsoleCommand( "acemenu_data12", Gears )
	RunConsoleCommand( "acemenu_data13", Dual and 1 or 0 )

	Header( "SizeHeader", "Size:" )
	local Stats = vgui.Create( "DLabel" )
	Stats:SetDark( true )
	Stats:SetWrap( true )
	Stats:SetAutoStretchVertical( true )

	local function UpdateStats()
		local S = Size.Stats( Table.family, Scale, Gears, Table.straight, View.Range, View.Split )
		local Text = string.format( "%d kg, rated %d Nm / %d ft-lb, shift %.2f s", math.Round( S.Mass ), S.MaxTorque, math.Round( S.MaxTorque * 0.7376 ), S.Switch )
		if View.Range or View.Split then
			Text = Text .. string.format( "\n%d speeds from %d main gears", Gears * ( View.Range and 2 or 1 ) * ( View.Split and 2 or 1 ), Gears )
		end
		Stats:SetText( Text )
		acemenupanel.GearboxRating = S.MaxTorque
	end

	Slider( "Size", Size.Min, Size.Max, 2, Scale,
		"Linear size, 1 = the small model.\nTorque rating and weight both grow with size cubed,\nso the rating per kilogram stays the same.",
		function( V )
			Scale = Size.ClampScale( V )
			SizeVar:SetFloat( Scale )
			RunConsoleCommand( "acemenu_data11", Scale )
			UpdateStats()
		end )

	if not Family.Fixed then
		Slider( Table.auto and "Forward gears" or "Gears", Family.Gears[1], Family.Gears[2], 0, Gears,
			( Table.auto and "Number of forward gears." or "Number of gears, the last one usually set as reverse." )
				.. "\nEach gear adds weight and lowers the rating a little."
				.. ( Family.CanCompound and "\nFor more speeds, add a range section or a splitter below, as truck gearboxes do." or "" ),
			function( V )
				local New = Size.ClampGears( Family, V )
				if New == Gears then return end
				Gears = New
				View.Gears = New
				GearsVar:SetInt( New )
				RunConsoleCommand( "acemenu_data12", New )
				UpdateStats()
				ShowFirst( View.GearRows, New )
				ShowFirst( View.ShiftRows, New )
			end )
	end

	--[[
		Range section and splitter (compound truck gearboxes, see ACE.GearboxSize). Off writes 0;
		the ratio is remembered while the menu is open. Changing them relabels the gear sliders,
		so the page is rebuilt (they are set once, not dragged).
	]]
	if Family.CanCompound then
		acemenupanel.GearboxCompound = acemenupanel.GearboxCompound or { Range = Size.RangeDefault, Split = Size.SplitDefault }
		local C = acemenupanel.GearboxCompound
		View.Range = C.RangeOn and C.Range or nil
		View.Split = C.SplitOn and C.Split or nil
		RunConsoleCommand( "acemenu_data14", View.Range or 0 )
		RunConsoleCommand( "acemenu_data15", View.Split or 0 )

		CheckBox( "Range section (doubles the speeds)", C.RangeOn or false,
			"A planetary low/high stage behind the main gears: every main gear is used once in low range\nand again in high. Truck boxes use it for 10-18 speeds. About 15 % heavier;\nrange shifts take about twice as long as a gear shift.",
			function( V ) C.RangeOn = V Rebuild() end )
		if C.RangeOn then
			Slider( "Low range ratio (x:1)", Size.RangeMin, Size.RangeMax, 2, C.Range,
				"Reduction of the low range. About 3.5:1 on 10-18 speed truck boxes, so the high range\ncarries on where the low range stops.",
				function( V ) C.Range = Size.ClampRange( V ) or Size.RangeMin View.Range = C.Range RunConsoleCommand( "acemenu_data14", C.Range ) UpdateStats() end )
		end
		CheckBox( "Splitter (halves every step)", C.SplitOn or false,
			"A small two-ratio stage on the input that splits each gear into two close steps,\nfor a diesel's narrow powerband. About 8 % heavier; split shifts are quick.",
			function( V ) C.SplitOn = V Rebuild() end )
		if C.SplitOn then
			Slider( "Splitter step (x:1)", Size.SplitMin, Size.SplitMax, 2, C.Split,
				"Ratio between the two halves of each gear. About 1.2:1 on truck boxes.",
				function( V ) C.Split = Size.ClampSplit( V ) or Size.SplitMin View.Split = C.Split RunConsoleCommand( "acemenu_data15", C.Split ) UpdateStats() end )
		end
	else
		RunConsoleCommand( "acemenu_data14", 0 )
		RunConsoleCommand( "acemenu_data15", 0 )
	end

	if Family.CanDual and not Family.DualForced then
		CheckBox( "Dual clutch", Dual,
			"Drive and brake each side on its own, for skid-steered vehicles:\nseparate Left/Right Clutch and Brake inputs.",
			function( V ) acemenupanel.GearboxDual[Table.family] = V RunConsoleCommand( "acemenu_data13", V and 1 or 0 ) end )
	end

	AddItem( Stats )
	UpdateStats()
	return Gears
end

local function CreateGears( Table, View )
	local CData = acemenupanel.CData
	local Gears = View.Gears
	local S = Store( Table, View.Max, View.Gears )

	Header( "GearsHeader", "Gears:" )

	local Toggle = CheckBox( "Real gear ratios", RealRatiosConVar:GetBool(),
		"On: gears are entered as a data sheet gives them (4.1 = 4.1:1 reduction).\nOff: ACE's output/input speed values (0.25 = 4:1).\nGearboxes are stored the same way either way.",
		function( V ) RealRatiosConVar:SetBool( V ) Rebuild() end )
	CData.RealRatios = Toggle

	if Table.cvt then
		CData.Reverse = GearSlider( 2, "Reverse", S.Reverse, function( V ) S.Reverse = V end )
		local Min = Table.geartable[-3] or 3000
		local Max = Table.geartable[-2] or 5000
		S.MinRPM, S.MaxRPM = S.MinRPM or Min, S.MaxRPM or Max
		RunConsoleCommand( "acemenu_data1", 0.01 )
		RunConsoleCommand( "acemenu_data3", S.MinRPM )
		RunConsoleCommand( "acemenu_data4", S.MaxRPM )
		Slider( "Min target RPM", 500, 20000, 0, S.MinRPM, "The CVT keeps the engine at or above this.", function( V ) S.MinRPM = V RunConsoleCommand( "acemenu_data3", V ) end )
		Slider( "Max target RPM", 500, 20000, 0, S.MaxRPM, "The CVT keeps the engine at or below this.", function( V ) S.MaxRPM = V RunConsoleCommand( "acemenu_data4", V ) end )
	elseif ( Table.family == "clutch" ) then
		RunConsoleCommand( "acemenu_data1", 1 )
		RunConsoleCommand( "acemenu_data10", 1 )
	else
		-- Every gear the family allows gets a slider; the gear count only shows or hides them.
		View.GearRows = {}
		for I = 1, View.Max do
			View.GearRows[I] = GearSlider( I, ( View.Range or View.Split ) and "Main gear " .. I or "Gear " .. I, S.Gears[I], function( V ) S.Gears[I] = V end )
		end
		ShowFirst( View.GearRows, Gears )
		CData.GearSliders = View.GearRows
		if Table.auto then
			CData.Reverse = GearSlider( 8, "Reverse", S.Reverse, function( V ) S.Reverse = V end )
		end
	end

	if Table.family ~= "clutch" then
		CData.Final = GearSlider( 10, "Final drive", S.Final, function( V ) S.Final = V end )

		local Row = vgui.Create( "DPanel" )
		Row:SetPaintBackground( false )
		Row:SetTall( 20 )
		local Invert = Row:Add( "DButton" )
		Invert:Dock( LEFT )
		Invert:SetWide( 130 )
		Invert:SetText( "Invert final drive" )
		Invert:SetIcon( "icon16/arrow_refresh.png" )
		Invert.DoClick = function()
			if IsValid( CData.Final ) then CData.Final:SetValue( -CData.Final:GetValue() ) end
		end
		AddItem( Row )
	end
	return S
end

-- Gear chart, and for automatics the upshift speeds worked out from the same inputs.
local function CreateChart( Table, View, S )
	local CData = acemenupanel.CData
	if Table.cvt or Table.family == "clutch" or Table.family == "diff" then return end

	Header( "ChartHeader", Table.auto and "Gear chart and upshift speeds:" or "Gear chart:" )

	NumberRow( "Wheel diameter (in)", WheelVar:GetFloat(), 1, 1000, 1, "For tracked vehicles use the drive sprocket diameter.",
		function( V ) WheelVar:SetFloat( V ) end )
	NumberRow( "Shift RPM", RPMVar:GetFloat(), 100, 30000, 0, "Engine RPM each gear is run up to before the next one.",
		function( V ) RPMVar:SetFloat( V ) end )
	NumberRow( "Ratio after this box", AfterVar:GetFloat(), 0.001, 100, 3,
		"Everything between this gearbox and the wheels, in ACE gear values multiplied together\n(gear times final drive of each differential or transfer case). 1 if this box drives the wheels.",
		function( V ) AfterVar:SetFloat( V ) end )

	local Graph = vgui.Create( "ACE_Graph" )
	Graph:SetTall( math.max( acemenupanel:GetWide() * 0.55, 150 ) )
	CData.GearChart = Graph
	AddItem( Graph )

	local function Inputs()
		local List = {}
		for I = 1, View.Gears do
			local G = ( CData.GearSliders or {} )[I]
			if IsValid( G ) then List[#List + 1] = { gear = I, value = ACE.GearSliderValue( G ) } end
		end
		-- A compound box is charted speed by speed, numbered as its Gear input counts them.
		if View.Range or View.Split then
			local Main = {}
			for I, G in ipairs( List ) do Main[I] = G.value end
			List = {}
			for I, Speed in ipairs( ACE.GearboxSize.Expand( Main, View.Range, View.Split ) ) do
				List[I] = { gear = I, value = Speed.Value }
			end
		end
		local Final = IsValid( CData.Final ) and ACE.GearSliderValue( CData.Final ) or 1
		return List, Final * AfterVar:GetFloat()
	end

	local LastKey, NextCheck = nil, 0
	Graph.Think = function( Self )
		local Now = RealTime()
		if Now < NextCheck then return end
		NextCheck = Now + 0.2
		local List, Final = Inputs()
		local Key = Final .. "|" .. WheelVar:GetFloat() .. "|" .. RPMVar:GetFloat()
		for _, G in ipairs( List ) do Key = Key .. "|" .. G.value end
		if Key == LastKey then return end
		LastKey = Key
		ACE.PlotGearChart( Self, List, Final, WheelVar:GetFloat(), RPMVar:GetFloat() )
	end

	if not Table.auto then return end

	-- Upshift speeds: each gear shifts up when the vehicle passes its speed (Shift Speed Scale
	-- multiplies them all at run time).
	local Boxes = {}
	for I = 1, View.Max do
		Boxes[I] = NumberRow( "Gear " .. I .. " upshift (km/h)", S.Shift[I], 0, 2000, 1,
			"Vehicle speed at which gear " .. I .. " shifts up. The top gear's value is not used.",
			function( V ) S.Shift[I] = V SerializeShift( S ) end )
	end
	View.ShiftRows = Boxes
	ShowFirst( Boxes, View.Gears )
	SerializeShift( S )

	local Calc = vgui.Create( "DButton" )
	Calc:SetText( "Set upshift speeds from the chart" )
	Calc:SetTooltip( "Uses the shift RPM, wheel diameter and ratio after this box above." )
	Calc:SetTall( 22 )
	Calc.DoClick = function()
		local List, Final = Inputs()
		for _, G in ipairs( List ) do
			local Kmh = SpeedKmh( RPMVar:GetFloat(), math.abs( G.value * Final ), WheelVar:GetFloat() )
			if IsValid( Boxes[G.gear] ) then Boxes[G.gear].Wang:SetValue( math.Round( Kmh, 1 ) ) end
		end
	end
	AddItem( Calc )
end

-- Differential, clutch and assisted driving. Stored on the gearbox and kept through duplication.
local function CreateSetupPanel( Table, Gears )
	local Family = Table.family
	local HasDiff = Family ~= "clutch" and Family ~= "doublediff" and Family ~= "transfer"
	local HasClutch = Family ~= "diff"

	Header( "SetupHeader", "Drivetrain setup:" )

	if HasDiff then
		local Diff = vgui.Create( "DComboBox" )
		Diff:SetTall( 22 )
		Diff:SetSortItems( false )
		Diff:SetTooltip( "Open: equal torque to both sides, the unloaded side spins.\nLocked: both sides turn together.\nLimited slip: a clutch pack between the sides locks with preload plus a share of the input torque." )
		local Current = GetConVar( "acemenu_gb_diff" ):GetString()
		Diff:AddChoice( "Open differential", "open", Current == "open" )
		Diff:AddChoice( "Locked differential", "locked", Current == "locked" )
		Diff:AddChoice( "Limited slip differential", "lsd", Current == "lsd" )
		Diff.OnSelect = function( _, _, _, Value )
			RunConsoleCommand( "acemenu_gb_diff", Value )
			if ( Value == "lsd" ) ~= ( Current == "lsd" ) then Rebuild() end
		end
		AddItem( Diff )

		if Current == "lsd" then
			Slider( "LSD preload (Nm)", 0, math.max( acemenupanel.GearboxRating or 1, 1 ), 0, GetConVar( "acemenu_gb_lsdpreload" ):GetFloat(),
				"Locking torque the limited slip differential has with no input torque (spring preload).",
				function( V ) RunConsoleCommand( "acemenu_gb_lsdpreload", V ) end )
			Slider( "LSD lock (share of input torque)", 0, 1, 2, GetConVar( "acemenu_gb_lsdramp" ):GetFloat(),
				"How much of the torque going through the differential also locks it (ramp angle). Road cars run about 0.25-0.5.",
				function( V ) RunConsoleCommand( "acemenu_gb_lsdramp", V ) end )
		end
	else
		RunConsoleCommand( "acemenu_gb_diff", "open" )
	end

	if HasClutch then
		Slider( "Clutch strength", 0, 2.5, 1, GetConVar( "acemenu_gb_clutch" ):GetFloat(),
			"Clutch capacity as a multiple of the engine's peak torque.\n"
				.. "0: matched - 1.5x the engine, up to the gearbox rating.\n"
				.. "1.2 to 2.5: custom. Realistic: 1.2-1.5 for cars, 1.5-2 for diesels and trucks.\n"
				.. "The disc must fit the gearbox: one plate carries the gearbox rating,\n"
				.. "a twin plate up to twice it - a small gearbox can't take a big engine's clutch.\n"
				.. "Stronger slips less, but the heavier disc slows shifts and grinds sooner,\n"
				.. "and the gears wear out when it passes more than their rating.",
			function( V )
				V = math.Round( V, 1 )
				if V > 0 and V < 1.2 then V = V < 0.6 and 0 or 1.2 end
				RunConsoleCommand( "acemenu_gb_clutch", V )
			end )

		CheckBox( "Assisted driving", GetConVar( "acemenu_gb_assisted" ):GetBool(),
			"Automatic clutch, no stalling, rev-matched shifts.\nOnly works when the server allows assisted gearboxes.",
			function( V ) RunConsoleCommand( "acemenu_gb_assisted", V and 1 or 0 ) end )
	end

	if Family == "manual" and Gears > 1 then
		CheckBox( "Dual-clutch shifting", GetConVar( "acemenu_gb_dct" ):GetBool(),
			"No torque interruption: the next gear is preselected on a second clutch\nand takes the torque over as the first one opens.",
			function( V ) RunConsoleCommand( "acemenu_gb_dct", V and 1 or 0 ) end )
	end
end

function ACE.GearboxGUICreate( Table )
	local CData = acemenupanel.CData

	acemenupanel:CPanelText( "Name", Table.name, "DermaDefaultBold" )

	CData.DisplayModel = vgui.Create( "DModelPanel", acemenupanel.CustomDisplay )
	CData.DisplayModel:SetModel( Table.model )
	CData.DisplayModel:SetSize( acemenupanel:GetWide(), acemenupanel:GetWide() * 0.5 )
	-- Frame the model: look at its centre from far enough that its bounds fill the view.
	local Ent = CData.DisplayModel:GetEntity()
	if IsValid( Ent ) then
		local Min, Max = Ent:GetRenderBounds()
		local Centre = ( Min + Max ) * 0.5
		local Radius = ( Max - Min ):Length() * 0.5
		CData.DisplayModel:SetFOV( 40 )
		CData.DisplayModel:SetLookAt( Centre )
		CData.DisplayModel:SetCamPos( Centre + Vector( 1, 1, 0.6 ):GetNormalized() * Radius * 2.6 )
	end
	CData.DisplayModel.LayoutEntity = function() end
	AddItem( CData.DisplayModel )

	acemenupanel:CPanelText( "Desc", Table.desc )

	-- Fixed-size items only show up here from old saves; the size block needs a family.
	local Family = Table.scalable and ACE.GearboxSize.Families[Table.family]
	local View = { Gears = Table.gears or 0 }
	View.Max = View.Gears
	if Family then
		View.Max = Family.Fixed or Family.Gears[2]
		View.Gears = CreateSizePanel( Table, Family, View )
	end

	local S = CreateGears( Table, View )
	CreateChart( Table, View, S )
	CreateSetupPanel( Table, View.Gears )

	acemenupanel.CustomDisplay:PerformLayout()
end

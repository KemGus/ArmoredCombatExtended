-- ACE_Graph: a small line-graph panel for menus (engine curves, gear charts).
--
-- Based on the graph from ACF-3's lua/vgui/acf_panel.lua (PANEL:AddGraph),
-- Copyright (c) 2019 Stooberton, MIT License: https://github.com/ACF-Team/ACF-3/blob/master/LICENSE
-- Changes from the original: axis minimums are honoured, PlotLimitLine's vertical flag means
-- a vertical line (it was inverted in ACF-3), sampled series are cached, axes get tick labels,
-- and the hover readout lists every series at the cursor.
--
-- Usage:
--   local Graph = vgui.Create("ACE_Graph")
--   Graph:SetXRange(0, 6000)
--   Graph:SetYRange(0, 500)
--   Graph:PlotLimitFunction("Torque", 800, 6000, Color(255, 80, 80), function(X) return ... end)

local PANEL = {}

local Clamp = math.Clamp
local Round = math.Round
local floor = math.floor
local max   = math.max
local log10 = math.log10

local DefaultColor = Color(255, 0, 255)
local Font         = "DermaDefault"

local MarginLeft   = 40
local MarginRight  = 8
local MarginTop    = 18
local MarginBottom = 30

-- Picks a grid step of 1, 2 or 5 times a power of ten that gives roughly Target divisions.
local function NiceStep(Range, Target)
	if Range <= 0 then return 1 end

	local Raw  = Range / Target
	local Mag  = 10 ^ floor(log10(Raw))
	local Norm = Raw / Mag

	if Norm < 1.5 then
		return Mag
	elseif Norm < 3.5 then
		return 2 * Mag
	elseif Norm < 7.5 then
		return 5 * Mag
	end

	return 10 * Mag
end

local function FormatTick(Value)
	if math.abs(Value) >= 10000 then
		return Round(Value / 1000) .. "k"
	end

	return tostring(Round(Value, 2))
end

local function DefaultFormat(Value)
	return tostring(Round(Value, 1))
end

function PANEL:Init()
	self:SetMouseInputEnabled(true)
	self:SetTall(200)

	self.BGColor   = Color(255, 255, 255)
	self.FGColor   = Color(25, 25, 25)
	self.GridColor = Color(210, 210, 210)

	self.Fidelity = 4
	self.XSpacing = 0
	self.YSpacing = 0
	self.XLabel   = ""
	self.YLabel   = ""
	self.XFormat  = DefaultFormat
	self.ShowLegend = true

	self:SetXRange(0, 100)
	self:SetYRange(0, 100)
	self:Clear()
end

--- Sets the background, foreground (axes and text) and grid colours.
-- @param BG Color Background colour, or nil to keep the current one.
-- @param FG Color Axis and text colour, or nil to keep the current one.
-- @param Grid Color Grid line colour, or nil to keep the current one.
function PANEL:SetColors(BG, FG, Grid)
	self.BGColor   = BG or self.BGColor
	self.FGColor   = FG or self.FGColor
	self.GridColor = Grid or self.GridColor
end

--- Sets how many pixels apart function samples are taken. Lower is smoother.
-- @param Value number Pixels per sample, at least 1.
function PANEL:SetFidelity(Value)
	self.Fidelity = max(1, floor(tonumber(Value) or 4))
	self:InvalidateCache()
end

--- Sets the visible X range.
-- @param Min number Lower bound.
-- @param Max number Upper bound.
function PANEL:SetXRange(Min, Max)
	self.MinX = math.min(Min, Max)
	self.MaxX = math.max(Min, Max)
	self.XRange = max(self.MaxX - self.MinX, 1e-6)
	self:InvalidateCache()
end

--- Sets the visible Y range.
-- @param Min number Lower bound.
-- @param Max number Upper bound.
function PANEL:SetYRange(Min, Max)
	self.MinY = math.min(Min, Max)
	self.MaxY = math.max(Min, Max)
	self.YRange = max(self.MaxY - self.MinY, 1e-6)
	self:InvalidateCache()
end

--- Sets the X grid step. Zero or nil picks a step automatically.
-- @param Spacing number Grid step in X units.
function PANEL:SetXSpacing(Spacing)
	self.XSpacing = math.abs(tonumber(Spacing) or 0)
end

--- Sets the Y grid step. Zero or nil picks a step automatically.
-- @param Spacing number Grid step in Y units.
function PANEL:SetYSpacing(Spacing)
	self.YSpacing = math.abs(tonumber(Spacing) or 0)
end

--- Sets the X axis caption.
-- @param Text string Caption drawn under the X axis.
function PANEL:SetXLabel(Text)
	self.XLabel = Text or ""
end

--- Sets the Y axis caption.
-- @param Text string Caption drawn above the Y axis.
function PANEL:SetYLabel(Text)
	self.YLabel = Text or ""
end

--- Shows or hides the series legend in the top right corner.
-- @param Visible boolean False hides the legend; the hover readout still names every series.
function PANEL:SetLegendVisible(Visible)
	self.ShowLegend = Visible and true or false
end

--- Sets how the X value is written in the hover readout.
-- @param Format function Takes a number and returns a string.
function PANEL:SetXFormat(Format)
	self.XFormat = Format or DefaultFormat
end

-- Series are kept in insertion order so the legend and readout stay stable.
function PANEL:AddSeries(Kind, Label, Data)
	Data.kind  = Kind
	Data.label = Label
	Data.col   = Data.col or DefaultColor
	Data.fmt   = Data.fmt or DefaultFormat

	local List = self.Series

	for I, Entry in ipairs(List) do
		if Entry.label == Label and Entry.kind == Kind then
			List[I] = Data
			self:InvalidateCache()
			return
		end
	end

	List[#List + 1] = Data
	self:InvalidateCache()
end

--- Plots Func(X) across the whole X range.
-- @param Label string Series name, shown in the legend and readout.
-- @param Col Color Line colour.
-- @param Func function Takes X, returns Y.
-- @param Format function Optional; formats the Y value in the readout.
function PANEL:PlotFunction(Label, Col, Func, Format)
	self:AddSeries("func", Label, { func = Func, col = Col, fmt = Format })
end

--- Plots Func(X) between Min and Max only.
-- @param Label string Series name.
-- @param Min number First X value to plot.
-- @param Max number Last X value to plot.
-- @param Col Color Line colour.
-- @param Func function Takes X, returns Y.
-- @param Format function Optional; formats the Y value in the readout.
function PANEL:PlotLimitFunction(Label, Min, Max, Col, Func, Format)
	self:AddSeries("func", Label, { func = Func, min = math.min(Min, Max), max = math.max(Min, Max), col = Col, fmt = Format })
end

--- Plots a sequence of points joined by straight lines.
-- @param Label string Series name.
-- @param Points table Array of { x = X, y = Y }, sorted by X.
-- @param Col Color Line colour.
-- @param Format function Optional; formats the Y value in the readout.
function PANEL:PlotTable(Label, Points, Col, Format)
	self:AddSeries("table", Label, { tbl = Points or {}, col = Col, fmt = Format })
end

--- Marks a single point with a small square and a caption.
-- @param Label string Caption drawn above the point.
-- @param X number X position.
-- @param Y number Y position.
-- @param Col Color Marker colour.
function PANEL:PlotPoint(Label, X, Y, Col)
	self.Points[#self.Points + 1] = { label = Label, x = X, y = Y, col = Col or DefaultColor }
end

--- Draws a straight marker line across the plot.
-- @param Label string Caption drawn next to the line.
-- @param Vertical boolean True for a vertical line at X = Value, false for a horizontal line at Y = Value.
-- @param Value number Position of the line.
-- @param Col Color Line colour.
function PANEL:PlotLimitLine(Label, Vertical, Value, Col)
	self.Lines[#self.Lines + 1] = { label = Label, vertical = Vertical and true or false, val = Value, col = Col or DefaultColor }
end

--- Shades the X interval between Min and Max, for example a powerband.
-- @param Label string Caption drawn inside the band.
-- @param Min number Start of the band.
-- @param Max number End of the band.
-- @param Col Color Fill colour, usually translucent.
function PANEL:PlotBand(Label, Min, Max, Col)
	self.Bands[#self.Bands + 1] = { label = Label, min = math.min(Min, Max), max = math.max(Min, Max), col = Col or DefaultColor }
end

--- Removes every plotted series (functions and tables).
function PANEL:ClearFunctions()
	self.Series = {}
	self:InvalidateCache()
end

--- Removes every marker line.
function PANEL:ClearLimitLines()
	self.Lines = {}
end

--- Removes every marked point.
function PANEL:ClearPoints()
	self.Points = {}
end

--- Removes every shaded band.
function PANEL:ClearBands()
	self.Bands = {}
end

--- Removes every series, point, line and band.
function PANEL:Clear()
	self:ClearFunctions()
	self:ClearLimitLines()
	self:ClearPoints()
	self:ClearBands()
end

function PANEL:InvalidateCache()
	self.Cache = nil
end

function PANEL:PlotArea()
	local W, H = self:GetSize()

	return MarginLeft, MarginTop, max(W - MarginLeft - MarginRight, 1), max(H - MarginTop - MarginBottom, 1)
end

function PANEL:ToScreen(X, Y, PX, PY, PW, PH)
	local SX = PX + (Clamp(X, self.MinX, self.MaxX) - self.MinX) / self.XRange * PW
	local SY = PY + PH - (Clamp(Y, self.MinY, self.MaxY) - self.MinY) / self.YRange * PH

	return SX, SY
end

-- Samples every function series once per size/data change instead of every frame.
function PANEL:BuildCache(PW)
	local Cache = { width = PW }
	local Step  = self.Fidelity / PW * self.XRange

	for I, Series in ipairs(self.Series) do
		if Series.kind == "func" then
			local From = math.max(Series.min or self.MinX, self.MinX)
			local To   = math.min(Series.max or self.MaxX, self.MaxX)
			local Pts  = {}

			if To > From then
				local X = From

				while true do
					local Ok, Y = pcall(Series.func, X)

					Pts[#Pts + 1] = { x = X, y = Ok and tonumber(Y) or 0 }

					if X >= To then break end

					X = math.min(X + Step, To)
				end
			end

			Cache[I] = Pts
		else
			Cache[I] = Series.tbl
		end
	end

	self.Cache = Cache

	return Cache
end

-- Linear lookup of Y at X on a sorted point list.
local function SampleAt(Pts, X)
	local Count = #Pts
	if Count == 0 then return end
	if X < Pts[1].x or X > Pts[Count].x then return end

	for I = 2, Count do
		local A, B = Pts[I - 1], Pts[I]

		if X >= A.x and X <= B.x then
			local Span = B.x - A.x
			if Span <= 0 then return B.y end

			return A.y + (B.y - A.y) * (X - A.x) / Span
		end
	end

	return Pts[Count].y
end

function PANEL:PaintGrid(PX, PY, PW, PH)
	local XStep = self.XSpacing > 0 and self.XSpacing or NiceStep(self.XRange, max(2, floor(PW / 70)))
	local YStep = self.YSpacing > 0 and self.YSpacing or NiceStep(self.YRange, max(2, floor(PH / 30)))
	local FG    = self.FGColor

	surface.SetDrawColor(self.GridColor)

	local X = math.ceil(self.MinX / XStep) * XStep

	while X <= self.MaxX + 1e-6 do
		local SX = self:ToScreen(X, self.MinY, PX, PY, PW, PH)

		surface.DrawLine(SX, PY, SX, PY + PH)
		draw.SimpleText(FormatTick(X), Font, SX, PY + PH + 2, FG, TEXT_ALIGN_CENTER, TEXT_ALIGN_TOP)

		X = X + XStep
	end

	local Y = math.ceil(self.MinY / YStep) * YStep

	while Y <= self.MaxY + 1e-6 do
		local _, SY = self:ToScreen(self.MinX, Y, PX, PY, PW, PH)

		surface.DrawLine(PX, SY, PX + PW, SY)
		draw.SimpleText(FormatTick(Y), Font, PX - 3, SY, FG, TEXT_ALIGN_RIGHT, TEXT_ALIGN_CENTER)

		Y = Y + YStep
	end
end

function PANEL:PaintReadout(PX, PY, PW, PH, Cache)
	local MX, MY = self:CursorPos()

	if MX < PX or MX > PX + PW or MY < PY or MY > PY + PH then return end

	local X = self.MinX + (MX - PX) / PW * self.XRange

	surface.SetDrawColor(self.FGColor.r, self.FGColor.g, self.FGColor.b, 90)
	surface.DrawLine(MX, PY, MX, PY + PH)

	local Rows = { { text = self.XLabel .. ": " .. self.XFormat(X), col = self.FGColor } }

	for I, Series in ipairs(self.Series) do
		local Y = SampleAt(Cache[I] or {}, X)

		if Y then
			local SX, SY = self:ToScreen(X, Y, PX, PY, PW, PH)

			surface.SetDrawColor(Series.col)
			surface.DrawRect(SX - 2, SY - 2, 5, 5)

			Rows[#Rows + 1] = { text = Series.label .. ": " .. Series.fmt(Y), col = Series.col }
		end
	end

	surface.SetFont(Font)

	local BoxW, LineH = 0, 13

	for _, Row in ipairs(Rows) do
		BoxW = max(BoxW, surface.GetTextSize(Row.text))
	end

	BoxW = BoxW + 8

	local BoxH = #Rows * LineH + 4
	local BoxX = MX + 10

	if BoxX + BoxW > PX + PW then
		BoxX = MX - 10 - BoxW
	end

	local BoxY = PY + 2

	surface.SetDrawColor(self.BGColor.r, self.BGColor.g, self.BGColor.b, 230)
	surface.DrawRect(BoxX, BoxY, BoxW, BoxH)
	surface.SetDrawColor(self.FGColor)
	surface.DrawOutlinedRect(BoxX, BoxY, BoxW, BoxH)

	for I, Row in ipairs(Rows) do
		draw.SimpleText(Row.text, Font, BoxX + 4, BoxY + 2 + (I - 1) * LineH, Row.col)
	end
end

function PANEL:Paint(W, H)
	local PX, PY, PW, PH = self:PlotArea()
	local FG = self.FGColor

	surface.SetDrawColor(self.BGColor)
	surface.DrawRect(0, 0, W, H)

	-- Bands sit under everything else
	for _, Band in ipairs(self.Bands) do
		local X1 = self:ToScreen(math.max(Band.min, self.MinX), 0, PX, PY, PW, PH)
		local X2 = self:ToScreen(math.min(Band.max, self.MaxX), 0, PX, PY, PW, PH)

		if X2 > X1 then
			surface.SetDrawColor(Band.col)
			surface.DrawRect(X1, PY, X2 - X1, PH)
			draw.SimpleText(Band.label, Font, (X1 + X2) * 0.5, PY + PH - 2, FG, TEXT_ALIGN_CENTER, TEXT_ALIGN_BOTTOM)
		end
	end

	self:PaintGrid(PX, PY, PW, PH)

	for _, Line in ipairs(self.Lines) do
		surface.SetDrawColor(Line.col)

		if Line.vertical then
			if Line.val >= self.MinX and Line.val <= self.MaxX then
				local SX = self:ToScreen(Line.val, 0, PX, PY, PW, PH)

				surface.DrawLine(SX, PY, SX, PY + PH)
				draw.SimpleText(Line.label, Font, SX + 2, PY + 1, Line.col, TEXT_ALIGN_LEFT, TEXT_ALIGN_TOP)
			end
		elseif Line.val >= self.MinY and Line.val <= self.MaxY then
			local _, SY = self:ToScreen(self.MinX, Line.val, PX, PY, PW, PH)

			surface.DrawLine(PX, SY, PX + PW, SY)
			draw.SimpleText(Line.label, Font, PX + PW - 2, SY - 1, Line.col, TEXT_ALIGN_RIGHT, TEXT_ALIGN_BOTTOM)
		end
	end

	local Cache = self.Cache

	if not Cache or Cache.width ~= PW then
		Cache = self:BuildCache(PW)
	end

	for I, Series in ipairs(self.Series) do
		local Pts = Cache[I]

		if Pts then
			surface.SetDrawColor(Series.col)

			for J = 2, #Pts do
				local X1, Y1 = self:ToScreen(Pts[J - 1].x, Pts[J - 1].y, PX, PY, PW, PH)
				local X2, Y2 = self:ToScreen(Pts[J].x, Pts[J].y, PX, PY, PW, PH)

				surface.DrawLine(X1, Y1, X2, Y2)
				surface.DrawLine(X1, Y1 + 1, X2, Y2 + 1)
			end
		end
	end

	for _, Point in ipairs(self.Points) do
		local SX, SY = self:ToScreen(Point.x, Point.y, PX, PY, PW, PH)

		surface.SetDrawColor(Point.col)
		surface.DrawRect(SX - 3, SY - 3, 7, 7)
		draw.SimpleText(Point.label, Font, SX, SY - 4, Point.col, TEXT_ALIGN_CENTER, TEXT_ALIGN_BOTTOM)
	end

	-- Axes
	surface.SetDrawColor(FG)
	surface.DrawRect(PX - 1, PY, 2, PH + 1)
	surface.DrawRect(PX - 1, PY + PH, PW + 1, 2)

	draw.SimpleText(self.XLabel, Font, PX + PW, H - 1, FG, TEXT_ALIGN_RIGHT, TEXT_ALIGN_BOTTOM)
	draw.SimpleText(self.YLabel, Font, 2, 2, FG, TEXT_ALIGN_LEFT, TEXT_ALIGN_TOP)

	-- Legend, top right
	if self.ShowLegend then
		local LX = PX + PW

		for I = #self.Series, 1, -1 do
			local Series = self.Series[I]
			local TW = draw.SimpleText(Series.label, Font, LX, 2, Series.col, TEXT_ALIGN_RIGHT, TEXT_ALIGN_TOP)

			LX = LX - TW - 10
		end
	end

	if self:IsHovered() then
		self:PaintReadout(PX, PY, PW, PH, Cache)
	end
end

vgui.Register("ACE_Graph", PANEL, "DPanel")

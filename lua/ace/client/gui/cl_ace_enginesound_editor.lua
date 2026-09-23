-- Editor window for engine sound banks, opened from the sound replacer tool.

ACE = ACE or {}
ACE.EngineSound = ACE.EngineSound or {}

local EngineSound = ACE.EngineSound

local Editor -- the open DFrame, if any

local RowHeight = 22

local function SendBanks(Engine, Banks, Reset)
	net.Start("ACE_EngineSound_MenuSet")
	net.WriteEntity(Engine)
	net.WriteBool(Reset)

	if not Reset then
		EngineSound.WriteBanks(Banks)
	end

	net.SendToServer()
end

local function AddNumber(Parent, Tooltip, Min, Max, Decimals, Value, OnChange)
	local Wang = Parent:Add("DNumberWang")
	Wang:Dock(RIGHT)
	Wang:DockMargin(2, 0, 0, 0)
	Wang:SetWide(56)
	Wang:SetMinMax(Min, Max)
	Wang:SetDecimals(Decimals)
	Wang:SetValue(Value)
	Wang:SetTooltip(Tooltip)
	Wang.OnValueChanged = function(_, New)
		OnChange(tonumber(New) or Value)
	end

	return Wang
end

local function AddButton(Parent, Text, Icon, Tooltip, OnClick)
	local Button = Parent:Add("DButton")
	Button:SetText(Text)
	Button:SetTooltip(Tooltip)
	Button.DoClick = OnClick

	if Icon then
		Button:SetIcon(Icon)
	end

	return Button
end

local function BuildSoundRow(List, Bank, Index, Rebuild)
	local Snd = Bank.Sounds[Index]
	local Row = List:Add("DPanel")
	Row:Dock(TOP)
	Row:DockMargin(0, 0, 0, 2)
	Row:SetTall(RowHeight)
	Row:SetPaintBackground(false)

	local Remove = AddButton(Row, "", "icon16/cross.png", "Remove this sound", function()
		table.remove(Bank.Sounds, Index)
		Rebuild()
	end)
	Remove:Dock(RIGHT)
	Remove:SetWide(RowHeight)

	local Play = AddButton(Row, "", "icon16/sound.png", "Preview this sound", function()
		if Snd.Path ~= "" then
			surface.PlaySound(Snd.Path)
		end
	end)
	Play:Dock(RIGHT)
	Play:SetWide(RowHeight)

	AddNumber(Row, "Crossfade width: how many neighbouring sounds this one fades across (0 = only the next one)", 0, EngineSound.MaxWidth, 0, Snd.Width, function(V) Snd.Width = math.Round(V) end)
	AddNumber(Row, "Volume (0-2)", 0, EngineSound.MaxVolume, 2, Snd.Volume, function(V) Snd.Volume = V end)
	AddNumber(Row, "Pitch at the recorded RPM (100 = unchanged)", 1, 255, 0, Snd.Pitch, function(V) Snd.Pitch = math.Round(V) end)
	AddNumber(Row, "RPM the sound was recorded at", 1, EngineSound.MaxRPM, 0, Snd.RPM, function(V) Snd.RPM = math.Round(V) end)

	local UseSelected = AddButton(Row, "", "icon16/arrow_left.png", "Use the sound selected in the sound browser", nil)
	UseSelected:Dock(RIGHT)
	UseSelected:SetWide(RowHeight)

	local Path = Row:Add("DTextEntry")
	Path:Dock(FILL)
	Path:SetValue(Snd.Path)
	Path:SetPlaceholderText("path/to/sound.wav")
	Path.OnChange = function(Self)
		Snd.Path = Self:GetValue()
	end

	UseSelected.DoClick = function()
		local Selected = GetConVar("wire_soundemitter_sound")
		local Value = Selected and Selected:GetString() or ""

		if Value ~= "" then
			Snd.Path = Value
			Path:SetValue(Value)
		end
	end
end

local function BuildBank(Scroll, Banks, BankIndex, Rebuild)
	local Bank = Banks[BankIndex]

	local Panel = Scroll:Add("DPanel")
	Panel:Dock(TOP)
	Panel:DockMargin(0, 0, 0, 6)
	Panel:DockPadding(4, 4, 4, 4)

	local Header = Panel:Add("DPanel")
	Header:Dock(TOP)
	Header:SetTall(RowHeight)
	Header:SetPaintBackground(false)

	local Title = Header:Add("DLabel")
	Title:Dock(LEFT)
	Title:SetDark(true)
	Title:SetFont("DermaDefaultBold")
	Title:SetText("Bank " .. BankIndex)
	Title:SizeToContentsX(12)

	local Exhaust = Header:Add("DCheckBoxLabel")
	Exhaust:Dock(LEFT)
	Exhaust:DockMargin(8, 4, 0, 0)
	Exhaust:SetText("Play at exhaust")
	Exhaust:SetDark(true)
	Exhaust:SetValue(Bank.Exhaust)
	Exhaust:SetTooltip("Play this bank from the entity wired to the engine's Exhaust input")
	Exhaust:SizeToContents()
	Exhaust.OnChange = function(_, Value) Bank.Exhaust = Value end

	local RemoveBank = AddButton(Header, "Remove bank", "icon16/delete.png", nil, function()
		table.remove(Banks, BankIndex)
		Rebuild()
	end)
	RemoveBank:Dock(RIGHT)
	RemoveBank:SetWide(100)

	local function AddVolumeSlider(Text, Key, Tooltip)
		local Slider = Panel:Add("DNumSlider")
		Slider:Dock(TOP)
		Slider:SetTall(RowHeight)
		Slider:SetText(Text)
		Slider:SetDark(true)
		Slider:SetMinMax(0, 1)
		Slider:SetDecimals(2)
		Slider:SetValue(Bank[Key])
		Slider:SetTooltip(Tooltip)
		Slider.OnValueChanged = function(_, Value) Bank[Key] = Value end
	end

	AddVolumeSlider("Off-throttle volume", "OffVolume", "Bank volume with the throttle closed")
	AddVolumeSlider("On-throttle volume", "OnVolume", "Bank volume at full throttle")

	local Columns = Panel:Add("DLabel")
	Columns:Dock(TOP)
	Columns:SetDark(true)
	Columns:SetTall(16)
	Columns:SetText("Sound path  |  RPM  |  Pitch  |  Volume  |  Width")

	local List = Panel:Add("DPanel")
	List:Dock(TOP)
	List:SetPaintBackground(false)

	for I = 1, #Bank.Sounds do
		BuildSoundRow(List, Bank, I, Rebuild)
	end

	List:SetTall(#Bank.Sounds * (RowHeight + 2))

	local AddSound = AddButton(Panel, "Add sound", "icon16/add.png", nil, function()
		if #Bank.Sounds >= EngineSound.MaxSounds then return end

		local Last = Bank.Sounds[#Bank.Sounds]

		Bank.Sounds[#Bank.Sounds + 1] = { Path = "", RPM = Last and Last.RPM + 1000 or 1000, Pitch = 100, Volume = 1, Width = 0 }
		Rebuild()
	end)
	AddSound:Dock(TOP)
	AddSound:SetEnabled(#Bank.Sounds < EngineSound.MaxSounds)

	-- padding + header + two sliders + column captions + rows + add button
	Panel:SetTall(8 + RowHeight * 3 + 16 + List:GetTall() + RowHeight + 4)
end

--- Opens the sound bank editor with data sent by the server.
-- @param Engine Entity The engine being edited.
-- @param IsLegacy boolean True if the engine currently uses its single sound.
-- @param IdleRPM number Engine idle RPM, shown as a hint.
-- @param LimitRPM number Engine redline, shown as a hint.
-- @param Banks table Current banks, or a single bank made from the legacy sound.
function EngineSound.OpenEditor(Engine, IsLegacy, IdleRPM, LimitRPM, Banks)
	if IsValid(Editor) then
		Editor:Remove()
	end

	Banks = table.Copy(Banks or {})

	local Frame = vgui.Create("DFrame")
	Frame:SetTitle("Engine sound banks")
	Frame:SetSize(math.min(760, ScrW() - 40), math.min(560, ScrH() - 40))
	Frame:Center()
	Frame:MakePopup()
	Frame:SetSizable(true)
	Editor = Frame

	local Info = Frame:Add("DLabel")
	Info:Dock(TOP)
	Info:SetTall(34)
	Info:SetWrap(true)
	Info:SetText(("Idle %d RPM, redline %d RPM. %s Each sound is pitched by RPM / recorded RPM and crossfaded with its neighbours. Up to %d banks of %d sounds.")
		:format(IdleRPM, LimitRPM, IsLegacy and "The engine uses its single sound; applying switches it to banks." or "", EngineSound.MaxBanks, EngineSound.MaxSounds))

	local Footer = Frame:Add("DPanel")
	Footer:Dock(BOTTOM)
	Footer:SetTall(RowHeight + 4)
	Footer:SetPaintBackground(false)

	local Scroll = Frame:Add("DScrollPanel")
	Scroll:Dock(FILL)
	Scroll:DockMargin(0, 4, 0, 4)

	local AddBank

	local function Rebuild()
		Scroll:Clear()

		for I = 1, #Banks do
			BuildBank(Scroll, Banks, I, Rebuild)
		end

		if IsValid(AddBank) then
			AddBank:SetEnabled(#Banks < EngineSound.MaxBanks)
		end
	end

	AddBank = AddButton(Footer, "Add bank", "icon16/add.png", nil, function()
		if #Banks >= EngineSound.MaxBanks then return end

		Banks[#Banks + 1] = { Exhaust = false, OffVolume = 0.25, OnVolume = 1, Sounds = { { Path = "", RPM = IdleRPM > 0 and IdleRPM or 1000, Pitch = 100, Volume = 1, Width = 0 } } }
		Rebuild()
	end)
	AddBank:Dock(LEFT)
	AddBank:SetWide(110)

	local Reset = AddButton(Footer, "Use single sound", "icon16/arrow_undo.png", "Remove all banks and go back to the engine's single sound", function()
		if IsValid(Engine) then
			SendBanks(Engine, nil, true)
		end

		Frame:Close()
	end)
	Reset:Dock(LEFT)
	Reset:DockMargin(4, 0, 0, 0)
	Reset:SetWide(130)

	local Apply = AddButton(Footer, "Apply to engine", "icon16/accept.png", nil, function()
		if not IsValid(Engine) then return end

		local Clean = EngineSound.SanitizeBanks(Banks)

		if not Clean then
			Derma_Message("Add at least one sound with a valid path first.", "Engine sound banks", "OK")
			return
		end

		SendBanks(Engine, Clean, false)
	end)
	Apply:Dock(RIGHT)
	Apply:SetWide(130)

	Rebuild()
end

--- Asks the server for an engine's banks; the editor opens when they arrive.
-- @param Engine Entity The acf_engine to edit.
function EngineSound.RequestEditor(Engine)
	if not IsValid(Engine) then return end

	net.Start("ACE_EngineSound_MenuGet")
	net.WriteEntity(Engine)
	net.SendToServer()
end

net.Receive("ACE_EngineSound_MenuData", function()
	local Engine   = net.ReadEntity()
	local IsLegacy = net.ReadBool()
	local IdleRPM  = net.ReadUInt(16)
	local LimitRPM = net.ReadUInt(16)
	local Banks    = EngineSound.ReadBanks() or {}

	if not IsValid(Engine) then return end

	EngineSound.OpenEditor(Engine, IsLegacy, IdleRPM, LimitRPM, Banks)
end)

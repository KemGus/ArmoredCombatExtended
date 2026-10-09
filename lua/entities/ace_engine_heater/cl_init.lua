include("shared.lua")

local ACE_ToolInfoWhileSeated = GetConVar("ace_tool_info_while_seated") or CreateClientConVar("ace_tool_info_while_seated", 0, true, false)

function ENT:Draw()
	local Ply = LocalPlayer()
	local HideBubble = not ACE_ToolInfoWhileSeated:GetBool() and IsValid(Ply) and Ply:InVehicle()

	self.BaseClass.DoNormalDraw(self, false, HideBubble)
	Wire_Render(self)
end

--- Menu page for an engine heater definition.
-- @param Table table Heater definition (lua/ace/shared/tools/engine_heaters.lua).
function ACE.EngineHeaterGUICreate(Table)
	acemenupanel:CPanelText("Name", Table.name, "DermaDefaultBold")
	acemenupanel:CPanelText("Desc", Table.desc)
	acemenupanel:CPanelText("Weight", "Weight: " .. Table.weight .. " kg")
	acemenupanel:CPanelText("Usage", "Link it to an engine with the menu tool. Wire Active to 1 (or leave it unwired: it is on by default) a few minutes before starting in the cold. It keeps the coolant between about 65 and 75 °C and shuts off on its own.")
	acemenupanel.CustomDisplay:PerformLayout()
end

-- Spawn menu > Utilities > ACE > Small Arms. The settings are server-wide, so only the host
-- (or an admin through the console) can change them; everyone else sees the current values.
local function BuildPanel(Panel)
	Panel:ClearControls()
	Panel:Help("Makes weapon packs fire ACE bullets, so they penetrate and get stopped by ACE armor.")

	Panel:CheckBox("Enabled", "ace_smallarms_enabled")
	Panel:ControlHelp("Off: every gun fires its normal bullets again.")

	local Combo = Panel:ComboBox("Damage to players and NPCs")
	Combo:AddChoice("Weapon pack damage", "pack", ACE.SmallArms.DamageMode:GetString() ~= "ace")
	Combo:AddChoice("ACE physics damage", "ace", ACE.SmallArms.DamageMode:GetString() == "ace")
	function Combo:OnSelect(_, _, Value)
		RunConsoleCommand("ace_smallarms_damage", Value)
	end
	Panel:ControlHelp("Pack: each gun keeps its own damage. ACE: damage comes from caliber and bullet energy. Armor and cover are always ACE either way.")

	Panel:Help("Your own settings:")
	Panel:CheckBox("Show round stats when drawing a gun", "ace_smallarms_showstats")
	Panel:ControlHelp("Pops up caliber, muzzle velocity and penetration, like ACE's own weapons.")
end

hook.Add("PopulateToolMenu", "ACE_SmallArms_Options", function()
	spawnmenu.AddToolMenuOption("Utilities", "ACE", "ACE_SmallArms", "Small Arms", "", "", BuildPanel)
end)

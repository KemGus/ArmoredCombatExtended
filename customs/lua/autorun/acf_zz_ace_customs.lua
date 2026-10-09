--[[
	ACE Customs: the mobility rework (drivetrain, engines, cooling, heaters, sounds) as an
	addition to ACE Canary. Built by tools/customs/build_customs.py from the mobility-realism
	branch; nothing here edits ACE's own files.

	Runs after ACE's autorun (acf_globals.lua sorts before this file) and then:
	  - applies the small hand patches in ace_customs/patches/ (globals, loader, server base),
	  - re-runs Customs' versions of the shared ACE files it changes (ace_customs/override/),
	  - swaps in Customs' acf_engine, acf_gearbox, acf_fueltank and torch as GMod registers
	    them (PreRegisterSENT / PreRegisterSWEP), and its acemenu and acesound tools
	    (PreRegisterTOOL). Class names stay the same, so dupes paste with or without Customs.
]]
AddCSLuaFile()

if not ACE or not ACE.DefineEngine or not ACE.Weapons then
	ErrorNoHalt("[ACE Customs] ACE was not found. ACE Customs needs ACE Canary Edition installed.\n")
	return
end

ACE.Customs = { Loaded = true }

local Override = "ace_customs/override/"
local Patches  = "ace_customs/patches/"

-- Sends every client-side Customs file once, so the hooks below can include them on clients.
if SERVER then
	local function SendFolder(Folder)
		local Files, Folders = file.Find(Folder .. "*", "LUA")
		for _, Name in ipairs(Files) do
			local Path = Folder .. Name
			local ServerOnly = string.find(Path, "/server/", 1, true)
				or string.find(Path, "starfall/libs_sv/", 1, true)
				or (string.find(Path, "/entities/", 1, true) and Name == "init.lua")
			if not ServerOnly and string.EndsWith(Name, ".lua") then AddCSLuaFile(Path) end
		end
		for _, Sub in ipairs(Folders) do SendFolder(Folder .. Sub .. "/") end
	end
	SendFolder("ace_customs/")
end

local function Shared(Path) include(Path) end
local function Server(Path) if SERVER then include(Path) end end

-- The same order as the branch's acf_globals.lua.
Shared(Patches .. "sh_globals.lua")
Shared(Override .. "ace/shared/sh_ace_functions.lua")
if SERVER then AddCSLuaFile("ace/shared/mobility/sh_mobility.lua") end
Shared("ace/shared/mobility/sh_mobility.lua")
Shared(Patches .. "sh_loader.lua")

Server(Patches .. "sv_acfbase.lua")
Server(Override .. "ace/server/sv_heat.lua")
Server("ace/server/sv_mobility.lua")
Server("ace/server/sv_mobility_log.lua")
Server(Override .. "ace/server/sv_adminsettings.lua")

-- Customs' menu GUI (override/ace/client/cl_acemenu_gui.lua) is a vgui panel file: Customs'
-- acemenu tool registers it with vgui.RegisterFile when its panel is built.

-- Entities and weapons: Customs' version replaces ACE's as GMod registers the class.
-- t is the table GMod is about to register; it is refilled in place from Customs' files.
local function Refill(t, Global, Dir, ServerFile, ClientFile)
	local Folder = t.Folder
	for Key in pairs(t) do t[Key] = nil end
	t.Folder = Folder
	-- GMod starts every SWEP table with these before including its files.
	if Global == "SWEP" then
		t.Primary   = {}
		t.Secondary = {}
	end

	local Old = _G[Global]
	_G[Global] = t
	if SERVER then
		include(Dir .. (file.Exists(Dir .. ServerFile, "LUA") and ServerFile or "shared.lua"))
	else
		include(Dir .. (file.Exists(Dir .. ClientFile, "LUA") and ClientFile or "shared.lua"))
	end
	_G[Global] = Old
end

local Entities = { acf_engine = true, acf_gearbox = true, acf_fueltank = true }
hook.Add("PreRegisterSENT", "ACE_Customs", function(t, Class)
	if not Entities[Class] then return end
	Refill(t, "ENT", Override .. "entities/" .. Class .. "/", "init.lua", "cl_init.lua")
end)

local Weapons = { weapon_ace_torch = true }
hook.Add("PreRegisterSWEP", "ACE_Customs", function(t, Class)
	if not Weapons[Class] then return end
	Refill(t, "SWEP", Override .. "weapons/" .. Class .. "/", "init.lua", "cl_init.lua")
end)

-- Sandbox registers the global TOOL after this hook, so a fresh tool object built from
-- Customs' file takes the old one's place.
local Tools = { acemenu = true, acesound = true }
hook.Add("PreRegisterTOOL", "ACE_Customs", function(_, Mode)
	if not Tools[Mode] or not ToolObj then return end
	TOOL = ToolObj:Create()
	TOOL.Mode = Mode
	include(Override .. "weapons/gmod_tool/stools/" .. Mode .. ".lua")
	TOOL:CreateConVars()
end)

-- Starfall: swap the server acf library module for Customs' version once Starfall has
-- loaded its modules (its Initialize hook).
if SERVER then
	hook.Add("InitPostEntity", "ACE_Customs_Starfall", function()
		local Path = "starfall/libs_sv/acf.lua"
		local Module = SF and SF.Modules and SF.Modules.acf and SF.Modules.acf[Path]
		if not Module then return end
		local Compiled = CompileFile(Override .. Path)
		-- The module registers ACF's privileges again; Starfall's reload flag allows that.
		local Reloading = SF.ReloadingLibrary
		SF.ReloadingLibrary = true
		local Init = Compiled and Compiled()
		SF.ReloadingLibrary = Reloading
		if Init then Module.init = Init end
	end)
end

print("[ACE Customs] Loaded.")

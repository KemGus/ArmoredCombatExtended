-- Loads the mobility menu graphs, the link preview and the engine sound system.
AddCSLuaFile()

ACE = ACE or {}

if SERVER then
	AddCSLuaFile("ace/shared/sh_ace_engine_sounds.lua")
	AddCSLuaFile("ace/client/cl_ace_engine_sounds.lua")
	AddCSLuaFile("ace/client/cl_ace_linkvis.lua")
	AddCSLuaFile("ace/client/gui/cl_ace_graph.lua")
	AddCSLuaFile("ace/client/gui/cl_ace_enginesound_editor.lua")
end

include("ace/shared/sh_ace_engine_sounds.lua")

if SERVER then
	include("ace/server/sv_ace_engine_sounds.lua")
else
	include("ace/client/cl_ace_engine_sounds.lua")
	include("ace/client/cl_ace_linkvis.lua")
	include("ace/client/gui/cl_ace_graph.lua")
	include("ace/client/gui/cl_ace_enginesound_editor.lua")
end

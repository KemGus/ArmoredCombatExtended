-- Loads the drivetrain modules on both realms. The server runs the physics; the client uses
-- the engine model for menu graphs.

local Files = {
	"units.lua",
	"engine_model.lua",
	"solver.lua",
	"torque_converter.lua",
	"drivetrain.lua",
	"vehicle.lua",
}

for _, Name in ipairs(Files) do
	local Path = "ace/shared/mobility/" .. Name
	if SERVER then AddCSLuaFile(Path) end
	include(Path)
end

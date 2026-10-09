-- ACE Customs: what the mobility branch changes in ACE's lua/ace/shared/sh_ace_loader.lua,
-- plus its definition additions to ACE's ammocrates.lua and fueltanks/basic.lua. ACE's
-- loader has already run; this adds the new definition types, recomputes engine
-- performance with the new torque curves and re-runs the engine definitions.

local Mobility = ACE.Weapons.Mobility

local radiator_base = {
	ent    = "ace_radiator",
	type   = "Radiators"
}
local engine_heater_base = {
	ent    = "ace_engine_heater",
	type   = "EngineHeaters"
}

if CLIENT then
	radiator_base.guicreate      = function( _, tbl ) ACE.RadiatorGUICreate( tbl ) end
	radiator_base.guiupdate      = function( _, tbl ) ACE.RadiatorGUIUpdate( tbl ) end

	engine_heater_base.guicreate = function( _, tbl ) ACE.EngineHeaterGUICreate( tbl ) end
	engine_heater_base.guiupdate = function() return end
end

ACE.Weapons.Radiators     = ACE.Weapons.Radiators or {}
ACE.Weapons.EngineHeaters = ACE.Weapons.EngineHeaters or {}

--- Defines a radiator (entities/ace_radiator).
-- @param id string Radiator id.
-- @param data table Definition: name, desc.
function ACE.DefineRadiator( id, data )
	data.id = id
	table.Inherit( data, radiator_base )
	ACE.Weapons.Radiators[ id ] = data
	Mobility[ id ] = data
end

--- Defines an engine heater (entities/ace_engine_heater).
-- @param id string Heater id.
-- @param data table Definition: name, desc, model, weight, heatw (W), fuelkgh (kg/h), elecw (W).
function ACE.DefineEngineHeater( id, data )
	data.id = id
	table.Inherit( data, engine_heater_base )
	ACE.Weapons.EngineHeaters[ id ] = data
end

-- Engine performance from the per-type torque curves (ACE.GetEngineTorqueCurve).
local DefineEngine = ACE.Customs.DefineEngine or ACE.DefineEngine
ACE.Customs.DefineEngine = DefineEngine

function ACE.DefineEngine( id, data )
	DefineEngine( id, data )
	if ACE.Weapons.Engines[ id ] ~= data then return end

	local engineData = ACE.CalcEnginePerformanceData(ACE.GetEngineTorqueCurve(data), data.torque, data.idlerpm, data.limitrpm, data.fuel)

	data.peaktqrpm    = engineData.peakTqRPM
	data.peakpower    = engineData.peakPower
	data.peakpowerrpm = engineData.peakPowerRPM
	data.peakminrpm   = engineData.powerbandMinRPM
	data.peakmaxrpm   = engineData.powerbandMaxRPM
	data.curvefactor  = (data.limitrpm - data.idlerpm) / data.limitrpm
end

-- Engines: Customs' version of each definition file where it has one, ACE's otherwise, in
-- the loader's order (ace_engine_properties.lua first).
for _, Name in ipairs( file.Find( "ace/shared/engines/*.lua", "LUA" ) ) do
	local Path = "ace_customs/override/ace/shared/engines/" .. Name
	include( file.Exists( Path, "LUA" ) and Path or "ace/shared/engines/" .. Name )
end

--Radiator. DefaultSize has issues with 3d vectors. Using external scaling for now.
ACE.DefineModelData("Radiator",{

	Shape = "Radiator",
	Model = "models/radiators/radiator_med.mdl", --Note: The model can be used as ID if needed.
	physMaterial = "metal",
	DefaultSize = 1, --Maybe later make scalable models support 3d hitboxes? Until then cope with it.
	CustomMesh = { --Its a box anyways
		{
			Vector(17.8875, 2.25, 11.25),
			Vector(17.8875, -2.25, 11.25),
			Vector(-17.8875, 2.25, 11.25),
			Vector(-17.8875, -2.25, 11.25),
			Vector(17.8875, 2.25, -11.25),
			Vector(17.8875, -2.25, -11.25),
			Vector(-17.8875, 2.25, -11.25),
			Vector(-17.8875, -2.25, -11.25)
		},
	},
	volumefunction = function( L, W, H )
		local volume = L * W * H
		return volume
	end
})

-- Radiator definition shown in the menu
ACE.DefineRadiator( "Basic_Radiator", {
	name = "Radiator",
	desc = "Basic Radiator for cooling engines"
} )

-- New definition files, kept out of the folders ACE's loader scans so they load after the
-- definition functions above exist.
for _, Name in ipairs( file.Find( "ace_customs/defs/*.lua", "LUA" ) ) do
	include( "ace_customs/defs/" .. Name )
end

-- ACE Customs: what the mobility branch changes in ACE's lua/autorun/acf_globals.lua.

ACE.ThermalTimeScale    = 2                         -- How many times faster than real time heat moves. Live value of ace_heat_timescale or this map's saved value, kept current by sv_heat.lua.
ACE.RadiatorEff         = 0.125                     -- Multiplier for radiator cooling effectiveness
ACE.RadiatorHeatCap     = 0.2                       -- Multiplier for radiator specific heat cap. Makes radiators more or less effective at storing energy
ACE.ElecRate            = 3                         -- multiplier for electrics

-- Engines with a linked exhaust entity puff smoke from it (drawn on clients; each client can
-- also turn it off locally with ace_exhaust_smoke_draw).
CreateConVar("ace_exhaust_smoke", 1, bit.bor(FCVAR_ARCHIVE, FCVAR_REPLICATED), "Allow exhaust smoke from engines with a linked exhaust entity.", 0, 1)

if SERVER then
	util.AddNetworkString( "ACE_HeatSettings" )
else
	-- Engine and drivetrain hints in chat (ACE.SendEngineHint reads it on the server).
	CreateClientConVar("ace_engine_hints", "1", true, true, "Show ACE engine and drivetrain hints in chat.", 0, 1)
end

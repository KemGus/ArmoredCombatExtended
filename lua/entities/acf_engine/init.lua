-- init.lua

AddCSLuaFile( "shared.lua" )
AddCSLuaFile( "cl_init.lua" )

include("shared.lua")

do

	local EngineWireDescs = {
		--Inputs
		["Throttle"]    = "Controls the amount of fuel which will be displaced to the engine.\n Increasing it will also increase RPM, Power and fuel consumption. Values go from 0-100.\n Electric motors also take -100 to 0: regenerative braking strength, 0 is none and -100 is full.",
		["Exhaust"]     = "Optional exhaust entity: sound banks marked 'Play at exhaust' play from it, and exhaust smoke comes out along its forward axis.",
		["Reverse"]     = "Electric motors only: 1 drives the motor backwards, so a vehicle can reverse without a reverse gear. Switched while moving, the motor is braked to a stop first, charging the battery, and then driven the other way.",

		--Outputs
		["RPM"]         = "Returns the current RPM.",
		["Torque"]      = "Returns the current Torque.",
		["Power"]       = "Returns the current power of this engine.",
		["Fuel Use"]    = "Gives the actual fuel consumption of the engine.",
		["EngineHeat"]  = "Coolant temperature in °C. The thermostat opens at about 82 °C and the coolant boils at 120 °C. Air-cooled engines: the oil.",
		["Oil Temp"]    = "Sump oil temperature in °C, 0 for electric motors. Cold oil raises friction; past about 150 °C it wears the engine.",
		["Block Temp"]  = "Engine metal temperature, block and head, in °C. Hot metal costs torque and past about 200 °C wears the engine. Air-cooled engines: cylinder heads, limit 260 °C.",
		["Stalled"]     = "1 when the engine has stalled. Cycle Active to crank it again."
	}

	function ENT:Initialize()

		self.Throttle       = 0
		self.Active         = false
		self.IsMaster       = true
		self.GearLink       = {} -- a "Link" has these components: Ent, Rope, RopeLen, ReqTq
		self.FuelLink       = {}
		self.RadLink       = {}
		self.BatteryLink    = {} -- batteries feeding a combustion engine's starter
		self.HeaterLink     = {} -- coolant heaters (entities/ace_engine_heater)
		self.StarterSize    = 1  -- starter setup (ENT:SetStarterSetup)
		self.StarterExtraKg = 0
		self.OTWarnings		= {} --Used to remember all the one time warnings.

		self.NextUpdate     = 0
		self.LastThink      = 0
		self.MassRatio      = 1
		self.FuelTank       = 0
		self.Heat           = ACE.AmbientTemp
		self.TotalFuel      = 0
		self.Legal          = true
		self.CanUpdate      = true
		self.RequiresDriver = false
		self.NextLegalCheck = ACE.CurTime + math.random(ACE.Legal.Min, ACE.Legal.Max) -- give any spawning issues time to iron themselves out
		self.Legal          = true
		self.LegalIssues    = ""
		self.LockOnActive   = false --used to turn on the engine in case of being lockdown by not legal
		self.CrewLink       = {}
		self.HasDriver      = false
		self.HasFuel		= false
		self.HasSeatDriver = false
		self.CanUseSeatDriver = false
		self.SeatDriverEnt = nil

		self.HeatGeneration = 0 --Heat generated per second

		self.LastFuel = nil

		self.ThermalSurfaceArea = 0.1 --In m^2

		self.LastDamageTime = CurTime()

		self.Inputs = WireLib.CreateSpecialInputs( self, ACE.EngineInputs(false) )
		self.Outputs = WireLib.CreateSpecialOutputs( self,  { "RPM (" .. EngineWireDescs["RPM"] .. ")", "Torque (" .. EngineWireDescs["Torque"] .. ")", "Power (" .. EngineWireDescs["Power"] .. ")", "Fuel Use (" .. EngineWireDescs["Fuel Use"] .. ")", "Total Fuel" , "Entity", "Mass", "Physical Mass" , "EngineHeat (" .. EngineWireDescs["EngineHeat"] .. ")", "Stalled (" .. EngineWireDescs["Stalled"] .. ")",
														"Oil Temp (" .. EngineWireDescs["Oil Temp"] .. ")", "Block Temp (" .. EngineWireDescs["Block Temp"] .. ")" },
														{ "NORMAL","NORMAL","NORMAL", "NORMAL", "NORMAL", "ENTITY", "NORMAL", "NORMAL", "NORMAL", "NORMAL", "NORMAL", "NORMAL", "NORMAL" } )

		Wire_TriggerOutput( self, "Entity", self )
		Wire_TriggerOutput(self, "EngineHeat", self.Heat)
		Wire_TriggerOutput(self, "Block Temp", self.Heat)

		self.WireDebugName = "ACF Engine"

		self.CanLegalCheck = true

	end

	--- Wire inputs of an engine; electric motors add Reverse.
	-- @param Electric boolean Whether the engine is an electric motor.
	-- @return table Names, table Types.
	function ACE.EngineInputs(Electric)
		local Names = { "Active", "Throttle (" .. EngineWireDescs["Throttle"] .. ")", "Exhaust (" .. EngineWireDescs["Exhaust"] .. ")" }
		local Types = { "NORMAL", "NORMAL", "ENTITY" }
		if Electric then
			Names[#Names + 1] = "Reverse (" .. EngineWireDescs["Reverse"] .. ")"
			Types[#Types + 1] = "NORMAL"
		end
		return Names, Types
	end

end

-- The rest of the engine lives next to this file, split by concern.
include("sv_engine_spawn.lua")
include("sv_engine_wire.lua")
include("sv_engine_crew.lua")
include("sv_engine_think.lua")
include("sv_engine_starter.lua")
include("sv_engine_fuel.lua")
include("sv_engine_links.lua")
include("sv_engine_dupe.lua")

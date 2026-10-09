--[[
	Engine heaters: fuel-fired coolant heaters (parking heaters) that warm a cold engine before
	it is started. They burn fuel from the engine's own tanks, run their fan, pump and glow pin
	off the engine's starter battery, and pump the engine's coolant through their own heat
	exchanger. Linked to an engine with the ACE menu tool (entities/ace_engine_heater).

	heatw: heat output at full (boost) power [W]. fuelkgh: fuel burned at that power [kg/h].
	elecw: electrical power drawn [W]. weight: kg.
	rapidk: a gameplay preheater with no real counterpart: it warms the linked engine's metal,
	  coolant and oil together by rapidk °C per real second whatever its size, and burns fuel
	  for that heat at the large heater's efficiency. No real heater warms an engine this fast.

	Small - Webasto Thermo Pro 90 (published specifications, webasto-group.com): 9.1 kW boost,
	  1.1 l/h of diesel at boost (0.92 kg/h at 0.84 kg/l), 7.3 A at 12 V (88 W) at boost, 4.9 kg.
	Large - Webasto Thermo E+ 320 (published specifications, webasto-group.com): 32 kW,
	  3.2 kg/h, 214 W, 19.4 kg.
]]

ACE.DefineEngineHeater("Heater_Small", {
	name      = "Coolant Heater - 9 kW",
	desc      = "Fuel-fired coolant heater for car and light vehicle engines. Link it to an engine; while switched on it burns fuel from the engine's tanks and draws power from its starter battery to warm the coolant, so the engine starts in the cold.\n\nHeat: 9.1 kW\nFuel: 0.92 kg/h\nPower: 88 W",
	model     = "models/hunter/blocks/cube025x025x025.mdl",
	weight    = 4.9,
	heatw     = 9100,
	fuelkgh   = 0.92,
	elecw     = 88,
	acepoints = 5,
})

ACE.DefineEngineHeater("Heater_Large", {
	name      = "Coolant Heater - 32 kW",
	desc      = "Fuel-fired coolant heater for truck, tank and other large diesel engines. Link it to an engine; while switched on it burns fuel from the engine's tanks and draws power from its starter battery to warm the coolant, so the engine starts in the cold.\n\nHeat: 32 kW\nFuel: 3.2 kg/h\nPower: 214 W",
	model     = "models/hunter/blocks/cube025x05x025.mdl",
	weight    = 19.4,
	heatw     = 32000,
	fuelkgh   = 3.2,
	elecw     = 214,
	acepoints = 10,
})

ACE.DefineEngineHeater("Heater_Rapid", {
	name      = "Rapid Preheater",
	desc      = "Gameplay preheater: no real heater is this fast. Warms the whole engine - metal, coolant and oil - by about 8 °C a second, so any piston engine starts within about 6 seconds at -20 °C (9 at -30). Burns fuel from the engine's tanks for all that heat and draws 500 W from the starter battery.",
	model     = "models/hunter/blocks/cube05x05x025.mdl",
	weight    = 40,
	rapidk    = 8,
	elecw     = 500,
	acepoints = 15,
})


-- Flat 4 engines

ACE.DefineEngine( "1.4-B4", {
	name = "1.4L Flat 4 Petrol",
	desc = "Small air cooled flat four, most commonly found in nazi insects.",
	model = "models/engines/b4small.mdl",
	sound = "acf_engines/b4_petrolsmall.wav",
	category = "B4",
	fuel = "Petrol",
	enginetype = "B4",
	weight = 30,
	torque = 148,
	flywheelmass = 0.06,
	idlerpm = 600,
	limitrpm = 6500
} )

ACE.DefineEngine( "1.7-B4", {
	name = "1.7L Flat 4 Multifuel",
	desc = "Torquey mini boxer. Useful in a small buggy.",
	model = "models/engines/b4small.mdl",
	sound = "acf_engines/b4_petrolsmall.wav",
	category = "B4",
	fuel = "Multifuel",
	enginetype = "B4",
	weight = 40,
	torque = 208,
	flywheelmass = 0.2,
	idlerpm = 600,
	limitrpm = 4000
} )

ACE.DefineEngine( "2.1-B4", {
	name = "2.1L Flat 4 Petrol",
	desc = "Tuned up flat four, probably find this in things that go fast in a desert.",
	model = "models/engines/b4med.mdl",
	sound = "acf_engines/b4_petrolmedium.wav",
	category = "B4",
	fuel = "Petrol",
	enginetype = "B4",
	weight = 63,
	torque = 450,
	flywheelmass = 0.15,
	idlerpm = 700,
	limitrpm = 5000
} )

ACE.DefineEngine( "2.4-B4", {
	name = "2.4L Flat 4 Multifuel",
	desc = "Small heavy duty multifuel. Heavy, but grunts hard.",
	model = "models/engines/b4med.mdl",
	sound = "acf_extra/vehiclefx/engines/coh/ba11.wav",
	category = "B4",
	fuel = "Multifuel",
	enginetype = "B4",
	weight = 67,
	torque = 772,
	flywheelmass = 0.4,
	idlerpm = 550,
	limitrpm = 2800
} )

ACE.DefineEngine( "3.2-B4", {
	name = "3.2L Flat 4 Petrol",
	desc = "Bored out fuckswindleton batshit flat four. Fuck yourself.",
	model = "models/engines/b4med.mdl",
	sound = "acf_engines/b4_petrollarge.wav",
	category = "B4",
	fuel = "Petrol",
	enginetype = "B4",
	weight = 105,
	torque = 450,
	flywheelmass = 0.15,
	idlerpm = 900,
	limitrpm = 6500
} )

--[[ -- These aren't boxer 4s. They're 3 cylinder(effectively 6 cylinder) opposing piston engines using a B6 model. Dramatically overperforming for their size. Don't even know where to begin to clean this up.
ACE.DefineEngine( "7.4-B4", {
	name = "7.4L Flat 4 Multifuel",
	desc = "3TD-3. Compact flat APC engine, with good power reserve, but with comparably high consumption. Used in BTR-4s.",
	model = "models/engines/b6med.mdl",
	sound = "acf_extra/vehiclefx/engines/gnomefather/t71.wav",
	category = "B4",
	fuel = "Multifuel",
	enginetype = "B4",
	weight = 800,
	torque = 2678,
	flywheelmass = 4.3,
	idlerpm = 600,
	limitrpm = 2800
} )

ACE.DefineEngine( "8.2-B4", {
	name = "8.2L Flat 4 Multifuel",
	desc = "3TD-4. Compact flat APC engine, with great power reserve, but with comparably high consumption.",
	model = "models/engines/b6med.mdl",
	sound = "acf_extra/vehiclefx/engines/gnomefather/t71.wav",
	category = "B4",
	fuel = "Multifuel",
	enginetype = "B4",
	weight = 800,
	torque = 2790,
	flywheelmass = 4.3,
	idlerpm = 600,
	limitrpm = 2800
} )

ACE.DefineEngine( "14.3-B4", {
	name = "14.3L Flat 4 Multifuel",
	desc = "ACE 1000. Not so large flat IFV engine, with big power reserve, but with comparably high consumption.",
	model = "models/engines/b6med.mdl",
	sound = "acf_extra/vehiclefx/engines/gnomefather/t71.wav",
	category = "B4",
	fuel = "Multifuel",
	enginetype = "B4",
	weight = 1620,
	torque = 4204,
	flywheelmass = 6.8,
	idlerpm = 400,
	limitrpm = 2600
} )
]]--

ACE.DefineEngine( "5.9-B4", {
	name = "5.9L Flat 4 Petrol",
	desc = "Lycoming O-360-A, the light aircraft flat four: 180 hp at 2,700 rpm. Air-cooled, low revving and heavy for its power next to a car engine, but it does not boil.",
	model = "models/engines/b4med.mdl",
	sound = "acf_engines/b4_petrolmedium.wav",
	category = "B4",
	fuel = "Petrol",
	cooling = "air",
	enginetype = "B4",
	-- O-360-A1A (FAA type certificate E-286, via Wikipedia): 134 kW (180 hp) at 2,700 rpm,
	-- 117 kg dry, 5.9 L, bore 130 x stroke 111 mm, 8.5:1.
	weight = 117,
	torque = 480,
	displacement = 5.9,
	cylinders = 4,
	stroke = 0.111,
	compression = 8.5,
	-- No full-throttle torque curve is published for direct-drive aero engines (they run on a
	-- propeller, rated at maximum speed). Estimated: nearly flat, highest at 75-85 % of rated
	-- speed, so power peaks at the rated speed as the type certificate gives it.
	torquecurve = {0.70, 0.76, 0.82, 0.87, 0.91, 0.94, 0.965, 0.98, 0.99, 1.0, 1.0, 0.995, 0.99},
	flywheelmass = 0.3,
	idlerpm = 650, -- estimated
	limitrpm = 2700
} )


-- V8 engines

-- Petrol

ACE.DefineEngine( "5.7-V8", {
	name = "5.7L V8 Petrol",
	desc = "Car sized petrol engine, good power and mid range torque",
	model = "models/engines/v8s.mdl",
	sound = "acf_engines/v8_petrolsmall.wav",
	category = "V8",
	fuel = "Petrol",
	enginetype = "V8",
	weight = 260,
	torque = 480,
	flywheelmass = 0.15,
	idlerpm = 800,
	limitrpm = 6500,
} )

ACE.DefineEngine( "9.0-V8", {
	name = "9.0L V8 Petrol",
	desc = "Thirsty, giant V8, for medium applications",
	model = "models/engines/v8m.mdl",
	sound = "acf_engines/v8_petrolmedium.wav",
	category = "V8",
	fuel = "Petrol",
	enginetype = "V8",
	weight = 400,
	torque = 690,
	flywheelmass = 0.25,
	idlerpm = 700,
	limitrpm = 5500,
} )

ACE.DefineEngine( "18.0-V8", {
	name = "18.0L V8 Petrol",
	desc = "American gasoline tank V8, good overall power and torque and fairly lightweight",
	model = "models/engines/v8l.mdl",
	sound = "acf_engines/v8_petrollarge.wav",
	category = "V8",
	fuel = "Petrol",
	enginetype = "V8",
	weight = 850,
	-- Ford GAA: 1,050 lb·ft (1,424 N·m) at 2,200 rpm, 500 hp at 2,600 rpm (TM 9-1731B par. 4);
	-- on its published curve this gives 498 hp at 2,600 rpm.
	torque = 1424,
	flywheelmass = 2.8,
	-- Ford GAA: 1,100 cu in (18.03 L), bore 5.4 in, stroke 6 in, 8 cyl (TM 9-1731B, 1945)
	displacement = 18.03,
	cylinders = 8,
	stroke = 0.1524,
	-- TM 9-1731B fig. 10, 1,000-2,800 rpm (tools/mobility_torque_curves.py "ford_gaa")
	torquecurve = {0.908, 0.927, 0.945, 0.961, 0.974, 0.984, 0.991, 0.997, 1.0, 0.994, 0.979, 0.956, 0.926},
	idlerpm = 600,
	limitrpm = 2800, -- end of the published full-load curve
} )

-- Diesel

ACE.DefineEngine( "4.5-V8", {
	name = "4.5L V8 Diesel",
	desc = "Light duty diesel v8, good for light vehicles that require a lot of torque",
	model = "models/engines/v8s.mdl",
	sound = "acf_engines/v8_dieselsmall.wav",
	category = "V8",
	fuel = "Diesel",
	enginetype = "V8",
	weight = 320,
	torque = 622,
	flywheelmass = 0.75,
	idlerpm = 800,
	limitrpm = 5000,
} )

ACE.DefineEngine( "7.8-V8", {
	name = "7.8L V8 Diesel",
	desc = "Redneck chariot material. Truck duty V8 diesel, has a good, wide powerband",
	model = "models/engines/v8m.mdl",
	sound = "acf_engines/v8_dieselmedium2.wav",
	category = "V8",
	fuel = "Diesel",
	enginetype = "V8",
	weight = 520,
	torque = 1050,
	flywheelmass = 1.6,
	idlerpm = 650,
	limitrpm = 4000,
} )

ACE.DefineEngine( "19.0-V8", {
	name = "19.0L V8 Diesel",
	desc = "Heavy duty diesel V8, used in heavy construction equipment and tanks",
	model = "models/engines/v8l.mdl",
	sound = "acf_engines/v8_diesellarge.wav",
	category = "V8",
	fuel = "Diesel",
	enginetype = "V8",
	weight = 1200,
	torque = 3450,
	flywheelmass = 4.5,
	idlerpm = 500,
	limitrpm = 2500,
} )


-- V12 engines

-- Petrol

ACE.DefineEngine( "4.6-V12", {
	name = "4.6L V12 Petrol",
	desc = "An elderly racecar engine; low on torque, but plenty of power",
	model = "models/engines/v12s.mdl",
	sound = "acf_engines/v12_petrolsmall.wav",
	category = "V12",
	fuel = "Petrol",
	enginetype = "GenericPetrol",
	weight = 188,
	torque = 352,
	flywheelmass = 0.2,
	idlerpm = 1000,
	limitrpm = 8000,
} )

ACE.DefineEngine( "7.0-V12", {
	name = "7.0L V12 Petrol",
	desc = "A high end V12; primarily found in very expensive cars",
	model = "models/engines/v12s.mdl",
	sound = "acf_engines/v12_petrolmedium.wav",
	category = "V12",
	fuel = "Petrol",
	enginetype = "GenericPetrol",
	weight = 360,
	torque = 450,
	flywheelmass = 0.45,
	idlerpm = 800,
	limitrpm = 7500,
} )

ACE.DefineEngine( "23.0-V12", {
	name = "23.0L V12 Petrol",
	desc = "A large, thirsty gasoline V12, found in early cold war tanks",
	model = "models/engines/v12l.mdl",
	sound = "acf_engines/v12_petrollarge.wav",
	category = "V12",
	fuel = "Petrol",
	enginetype = "GenericPetrol",
	weight = 1350,
	torque = 2888,
	flywheelmass = 5,
	idlerpm = 600,
	limitrpm = 3250,
} )

ACE.DefineEngine( "25.0-V12", {
	name = "25.0L V12 Petrol",
	desc = "Best petrol V12 engine ever ",
	model = "models/engines/v12l.mdl",
	sound = "acf_engines/v12_petrollarge.wav",
	category = "V12",
	fuel = "Petrol",
	enginetype = "GenericPetrol",
	weight = 2600,
	torque = 3075,
	flywheelmass = 5.2,
	idlerpm = 500,
	limitrpm = 5000,
} )

-- Diesel

ACE.DefineEngine( "4.0-V12", {
	name = "4.0L V12 Diesel",
	desc = "Reliable truck-duty diesel; a lot of smooth torque",
	model = "models/engines/v12s.mdl",
	sound = "acf_engines/v12_dieselsmall.wav",
	category = "V12",
	fuel = "Diesel",
	enginetype = "GenericDiesel",
	weight = 305,
	torque = 562,
	flywheelmass = 0.475,
	idlerpm = 650,
	limitrpm = 4000,
} )

ACE.DefineEngine( "9.2-V12", {
	name = "9.2L V12 Diesel",
	desc = "High torque light-tank V12, used mainly for vehicles that require balls",
	model = "models/engines/v12m.mdl",
	sound = "acf_engines/v12_dieselmedium.wav",
	category = "V12",
	fuel = "Diesel",
	enginetype = "GenericDiesel",
	weight = 600,
	torque = 1125,
	flywheelmass = 2.5,
	idlerpm = 675,
	limitrpm = 3500,
} )

ACE.DefineEngine( "21.0-V12", {
	name = "21.0L V12 Diesel",
	desc = "AVDS-1790-2 tank engine; massively powerful, but enormous and heavy",
	model = "models/engines/v12l.mdl",
	sound = "acf_engines/v12_diesellarge.wav",
	category = "V12",
	fuel = "Diesel",
	enginetype = "GenericDiesel",
	weight = 1800,
	-- AVDS-1790-2: 750 hp at 2,400 rpm (TM 9-2815-220-24). On the generic AVDS curve this
	-- torque gives 752 hp at 2,400 rpm; the published peak is 2,449 N·m at 1,800 rpm.
	torque = 2330,
	flywheelmass = 7,
	-- AVDS-1790: 29.3 L, 146 x 146 mm, 12 cyl (RENK America AVDS-1790 data sheet)
	displacement = 29.3,
	cylinders = 12,
	stroke = 0.146,
	idlerpm = 700, -- TM 9-2815-220-24: idles at 675-725 rpm
	limitrpm = 2500,
} )

ACE.DefineEngine( "13.0-V12", {
	name = "13.0L V12 Petrol",
	desc = "Thirsty gasoline v12, good torque and power for medium applications.",
	model = "models/engines/v12m.mdl",
	sound = "acf_engines/v12_special.wav",
	category = "V12",
	fuel = "Petrol",
	enginetype = "GenericPetrol",
	weight = 520,
	torque = 990,
	flywheelmass = 1,
	idlerpm = 700,
	limitrpm = 4250,
} )

ACE.DefineEngine( "16.5-V12", {
	name = "16.5L V12 Diesel",
	desc = "V-2-34. Pretty powerful but heavy with nice torque.",
	model = "models/engines/v8l.mdl",
	sound = "acf_engines/v12_dieselmedium.wav",
	category = "V12",
	fuel = "Diesel",
	enginetype = "GenericDiesel",
	weight = 1050,
	-- V-2-34: 2,160 N·m at 1,200 rpm, 500 hp at 1,800 rpm ([V-2]); 513 hp at 1,800 rpm on the
	-- generic AVDS curve.
	torque = 2160,
	flywheelmass = 2,
	-- V-2-34: 38.88 L, bore 150 mm, stroke 180 mm (left bank; 186.7 mm right), 12 cyl
	-- (T-34-85 technical manual, via ru.wikipedia "V-2")
	displacement = 38.88,
	cylinders = 12,
	stroke = 0.18,
	idlerpm = 675,
	limitrpm = 1800, -- V-2-34: 500 hp at 1,800 rpm, 2,050 rpm maximum
} )

ACE.DefineEngine( "24.8-V12", {
	name = "24.8-V12 Diesel",
	desc = "AVDS-1790-9A tank engine; massively powerful, but enormous and heavy",
	model = "models/engines/v12l.mdl",
	sound = "acf_extra/vehiclefx/engines/gnomefather/m60.wav",
	category = "V12",
	fuel = "Diesel",
	enginetype = "GenericDiesel",
	weight = 2100,
	-- AVDS-1790-9AR (Merkava Mk 3): 1,200 hp at 2,400 rpm, 3,820 N·m at 1,900 rpm
	-- ([AVDS-9AR]). On the generic AVDS curve this torque peaks at 1,925 rpm and gives
	-- 1,210 hp at 2,400 rpm.
	torque = 3820,
	-- AVDS-1790: 29.3 L, 146 x 146 mm, 12 cyl (RENK America AVDS-1790 data sheet)
	displacement = 29.3,
	cylinders = 12,
	stroke = 0.146,
	flywheelmass = 7,
	idlerpm = 500,
	limitrpm = 2400, -- rated speed ([AVDS-9AR])
} )

ACE.DefineEngine( "27.0-V12", {
	name = "27.0-V12 Diesel",
	desc = "AVDS-1790-1500 tank engine; massively powerful, but enormous and heavy. Best diesel engine in V12",
	model = "models/engines/v12lbig.mdl",
	sound = "acf_extra/vehiclefx/engines/gnomefather/m60.wav",
	category = "V12",
	fuel = "Diesel",
	enginetype = "GenericDiesel",
	weight = 3150,
	-- AVDS-1790 1500: 1,500 hp at 2,600 rpm, 3,635 lb·ft (4,928 N·m) at 1,800 rpm, a 20%
	-- torque rise ([AVDS-1500]).
	torque = 4928,
	-- AVDS-1790: 29.3 L, 146 x 146 mm, 12 cyl (RENK America AVDS-1790 data sheet)
	displacement = 29.3,
	cylinders = 12,
	stroke = 0.146,
	-- Idle to 1,800 rpm follows the AVDS-1790 rise (not published for this rating); from the
	-- peak the torque falls linearly to 4,107 N·m (1,500 hp) at 2,600 rpm.
	torquecurve = {0.41, 0.516, 0.622, 0.727, 0.833, 0.926, 0.976, 0.997, 0.979, 0.943, 0.906, 0.87, 0.833},
	flywheelmass = 6.6,
	idlerpm = 500,
	limitrpm = 2600, -- rated speed ([AVDS-1500])
} )

ACE.DefineEngine( "47.6-V12", {
	name = "47.6L V12 Diesel",
	desc = "MTU MB 873 Ka-501, the Leopard 2's twin-turbo tank diesel. 1,500 PS, huge and heavy.",
	model = "models/engines/v12lbig.mdl",
	sound = "acf_extra/vehiclefx/engines/gnomefather/m60.wav",
	category = "V12",
	fuel = "Diesel",
	enginetype = "GenericDiesel",
	-- About 2,200 kg dry; no primary source found for the figure.
	weight = 2200,
	-- MB 873 Ka-501: 1,103 kW (1,500 PS) at 2,600 rpm, 4,700 N·m at 1,600-1,700 rpm ([MB 873]).
	torque = 4700,
	-- 47.6 L, 170 x 175 mm, 12 cyl ([MB 873])
	displacement = 47.6,
	cylinders = 12,
	stroke = 0.175,
	-- Only the two points above are published. Idle to peak follows the AVDS-1790 rise; from
	-- 1,700 rpm the torque falls linearly to 4,051 N·m (1,103 kW) at 2,600 rpm.
	torquecurve = {0.41, 0.541, 0.672, 0.803, 0.923, 0.982, 1.0, 0.983, 0.959, 0.935, 0.911, 0.886, 0.862},
	flywheelmass = 7,
	idlerpm = 700, -- not published; the AVDS-1790's idle
	limitrpm = 2600, -- rated speed, the end of the published range
} )

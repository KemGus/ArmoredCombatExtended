--Fuel Density
ACE.FuelDensity = { --kg/liter
	Diesel = 0.832,
	Petrol = 0.745,
	Electric = 1.35 -- li-ion --WAS 3.1
}
ACE.FuelPowerDensity = { --KJ/liter
	Diesel = 38.6,
	Petrol = 33.6,
	Electric = 1 --TODO: Find conversion units. Fine for now. Electric doesn't generate too much heat to be of concern.
}



ACE.PerFuelRelativeEfficiency = { --Efficiency multipliers when using various fuels
	Diesel = 1.375, --42% more fuel efficicient but slightly less(1.02x) kg efficient for a unit of fuel.
	Petrol = 1,
	Electric = 1 --TODO: Find conversion units. Fine for now. Electric doesn't generate too much heat to be of concern.
}

--Power density of fuel. They're close enough so we'll use the density of gasoline to give engines the benefit of the doubt. 
--This way we score efficiency more on the type of engine and less so fuel which will be seperated. Especially as we're scoring their efficiency as a type.
--local BasePetrol = 1/13 --13kWh per kg gasoline. or ~0.077 kg per kw hr
--local BaseDiesel = 1/12.6 --12.6kWh per kg Diesel. Or ~0.079 kg per kw hr

local BaseFuel = 1/13 --13kWh per kg or ~0.077 kg per kw hr. The fuel density of gasoline. Diesel is 12.6kWh per kg or ~0.079 kg per kw hr.

ACE.Efficiency = { --how efficient various engine types are, Final units are in kg/kWhr
	GenericPetrol = (BaseFuel / 0.35), --Divide by % efficiency. Was 38%. Needs to be kept for other legacy engines.
	GenericDiesel = (BaseFuel / 0.5), --Was 49% efficient. Was 38%. Needs to be kept for other legacy engines.

	Single = (BaseFuel / 0.4), --Divide by % efficiency. Was 38%
	I2 = (BaseFuel / 0.395), --Divide by % efficiency. Was 38%
	I3 = (BaseFuel / 0.39), --Divide by % efficiency. Was 38%
	I4 = (BaseFuel / 0.385), --Divide by % efficiency. Was 38%
	I5 = (BaseFuel / 0.38), --Divide by % efficiency. Was 38%
	I6 = (BaseFuel / 0.375), --Divide by % efficiency. Was 38%

	B4 = (BaseFuel / 0.365), --Divide by % efficiency. Was 38%
	B6 = (BaseFuel / 0.36), --Divide by % efficiency. Was 38%

	V2 = (BaseFuel / 0.35), --Divide by % efficiency. Was 38%
	V4 = (BaseFuel / 0.345), --Divide by % efficiency. Was 38%
	V6 = (BaseFuel / 0.34), --Divide by % efficiency. Was 38%
	V8 = (BaseFuel / 0.335), --Divide by % efficiency. Was 38%
	V10 = (BaseFuel / 0.33), --Divide by % efficiency. Was 38%
	V12 = (BaseFuel / 0.325), --Divide by % efficiency. Was 38%

	Turbine = (BaseFuel / 0.35), --Was 32% efficient. Somewhere between a turboshaft and turbofan.
	--Turbofan = (BaseFuel / 0.4), --Was 32% efficient.
	GroundTurbine = (BaseFuel / 0.3), --Was 32% efficient.
	Wankel = (BaseFuel / 0.25), --Was 34%. Almost on par with regular petrol. Get. Outta. Here.
	Radial = (BaseFuel / 0.28), --Was 30% efficient.

	Racing = (BaseFuel / 0.2), --Racing duty engines meant for absurd speeds. Inefficient but power dense as hell.

	Electric = 0.85 --percent efficiency converting chemical kw into mechanical kw WAS 0.85
}

ACE.TorqueScale = { --how fast damage drops torque, lower loses more % torque
	GenericPetrol = 0.25,
	GenericDiesel = 0.5,

	Single = 0.25,
	I2 = 0.25,
	I3 = 0.275,
	I4 = 0.3,
	I5 = 0.325,
	I6 = 0.35,

	B4 = 0.3,
	B6 = 0.325,

	V2 = 0.25,
	V4 = 0.275,
	V6 = 0.3,
	V8 = 0.3,
	V10 = 0.325,
	V12 = 0.35,

	Turbine = 0.15,
	GroundTurbine = 0.2,
	Wankel = 0.2,
	Radial = 0.3,

	Racing = 0.1,

	Electric = 0.2
}

ACE.EngineHPMult = { --health multiplier for engines

	GenericPetrol = 0.15,
	GenericDiesel = 0.2,

	Single = 0.1,
	I2 = 0.1,
	I3 = 0.125,
	I4 = 0.15,
	I5 = 0.175,
	I6 = 0.2,

	B4 = 0.125,
	B6 = 0.15,

	V2 = 0.1,
	V4 = 0.1,
	V6 = 0.125,
	V8 = 0.15,
	V10 = 0.175,
	V12 = 0.2,

	Turbine = 0.05,
	GroundTurbine = 0.05,
	Wankel = 0.1,
	Radial = 0.2,

	Racing = 0.1,

	Electric = 0.1
}


-- Kept for addons that still read it. Fuel no longer reshapes a curve: an engine's curve
-- comes from its combustion type (see ACE.GetEngineTorqueCurve), so every entry is empty and
-- ACE.ApplyEngineFuelModifierToCurve treats a missing multiplier as 1.
ACE.PerFuelTorqueCurveMul = {
	Diesel = {},
	Petrol = {},
	Electric = {}
}

--[[
	Generic wide-open-throttle torque curves: brake torque / peak torque, sampled evenly from
	idle (first point) to the engine's limit RPM (last point). Every curve is a real engine's
	published or measured full-load curve, resampled by tools/mobility_torque_curves.py; the
	engine, the data and the citation for each are in docs/mobility-sources.md.

	Where no data exists for a layout, the layout uses the closest engine class that has data
	(noted per line). Cylinder layout by itself barely changes a full-load curve; bore/stroke,
	valve timing and charging do.
]]
local Curve = {
	-- EPA ALPHA package, 2014 Mazda 2.0 L SKYACTIV-G: naturally aspirated DOHC car I4, measured.
	SkyactivI4 = {0.564, 0.714, 0.789, 0.925, 0.929, 0.993, 0.971, 1.0, 0.989, 0.966, 0.942, 0.889, 0.65},
	-- EPA ALPHA package, 2014 Chevrolet 4.3 L LV3: naturally aspirated pushrod truck V6 (GM curve).
	LV3V6 = {0.559, 0.728, 0.775, 0.832, 0.897, 0.925, 0.933, 0.967, 1.0, 0.991, 0.973, 0.954, 0.888},
	-- TM 9-1731B fig. 10, Ford GAA 18.0 L V8 tank engine (1,000-2,800 rpm).
	GAA = {0.908, 0.927, 0.945, 0.961, 0.974, 0.984, 0.991, 0.997, 1.0, 0.994, 0.979, 0.956, 0.926},
	-- RENK AVDS-1790-2CAU data sheet: turbocharged air-cooled V12 tank diesel.
	AVDS = {0.41, 0.497, 0.585, 0.672, 0.759, 0.847, 0.923, 0.969, 0.994, 1.0, 0.984, 0.967, 0.94},
	-- VECTO generic 325 kW 12.7 L heavy truck diesel.
	Vecto325 = {0.557, 0.668, 0.778, 0.889, 1.0, 1.0, 1.0, 1.0, 1.0, 0.952, 0.903, 0.855, 0.807},
	-- VECTO generic 175 kW 6.9 L medium truck diesel.
	Vecto175 = {0.5, 0.611, 0.721, 0.83, 0.918, 0.98, 1.0, 1.0, 1.0, 0.996, 0.96, 0.923, 0.882},
	-- EPA ALPHA package, 2015 BMW 3.0 L N57: turbocharged car diesel, measured (1,000-4,620 rpm).
	N57 = {0.539, 0.858, 0.956, 0.969, 0.991, 1.0, 0.995, 0.966, 0.928, 0.846, 0.767, 0.663, 0.544},
	-- Kubota D1105 data sheet: naturally aspirated small industrial diesel (1,600-3,000 rpm).
	D1105 = {0.951, 0.969, 0.983, 0.991, 0.997, 1.0, 0.988, 0.972, 0.949, 0.923, 0.892, 0.858, 0.824},
	-- Free power turbine at full gas-generator output: straight line through the AGT1500's
	-- 5,355 N·m @ 1,000 rpm and 3,754 N·m @ 3,000 rpm, idle at 14% (aero) / 20% (ground) of top speed.
	AeroTurbine = {1.0, 0.97, 0.941, 0.911, 0.882, 0.852, 0.823, 0.793, 0.763, 0.734, 0.704, 0.675, 0.645},
	GroundTurbine = {1.0, 0.972, 0.944, 0.915, 0.887, 0.859, 0.831, 0.803, 0.774, 0.746, 0.718, 0.69, 0.661},
	-- 2012 Nissan LEAF motor (80 kW, 280 N·m, 10,400 rpm): constant torque to 26% of top speed, then constant power.
	PMMotor = {1.0, 1.0, 1.0, 1.0, 0.787, 0.63, 0.525, 0.45, 0.394, 0.35, 0.315, 0.286, 0.262},
}
ACE.MobilityReferenceCurves = Curve

-- Spark-ignition (petrol) and non-reciprocating engines, by enginetype.
ACE.GenericTorqueCurves = {
	GenericPetrol = Curve.LV3V6,

	Single = Curve.SkyactivI4, -- no public motorcycle full-load data; closest measured NA petrol engine
	I2 = Curve.SkyactivI4,     -- same
	I3 = Curve.SkyactivI4,
	I4 = Curve.SkyactivI4,
	I5 = Curve.LV3V6,
	I6 = Curve.LV3V6,

	B4 = Curve.SkyactivI4,
	B6 = Curve.LV3V6,

	V2 = Curve.SkyactivI4,     -- no public motorcycle full-load data
	V4 = Curve.SkyactivI4,
	V6 = Curve.LV3V6,
	V8 = Curve.LV3V6,          -- the LV3 is the V6 of GM's Gen V small-block V8 family
	V10 = Curve.LV3V6,
	V12 = Curve.LV3V6,

	Turbine = Curve.AeroTurbine,
	GroundTurbine = Curve.GroundTurbine,
	Wankel = Curve.SkyactivI4, -- no public rotary full-load data
	Radial = Curve.GAA,        -- WWII tank petrol engine class (R975 and GAA both powered the M4)

	Racing = Curve.SkyactivI4, -- no public racing-engine full-load data

	Electric = Curve.PMMotor,

	GenericDiesel = Curve.AVDS, -- legacy key; diesels normally resolve through ACE.GenericDieselTorqueCurves
}

-- Compression-ignition engines (Diesel and Multifuel fuel), by enginetype.
ACE.GenericDieselTorqueCurves = {
	GenericDiesel = Curve.AVDS,

	I2 = Curve.D1105,
	I3 = Curve.D1105,
	I4 = Curve.N57,
	I5 = Curve.Vecto175,
	I6 = Curve.Vecto325,

	B4 = Curve.AVDS,
	B6 = Curve.AVDS,

	V4 = Curve.N57,
	V6 = Curve.Vecto175,
	V8 = Curve.Vecto175,
	V10 = Curve.AVDS,
	V12 = Curve.AVDS,

	Radial = Curve.AVDS,
}

local NotReciprocating = { Turbine = true, GroundTurbine = true, Electric = true }

--- Returns the wide-open-throttle torque curve of an engine definition.
-- An explicit `torquecurve` wins; otherwise the generic curve for its enginetype, taken from
-- the diesel table when the engine burns Diesel or Multifuel.
-- @param Def Engine definition (fields torquecurve, enginetype, fuel).
-- @return Curve points, 0..1 over idle..limit RPM. Do not modify the returned table.
function ACE.GetEngineTorqueCurve(Def)
	if Def.torquecurve then return Def.torquecurve end
	local Type = Def.enginetype or "GenericPetrol"
	local Fuel = Def.fuel or "Petrol"
	if (Fuel == "Diesel" or Fuel == "Multifuel") and not NotReciprocating[Type] then
		return ACE.GenericDieselTorqueCurves[Type] or ACE.GenericDieselTorqueCurves.GenericDiesel
	end
	return ACE.GenericTorqueCurves[Type] or ACE.GenericTorqueCurves.GenericPetrol
end

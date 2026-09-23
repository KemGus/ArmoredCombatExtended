-- Unit conversions between Source/GMod quantities and SI.
-- The drivetrain works in SI (kg, m, s, rad/s, N·m) and only converts at the
-- boundary where it reads or writes VPhysics.

ACE = ACE or {}
ACE.Mobility = ACE.Mobility or {}

local Units = {}
ACE.Mobility.Units = Units

Units.InchToMeter = 0.0254
Units.MeterToInch = 1 / 0.0254
Units.RPMToRad    = math.pi / 30
Units.RadToRPM    = 30 / math.pi
Units.DegToRad    = math.pi / 180
Units.RadToDeg    = 180 / math.pi
Units.KwToHp      = 1.34102
Units.Gravity     = 9.80665

-- VPhysics reports GetInertia() in kg·in², so kg·m² = kg·in² · 0.0254².
Units.SourceInertiaToSI = Units.InchToMeter ^ 2

--[[
	ApplyTorqueCenter takes an angular impulse. Measured with gmodkit on a free prop
	(see tests/mobility_calibration.md): one call changes angular velocity by
	Δω[deg/s] = arg / I_source[kg·in²], independent of tickrate.
	An SI angular impulse L [N·m·s] = I_si[kg·m²] · Δω[rad/s], so
	arg = L · (1 / 0.0254²) · (180 / π).
]]
Units.SIAngularImpulseToSource = (1 / Units.InchToMeter ^ 2) * Units.RadToDeg

--- Converts an SI angular impulse (N·m·s) to the value ApplyTorqueCenter expects.
-- @param Impulse Angular impulse in N·m·s.
-- @return The scalar to multiply the world axis by before calling ApplyTorqueCenter.
function Units.ToSourceAngularImpulse(Impulse)
	return Impulse * Units.SIAngularImpulseToSource
end

--- Converts a VPhysics inertia component (kg·in²) to kg·m².
-- @param SourceInertia Inertia as returned by PhysObj:GetInertia().
-- @return Inertia in kg·m².
function Units.InertiaToSI(SourceInertia)
	return SourceInertia * Units.SourceInertiaToSI
end

return Units

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

-- VPhysics (IVP) works in metric internally and PhysObj:GetInertia() returns kg·m².
-- Measured with gmodkit: a 100 kg cube1x1x1 reports 17.1 and a 30 kg race wheel 1.51, which
-- only fit kg·m² (in kg·in² the cube would read ~37500).
Units.SourceInertiaToSI = 1

--[[
	ApplyTorqueCenter takes an angular impulse. Measured with gmodkit on free props (cubes of
	100-400 kg, a race wheel, all three axes, 33 and 66 tick): one call changes angular velocity
	by Δω[deg/s] = arg / GetInertia() to within 1e-6, independent of tickrate.
	An SI angular impulse L [N·m·s] = I[kg·m²] · Δω[rad/s], so arg = L · (180 / π).
]]
Units.SIAngularImpulseToSource = Units.RadToDeg

--- Converts an SI angular impulse (N·m·s) to the value ApplyTorqueCenter expects.
-- @param Impulse Angular impulse in N·m·s.
-- @return The scalar to multiply the world axis by before calling ApplyTorqueCenter.
function Units.ToSourceAngularImpulse(Impulse)
	return Impulse * Units.SIAngularImpulseToSource
end

--- Converts a VPhysics inertia component to kg·m² (it already is; kept as the one boundary).
-- @param SourceInertia Inertia as returned by PhysObj:GetInertia().
-- @return Inertia in kg·m².
function Units.InertiaToSI(SourceInertia)
	return SourceInertia * Units.SourceInertiaToSI
end

return Units

--[[
	Coupling between the drivetrain solver and VPhysics.

	VPhysics owns the wheels and the chassis: it resolves tyre contact after the drivetrain has
	applied its impulses for the tick. Inside the tick the solver still has to know how hard a
	driven wheel pushes back, or the engine would only ever feel a few kg·m² of wheel and
	over-rev, to be dragged back by Source next tick.

	So each driven wheel gets a "ground body" in the solver: the wheel's share of the vehicle
	seen at the axle (J = m_share·r², ω = contact ground speed / r), joined to the wheel by a
	Coulomb friction constraint capped at μ·N·r. While the tyre grips, the engine feels the
	vehicle's mass. Past the traction limit the wheel breaks loose and only sliding friction
	loads the drivetrain. The angular impulse handed to VPhysics is therefore bounded by what
	the tyre can pass to the ground in one tick, so VPhysics can always absorb it through its
	own contact friction and the two never fight.
]]

ACE = ACE or {}
ACE.Mobility = ACE.Mobility or {}

local Vehicle = {}
ACE.Mobility.Vehicle = Vehicle

local max = math.max

local function clamp(v, lo, hi)
	if v < lo then return lo end
	if v > hi then return hi end
	return v
end

--- Builds the ground-contact description for one driven wheel.
-- @param ShareMass Vehicle mass this wheel propels, kg.
-- @param R Rolling radius, m.
-- @param GroundSpeed Ground speed at the contact patch along the rolling direction, m/s.
-- @param Mu Tyre-road friction coefficient.
-- @param NormalLoad Wheel load, N.
-- @param Grounded Whether the wheel touches the ground.
-- @return Ground table { J, W, Cap } for Drivetrain, or nil when airborne.
function Vehicle.Ground(ShareMass, R, GroundSpeed, Mu, NormalLoad, Grounded)
	if not Grounded or R <= 0 or ShareMass <= 0 then return nil end
	return {
		J = ShareMass * R * R,
		W = GroundSpeed / R,
		Cap = Mu * max(NormalLoad, 0) * R,
	}
end

--- Clutch capacity in Assisted mode: a centrifugal clutch that engages as the engine rises
-- above idle, so the car can launch and stop in gear without stalling. The driver's pedal
-- still works on top of it.
-- @param State Engine state.
-- @param Spec Engine spec.
-- @param MaxCap Full clutch capacity, N·m.
-- @param Pedal Clutch pedal 0 (released) .. 1 (pressed).
-- @param Throttle 0..1.
-- @return Clutch capacity, N·m.
function Vehicle.AssistedClutch(State, Spec, MaxCap, Pedal, Throttle)
	local Idle = Spec.IdleW
	-- Engagement point rises with throttle, like a launch-control target.
	local Engage = Idle * 1.3 + clamp(Throttle, 0, 1) * 0.45 * (Spec.LimitW - Idle)
	local Start = Idle * 1.1
	local Frac = clamp((State.W - Start) / max(Engage - Start, 1), 0, 1)
	return MaxCap * Frac * Frac * (1 - clamp(Pedal, 0, 1))
end

return Vehicle

--[[
	Drivetrain solver.

	The drivetrain is a set of rotating bodies (crank, gearbox shafts, wheels) tied together by
	linear velocity constraints of the form  Σ kᵢ·ωᵢ = target. Gear ratios, differentials,
	clutches, brakes, bearing drag and steering differentials are all expressed that way:

	  rigid gear       ωa − r·ωb = 0                      (unbounded impulse)
	  clutch/brake     ωa − ωb = 0 / ω = 0                 (|impulse| ≤ capacity·h)
	  open diff        ωc − ½ωL − ½ωR = 0                  (equal torque split)
	  steering diff    ½ωL − ½ωR − s·g·ωin = 0

	Each substep integrates applied torques explicitly, then solves the constraints with
	sequential impulses (projected Gauss-Seidel, as in Catto, "Iterative Dynamics with
	Temporal Coherence", GDC 2005). Friction elements are bounded impulses, so a clutch can
	never overshoot lock and the result is stable at any tickrate; see
	docs/mobility-sources.md. Impulses accumulate across substeps (warm start) because the
	constraint set does not change within a tick.
]]

ACE = ACE or {}
ACE.Mobility = ACE.Mobility or {}

local Solver = {}
ACE.Mobility.Solver = Solver

local huge = math.huge
local abs  = math.abs

--- Creates a rotating body.
-- @param J Moment of inertia in kg·m² (math.huge for a fixed reference).
-- @param W Initial angular velocity in rad/s.
-- @return Body table.
function Solver.Body(J, W)
	return { J = J, InvJ = (J == huge or J <= 0) and 0 or 1 / J, W = W or 0, Torque = 0 }
end

--- Creates a velocity constraint Σ Coefs[i]·Bodies[i].W = Target.
-- @param Bodies Array of bodies.
-- @param Coefs Array of coefficients, one per body.
-- @param Cap Maximum transmitted torque in N·m, or nil for a rigid constraint.
-- @return Constraint table. Its Acc field holds the accumulated impulse after a solve.
function Solver.Constraint(Bodies, Coefs, Cap, Target)
	return { Bodies = Bodies, Coefs = Coefs, Cap = Cap, Target = Target or 0, Acc = 0 }
end

local function prepare(C, H)
	local Denominator = 0
	local Bodies, Coefs = C.Bodies, C.Coefs
	for I = 1, #Bodies do
		Denominator = Denominator + Coefs[I] * Coefs[I] * Bodies[I].InvJ
	end
	C.Mass = Denominator > 0 and 1 / Denominator or 0
	C.Max = C.Cap and C.Cap * H or huge
end

local function solveOne(C)
	if C.Mass == 0 then return end
	local Bodies, Coefs = C.Bodies, C.Coefs
	local N = #Bodies
	local Cdot = -C.Target
	for I = 1, N do
		Cdot = Cdot + Coefs[I] * Bodies[I].W
	end
	local Lambda = -Cdot * C.Mass
	local Old = C.Acc
	local New = Old + Lambda
	local Max = C.Max
	if New > Max then New = Max elseif New < -Max then New = -Max end
	Lambda = New - Old
	if Lambda == 0 then return end
	C.Acc = New
	for I = 1, N do
		local B = Bodies[I]
		B.W = B.W + Coefs[I] * Lambda * B.InvJ
	end
end

--- Runs one substep: applies body torques, then solves all constraints.
-- Constraints keep their accumulated impulse (Acc) between calls. Zero it with
-- Solver.Reset before the first substep of a tick.
-- @param Bodies Array of bodies (their Torque fields are applied then cleared).
-- @param Constraints Array of constraints.
-- @param H Substep length in seconds.
-- @param Iterations Gauss-Seidel sweeps; each sweep runs forwards then backwards.
function Solver.Step(Bodies, Constraints, H, Iterations)
	for I = 1, #Bodies do
		local B = Bodies[I]
		if B.Torque ~= 0 then
			B.W = B.W + B.Torque * H * B.InvJ
			B.Torque = 0
		end
	end

	local Count = #Constraints
	for I = 1, Count do
		local C = Constraints[I]
		local Prev = C.Max
		prepare(C, H)
		-- Warm start: re-apply last substep's impulse, clamped to this substep's capacity.
		if Prev and C.Acc ~= 0 and C.Mass ~= 0 then
			local Warm = C.Acc
			if Warm > C.Max then Warm = C.Max elseif Warm < -C.Max then Warm = -C.Max end
			C.Acc = Warm
			for J = 1, #C.Bodies do
				local B = C.Bodies[J]
				B.W = B.W + C.Coefs[J] * Warm * B.InvJ
			end
		else
			C.Acc = 0
		end
	end

	for _ = 1, Iterations or 8 do
		for I = 1, Count do solveOne(Constraints[I]) end
		for I = Count, 1, -1 do solveOne(Constraints[I]) end
	end
end

--- Clears accumulated impulses (call when the constraint set is rebuilt).
function Solver.Reset(Constraints)
	for I = 1, #Constraints do
		Constraints[I].Acc = 0
		Constraints[I].Max = nil
	end
end

--- Torque currently carried by a constraint, in N·m, from its last solve.
-- @param C Constraint.
-- @param H Substep length used for that solve.
function Solver.Torque(C, H)
	return C.Acc / H
end

--- Applies a friction torque on a body that cannot reverse its rotation within the substep.
-- Used for bearing drag, rolling resistance and similar losses.
-- @param B Body.
-- @param T Friction torque magnitude in N·m.
-- @param H Substep length.
function Solver.Drag(B, T, H)
	if B.InvJ == 0 or T <= 0 then return 0 end
	local W = B.W
	local Dw = T * H * B.InvJ
	if abs(W) <= Dw then
		B.W = 0
		return W * B.J
	end
	B.W = W - (W > 0 and Dw or -Dw)
	return (W > 0 and 1 or -1) * T * H
end

return Solver

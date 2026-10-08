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

-- Gaussian elimination with partial pivoting on an M×M system (in place). Near-singular pivots
-- (redundant constraints) solve to zero instead of blowing up.
local function gauss(A, R, M)
	for K = 1, M do
		local P, Best = K, abs(A[K][K])
		for I = K + 1, M do
			local V = abs(A[I][K])
			if V > Best then P, Best = I, V end
		end
		if P ~= K then A[P], A[K] = A[K], A[P]; R[P], R[K] = R[K], R[P] end
		local Piv = A[K][K]
		if abs(Piv) > 1e-14 then
			local RowK = A[K]
			for I = K + 1, M do
				local RowI = A[I]
				local F = RowI[K] / Piv
				if F ~= 0 then
					for J = K, M do RowI[J] = RowI[J] - F * RowK[J] end
					R[I] = R[I] - F * R[K]
				end
			end
		end
	end
	local X = {}
	for K = M, 1, -1 do
		local RowK = A[K]
		local Sum = R[K]
		for J = K + 1, M do Sum = Sum - RowK[J] * X[J] end
		local Piv = RowK[K]
		X[K] = abs(Piv) > 1e-14 and Sum / Piv or 0
	end
	return X
end

-- Largest system solved directly; bigger ones (tanks with many road wheels) fall back to
-- extra Gauss-Seidel sweeps.
Solver.DirectLimit = 40

--[[
	Direct solve of the boxed velocity problem  A·λ = -b,  |λ_i| <= Max_i  with an active-set
	loop (Murty's principal pivoting, as used for friction LCPs in Baraff 1994, "Fast contact force
	computation for nonpenetrating rigid bodies"). A drivetrain is stiff by nature: a gearbox
	input shaft of 0.02 kg·m² sits between an engine and wheels 100-1000 times heavier, and
	Gauss-Seidel needs hundreds of sweeps to converge there. Left unconverged it hands the two
	sides of an axle different torques. The direct solve is exact in one pass.
]]
local function directSolve(Constraints, Count)
	local Idx = {}
	for I = 1, Count do
		local C = Constraints[I]
		if C.Mass ~= 0 then Idx[#Idx + 1] = C end
	end
	local N = #Idx
	if N == 0 then return true, true end
	if N > Solver.DirectLimit then return false end

	local B, A = {}, {}
	for I = 1, N do
		local C = Idx[I]
		local E = -C.Target
		for K = 1, #C.Bodies do E = E + C.Coefs[K] * C.Bodies[K].W end
		B[I] = E
	end
	for I = 1, N do
		local Ci = Idx[I]
		local Row = {}
		for J = 1, N do
			local Cj = Idx[J]
			local Sum = 0
			for P = 1, #Ci.Bodies do
				local Body = Ci.Bodies[P]
				if Body.InvJ ~= 0 then
					for Q = 1, #Cj.Bodies do
						if Cj.Bodies[Q] == Body then Sum = Sum + Ci.Coefs[P] * Cj.Coefs[Q] * Body.InvJ end
					end
				end
			end
			Row[J] = Sum
		end
		A[I] = Row
	end

	local State, L = {}, {}
	for I = 1, N do State[I], L[I] = 0, 0 end

	--[[
		All violated limits are switched at once, which usually settles in a few rounds. Should it
		still be switching after N rounds, it changes only the first violated one per round
		(Murty's least-index rule, which cannot cycle on this symmetric positive definite system).
	]]
	local Converged = false
	for Round = 1, 4 * N + 4 do
		local Single = Round > N
		local Free = {}
		for I = 1, N do
			if State[I] == 0 then Free[#Free + 1] = I else L[I] = State[I] * Idx[I].Max end
		end
		local M = #Free
		local Sys, Rhs = {}, {}
		for P = 1, M do
			local I = Free[P]
			local Ai = A[I]
			local Row = {}
			for Q = 1, M do Row[Q] = Ai[Free[Q]] end
			-- A tiny compliance keeps redundant (looped) constraints solvable.
			Row[P] = Row[P] * (1 + 1e-9) + 1e-12
			Sys[P] = Row
			local R = -B[I]
			for J = 1, N do
				if State[J] ~= 0 then R = R - Ai[J] * L[J] end
			end
			Rhs[P] = R
		end
		local X = gauss(Sys, Rhs, M)
		for P = 1, M do L[Free[P]] = X[P] end

		local Changed = false
		for I = 1, N do
			if State[I] == 0 then
				local Max = Idx[I].Max
				local Tol = Max * 1e-9 + 1e-12
				if L[I] > Max + Tol then State[I], Changed = 1, true
				elseif L[I] < -Max - Tol then State[I], Changed = -1, true end
				if Changed and Single then break end
			end
		end
		if not Changed then
			-- A clamped constraint whose residual now points the other way wants less than its limit.
			for I = 1, N do
				if State[I] ~= 0 then
					local V = B[I]
					local Ai = A[I]
					for J = 1, N do V = V + Ai[J] * L[J] end
					if (State[I] == 1 and V > 1e-9) or (State[I] == -1 and V < -1e-9) then
						State[I], Changed = 0, true
						if Single then break end
					end
				end
			end
		end
		if not Changed then
			Converged = true
			break
		end
	end

	--[[
		The active-set loop can cycle without settling (a dual steering box feeding two more dual
		boxes: 22 constraints, still switching after 46 rounds). Its last round then holds impulses
		for constraints it had just clamped, far past their limits (a 0.12 N·m·s gearbox loss
		applied as 59), and those kicked a 0.02 kg·m² shaft to 1,000 rad/s in one substep: the
		clutches slipping against it read as megawatts of heat. Every impulse is held to its
		limit, and an unsettled solve is finished by Gauss-Seidel from there.
	]]
	for I = 1, N do
		local C = Idx[I]
		local Lambda = L[I]
		local Max = C.Max
		if Lambda > Max then Lambda = Max elseif Lambda < -Max then Lambda = -Max end
		C.Acc = Lambda
		if Lambda ~= 0 then
			for K = 1, #C.Bodies do
				local Body = C.Bodies[K]
				Body.W = Body.W + C.Coefs[K] * Lambda * Body.InvJ
			end
		end
	end
	return true, Converged
end

--- Runs one substep: applies body torques, then solves all constraints.
-- Small systems are solved directly; larger ones by warm-started Gauss-Seidel.
-- Zero accumulated impulses with Solver.Reset before the first substep of a tick.
-- @param Bodies Array of bodies (their Torque fields are applied then cleared).
-- @param Constraints Array of constraints.
-- @param H Substep length in seconds.
-- @param Iterations Gauss-Seidel sweeps; each sweep runs forwards then backwards. After a direct
-- solve two polishing sweeps are run to absorb round-off.
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
		prepare(Constraints[I], H)
		Constraints[I].Acc = 0
	end

	local Sweeps = Iterations or 8
	local Direct, Converged = directSolve(Constraints, Count)
	if Direct then
		-- Settled: two sweeps absorb round-off. Not settled: the clamped impulses are a feasible
		-- warm start for a full Gauss-Seidel solve.
		Sweeps = Converged and 2 or Sweeps * 4
	else
		-- Warm start from the previous substep's impulses, clamped to this substep's capacity.
		for I = 1, Count do
			local C = Constraints[I]
			local Warm = C.Prev or 0
			if Warm ~= 0 and C.Mass ~= 0 then
				if Warm > C.Max then Warm = C.Max elseif Warm < -C.Max then Warm = -C.Max end
				C.Acc = Warm
				for J = 1, #C.Bodies do
					local B = C.Bodies[J]
					B.W = B.W + C.Coefs[J] * Warm * B.InvJ
				end
			end
		end
		Sweeps = Sweeps * 4
	end

	for _ = 1, Sweeps do
		for I = 1, Count do solveOne(Constraints[I]) end
		for I = Count, 1, -1 do solveOne(Constraints[I]) end
	end
	for I = 1, Count do Constraints[I].Prev = Constraints[I].Acc end
end

--- Clears accumulated impulses (call when the constraint set is rebuilt).
function Solver.Reset(Constraints)
	for I = 1, #Constraints do
		Constraints[I].Acc = 0
		Constraints[I].Prev = nil
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

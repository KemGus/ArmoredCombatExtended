-- Self-test for the drivetrain solver (lua/ace/shared/mobility/solver.lua) on a recorded substep
-- where its direct solve used to cycle without settling: a dual steering box feeding two more
-- dual boxes (the harness Scania, 2026-10-08). The unsettled result applied impulses far past
-- their limits and threw a 0.02 kg·m² shaft to 1,000 rad/s; the side clutches slipping against
-- it read as megawatts of clutch heat. The fixture holds the bodies and constraints before the
-- step (tests/fixtures/mobility/scania_dual_chain_step.lua).
local root = assert(arg[1], "usage: ace_mobility_solver_dualchain_luajit_selftest.lua <ACE repo>")
root = root:gsub("\\", "/"):gsub("/$", "")

ACE = ACE or {}
local Solver = dofile(root .. "/lua/ace/shared/mobility/solver.lua")
local D = dofile(root .. "/tests/fixtures/mobility/scania_dual_chain_step.lua")

local Passed = 0
local function check(Cond, Label, ...)
	if not Cond then error(("FAIL %s %s"):format(Label, table.concat({ ... }, " ")), 2) end
	Passed = Passed + 1
end

local Bodies, Cons = {}, {}
for I, Rec in ipairs(D.Bodies) do
	local B = Solver.Body(Rec.J < 0 and math.huge or Rec.J, Rec.W)
	B.Torque = Rec.T
	Bodies[I] = B
end
for I, Rec in ipairs(D.Cons) do
	local Bs = {}
	for K, Ix in ipairs(Rec.B) do Bs[K] = Bodies[Ix] end
	local C = Solver.Constraint(Bs, Rec.C, Rec.Cap >= 0 and Rec.Cap or nil, Rec.Tg)
	C.Prev, C.Tag = Rec.Prev, Rec.Tag
	Cons[I] = C
end

Solver.Step(Bodies, Cons, D.H, 6)

local Fastest = 0
for _, B in ipairs(Bodies) do Fastest = math.max(Fastest, math.abs(B.W)) end
check(Fastest < 5, "no shaft runs away (rad/s)", Fastest)

for _, C in ipairs(Cons) do
	check(math.abs(C.Acc) <= C.Max * (1 + 1e-6) + 1e-9, "impulse within its limit: " .. tostring(C.Tag), C.Acc, C.Max)
	if not C.Cap then
		local V = -C.Target
		for K, B in ipairs(C.Bodies) do V = V + C.Coefs[K] * B.W end
		check(math.abs(V) < 1e-3, "rigid constraint holds: " .. tostring(C.Tag), V)
	end
end

print(("Solver dual-chain self-test: PASS (%d checks)"):format(Passed))

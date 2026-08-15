-- Mobility must behave the same per second of real time on any tickrate.
-- ACE was tuned on a 66-tick server; the drivetrain integrated several
-- quantities per tick with no time scaling, so a 33-tick server changed how
-- engines revved, heated and how much torque reached the wheels.
--
-- sv_heat.lua and sh_ace_functions.lua load under plain LuaJIT, so those are
-- exercised for real. acf_engine/init.lua uses GLua's `continue`, which LuaJIT
-- cannot parse, so the flywheel is covered by asserting the integration steps
-- in the source still carry their time scale.
local repo = assert(arg[1], "usage: luajit ace_mobility_tickrate_luajit_selftest.lua <ace-repo>")

local BASE_TICK = 0.015

ACE = { AmbientTemp = 20, MobilityBaseTick = BASE_TICK }
ACF = ACE
AddCSLuaFile = function() end
include = function() end
timer = { Simple = function() end, Create = function() end, Remove = function() end }
hook = { Add = function() end, Run = function() end }
CLIENT, SERVER = false, true

math.Clamp = function(value, minimum, maximum)
	return math.max(minimum, math.min(maximum, value))
end
math.Round = function(value) return math.floor(value + 0.5) end
math.Remap = function(v, a, b, c, d) return c + (v - a) / (b - a) * (d - c) end

dofile(repo .. "/lua/acf/server/sv_heat.lua")
dofile(repo .. "/lua/acf/shared/sh_ace_functions.lua")

local assertions = 0

local function check(condition, message)
	assertions = assertions + 1
	if not condition then
		io.stderr:write("ACE mobility tickrate self-test: FAIL - " .. message .. "\n")
		os.exit(1)
	end
end

local function close(a, b, tolerance, message)
	check(math.abs(a - b) <= tolerance,
		string.format("%s (%.6f vs %.6f, tolerance %.6f)", message, a, b, tolerance))
end

------------------------------------------------------------------ torque limit

-- The drivetrain clamps an impulse (torque * step). A flat ceiling on a
-- per-step quantity is a per-second ceiling that shrinks with the tickrate.
do
	close(ACE_TorqueImpulseLimit(BASE_TICK), 500000, 1e-6,
		"the limit at the base tick must be the historical 500000")

	-- A saturated drivetrain delivers Limit per step, so Limit / step is what
	-- actually reaches the wheels per second. That has to match across tickrates.
	local perSecond66 = ACE_TorqueImpulseLimit(BASE_TICK) / BASE_TICK
	local perSecond33 = ACE_TorqueImpulseLimit(BASE_TICK * 2) / (BASE_TICK * 2)
	close(perSecond33, perSecond66, 1e-6,
		"a saturated drivetrain must deliver the same torque per second at 33 tick")
end

------------------------------------------------------------------------- heat

local function runEngine(steps, step, seconds)
	local engine = {
		Active   = true,
		FlyRPM   = 3000,
		FuelType = "Diesel",
		Heat     = ACE.AmbientTemp,
	}

	for _ = 1, steps do
		engine.Heat = ACE_HeatFromEngine(engine, step)
	end

	check(seconds > 0, "bad test setup")
	return engine.Heat
end

do
	-- One second of running, integrated at both tickrates.
	local warm66 = runEngine(66, BASE_TICK, 1)
	local warm33 = runEngine(33, BASE_TICK * 2, 1)

	check(warm66 > ACE.AmbientTemp, "a running engine must warm up at all")
	close(warm33, warm66, 0.05,
		"engine heat after one second must not depend on the tickrate")

	-- Ten seconds, where the linear cooling term has had time to diverge.
	local long66 = ACE.AmbientTemp
	local long33 = ACE.AmbientTemp
	local e66 = { Active = true, FlyRPM = 3000, FuelType = "Diesel", Heat = long66 }
	local e33 = { Active = true, FlyRPM = 3000, FuelType = "Diesel", Heat = long33 }
	for _ = 1, 660 do e66.Heat = ACE_HeatFromEngine(e66, BASE_TICK) end
	for _ = 1, 330 do e33.Heat = ACE_HeatFromEngine(e33, BASE_TICK * 2) end
	close(e33.Heat, e66.Heat, 0.5,
		"engine heat after ten seconds must not depend on the tickrate")

	-- Omitting the step must reproduce the old per-tick behaviour exactly, so
	-- any caller that has not been updated is unaffected.
	local implicit = { Active = true, FlyRPM = 3000, FuelType = "Diesel", Heat = ACE.AmbientTemp }
	local explicit = { Active = true, FlyRPM = 3000, FuelType = "Diesel", Heat = ACE.AmbientTemp }
	for _ = 1, 100 do
		implicit.Heat = ACE_HeatFromEngine(implicit)
		explicit.Heat = ACE_HeatFromEngine(explicit, BASE_TICK)
	end
	close(implicit.Heat, explicit.Heat, 1e-9,
		"omitting the step must match the default tick exactly")
end

---------------------------------------------------------------- flywheel source

-- LuaJIT cannot parse acf_engine/init.lua (GLua `continue`), so guard the two
-- flywheel integration steps by reading them out of the file. Both accumulate
-- into FlyRPM once per tick and both must carry the time scale.
do
	local handle = assert(io.open(repo .. "/lua/entities/acf_engine/init.lua", "r"))
	local source = handle:read("*a")
	handle:close()

	check(source:find("ACE.MobilityBaseTick", 1, true) ~= nil,
		"the engine must normalise its step against ACE.MobilityBaseTick")

	local scaled = 0
	for line in source:gmatch("[^\r\n]+") do
		if line:find("self.FlyRPM%s*=") and line:find("self.FlyRPM", line:find("=") or 1, true) then
			check(line:find("TickMul", 1, true) ~= nil,
				"flywheel integration step is missing its time scale: " .. line:gsub("^%s+", ""))
			scaled = scaled + 1
		end
	end

	check(scaled == 2,
		string.format("expected 2 flywheel integration steps, found %d", scaled))
end

print(string.format("ACE mobility tickrate self-test: PASS (%d assertions)", assertions))

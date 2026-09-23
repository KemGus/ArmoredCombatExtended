-- Loads every engine definition with a stub ACE.DefineEngine and checks that each one builds
-- through the mobility engine model and can start and hold idle on a neutral gearbox.
local root = assert(arg[1], "usage: ace_engine_definitions_luajit_selftest.lua <ACE repo>")
root = root:gsub("\\", "/"):gsub("/$", "")

local Rig = dofile(root .. "/tests/lua/mobility_rig.lua")(root)
local M = ACE.Mobility

local Dir = "lua/ace/shared/engines"

local function listLua()
	local Files = {}
	local Handle = io.popen('ls "' .. root .. "/" .. Dir .. '" 2>nul')
	local Out = Handle and Handle:read("*a") or ""
	if Handle then Handle:close() end
	if not Out:find("%.lua") then
		Handle = io.popen('dir /b "' .. (root .. "/" .. Dir):gsub("/", "\\") .. '"')
		Out = Handle:read("*a")
		Handle:close()
	end
	for Name in Out:gmatch("[^\r\n]+") do
		if Name:match("%.lua$") and Name ~= "ace_engine_properties.lua" then Files[#Files + 1] = Name end
	end
	table.sort(Files)
	return Files
end

local Defs = {}
function ACE.DefineEngine(Id, Data)
	Data.id = Id
	Defs[#Defs + 1] = Data
end

local Files = listLua()
assert(#Files >= 15, "engine definition files not found under " .. Dir)
for _, Name in ipairs(Files) do
	local F = assert(io.open(root .. "/" .. Dir .. "/" .. Name, "rb"))
	local Src = F:read("*a")
	F:close()
	assert(loadstring(Src, Name))()
end
assert(#Defs >= 100, "expected every ACE engine, got " .. #Defs)

local Failures, Passed = {}, 0
local function fail(Def, Msg)
	Failures[#Failures + 1] = ("%s: %s"):format(Def.id, Msg)
end

local function finitePositive(V) return type(V) == "number" and V == V and V > 0 and V < math.huge end

for _, Def in ipairs(Defs) do
	local Curve = ACE.GetEngineTorqueCurve(Def)
	local Ok, Spec = pcall(M.Engine.Build, Def, Curve)
	if not Ok then
		fail(Def, "Build errored: " .. tostring(Spec))
	elseif not finitePositive(Spec.Inertia) then
		fail(Def, "inertia " .. tostring(Spec.Inertia))
	elseif not finitePositive(Spec.DispL) then
		fail(Def, "displacement " .. tostring(Spec.DispL))
	else
		local V = Rig.New({ EngineDef = Def, Mass = 1000, Ratios = { 1 }, Final = 1 })
		Rig.StartEngine(V)
		V.Gear = 0
		if not V.State.Running then
			fail(Def, "did not start")
		elseif Spec.Kind ~= "electric" and Spec.Kind ~= "turbine" then
			-- Let the governor settle (heavy tank flywheels take a few seconds), then hold idle
			-- for two seconds in neutral: speed must stay within 15% of idle.
			Rig.Run(V, V.Time + 3, function(X) X.Throttle = 0 end)
			local Lo, Hi = math.huge, 0
			Rig.Run(V, V.Time + 2, function(X) X.Throttle = 0 end, function(X)
				local R = Rig.RPM(X)
				Lo, Hi = math.min(Lo, R), math.max(Hi, R)
			end)
			if not V.State.Running or Lo < Def.idlerpm * 0.85 or Hi > Def.idlerpm * 1.15 then
				fail(Def, ("cannot hold idle %d rpm: %.0f-%.0f rpm, running=%s"):format(
					Def.idlerpm, Lo, Hi, tostring(V.State.Running)))
			end
		end
	end
	Passed = Passed + 1
end

if #Failures > 0 then
	error(("ACE engine definitions self-test: %d of %d failed\n  %s"):format(
		#Failures, #Defs, table.concat(Failures, "\n  ")), 0)
end
print(("ACE engine definitions self-test: PASS (%d engines)"):format(Passed))

-- Exhaust smoke, client side. An engine with an entity wired to its Exhaust input puffs smoke out
-- of that entity's forward face while it runs. Driven from the engine sound stream: the sound
-- Think in cl_ace_engine_sounds.lua calls ACE.ExhaustSmoke.Think for engines with an exhaust.
--
-- The look follows simfphys's "simfphys_exhaust" effect (simfphys base by Blu-x92, lua/effects/
-- simfphys_exhaust.lua): HL2 smoke sprites blown out along the pipe at a speed and size that grow
-- with load = throttle * (0.2 + 0.8 * RPM / redline)^2, grey that darkens under load, strong air
-- resistance so puffs stop and billow, and a slight rise. Unlike that effect (one emitter and one
-- particle per frame), this reuses a single emitter and emits at a time-based rate, with a global
-- budget so dozens of engines cannot flood the particle system.
--
-- Optional twice over: the server convar ace_exhaust_smoke (replicated, ACE server settings) and
-- the client convar ace_exhaust_smoke_draw (ACE client settings).

ACE = ACE or {}
ACE.ExhaustSmoke = ACE.ExhaustSmoke or {}

local Smoke = ACE.ExhaustSmoke

local DrawVar = CreateClientConVar("ace_exhaust_smoke_draw", 1, true, false, "Draw smoke from engine exhausts.", 0, 1)

Smoke.MinRate        = 6   -- particles per second per exhaust at idle
Smoke.MaxRate        = 30  -- particles per second per exhaust at full load
Smoke.MaxPerFrame    = 3   -- per exhaust, so a long frame cannot dump a burst
Smoke.GlobalBudget   = 300 -- particles per second over all exhausts
Smoke.MaxDistance    = 6000 -- units; no smoke beyond this, and less of it towards it
Smoke.StartPuff      = 6   -- particles in the dark puff when an engine catches

local Materials = {}

for I = 1, 16 do
	Materials[I] = string.format("particle/smokesprites_%04d", I)
end

local Clamp  = math.Clamp
local Rand   = math.Rand
local random = math.random
local max    = math.max

local Emitter
local Budget = Smoke.GlobalBudget
local BudgetTime = 0
local Rise = Vector(0, 0, 60)

local function GetEmitter(Pos)
	if not Emitter then
		Emitter = ParticleEmitter(Pos, false)
	end

	return Emitter
end

--- Whether exhaust smoke is drawn: allowed by the server and wanted by this client.
-- @return boolean
function Smoke.Enabled()
	if not DrawVar:GetBool() then return false end

	local ServerVar = GetConVar("ace_exhaust_smoke")

	return not ServerVar or ServerVar:GetBool()
end

-- Local position of the middle of the exhaust entity's forward face (+X), cached per model.
local function Outlet(Exhaust, State)
	local Model = Exhaust:GetModel()

	if State.SmokeModel ~= Model then
		local Mins, Maxs = Exhaust:OBBMins(), Exhaust:OBBMaxs()
		local Center = (Mins + Maxs) * 0.5

		State.SmokeModel = Model
		State.SmokeOutlet = Vector(Maxs.x, Center.y, Center.z)
	end

	return Exhaust:LocalToWorld(State.SmokeOutlet)
end

local function EmitOne(Em, Pos, Dir, Vel, Load, Scale, Dark)
	local Particle = Em:Add(Materials[random(1, 16)], Pos)
	if not Particle then return end

	local Spread = VectorRand() * 0.25
	local Grey = Clamp(100 - 40 * Load - Dark, 20, 255)

	Particle:SetVelocity(Vel + (Dir + Spread) * (50 + Load * 100) * Scale)
	-- Idle exhaust is a thin but visible haze that lingers; load makes it bigger, darker and faster.
	Particle:SetDieTime(1.2 + Load * 0.6 + Rand(0, 0.4))
	Particle:SetAirResistance(200)
	Particle:SetGravity(Rise)
	Particle:SetStartAlpha(Clamp(45 + Load ^ 2 * 50 + Dark * 0.5, 0, 255))
	Particle:SetEndAlpha(0)
	Particle:SetStartSize(3 * Scale)
	Particle:SetEndSize((22 + Load * 60) * Scale)
	Particle:SetRoll(Rand(-1, 1))
	Particle:SetRollDelta(Rand(-0.5, 0.5))
	Particle:SetColor(Grey, Grey, Grey * 1.02)
	Particle:SetCollide(false)
end

--- Emits smoke for one engine this frame. Called by the engine sound Think.
-- @param State table The engine's sound state (Exhaust, Running, SmoothRPM, SmoothThrottle, Limit, MaxDB).
-- @param Dt number Frame time in seconds.
function Smoke.Think(State, Dt)
	local Exhaust = State.Exhaust
	if not IsValid(Exhaust) or not Smoke.Enabled() then return end

	local Running = State.Running

	-- Remember combustion starting, for the puff when an engine catches
	local Was = State.SmokeWasRunning
	if Was == nil then Was = Running end -- an engine already running when first heard did not just catch

	local Caught = Running and not Was
	State.SmokeWasRunning = Running

	if not Running or Dt <= 0 then return end

	local Now = RealTime()

	if Now > BudgetTime then
		-- Refill the global budget once per frame
		Budget = math.min(Budget + Smoke.GlobalBudget * (Now - BudgetTime), Smoke.GlobalBudget * 0.25)
		BudgetTime = Now
	end

	if Budget < 1 then return end

	local Pos = Outlet(Exhaust, State)
	local Dist = Pos:Distance(EyePos())
	if Dist > Smoke.MaxDistance then return end

	local Load = State.SmoothThrottle * (0.2 + 0.8 * math.min(State.SmoothRPM / State.Limit, 1)) ^ 2
	local Falloff = 1 - Dist / Smoke.MaxDistance
	local Rate = (Smoke.MinRate + (Smoke.MaxRate - Smoke.MinRate) * Load) * Falloff

	-- Bigger engines (higher MaxDB, 70 + 60 * hp / 2400) blow bigger plumes
	local Scale = Clamp((State.MaxDB - 55) / 25, 0.6, 2.5)

	-- Capped so time spent over budget does not turn into a backlog
	State.SmokeAccum = math.min((State.SmokeAccum or 0) + Rate * Dt, Smoke.MaxPerFrame)

	local Count = math.min(math.floor(State.SmokeAccum), Smoke.MaxPerFrame, math.floor(Budget))
	local Puff = Caught and Smoke.StartPuff or 0

	if Count < 1 and Puff == 0 then return end

	State.SmokeAccum = State.SmokeAccum - max(Count, 0)

	local Em = GetEmitter(Pos)
	local Dir = Exhaust:GetForward()
	local Vel = ACE.EngineSound.TrackVelocity and ACE.EngineSound.TrackVelocity(Exhaust, Exhaust:GetPos()) or vector_origin

	Em:SetPos(Pos)

	for _ = 1, Count do
		EmitOne(Em, Pos, Dir, Vel, Load, Scale, 0)
	end

	-- Unburnt fuel from the first firings: a short dark puff
	for _ = 1, Puff do
		EmitOne(Em, Pos, Dir, Vel, 0.6, Scale, 50)
	end

	Budget = Budget - Count - Puff
end

--[[
	Outlet indicator. Smoke leaves the exhaust entity's forward face (its local +X, the red axis
	of the model), which is not obvious on a round pipe. While the player holds the tool gun and
	aims at an engine or its exhaust, draw an arrow out of the outlet.
]]
local ArrowColor = Color(255, 140, 40)

hook.Add("PostDrawTranslucentRenderables", "ACE_ExhaustSmoke_Outlet", function(Depth, Skybox)
	if Depth or Skybox then return end

	local Ply = LocalPlayer()
	local Weapon = IsValid(Ply) and Ply:GetActiveWeapon()
	if not IsValid(Weapon) or Weapon:GetClass() ~= "gmod_tool" then return end

	local Aim = Ply:GetEyeTrace().Entity
	if not IsValid(Aim) then return end

	for Engine, State in pairs(ACE.EngineSound.GetStates and ACE.EngineSound.GetStates() or {}) do
		local Exhaust = State.Exhaust

		if IsValid(Exhaust) and (Aim == Engine or Aim == Exhaust) then
			local Pos = Outlet(Exhaust, State)
			local Dir = Exhaust:GetForward()
			local Size = math.max((Exhaust:OBBMaxs() - Exhaust:OBBMins()):Length() * 0.5, 12)
			local Tip = Pos + Dir * Size

			render.SetColorMaterial()
			render.DrawBeam(Pos, Tip, 1.5, 0, 1, ArrowColor)

			local Side = Dir:Cross(Vector(0, 0, 1))
			if Side:LengthSqr() < 0.01 then Side = Dir:Cross(Vector(1, 0, 0)) end
			Side:Normalize()

			render.DrawBeam(Tip, Tip - Dir * Size * 0.3 + Side * Size * 0.15, 1.5, 0, 1, ArrowColor)
			render.DrawBeam(Tip, Tip - Dir * Size * 0.3 - Side * Size * 0.15, 1.5, 0, 1, ArrowColor)
		end
	end
end)

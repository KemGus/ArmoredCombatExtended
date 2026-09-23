-- Engine sounds, client side. Builds the sound patches for each running engine from the server's
-- description, then sets their pitch and volume every frame from the streamed RPM and throttle.

ACE = ACE or {}
ACE.EngineSound = ACE.EngineSound or {}

local EngineSound = ACE.EngineSound

local DopplerVar = CreateClientConVar("ace_engine_sound_doppler", 1, true, false, "Apply a Doppler shift to engine sounds.", 0, 1)

EngineSound.SmoothingTime = 0.08 -- seconds; time constant of the RPM/throttle smoothing
EngineSound.StaleTime     = 1.5 -- seconds without updates before an engine is treated as out of earshot

local Clamp = math.Clamp
local cos   = math.cos
local exp   = math.exp
local abs   = math.abs
local HalfPi = math.pi * 0.5

local Engines = {} -- [Entity] = state, see Create below
local Pending = {} -- [Entity] = time the last data request was sent

local function StopPatches(State)
	for _, Bank in ipairs(State.Playing or {}) do
		for _, Entry in ipairs(Bank.Entries) do
			Entry.Patch:Stop()
		end
	end

	State.Playing = nil
end

local function Forget(Ent)
	local State = Engines[Ent]

	if State then
		StopPatches(State)
		Engines[Ent] = nil
	end
end

local function RequestData(Ent)
	local Now = RealTime()

	if Pending[Ent] and Now - Pending[Ent] < 2 then return end

	Pending[Ent] = Now

	net.Start("ACE_EngineSound_Request")
	net.WriteEntity(Ent)
	net.SendToServer()
end

-- Accept wav/mp3/ogg files that exist, and sound script names (no extension).
local function IsPlayable(Path)
	if Path == "" then return false end
	if not Path:find("%.%a+$") then return true end

	return file.Exists("sound/" .. Path, "GAME")
end

local function NewPatch(Target, Path, Level)
	if not IsPlayable(Path) then return end

	local Patch = CreateSound(Target, Path)
	if not Patch then return end

	Patch:SetSoundLevel(Level)
	Patch:PlayEx(0, 100)

	return Patch
end

-- Creates the CSoundPatch objects for an engine. Banks with Exhaust set play from the exhaust entity when it exists.
local function StartPatches(Ent, State)
	StopPatches(State)

	local Playing = {}

	for _, Bank in ipairs(State.Banks) do
		local Target = (Bank.Exhaust and IsValid(State.Exhaust)) and State.Exhaust or Ent
		local Entries = {}

		for Index, Snd in ipairs(Bank.Sounds) do
			local Patch = NewPatch(Target, Snd.Path, State.Level)

			if Patch then
				Entries[#Entries + 1] = { Patch = Patch, Sound = Snd, Index = Index }
			end
		end

		Playing[#Playing + 1] = { Bank = Bank, Target = Target, Entries = Entries }
	end

	State.Playing = Playing
end

net.Receive("ACE_EngineSound_Create", function()
	local Ent     = net.ReadEntity()
	local Exhaust = net.ReadEntity()
	local Version = net.ReadUInt(8)
	local Level   = net.ReadUInt(8)
	local IsBanks = net.ReadBool()
	local Banks, Legacy

	if IsBanks then
		Banks = EngineSound.ReadBanks()
	else
		Legacy = {
			Path  = net.ReadString(),
			Pitch = net.ReadUInt(8),
			Limit = net.ReadUInt(16),
		}
	end

	if not IsValid(Ent) then return end

	Pending[Ent] = nil

	local Old = Engines[Ent]

	if Old then
		StopPatches(Old)
	end

	local State = {
		Version  = Version,
		Level    = Level,
		Exhaust  = IsValid(Exhaust) and Exhaust or nil,
		Legacy   = Legacy,
		RPM      = Old and Old.RPM or 0,
		Throttle = Old and Old.Throttle or 0,
		LastUpdate = RealTime(),
		Fresh    = Old == nil, -- snap the smoothing to the first update instead of sweeping up from 0
	}

	State.SmoothRPM = State.RPM
	State.SmoothThrottle = State.Throttle

	if Legacy then
		-- The single sound is a bank of one; its pitch and volume use the original ACE formula.
		State.Banks = { { Exhaust = false, Sounds = { { Path = Legacy.Path } } } }
	else
		State.Banks = Banks or {}
	end

	Engines[Ent] = State
end)

net.Receive("ACE_EngineSound_Update", function()
	local Ent      = net.ReadEntity()
	local Version  = net.ReadUInt(8)
	local RPM      = net.ReadUInt(16)
	local Throttle = net.ReadUInt(7) / 100

	if not IsValid(Ent) then return end

	local State = Engines[Ent]

	if not State or State.Version ~= Version then
		RequestData(Ent)

		if not State then return end
	end

	State.RPM = RPM
	State.Throttle = Throttle
	State.LastUpdate = RealTime()

	if State.Fresh then
		State.Fresh = nil
		State.SmoothRPM = RPM
		State.SmoothThrottle = Throttle
	end
end)

net.Receive("ACE_EngineSound_Stop", function()
	local Ent = net.ReadEntity()

	if IsValid(Ent) then
		Forget(Ent)
	end
end)

hook.Add("EntityRemoved", "ACE_EngineSound_Cleanup", function(Ent)
	Forget(Ent)
	Pending[Ent] = nil
end)

-- Doppler: velocities come from position differences so parented entities work too.
local LastPositions = setmetatable({}, { __mode = "k" })

local function Velocity(Ent, Pos, Now)
	local Last = LastPositions[Ent]

	if Last and Last.Time == Now then return Last.Vel end

	local Vel = vector_origin

	if Last and Now > Last.Time then
		Vel = (Pos - Last.Pos) / (Now - Last.Time)

		-- Teleports and spawns would read as a huge one-frame speed
		if Vel:Length() > EngineSound.SpeedOfSound * 2 then
			Vel = vector_origin
		end
	end

	LastPositions[Ent] = { Pos = Pos, Time = Now, Vel = Vel }

	return Vel
end

--- Pitch multiplier for a sound source moving relative to the local player.
-- @param Source Entity The entity the sound plays from.
-- @return number Multiplier between 0.5 and 2.
function EngineSound.DopplerFactor(Source)
	local Ply = LocalPlayer()
	if not IsValid(Ply) or not IsValid(Source) then return 1 end

	local Now = RealTime()
	local Ear = Ply:EyePos()
	local Pos = Source:GetPos()
	local Dir = Pos - Ear
	local Dist = Dir:Length()

	if Dist < 1 then return 1 end

	Dir:Div(Dist)

	local Relative = Velocity(Source, Pos, Now) - Velocity(Ply, Ear, Now)
	local Closing = -Relative:Dot(Dir)
	local SpeedOfSound = EngineSound.SpeedOfSound

	return Clamp(SpeedOfSound / math.max(SpeedOfSound - Closing, SpeedOfSound * 0.1), 0.5, 2)
end

--- Equal-power crossfade weight of a sound centred on Mid, fading out towards Low and High.
-- A nil Low or High means the sound keeps full volume past Mid on that side.
-- @param RPM number Current RPM.
-- @param Low number|nil RPM where the weight reaches zero below Mid.
-- @param Mid number RPM where the weight is 1.
-- @param High number|nil RPM where the weight reaches zero above Mid.
-- @return number Weight from 0 to 1.
function EngineSound.Fade(RPM, Low, Mid, High)
	if RPM <= Mid then
		if not Low or Low >= Mid then return 1 end
		if RPM <= Low then return 0 end

		return cos((Mid - RPM) / (Mid - Low) * HalfPi)
	end

	if not High or High <= Mid then return 1 end
	if RPM >= High then return 0 end

	return cos((RPM - Mid) / (High - Mid) * HalfPi)
end

local Fade = EngineSound.Fade

-- Original single-sound model from acf_engine CalcRPM.
local function LegacyPitchVolume(Legacy, RPM, Throttle)
	local Pitch = math.min(20 + (RPM * (Legacy.Pitch / 100)) / 50, 255)
	local Volume = 0.25 + (0.1 + 0.9 * ((RPM / math.max(Legacy.Limit, 1)) ^ 1.5)) * Throttle / 1.5

	return Pitch, Volume
end

local function BankPitchVolume(Bank, Snd, Index, RPM, Throttle)
	local Sounds = Bank.Sounds
	local Count  = #Sounds
	local Width  = Snd.Width or 0
	local Low    = Index > 1 and Sounds[math.max(Index - 1 - Width, 1)].RPM or nil
	local High   = Index < Count and Sounds[math.min(Index + 1 + Width, Count)].RPM or nil
	local Level  = Bank.OffVolume + (Bank.OnVolume - Bank.OffVolume) * Throttle

	local Volume = Fade(RPM, Low, Snd.RPM, High) * Level * Snd.Volume
	local Pitch  = Snd.Pitch * RPM / math.max(Snd.RPM, 1)

	return Pitch, Volume
end

local function UpdateEngine(Ent, State, Alpha, Doppler)
	State.SmoothRPM = State.SmoothRPM + (State.RPM - State.SmoothRPM) * Alpha
	State.SmoothThrottle = State.SmoothThrottle + (State.Throttle - State.SmoothThrottle) * Alpha

	local RPM, Throttle = State.SmoothRPM, State.SmoothThrottle

	for _, Playing in ipairs(State.Playing) do
		local Target = Playing.Target

		if not IsValid(Target) then
			-- The exhaust went away; rebuild so its banks play from the engine
			State.Exhaust = nil
			StartPatches(Ent, State)
			return
		end

		local Shift = Doppler and EngineSound.DopplerFactor(Target) or 1

		for _, Entry in ipairs(Playing.Entries) do
			local Pitch, Volume

			if State.Legacy then
				Pitch, Volume = LegacyPitchVolume(State.Legacy, RPM, Throttle)
			else
				Pitch, Volume = BankPitchVolume(Playing.Bank, Entry.Sound, Entry.Index, RPM, Throttle)
			end

			Pitch = Clamp(Pitch * Shift, 1, 255)
			Volume = Clamp(Volume, 0, 1)

			if not Entry.Pitch or abs(Pitch - Entry.Pitch) >= 0.5 then
				Entry.Pitch = Pitch
				Entry.Patch:ChangePitch(Pitch, 0)
			end

			if not Entry.Volume or abs(Volume - Entry.Volume) >= 0.005 then
				Entry.Volume = Volume
				Entry.Patch:ChangeVolume(Volume, 0)
			end
		end
	end
end

hook.Add("Think", "ACE_EngineSound_Think", function()
	if not next(Engines) then return end

	local Now = RealTime()
	local Alpha = 1 - exp(-FrameTime() / EngineSound.SmoothingTime)
	local Doppler = DopplerVar:GetBool()

	for Ent, State in pairs(Engines) do
		if not IsValid(Ent) then
			StopPatches(State)
			Engines[Ent] = nil
		elseif Now - State.LastUpdate > EngineSound.StaleTime then
			-- No updates: the engine left our PAS. Keep the data so it can resume without a request.
			if State.Playing then
				StopPatches(State)
			end
		else
			if not State.Playing then
				StartPatches(Ent, State)
			end

			UpdateEngine(Ent, State, Alpha, Doppler)
		end
	end
end)

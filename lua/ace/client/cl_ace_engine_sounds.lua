-- Engine sounds, client side. Builds the sound patches for each running engine from the server's
-- description, then sets their pitch and volume every frame from the streamed RPM and throttle.
-- Also plays the starter motor while an engine cranks, keeps the sound following the crank as it
-- spins down after shut-off, muffles banks that ask for it while the local player sits in their
-- vehicle in first person, and drives
-- the exhaust smoke (cl_ace_exhaust_smoke.lua).

ACE = ACE or {}
ACE.EngineSound = ACE.EngineSound or {}

local EngineSound = ACE.EngineSound

local DopplerVar = CreateClientConVar("ace_engine_sound_doppler", 1, true, false, "Apply a Doppler shift to engine sounds.", 0, 1)
local MuffleVar = CreateClientConVar("ace_engine_sound_muffle", 1, true, false, "Allow the cabin muffling that engine sound banks ask for (it only applies in first person).", 0, 1)

EngineSound.SmoothingTime = 0.08 -- seconds; time constant of the RPM/throttle smoothing
EngineSound.StaleTime     = 1.5 -- seconds without updates before an engine is treated as out of earshot
EngineSound.VelocitySmoothing = 0.15 -- seconds; time constant of the Doppler velocity estimate

-- Interior muffling. DSP preset ids are from the GMod wiki "DSP Presets" page: 0 is the NULL
-- preset (no processing), 30 is "Lowpass" (cuts high frequencies; 31 is the same plus an 80 ms
-- delay, 14-16 are the echoing Water presets). Lowpass is what a hull does to engine noise.
-- The DSP is set per sound patch (CSoundPatch:SetDSP), so only these engine sounds are filtered,
-- never the rest of the game's audio. A bank's Muffle (0-1) sets how much it is muffled.
EngineSound.MuffleDSP      = 30
EngineSound.MuffleDSPFrom  = 0.25 -- effective muffling at which the lowpass is switched on
EngineSound.MaxMuffleCut   = 0.7 -- volume removed at muffling 1
EngineSound.CabinCheckTime = 0.5 -- seconds between checks of whether an engine shares our vehicle (first/third person is checked every frame)
EngineSound.DSPCrossfade   = 0.05 -- seconds; old patches fade out and new ones in when the muffling switches
EngineSound.ThirdPersonDistance = 48 -- units between the camera and the player's eyes that count as third person
EngineSound.CabinOpening   = EngineSound.CabinOpening or 0 -- 0 closed .. 1 open, set by Starfall (acf.setCabinOpening)

-- Starter motor. v8_start_loop1.wav is the HL2 jeep's cranking loop (hl2_sound_misc VPK, loops
-- from 1.8 s to its end); at pitch 100 it is taken to be a crank turning at StarterRefRPM.
-- An engine can carry its own starter sound (set in the sound bank editor of the sound replacer tool), networked as the
-- "ACE_StarterSound" string; it is played the same way.
EngineSound.StarterSound  = "vehicles/v8/v8_start_loop1.wav"
EngineSound.StarterRefRPM = 250
EngineSound.StarterLevel  = 75 -- SNDLVL_75dB ("busy traffic"); a starter is quieter than the engine

local Clamp = math.Clamp
local cos   = math.cos
local sin   = math.sin
local exp   = math.exp
local abs   = math.abs
local max   = math.max
local HalfPi = math.pi * 0.5
local TwoPi  = math.pi * 2

local Engines = {} -- [Entity] = state, see the Create receiver below

--- The sound state of every engine this client hears, keyed by engine entity. Read-only.
-- @return table [Entity] = state.
function EngineSound.GetStates()
	return Engines
end
local Pending = {} -- [Entity] = time the last data request was sent

-- Engines of the vehicle the local player last sat in, from the server's CFW contraption.
local Cabin = { Vehicle = NULL, Known = false, Engines = {} }

-- Stops an engine's sound patches; with Fade (seconds) they fade out instead of cutting off.
local function StopPatches(State, Fade)
	for _, Bank in ipairs(State.Playing or {}) do
		for _, Entry in ipairs(Bank.Entries) do
			if Fade then Entry.Patch:FadeOut(Fade) else Entry.Patch:Stop() end
		end
	end

	State.Playing = nil

	if State.Starter then
		if Fade then State.Starter:FadeOut(Fade) else State.Starter:Stop() end
		State.Starter = nil
	end
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
local PlayableCache = {}

local function IsPlayable(Path)
	if Path == "" then return false end
	if not Path:find("%.%a+$") then return true end

	local Cached = PlayableCache[Path]

	if Cached == nil then
		Cached = file.Exists("sound/" .. Path, "GAME")
		PlayableCache[Path] = Cached
	end

	return Cached
end

-- Third person when the game draws the local player, or when the camera (EyePos is the last
-- rendered view origin) is away from the player's eyes, as with vehicle chase cameras.
local function FirstPerson(Ply)
	if Ply:ShouldDrawLocalPlayer() then return false end

	return EyePos():DistToSqr(Ply:EyePos()) < EngineSound.ThirdPersonDistance ^ 2
end

--- Effective muffling of a bank for the local player: the bank's Muffle while we sit in its
-- vehicle in first person, reduced by the cabin opening.
-- @param State table Engine sound state.
-- @param Bank table Sound bank.
-- @return number 0-1.
function EngineSound.MuffleOf(State, Bank)
	if not State.Muffled then return 0 end

	return (Bank.Muffle or 0) * (1 - Clamp(EngineSound.CabinOpening, 0, 1))
end

local function DSPSignature(State)
	local Sig = 0

	for I, Bank in ipairs(State.Banks or {}) do
		if EngineSound.MuffleOf(State, Bank) >= EngineSound.MuffleDSPFrom then
			Sig = Sig + 2 ^ I
		end
	end

	return Sig
end

local function NewPatch(Target, Path, Level, DSP)
	if not IsPlayable(Path) then return end

	local Patch = CreateSound(Target, Path)
	if not Patch then return end

	Patch:SetSoundLevel(Level)

	if DSP then
		Patch:SetDSP(DSP)
	end

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
		local DSP = EngineSound.MuffleOf(State, Bank) >= EngineSound.MuffleDSPFrom and EngineSound.MuffleDSP or nil

		for Index, Snd in ipairs(Bank.Sounds) do
			local Patch = NewPatch(Target, Snd.Path, State.Level, DSP)

			if Patch then
				Entries[#Entries + 1] = { Patch = Patch, Sound = Snd, Index = Index }
			end
		end

		Playing[#Playing + 1] = { Bank = Bank, Target = Target, Entries = Entries }
	end

	State.Playing = Playing
	State.DSPSig = DSPSignature(State)
end

net.Receive("ACE_EngineSound_Create", function()
	local Ent     = net.ReadEntity()
	local Exhaust = net.ReadEntity()
	local Version = net.ReadUInt(8)
	local MaxDB   = net.ReadUInt(8)
	local Limit   = net.ReadUInt(16)
	local Burns   = net.ReadBool()
	local Turbine = net.ReadBool()
	local IsBanks = net.ReadBool()
	local Banks, Legacy

	if IsBanks then
		Banks = EngineSound.ReadBanks()
	else
		Legacy = {
			Path  = net.ReadString(),
			Pitch = net.ReadUInt(8),
			Limit = Limit,
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
		MaxDB    = MaxDB,
		Level    = EngineSound.SoundLevel(MaxDB),
		Limit    = math.max(Limit, 1),
		Burns    = Burns, -- combustion engine, so its exhaust smokes
		Turbine  = Turbine, -- gas turbine: its exhaust is hot clear gas, drawn as heat haze
		Exhaust  = IsValid(Exhaust) and Exhaust or nil,
		Legacy   = Legacy,
		RPM      = Old and Old.RPM or 0,
		Throttle = Old and Old.Throttle or 0,
		Running  = Old and Old.Running or false,
		Ran      = Old and Old.Ran or false,
		OffRPM   = Old and Old.OffRPM or nil,
		Combustion = Old and Old.Combustion or 0,
		Cranking = false,
		StarterLoad = 0,
		Cylinders = 4,
		StarterPhase = 0,
		Muffled  = Old and Old.Muffled or false,
		InSeat   = Old and Old.InSeat or false,
		NextCabinCheck = 0,
		LastUpdate = RealTime(),
		Fresh    = Old == nil, -- snap the smoothing to the first update instead of sweeping up from 0
	}

	State.SmoothRPM = State.RPM
	State.SmoothThrottle = State.Throttle

	if Legacy then
		-- The single sound is a bank of one; its pitch and volume use the legacy formula.
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
	local Running  = net.ReadBool()
	local Cranking = net.ReadBool()
	local StarterLoad, Cylinders = 0, nil

	if Cranking then
		StarterLoad = net.ReadUInt(5) / 31
		Cylinders = net.ReadUInt(4)
	end

	if not IsValid(Ent) then return end

	local State = Engines[Ent]

	if not State or State.Version ~= Version then
		RequestData(Ent)

		if not State then return end
	end

	State.RPM = RPM
	State.Throttle = Throttle
	State.Cranking = Cranking
	State.StarterLoad = StarterLoad
	State.Cylinders = Cylinders or State.Cylinders
	State.LastUpdate = RealTime()

	if State.Fresh then
		State.Fresh = nil
		State.SmoothRPM = RPM
		State.SmoothThrottle = Throttle
	end

	if Running then
		State.Ran = true
		State.OffRPM = nil
	elseif State.Running then
		-- Combustion just ended: from here the sound fades with the crank speed.
		State.OffRPM = max(State.SmoothRPM, 1)
	end

	State.Running = Running
end)

net.Receive("ACE_EngineSound_Stop", function()
	local Ent = net.ReadEntity()

	if IsValid(Ent) then
		Forget(Ent)
	end
end)

net.Receive("ACE_EngineSound_Cabin", function()
	Cabin.Vehicle = net.ReadEntity()
	Cabin.Known = net.ReadBool()
	Cabin.Engines = {}

	for _ = 1, net.ReadUInt(8) do
		local Ent = net.ReadEntity()

		if IsValid(Ent) then
			Cabin.Engines[Ent] = true
		end
	end

	-- Re-check every engine now instead of waiting for the periodic check
	for _, State in pairs(Engines) do
		State.NextCabinCheck = 0
	end
end)

hook.Add("EntityRemoved", "ACE_EngineSound_Cleanup", function(Ent)
	Forget(Ent)
	Pending[Ent] = nil
end)

-- Doppler: velocities come from position differences so parented entities work too. The raw
-- per-frame difference is noisy (frame time jitter, interpolated positions), so it is smoothed
-- with a VelocitySmoothing time constant. One record per entity is reused to avoid garbage.
local Tracks = setmetatable({}, { __mode = "k" })

--- Smoothed world velocity of an entity (or the local player's eyes), from its position history.
-- Cached per frame, so calling it several times per frame is cheap.
-- @param Ent Entity Entity to track.
-- @param Pos Vector Its current position.
-- @return Vector Velocity in units per second. Do not modify.
function EngineSound.TrackVelocity(Ent, Pos)
	local Now = RealTime()
	local Track = Tracks[Ent]

	if not Track then
		Track = { Pos = Vector(Pos), Time = Now, Vel = Vector(0, 0, 0) }
		Tracks[Ent] = Track

		return Track.Vel
	end

	local Dt = Now - Track.Time
	if Dt <= 0 then return Track.Vel end

	-- Long gaps (entity was out of earshot) restart the estimate instead of blending stale data
	if Dt < 0.5 then
		local Raw = (Pos - Track.Pos) / Dt

		-- Teleports and spawns would read as a huge one-frame speed
		if Raw:LengthSqr() < (EngineSound.SpeedOfSound * 0.5) ^ 2 then
			local Alpha = 1 - exp(-Dt / EngineSound.VelocitySmoothing)

			Track.Vel:Add((Raw - Track.Vel) * Alpha)
		end
	else
		Track.Vel:Zero()
	end

	Track.Pos:Set(Pos)
	Track.Time = Now

	return Track.Vel
end

local TrackVelocity = EngineSound.TrackVelocity

--- Pitch multiplier for a sound source moving relative to the local player.
-- Uses f' = f * (c + Vl) / (c - Vs), with Vl the listener's speed towards the source and Vs the
-- source's speed towards the listener, c = 343 m/s.
-- @param Source Entity The entity the sound plays from.
-- @return number Multiplier between 0.5 and 2.
function EngineSound.DopplerFactor(Source)
	local Ply = LocalPlayer()
	if not IsValid(Ply) or not IsValid(Source) then return 1 end

	local Ear = Ply:EyePos()
	local Pos = Source:GetPos()
	local SourceVel = TrackVelocity(Source, Pos)
	local EarVel = TrackVelocity(Ply, Ear)
	local Dir = Pos - Ear -- listener to source
	local Dist = Dir:Length()

	if Dist < 1 then return 1 end

	Dir:Div(Dist)

	local C = EngineSound.SpeedOfSound
	local Listener = EarVel:Dot(Dir) -- listener moving towards the source
	local SourceSpeed = -SourceVel:Dot(Dir) -- source moving towards the listener

	return Clamp((C + Listener) / max(C - SourceSpeed, C * 0.1), 0.5, 2)
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
local LegacyPitchVolume = EngineSound.LegacyPitchVolume

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

-- Whether the local player sits in a seat of the engine's vehicle. Uses the server's contraption
-- list for the current seat when there is one, and also accepts a shared physical parent. The
-- view (first or third person) is not part of this: it is checked every frame in the Think hook.
local function InCabin(Ent, Seat)
	if not IsValid(Seat) then return false end
	if Cabin.Known and Cabin.Vehicle == Seat and Cabin.Engines[Ent] then return true end

	return ACE.GetPhysicalParent(Seat) == ACE.GetPhysicalParent(Ent)
end

-- Starter motor: pitch follows the crank (the starter drives it through a fixed gear), volume
-- follows the motor current (highest when bogged down). Every compression stroke loads the
-- starter, so the volume pulses at the compression frequency, crank rev/s * cylinders / 2:
-- a slow, struggling crank audibly chugs, a healthy one blurs into a steady whir.
local function UpdateStarter(Ent, State, Dt, Shift, Muffle)
	if not State.Cranking then
		if State.Starter then
			State.Starter:FadeOut(0.15)
			State.Starter = nil
		end

		return
	end

	-- The engine's own starter sound when it has one that this client can play.
	local Path = Ent:GetNWString("ACE_StarterSound", "")
	if Path == "" or not IsPlayable(Path) then Path = EngineSound.StarterSound end

	if State.Starter and State.StarterPath ~= Path then
		State.Starter:Stop()
		State.Starter = nil
	end

	if not State.Starter then
		State.Starter = NewPatch(Ent, Path, math.min(EngineSound.StarterLevel, State.Level + 5), Muffle >= EngineSound.MuffleDSPFrom and EngineSound.MuffleDSP or nil)
		State.StarterPath = Path
		State.StarterPhase = 0

		if not State.Starter then return end
	end

	local RPM = State.SmoothRPM
	local Load = State.StarterLoad
	local Freq = RPM / 60 * State.Cylinders * 0.5
	local Depth = Clamp(1.1 - Freq / 10, 0.15, 0.85) -- a pulse faster than ~10 Hz is not heard as one

	State.StarterPhase = (State.StarterPhase + TwoPi * Freq * Dt) % TwoPi

	local Pulse = (0.5 + 0.5 * sin(State.StarterPhase)) ^ 3 -- sharp peak on each compression
	local Pitch = 100 * RPM / EngineSound.StarterRefRPM * (1 - 0.12 * Depth * Pulse)
	local Volume = (0.4 + 0.5 * Load) * (1 - Depth * (1 - Pulse)) * (1 - EngineSound.MaxMuffleCut * Muffle)

	State.Starter:ChangePitch(Clamp(Pitch * Shift, 30, 160), 0)
	State.Starter:ChangeVolume(Clamp(Volume, 0, 1), 0)
end

local function UpdateEngine(Ent, State, Alpha, Dt, Doppler)
	State.SmoothRPM = State.SmoothRPM + (State.RPM - State.SmoothRPM) * Alpha
	State.SmoothThrottle = State.SmoothThrottle + (State.Throttle - State.SmoothThrottle) * Alpha

	local RPM, Throttle = State.SmoothRPM, State.SmoothThrottle

	-- Combustion sound level: full while running; after shut-off it fades with the crank speed;
	-- before an engine has run (only the starter turning it) there is none.
	local Level = 0

	if State.Running then
		Level = 1
	elseif State.Ran and State.OffRPM then
		Level = Clamp(RPM / State.OffRPM, 0, 1)
	end

	State.Combustion = State.Combustion + (Level - State.Combustion) * Alpha

	local StarterMuffle = 0

	for _, Playing in ipairs(State.Playing) do
		local Target = Playing.Target
		local Muffle = EngineSound.MuffleOf(State, Playing.Bank)
		local Gain = State.Combustion * (1 - EngineSound.MaxMuffleCut * Muffle)

		StarterMuffle = max(StarterMuffle, Muffle)

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
			Volume = Clamp(Volume * Gain, 0, 1)

			if not Entry.Pitch or abs(Pitch - Entry.Pitch) >= 0.5 then
				Entry.Pitch = Pitch
				Entry.Patch:ChangePitch(Pitch, 0)
			end

			if not Entry.Volume or abs(Volume - Entry.Volume) >= 0.005 then
				-- A patch rebuilt for a muffling switch fades in over the crossfade.
				Entry.Patch:ChangeVolume(Volume, (not Entry.Volume and State.FadeIn) and EngineSound.DSPCrossfade or 0)
				Entry.Volume = Volume
			end
		end
	end

	if State.Cranking or State.Starter then
		UpdateStarter(Ent, State, Dt, Doppler and EngineSound.DopplerFactor(Ent) or 1, StarterMuffle)
	end

	State.FadeIn = nil
end

hook.Add("Think", "ACE_EngineSound_Think", function()
	if not next(Engines) then return end

	local Now = RealTime()
	local Dt = FrameTime()
	local Alpha = 1 - exp(-Dt / EngineSound.SmoothingTime)
	local Doppler = DopplerVar:GetBool()
	local MuffleOn = MuffleVar:GetBool()
	local Ply = LocalPlayer()
	local Seat = MuffleOn and IsValid(Ply) and Ply:GetVehicle() or NULL
	-- First or third person, every frame: switching the view switches the muffling at once.
	local Inside = IsValid(Seat) and FirstPerson(Ply)
	local Smoke = ACE.ExhaustSmoke

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
			-- Whether the engine shares our vehicle changes rarely and costs a parent walk, so it
			-- is checked on a cadence; the view is not (see Inside above).
			if Now >= State.NextCabinCheck then
				State.NextCabinCheck = Now + EngineSound.CabinCheckTime
				State.InSeat = InCabin(Ent, Seat)
			end

			State.Muffled = Inside and State.InSeat or false

			if State.Playing and DSPSignature(State) ~= State.DSPSig then
				-- DSP is set when a patch is created, so rebuild the patches with the new one
				-- this frame, crossfading over a few hundredths of a second.
				StopPatches(State, EngineSound.DSPCrossfade)
				State.FadeIn = true
			end

			if not State.Playing then
				StartPatches(Ent, State)
			end

			UpdateEngine(Ent, State, Alpha, Dt, Doppler)

			if Smoke and State.Exhaust and State.Burns then
				Smoke.Think(State, Dt)
			end
		end
	end
end)

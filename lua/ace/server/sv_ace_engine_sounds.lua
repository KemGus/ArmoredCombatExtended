-- Engine sounds, server side. The server only tells clients which sounds an engine uses and streams
-- its RPM and throttle; pitch, volume, crossfades and Doppler are worked out on each client.

ACE = ACE or {}
ACE.EngineSound = ACE.EngineSound or {}

local EngineSound = ACE.EngineSound

util.AddNetworkString("ACE_EngineSound_Create")
util.AddNetworkString("ACE_EngineSound_Update")
util.AddNetworkString("ACE_EngineSound_Stop")
util.AddNetworkString("ACE_EngineSound_Request")
util.AddNetworkString("ACE_EngineSound_MenuGet")
util.AddNetworkString("ACE_EngineSound_MenuData")
util.AddNetworkString("ACE_EngineSound_MenuSet")

local Clamp = math.Clamp
local Round = math.Round

local KeepAliveInterval = 0.5 -- resend unchanged values this often so clients know the engine is still running
local ExhaustCheckInterval = 1

local DefaultBankCache = {}

local function GetState(Engine)
	local State = Engine.ACE_EngineSoundState

	if not State then
		State = { Active = false, Version = 0, NextSend = 0, LastSent = 0, NextExhaustCheck = 0 }
		Engine.ACE_EngineSoundState = State
	end

	return State
end

-- Banks defined on the engine's definition (Lookup.soundbanks), used while its sound is not replaced.
local function DefaultBanks(Engine)
	local Id = Engine.Id
	if not Id then return end

	local Cached = DefaultBankCache[Id]

	if Cached == nil then
		local Def = ACE.Weapons and ACE.Weapons.Engines and ACE.Weapons.Engines[Id]

		Cached = Def and EngineSound.SanitizeBanks(Def.soundbanks) or false
		DefaultBankCache[Id] = Cached
	end

	return Cached or nil
end

--- Returns the banks an engine plays, or nil when it uses its single legacy sound.
-- @param Engine Entity The acf_engine.
-- @return table|nil Sanitised banks.
function EngineSound.GetBanks(Engine)
	if not IsValid(Engine) then return end
	if Engine.ACE_SoundBanks then return Engine.ACE_SoundBanks end
	if Engine.SoundPath ~= Engine.DefaultSound then return end

	return DefaultBanks(Engine)
end

local function IsMuted(Engine)
	return not EngineSound.GetBanks(Engine) and (Engine.SoundPath or "") == ""
end

local function WriteCreate(Engine, State)
	local Banks = EngineSound.GetBanks(Engine)
	local Exhaust = Engine.ACE_SoundExhaust

	net.WriteEntity(Engine)
	net.WriteEntity(IsValid(Exhaust) and Exhaust or NULL)
	net.WriteUInt(State.Version, 8)
	net.WriteUInt(Clamp(Round(Engine.MaxDB or 75), 0, 255), 8)
	net.WriteBool(Banks ~= nil)

	if Banks then
		EngineSound.WriteBanks(Banks)
	else
		net.WriteString(Engine.SoundPath or "")
		net.WriteUInt(Clamp(Round(Engine.SoundPitch or 100), 0, 255), 8)
		net.WriteUInt(Clamp(Round(Engine.LimitRPM or 6000), 1, 65535), 16)
	end
end

local function BroadcastCreate(Engine, State)
	net.Start("ACE_EngineSound_Create")
	WriteCreate(Engine, State)
	net.SendPAS(Engine:GetPos())
end

--- Starts an engine's sound on nearby clients. Call when the engine turns on.
-- @param Engine Entity The acf_engine.
function EngineSound.Start(Engine)
	if not IsValid(Engine) then return end

	local State = GetState(Engine)

	State.Active = true
	State.Muted = IsMuted(Engine)
	State.NextSend = 0

	if State.Muted then return end

	BroadcastCreate(Engine, State)
end

--- Stops an engine's sound on every client. Call when the engine turns off or is removed.
-- @param Engine Entity The acf_engine.
function EngineSound.Stop(Engine)
	if not IsValid(Engine) then return end

	local State = GetState(Engine)
	if not State.Active then return end

	State.Active = false

	net.Start("ACE_EngineSound_Stop")
	net.WriteEntity(Engine)
	net.Broadcast()
end

--- Resends an engine's sound setup after its sound, banks or exhaust changed.
-- Clients outside the PAS pick up the change through the version number in updates.
-- @param Engine Entity The acf_engine.
function EngineSound.Refresh(Engine)
	if not IsValid(Engine) then return end

	local State = GetState(Engine)

	State.Version = (State.Version + 1) % 256

	if not State.Active then return end

	local WasMuted = State.Muted

	State.Muted = IsMuted(Engine)

	if State.Muted then
		if not WasMuted then
			net.Start("ACE_EngineSound_Stop")
			net.WriteEntity(Engine)
			net.Broadcast()
		end

		return
	end

	BroadcastCreate(Engine, State)
end

local function CheckExhaust(Engine)
	local Exhaust = Engine.ACE_SoundExhaust
	if Exhaust == nil then return end

	if not IsValid(Exhaust) or Engine:GetPos():Distance(Exhaust:GetPos()) > EngineSound.MaxExhaustDistance then
		Engine.ACE_SoundExhaust = nil
		Engine:EmitSound("physics/metal/metal_sheet_impact_bullet" .. math.random(1, 2) .. ".wav", 70, 100)
		EngineSound.Refresh(Engine)
	end
end

--- Streams an engine's RPM and throttle to nearby clients. Safe to call every tick; it rate limits itself.
-- @param Engine Entity The acf_engine.
-- @param RPM number Current flywheel RPM.
-- @param Throttle number Throttle from 0 to 1.
function EngineSound.Update(Engine, RPM, Throttle)
	if not IsValid(Engine) then return end

	local State = GetState(Engine)
	if not State.Active or State.Muted then return end

	local Now = CurTime()
	if Now < State.NextSend then return end

	if Now >= State.NextExhaustCheck then
		State.NextExhaustCheck = Now + ExhaustCheckInterval
		CheckExhaust(Engine)
	end

	RPM = Clamp(Round(tonumber(RPM) or 0), 0, 65535)
	Throttle = Clamp(Round((tonumber(Throttle) or 0) * 100), 0, 100)

	local Changed = State.LastRPM ~= RPM or State.LastThrottle ~= Throttle

	if not Changed and Now - State.LastSent < KeepAliveInterval then return end

	State.NextSend = Now + EngineSound.UpdateInterval
	State.LastSent = Now
	State.LastRPM = RPM
	State.LastThrottle = Throttle

	net.Start("ACE_EngineSound_Update", true)
	net.WriteEntity(Engine)
	net.WriteUInt(State.Version, 8)
	net.WriteUInt(RPM, 16)
	net.WriteUInt(Throttle, 7)
	net.SendPAS(Engine:GetPos())
end

--- Sets the entity exhaust banks play from. Wired to the engine's "Exhaust" input.
-- @param Engine Entity The acf_engine.
-- @param Exhaust Entity The exhaust entity, or NULL/nil to play everything at the engine.
function EngineSound.SetExhaust(Engine, Exhaust)
	if not IsValid(Engine) then return end

	if not IsValid(Exhaust) or Exhaust == Engine then
		Exhaust = nil
	elseif Engine:GetPos():Distance(Exhaust:GetPos()) > EngineSound.MaxExhaustDistance then
		local Owner = Engine:CPPIGetOwner()

		if IsValid(Owner) then
			ACE.SendNotify(Owner, false, "The exhaust is too far from the engine (max " .. EngineSound.MaxExhaustDistance .. " units).")
		end

		Exhaust = nil
	end

	if Engine.ACE_SoundExhaust == Exhaust then return end

	Engine.ACE_SoundExhaust = Exhaust
	EngineSound.Refresh(Engine)
end

--- Replaces an engine's sound banks and stores them for the duplicator.
-- @param Engine Entity The acf_engine.
-- @param Banks table|nil Banks to use; nil goes back to the single legacy sound.
-- @return boolean True if banks are now set.
function EngineSound.SetBanks(Engine, Banks)
	if not IsValid(Engine) then return false end

	local Clean = EngineSound.SanitizeBanks(Banks)

	Engine.ACE_SoundBanks = Clean

	if Clean then
		duplicator.StoreEntityModifier(Engine, "ace_enginesoundbanks", { Banks = Clean })
	else
		duplicator.ClearEntityModifier(Engine, "ace_enginesoundbanks")
	end

	EngineSound.Refresh(Engine)

	return Clean ~= nil
end

duplicator.RegisterEntityModifier("ace_enginesoundbanks", function(_, Engine, Data)
	if not IsValid(Engine) or not istable(Data) then return end

	EngineSound.SetBanks(Engine, Data.Banks)
end)

-- Rate limit for client requests, per player.
local function AllowRequest(Ply, Key, Interval)
	local Now = CurTime()
	local Limits = Ply.ACE_EngineSoundLimits

	if not Limits then
		Limits = {}
		Ply.ACE_EngineSoundLimits = Limits
	end

	if (Limits[Key] or 0) > Now then return false end

	Limits[Key] = Now + Interval

	return true
end

local EngineClasses = { acf_engine = true, ace_engine = true }

-- At most MaxRequests sound requests per player per second; entering a busy PAS can need several at once.
local MaxRequests = 20

local function AllowSoundRequest(Ply)
	local Now = CurTime()

	if not Ply.ACE_EngineSoundWindow or Ply.ACE_EngineSoundWindow <= Now then
		Ply.ACE_EngineSoundWindow = Now + 1
		Ply.ACE_EngineSoundCount = 0
	end

	Ply.ACE_EngineSoundCount = Ply.ACE_EngineSoundCount + 1

	return Ply.ACE_EngineSoundCount <= MaxRequests
end

-- A client heard an update for an engine it has no data for, usually because it just entered the PAS.
net.Receive("ACE_EngineSound_Request", function(_, Ply)
	local Engine = net.ReadEntity()

	if not IsValid(Ply) or not IsValid(Engine) then return end

	local State = Engine.ACE_EngineSoundState
	if not State or not AllowSoundRequest(Ply) then return end
	if not State.Active or State.Muted then return end

	net.Start("ACE_EngineSound_Create")
	WriteCreate(Engine, State)
	net.Send(Ply)
end)

local function CanEdit(Ply, Engine)
	return IsValid(Ply) and IsValid(Engine) and EngineClasses[Engine:GetClass()] and Engine:CPPICanTool(Ply, "acesound")
end

net.Receive("ACE_EngineSound_MenuGet", function(_, Ply)
	local Engine = net.ReadEntity()

	if not AllowRequest(Ply, "menuget", 0.25) or not CanEdit(Ply, Engine) then return end

	local Banks = EngineSound.GetBanks(Engine)
	local IsLegacy = Banks == nil

	if IsLegacy then
		Banks = EngineSound.BanksFromLegacy(Engine.SoundPath, Engine.SoundPitch, Engine.IdleRPM, Engine.LimitRPM) or {}
	end

	net.Start("ACE_EngineSound_MenuData")
	net.WriteEntity(Engine)
	net.WriteBool(IsLegacy)
	net.WriteUInt(Clamp(Round(Engine.IdleRPM or 0), 0, 65535), 16)
	net.WriteUInt(Clamp(Round(Engine.LimitRPM or 0), 0, 65535), 16)
	EngineSound.WriteBanks(Banks)
	net.Send(Ply)
end)

net.Receive("ACE_EngineSound_MenuSet", function(_, Ply)
	local Engine = net.ReadEntity()
	local Reset = net.ReadBool()
	local Banks = not Reset and EngineSound.ReadBanks() or nil

	if not AllowRequest(Ply, "menuset", 0.5) then
		ACE.SendNotify(Ply, false, "Slow down - wait a moment before applying again.")
		return
	end

	if not CanEdit(Ply, Engine) then
		ACE.SendNotify(Ply, false, "You can't edit the sounds of that engine.")
		return
	end

	if Reset then
		EngineSound.SetBanks(Engine, nil)
		ACE.SendNotify(Ply, true, "Engine sound banks removed - using the single engine sound.")
	elseif EngineSound.SetBanks(Engine, Banks) then
		ACE.SendNotify(Ply, true, "Engine sound banks applied.")
	else
		ACE.SendNotify(Ply, false, "No valid sounds in those banks.")
	end
end)

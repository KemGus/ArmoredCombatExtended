-- Engine sound banks: limits, validation and the network format shared by server and client.
--
-- An engine either uses its single legacy sound (SoundPath/SoundPitch, pitch and volume from the
-- original ACE formula) or a list of banks. Each bank crossfades up to MaxSounds recordings by RPM
-- and plays at the engine or at a wired "Exhaust" entity. Multi-sound banks are ported from
-- ACF-3 PR #556 (TeeMeeFe, with the crossfade from mgcheezus's interpolation chip).
--
-- Bank format:
--   { Exhaust = bool, OffVolume = 0-1, OnVolume = 0-1,
--     Sounds = { { Path = string, RPM = number, Pitch = 1-255, Volume = 0-2, Width = 0-15 }, ... } }

ACE = ACE or {}
ACE.EngineSound = ACE.EngineSound or {}

local EngineSound = ACE.EngineSound

EngineSound.MaxBanks           = 4
EngineSound.MaxSounds          = 16 -- per bank
EngineSound.MaxWidth           = 15
EngineSound.MaxRPM             = 65535
EngineSound.MaxPathLength      = 200
EngineSound.MaxVolume          = 2
EngineSound.UpdateInterval     = 0.05 -- seconds between RPM/throttle updates (20 Hz)
EngineSound.MaxExhaustDistance = 512 -- same as the fuel tank link distance
EngineSound.SpeedOfSound       = 343 * 39.37 -- units per second

local BankBits  = 3 -- up to 7 banks
local SoundBits = 5 -- up to 31 sounds

local Clamp = math.Clamp
local Round = math.Round

local function Number(Value, Default, Min, Max)
	Value = tonumber(Value)

	if not Value or Value ~= Value then return Default end

	return Clamp(Value, Min, Max)
end

-- Sound paths are relative to sound/, plain characters only.
local function CleanPath(Path)
	if not isstring(Path) then return end

	Path = string.Trim(Path):lower():gsub("\\", "/")

	if Path == "" or #Path > EngineSound.MaxPathLength then return end
	if Path:find("..", 1, true) or Path:find("[^%w_%-%./ ]") then return end

	return Path
end

--- Validates and normalises a list of sound banks.
-- Drops bad entries, clamps every value and sorts each bank's sounds by RPM.
-- @param Banks table List of banks in the format described at the top of this file.
-- @return table|nil Clean banks, or nil if nothing usable was left.
function EngineSound.SanitizeBanks(Banks)
	if not istable(Banks) then return end

	local Clean = {}

	for _, Bank in ipairs(Banks) do
		if #Clean >= EngineSound.MaxBanks then break end

		if istable(Bank) and istable(Bank.Sounds) then
			local Sounds = {}

			for _, Snd in ipairs(Bank.Sounds) do
				if #Sounds >= EngineSound.MaxSounds then break end

				local Path = istable(Snd) and CleanPath(Snd.Path)

				if Path then
					Sounds[#Sounds + 1] = {
						Path   = Path,
						RPM    = Round(Number(Snd.RPM, 1000, 1, EngineSound.MaxRPM)),
						Pitch  = Round(Number(Snd.Pitch, 100, 1, 255)),
						Volume = Round(Number(Snd.Volume, 1, 0, EngineSound.MaxVolume), 2),
						Width  = Round(Number(Snd.Width, 0, 0, EngineSound.MaxWidth)),
					}
				end
			end

			if #Sounds > 0 then
				table.sort(Sounds, function(A, B) return A.RPM < B.RPM end)

				Clean[#Clean + 1] = {
					Exhaust   = Bank.Exhaust == true,
					OffVolume = Round(Number(Bank.OffVolume, 0.25, 0, 1), 2),
					OnVolume  = Round(Number(Bank.OnVolume, 1, 0, 1), 2),
					Sounds    = Sounds,
				}
			end
		end
	end

	if #Clean == 0 then return end

	return Clean
end

--- Writes sanitised banks to the current net message.
-- @param Banks table Banks from EngineSound.SanitizeBanks.
function EngineSound.WriteBanks(Banks)
	local Count = math.min(#Banks, EngineSound.MaxBanks)

	net.WriteUInt(Count, BankBits)

	for I = 1, Count do
		local Bank = Banks[I]
		local SoundCount = math.min(#Bank.Sounds, EngineSound.MaxSounds)

		net.WriteBool(Bank.Exhaust)
		net.WriteUInt(Round(Bank.OffVolume * 100), 7)
		net.WriteUInt(Round(Bank.OnVolume * 100), 7)
		net.WriteUInt(SoundCount, SoundBits)

		for J = 1, SoundCount do
			local Snd = Bank.Sounds[J]

			net.WriteString(Snd.Path)
			net.WriteUInt(Snd.RPM, 16)
			net.WriteUInt(Snd.Pitch, 8)
			net.WriteUInt(Round(Snd.Volume * 100), 8)
			net.WriteUInt(Snd.Width, 4)
		end
	end
end

--- Reads banks written by EngineSound.WriteBanks. The result is sanitised again.
-- @return table|nil Banks, or nil if none were valid.
function EngineSound.ReadBanks()
	local Banks = {}

	for I = 1, net.ReadUInt(BankBits) do
		local Bank = {
			Exhaust   = net.ReadBool(),
			OffVolume = net.ReadUInt(7) / 100,
			OnVolume  = net.ReadUInt(7) / 100,
			Sounds    = {},
		}

		for J = 1, net.ReadUInt(SoundBits) do
			Bank.Sounds[J] = {
				Path   = net.ReadString(),
				RPM    = net.ReadUInt(16),
				Pitch  = net.ReadUInt(8),
				Volume = net.ReadUInt(8) / 100,
				Width  = net.ReadUInt(4),
			}
		end

		Banks[I] = Bank
	end

	return EngineSound.SanitizeBanks(Banks)
end

--- Builds a one-sound bank that approximates the legacy single-sound pitch at mid RPM.
-- Used as a starting point by the bank editor.
-- @param Path string Sound path.
-- @param SoundPitch number Legacy pitch percentage (100 = normal).
-- @param IdleRPM number Engine idle RPM.
-- @param LimitRPM number Engine redline RPM.
-- @return table|nil Banks list with one bank, or nil if the path is empty.
function EngineSound.BanksFromLegacy(Path, SoundPitch, IdleRPM, LimitRPM)
	local MidRPM = ((IdleRPM or 800) + (LimitRPM or 6000)) * 0.5
	local Pitch = math.min(20 + MidRPM * ((SoundPitch or 100) / 100) / 50, 255)

	return EngineSound.SanitizeBanks({
		{ Sounds = { { Path = Path, RPM = MidRPM, Pitch = Pitch, Volume = 1, Width = 0 } } }
	})
end

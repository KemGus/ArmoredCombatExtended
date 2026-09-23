local root = assert(arg[1], "usage: ace_engine_sounds_luajit_selftest.lua <ACE repo>")
root = root:gsub("\\\\", "/"):gsub("/$", "")

local function readFile(path)
	local handle = assert(io.open(root .. "/" .. path, "r"))
	local source = handle:read("*a")
	handle:close()
	return source
end

-- Minimal GMod shims used by the shared sound file.
function istable(v) return type(v) == "table" end
function isstring(v) return type(v) == "string" end
function string.Trim(s) return (s:gsub("^%s+", ""):gsub("%s+$", "")) end
function math.Clamp(v, lo, hi) return math.min(math.max(v, lo), hi) end
function math.Round(v, d)
	local m = 10 ^ (d or 0)
	return math.floor(v * m + 0.5) / m
end

-- Fake net library: writes append to a queue, reads pop from it.
local queue, readIndex = {}, 1
net = {}
for _, kind in ipairs({ "UInt", "Bool", "String" }) do
	net["Write" .. kind] = function(value) queue[#queue + 1] = value end
	net["Read" .. kind] = function()
		local value = queue[readIndex]
		readIndex = readIndex + 1
		return value
	end
end

ACE = {}
assert(loadstring(readFile("lua/ace/shared/sh_ace_engine_sounds.lua")))()

local EngineSound = ACE.EngineSound

-- Sanitising clamps values, drops bad paths and sorts by RPM
local clean = EngineSound.SanitizeBanks({
	{ Exhaust = true, OffVolume = 5, Sounds = {
		{ Path = " Engines/High.WAV ", RPM = 6000, Pitch = 400, Volume = 3, Width = 99 },
		{ Path = "../escape.wav", RPM = 1000 },
		{ Path = "engines/low.wav", RPM = 900 },
	} },
	{ Sounds = {} },
})
assert(#clean == 1, "empty bank should be dropped")
local bank = clean[1]
assert(bank.Exhaust == true and bank.OffVolume == 1 and bank.OnVolume == 1)
assert(#bank.Sounds == 2, "path with .. should be rejected")
assert(bank.Sounds[1].Path == "engines/low.wav" and bank.Sounds[2].Path == "engines/high.wav")
assert(bank.Sounds[2].Pitch == 255 and bank.Sounds[2].Volume == 2 and bank.Sounds[2].Width == 15)
assert(EngineSound.SanitizeBanks({}) == nil)

-- Net round trip keeps the banks
EngineSound.WriteBanks(clean)
local back = EngineSound.ReadBanks()
assert(readIndex == #queue + 1, "reader must consume exactly what the writer wrote")
assert(#back == 1 and #back[1].Sounds == 2)
for i, snd in ipairs(clean[1].Sounds) do
	for key, value in pairs(snd) do
		assert(back[1].Sounds[i][key] == value, "round trip changed " .. key)
	end
end

-- Legacy conversion matches the old pitch formula at mid RPM
local legacy = EngineSound.BanksFromLegacy("engines/v8.wav", 100, 1000, 5000)
assert(legacy[1].Sounds[1].RPM == 3000 and legacy[1].Sounds[1].Pitch == 80)

-- Equal-power crossfade from the client file: neighbour weights squared sum to 1
local client = readFile("lua/ace/client/cl_ace_engine_sounds.lua")
local fadeStart = assert(client:find("function EngineSound.Fade", 1, true))
local fadeEnd = assert(client:find("\nlocal Fade = EngineSound.Fade", fadeStart, true))
local fadeChunk = assert(loadstring("local cos, HalfPi, EngineSound = math.cos, math.pi * 0.5, ACE.EngineSound\n"
	.. client:sub(fadeStart, fadeEnd)))
fadeChunk()

local Fade = EngineSound.Fade
for rpm = 1000, 3000, 125 do
	local a = Fade(rpm, nil, 1000, 3000)
	local b = Fade(rpm, 1000, 3000, nil)
	assert(math.abs(a * a + b * b - 1) < 1e-9, "crossfade is not equal-power at " .. rpm)
end
assert(Fade(500, nil, 1000, 3000) == 1 and Fade(9000, 1000, 3000, nil) == 1)
assert(Fade(3500, 500, 1000, 3000) == 0)

print("ACE engine sounds LuaJIT self-test: PASS")

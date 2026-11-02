-- ACE Small Arms: lets weapon packs (TFA, CW 2.0, ArcCW, ARC9, M9K, GMod base) fire through ACE ballistics.
-- Requires Armored Combat Extended. Weapons opt in with SWEP.ACE_Round or ACE.SmallArms.SetWeaponRound.

AddCSLuaFile()

ACE = ACE or {}
ACE.SmallArms = ACE.SmallArms or {}

-- Replicated so clients only hide the pack's own tracers while the server is swapping bullets.
ACE.SmallArms.Enabled = CreateConVar("ace_smallarms_enabled", "1", { FCVAR_ARCHIVE, FCVAR_REPLICATED, FCVAR_NOTIFY },
	"Fire weapon pack bullets through ACE ballistics: 1 = on, 0 = off", 0, 1)
ACE.SmallArms.DamageMode = CreateConVar("ace_smallarms_damage", "pack", { FCVAR_ARCHIVE, FCVAR_REPLICATED, FCVAR_NOTIFY },
	"Small-arms damage to players/NPCs: pack = the weapon pack's own damage, ace = ACE physics damage")
ACE.SmallArms.PenMul = CreateConVar("ace_smallarms_penmul", "1", { FCVAR_ARCHIVE, FCVAR_REPLICATED, FCVAR_NOTIFY },
	"Multiplies the armor penetration of every small-arms round (1 = default)", 0.1, 10)

local function IncludeShared(Path)
	if SERVER then AddCSLuaFile(Path) end
	include(Path)
end

local function IncludeServer(Path)
	if SERVER then include(Path) end
end

IncludeShared("ace/smallarms/sh_rounds.lua")
IncludeShared("ace/smallarms/sh_default_rounds.lua")
IncludeShared("ace/smallarms/sh_weapon_patch.lua")
IncludeServer("ace/smallarms/sv_fire.lua")
IncludeServer("ace/smallarms/sv_damage.lua")
IncludeShared("ace/smallarms/sh_firebullets.lua")

local function IncludeClient(Path)
	if SERVER then AddCSLuaFile(Path) else include(Path) end
end

IncludeClient("ace/smallarms/cl_options.lua")
IncludeClient("ace/smallarms/cl_stats.lua")

-- Shipped round tables for popular packs. Packs that set SWEP.ACE_Round themselves win over these.
for _, File in ipairs(file.Find("ace/smallarms/weapons/*.lua", "LUA")) do
	IncludeShared("ace/smallarms/weapons/" .. File)
end

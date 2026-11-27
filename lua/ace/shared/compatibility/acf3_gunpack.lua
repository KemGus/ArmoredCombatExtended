--[[
	ACF-3 compatibility layer for scalable guns.

	ACF-3 defines weapons with a caliber ENVELOPE (Caliber = {Base, Min, Max},
	in millimeters) and links ammo by weapon class + caliber match rather than
	exact ids. ACE's ACE.GunScale kernel expresses the same idea with a base def
	plus a key suffix, so the bridge is mostly unit/shape translation.

	This file:
		- Provides ACE.GunScale.ImportACF3, which converts an ACF-3-style weapon
		  definition into an ACE.DefineGun call (caliber cm, calrange mm,
		  scalable envelope).
		- Provides ACE.GunScale.ACF3CanLink, the ACF-3 link predicate (class +
		  caliber inside the weapon envelope), for extensions that replicated
		  ACF_CheckWeapon.
		- Installs ACF_/ACF3_ global aliases, but ONLY while ACE owns the
		  compatibility ACF namespace (same guard as the rest of acf_globals):
		  a real ACF-3 install keeps its own loader and is never masked.
]]--

AddCSLuaFile()

ACE = ACE or {}
ACE.GunScale = ACE.GunScale or {}

local GunScale = ACE.GunScale

--- Translates an ACF-3 weapon definition into an ACE gun definition.
-- ACF-3 fields used: Model, Mass, Caliber{Base,Min,Max} (mm),
-- Round{MaxLength,PropWeight} (cm/kg), GunClass, Spread, Sound, MuzzleFlash,
-- Year, Name, Description, ROFMod, MaxROF, MagSize, MagReload, BoreLength.
-- Unknown fields are ignored. The returned table is not registered - pass it
-- to ACE.DefineGun or ImportACF3.
-- @param def table ACF-3-style weapon definition.
-- @return table ACE-style gun definition.
function GunScale.TranslateACF3Def( def )
	if not istable( def ) then return end

	local cal = def.Caliber or {}
	local baseMM = tonumber( cal.Base ) or tonumber( def.caliber )
	local round = def.Round or {}

	return {
		name       = def.Name or def.name or "Imported ACF-3 Gun",
		desc       = def.Description or def.desc or "",
		model      = def.Model or def.model,
		gunclass   = def.GunClass or def.gunclass or "C",
		caliber    = ( baseMM or 0 ) / 10, -- ACF-3 calibers are mm, ACE are cm
		weight     = def.Mass or def.weight or 0,
		year       = def.Year or def.year or 0,
		spread     = def.Spread or def.spread,
		sound      = def.Sound or def.sound,
		muzzleflash = def.MuzzleFlash or def.muzzleflash,
		rofmod     = def.ROFMod or def.rofmod,
		maxrof     = def.MaxROF or def.maxrof,
		magsize    = def.MagSize or def.magsize,
		magreload  = def.MagReload or def.magreload,
		borelength = def.BoreLength or def.borelength,
		-- The ACF-3 envelope becomes an explicit mm range on the def.
		calrange   = ( cal.Min and cal.Max ) and { cal.Min, cal.Max } or nil,
		scalable   = ( cal.Min and cal.Max ) and true or false,
		round = {
			maxlength  = tonumber( round.MaxLength or round.maxlength ) or 0,
			propweight = tonumber( round.PropWeight or round.propweight ) or 0,
		},
	}
end

--- Registers an ACF-3-style weapon definition as an ACE scalable gun.
-- @param id string Definition id (e.g. "120mmC").
-- @param def table ACF-3-style weapon definition.
-- @return table|nil The translated ACE definition.
function GunScale.ImportACF3( id, def )
	local aceDef = GunScale.TranslateACF3Def( def )
	if not aceDef then return end

	ACE.DefineGun( id, aceDef )
	return aceDef
end

--- ACF-3 weapon/round link predicate: same weapon class, and the round's
-- caliber inside the weapon's caliber envelope. weapon can be a def table, a
-- spawned gun entity, or an id/key string; roundCal is in millimeters.
-- @return boolean
function GunScale.ACF3CanLink( weapon, gunclass, roundCalMM )
	local Limits
	if isentity( weapon ) then
		Limits = weapon.ScalableSpec or GunScale.Limits( weapon.Id )
	elseif isstring( weapon ) then
		Limits = GunScale.Limits( weapon )
	elseif istable( weapon ) then
		Limits = GunScale.Limits( weapon.id )
	end
	if not Limits then return false end

	if gunclass then
		local def = isstring( weapon ) and GunScale.ResolveDef( weapon )
			or ( isentity( weapon ) and GunScale.ResolveDef( weapon.Id ) )
			or weapon
		if istable( def ) and def.gunclass ~= gunclass then return false end
	end

	roundCalMM = tonumber( roundCalMM )
	if not roundCalMM then return false end

	return roundCalMM >= Limits.calmin * 10 - 0.05 and roundCalMM <= Limits.calmax * 10 + 0.05
end

-- Only install global aliases while ACE owns the compatibility ACF namespace;
-- a real ACF-3 install (autorun/acf_loader.lua) keeps its own symbols.
if not file.Exists( "autorun/acf_loader.lua", "LUA" )
and ( ACF == nil or rawget( ACF, "__ACECompatibilityView" ) ) then

	local Aliases = {
		{ name = "ACF3_ImportGun",     target = "ImportACF3" },
		{ name = "ACF3_CanLinkWeapon", target = "ACF3CanLink" },
	}

	for _, Alias in ipairs( Aliases ) do
		if rawget( _G, Alias.name ) == nil then
			rawset( _G, Alias.name, function( ... ) return GunScale[ Alias.target ]( ... ) end )
		end
	end
end

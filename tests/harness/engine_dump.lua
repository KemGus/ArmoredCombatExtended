-- engine_dump.lua
-- Server-side behaviour dump of every stock ACE engine, used to prove a refactor of
-- lua/entities/acf_engine/ changed nothing. Run with:
--   python -m gmodkit lua --file tests/harness/engine_dump.lua      (starts the run)
--   python -m gmodkit lua "return ENGINE_DUMP_STATUS"               (poll until "done")
-- Output: garrysmod/data/ace_engine_dump.json (sorted keys, floats rounded to 3 decimals).
-- For each engine id: spawn through ACE.MakeEngine (what the tool and the duplicator call),
-- freeze, snapshot, link a stock gearbox and a matching fuel tank, Active=1 and Throttle=100
-- through the wire inputs, step a fixed number of ticks, snapshot, then duplicator.Copy +
-- duplicator.Paste and snapshot the copy.

local OUT_FILE   = "ace_engine_dump.json"
local SIM_TICKS  = 300
local GEARBOX_ID = "1Gear-T-S"

-- Entity fields that differ from run to run for reasons unrelated to engine behaviour
-- (entity indices, absolute CurTime stamps, randomised legality timers). Filled in from the
-- run-to-run diff; see the task report for which ones and why.
local VOLATILE = {
	-- absolute CurTime stamps: shift with how long the server has been up
	LastDamageTime = true, LastFeedFlush = true, LastThink = true, MobMassAt = true,
	MobSolvedAt = true, NextFeedFlush = true, NextFeedScan = true, NextLegalCheck = true,
	NextUpdate = true, ThermalLast = true, acfphysstale = true,
	-- tables whose numeric sum is dominated by such stamps (ACE and ACF are the same table;
	-- ACE is dumped key by key through the sub-table list in snapshot())
	-- CFW contraption counter, grows with every spawn of the session
	["ACE.ContraptionId"] = true,
	ACF = true, ACE = true, ACE_EngineSoundState = true, OverlayData = true,
}

local function round3( n )
	if n ~= n then return "nan" end
	if n == math.huge then return "inf" end
	if n == -math.huge then return "-inf" end
	local s = string.format( "%.3f", n )
	if s == "-0.000" then s = "0.000" end
	return s
end

local function esc( s )
	return ( s:gsub( '[%c"\\]', function( c )
		if c == '"' then return '\\"' elseif c == "\\" then return "\\\\" end
		return string.format( "\\u%04x", c:byte() )
	end ) )
end

local function enc( v )
	local t = type( v )
	if t == "number" then
		local s = round3( v )
		if s == "nan" or s == "inf" or s == "-inf" then return '"' .. s .. '"' end
		return s
	elseif t == "boolean" then return tostring( v )
	elseif t == "string" then return '"' .. esc( v ) .. '"'
	elseif t == "nil" then return "null"
	elseif t == "table" then
		if #v > 0 and table.Count( v ) == #v then
			local items = {}
			for i = 1, #v do items[i] = enc( v[i] ) end
			return "[" .. table.concat( items, "," ) .. "]"
		end
		local keys = {}
		for k in pairs( v ) do keys[#keys + 1] = k end
		table.sort( keys, function( a, b ) return tostring( a ) < tostring( b ) end )
		local parts = {}
		for _, k in ipairs( keys ) do parts[#parts + 1] = '"' .. esc( tostring( k ) ) .. '":' .. enc( v[k] ) end
		return "{" .. table.concat( parts, "," ) .. "}"
	end
	return '"' .. esc( tostring( v ) ) .. '"'
end

-- Scalars as they are; vectors and angles as rounded strings; tables as their size and the sum
-- of their numeric values (torque curves, rpm tables). Entities, functions and the rest skipped.
local function scalar( Tab, Into, Prefix )
	for k, v in pairs( Tab ) do
		local t = type( v )
		local name = Prefix .. tostring( k )
		if not VOLATILE[name] then
			if t == "number" or t == "string" or t == "boolean" then
				Into[name] = v
			elseif t == "Vector" then
				Into[name] = round3( v.x ) .. " " .. round3( v.y ) .. " " .. round3( v.z )
			elseif t == "Angle" then
				Into[name] = round3( v.p ) .. " " .. round3( v.y ) .. " " .. round3( v.r )
			elseif t == "table" then
				local n, sum = 0, 0
				for _, x in pairs( v ) do
					n = n + 1
					if isnumber( x ) then sum = sum + x end
				end
				Into[name .. "#n"] = n
				Into[name .. "#sum"] = sum
			end
		end
	end
end

local function snapshot( Eng )
	local S = {}
	scalar( Eng:GetTable(), S, "" )
	for _, sub in ipairs( { "MobSpec", "ThermalSpec", "MobState", "ThermalState", "ACE" } ) do
		if istable( Eng[sub] ) then scalar( Eng[sub], S, sub .. "." ) end
	end
	local Phys = Eng:GetPhysicsObject()
	S["_model"]      = Eng:GetModel()
	S["_physMass"]   = IsValid( Phys ) and Phys:GetMass() or -1
	S["_physFrozen"] = IsValid( Phys ) and not Phys:IsMotionEnabled() or false
	S["_wireName"]   = Eng:GetNWString( "WireName" )
	local Menu = Eng.GetMenuSettings and Eng:GetMenuSettings()
	if Menu then S["_menuId"] = Menu.Id end
	-- the registered definition the engine was built from
	local Def = ACE.Weapons.Engines[Eng.Id or ""]
	if Def then
		for _, f in ipairs( { "torque", "peakpower", "peakpowerrpm", "idlerpm", "limitrpm", "flywheelmass", "weight" } ) do
			S["_def." .. f] = Def[f]
		end
	end
	return S
end

ENGINE_DUMP_STATUS = "starting"
file.Delete( OUT_FILE )

local function Fail( Msg ) ENGINE_DUMP_STATUS = "error: " .. tostring( Msg ) end

GKV.EnsureOwner( 0, function( Owner, Err )
	if not Owner then return Fail( Err ) end

	local Ids = {}
	for Id in pairs( ACE.Weapons.Engines ) do Ids[#Ids + 1] = Id end
	table.sort( Ids )

	local Results, Ents = {}, {}
	local HarnessErrors = {}
	local Cols = 12
	local Spacing = 700
	local Z = GKV.GroundZ( 0, 0 ) + 400

	local function Freeze( E )
		local P = E:GetPhysicsObject()
		if IsValid( P ) then P:EnableMotion( false ) end
	end

	local function Try( Name, f )
		local ok, err = pcall( f )
		if not ok then HarnessErrors[#HarnessErrors + 1] = Name .. ": " .. tostring( err ) end
	end

	-- Phase 1: spawn, snapshot, link, activate.
	for I, Id in ipairs( Ids ) do
		local Col, Row = ( I - 1 ) % Cols, math.floor( ( I - 1 ) / Cols )
		local Pos = Vector( -3850 + Col * Spacing, -3000 + Row * Spacing, Z )
		local R = { id = Id }
		Results[Id] = R
		Try( Id .. " spawn", function()
			local Eng = ACE.MakeEngine( Owner, Pos, Angle( 0, 0, 0 ), Id )
			if not IsValid( Eng ) then R.spawned = false return end
			R.spawned = true
			Ents[#Ents + 1] = Eng
			Freeze( Eng )
			R.engine = Eng
			R.spawn = snapshot( Eng )

			local Gear = ACE.MakeGearbox( Owner, Pos, Angle( 0, 0, 0 ), GEARBOX_ID, 0.1, 0.2, 0.3, 0.4, 0.5, 0.6, 0.7, 0.8, 0.9, 0.5 )
			if IsValid( Gear ) then
				Ents[#Ents + 1] = Gear
				Freeze( Gear )
				local OutW = Eng:LocalToWorld( Eng.Out )
				-- The shaft leaves along the engine's forward axis (transaxial: its left side) and
				-- ENT:Checkdriveshaft wants the gearbox input behind that point.
				local Dir = Eng.IsTrans and -Eng:GetRight() or Eng:GetForward()
				Gear:SetPos( Gear:GetPos() + ( OutW - Dir * 30 - Gear:LocalToWorld( Gear.In ) ) )
				local ok, Msg = Eng:Link( Gear )
				R.gearLinked, R.gearMsg = ok == true, Msg
			else
				R.gearLinked, R.gearMsg = false, "gearbox did not spawn"
			end

			local FuelName = Eng.FuelType == "Multifuel" and "Diesel" or Eng.FuelType
			local Tank = ACE.MakeFuelTank( Owner, Pos + Vector( 0, 250, 0 ), Angle( 0, 0, 0 ), "Tank_4x4x2", "Tank_4x4x2", FuelName, "Box" )
			if IsValid( Tank ) then
				Ents[#Ents + 1] = Tank
				Freeze( Tank )
				local ok, Msg = Eng:Link( Tank )
				R.fuelLinked, R.fuelMsg = ok == true, Msg
			else
				R.fuelLinked, R.fuelMsg = false, "tank did not spawn"
			end

			-- Big engines would otherwise switch themselves off for want of a driver; the
			-- spawn snapshot above already holds the real RequiresDriver value.
			Eng.RequiresDriver = false
			WireLib.TriggerInput( Eng, "Active", 1 )
			WireLib.TriggerInput( Eng, "Throttle", 100 )
		end )
	end

	-- Phase 2: step a fixed number of ticks, snapshot, then copy and paste.
	local Ticks = 0
	local HookName = "ace_engine_dump"
	hook.Add( "Tick", HookName, function()
		Ticks = Ticks + 1
		if Ticks < SIM_TICKS then return end
		hook.Remove( "Tick", HookName )

		local Pasted = {}
		for _, Id in ipairs( Ids ) do
			local R = Results[Id]
			local Eng = R.engine
			if IsValid( Eng ) then
				Try( Id .. " after", function()
					R.after = snapshot( Eng )
					R.flyRPM = Eng.FlyRPM
				end )
				Try( Id .. " paste", function()
					local Dupe = { Entities = {}, Constraints = {} }
					duplicator.Copy( Eng, Dupe )
					for _, D in pairs( Dupe.Entities ) do D.Pos = D.Pos + Vector( 0, -250, 0 ) end
					local Created = duplicator.Paste( Owner, Dupe.Entities, Dupe.Constraints )
					for _, P in pairs( Created ) do
						Ents[#Ents + 1] = P
						Freeze( P )
						Pasted[#Pasted + 1] = { id = Id, ent = P }
					end
				end )
			end
		end

		-- A few ticks later the pasted copies have finished their own initialisation.
		local Wait = 0
		hook.Add( "Tick", HookName, function()
			Wait = Wait + 1
			if Wait < 5 then return end
			hook.Remove( "Tick", HookName )

			for _, P in ipairs( Pasted ) do
				Try( P.id .. " pasteSnap", function()
					if IsValid( P.ent ) then Results[P.id].pasted = snapshot( P.ent ) end
				end )
			end

			local Out = { engines = {}, harnessErrors = HarnessErrors, simTicks = SIM_TICKS, gearbox = GEARBOX_ID }
			for _, Id in ipairs( Ids ) do
				local R = Results[Id]
				R.engine = nil
				Out.engines[#Out.engines + 1] = R
			end
			file.Write( OUT_FILE, enc( Out ) )

			for _, E in ipairs( Ents ) do if IsValid( E ) then E:Remove() end end
			ENGINE_DUMP_STATUS = "done"
		end )
	end )
	ENGINE_DUMP_STATUS = "running"
end )

return "started"

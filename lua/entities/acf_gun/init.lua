AddCSLuaFile("cl_init.lua")
AddCSLuaFile("shared.lua")

include("shared.lua")

local GunClasses = ACE.Classes.GunClass


--The distances these ents would have if its caliber was 10mm. Incremented by caliber size.
local CrewLinkDistBase = 200
local AmmoLinkDistBase = 512

local function AttemptFirstLoad(Gun, Crate)
	if not IsValid(Gun) or not IsValid(Crate) then return end
	if Gun.BulletData.Type ~= "Empty" then return end
	if not Crate.Load or not Gun.FirstLoad or not Gun.Legal then return end

	-- Reload=true sends the scale-0 muzzleflash effect (no sound/flash), which runs the client
	-- Animate(LoadOnly) that initializes the gun's animation state. Without it the client stays in
	-- cl_init's default state (Reload == CloseTime -> infinite playback rate + per-Think
	-- ResetSequence), which strobes the load animation.
	Gun:LoadAmmo(false, true)
end

-- Compute the next-shot reload time without mutating ammo, stamina, or the active
-- reload timer. Link changes and ROFLimit use this same calculation as LoadAmmo so
-- the visible Fire Rate cannot lag behind the configured weapon state.
local function GetGunReloadTime(Gun, BulletData, RoFMul)
	if not BulletData then return end

	local Adj = BulletData.LengthAdj or 1
	local MaxRof = Gun.ROFLimit
	if Gun.maxrof then
		MaxRof = MaxRof ~= 0 and math.min(Gun.maxrof, MaxRof) or Gun.maxrof
	end

	local FireRateModifier = Gun.RoFmod * Gun.PGRoFmod * ((RoFMul or 0) + 1)
	local DefaultReloadTime = ((math.max(BulletData.RoundVolume, Gun.MinLengthBonus / Adj) / 500) ^ 0.60)
		* FireRateModifier
	local LowestReloadTime = MaxRof > 0 and 60 / MaxRof or DefaultReloadTime
	local Loader = Gun:ChooseLoader()
	local CanUseLoader = not ACE.table_contains({ "AC", "MG", "RAC", "HMG", "GL", "SA" }, Gun.Class)
		and Gun.maxrof and Gun.LoaderCount > 0 and IsValid(Loader)

	if CanUseLoader then
		local CrewReload = Loader.Stamina / 100
		-- Crew stamina scales the reload down toward the fire-rate floor, but that floor is a hard
		-- minimum: a ROFLimit (or undersized ammo) slower than the shell's physical reload leaves
		-- LowestReloadTime > DefaultReloadTime, so the upper bound is raised to LowestReloadTime to
		-- keep the clamp band from inverting -- otherwise the loader would fire past the set cap.
		local SlowestReloadTime = math.max(LowestReloadTime, DefaultReloadTime)
		return math.Clamp(LowestReloadTime / CrewReload, LowestReloadTime, SlowestReloadTime), Loader
	end

	return math.max(DefaultReloadTime, LowestReloadTime)
end

local function RefreshGunRateOfFire(Gun, AmmoEnt)
	local BulletData
	local RoFMul
	if IsValid(AmmoEnt) and AmmoEnt.BulletData then
		BulletData = AmmoEnt.BulletData
		RoFMul = AmmoEnt.RoFMul
	elseif Gun.BulletData and Gun.BulletData.Type ~= "Empty" then
		BulletData = Gun.BulletData
		local Crate = BulletData.Crate and Entity(BulletData.Crate)
		RoFMul = IsValid(Crate) and Crate.RoFMul or 0
	end

	local ReloadTime = GetGunReloadTime(Gun, BulletData, RoFMul)
	if not ReloadTime then return false end

	Gun.RateOfFire = 60 / ReloadTime
	Wire_TriggerOutput(Gun, "Fire Rate", Gun.RateOfFire)

	return true
end

function ENT:Initialize()

	self.ReloadTime          = 1

	self.FirstLoad           = true
	self.Ready               = true
	self.Firing              = nil
	self.Reloading           = nil
	self.NextFire            = 0
	self.LastSend            = 0
	self.LastLoadDuration    = 0
	self.NextLegalCheck      = ACE.CurTime + math.random(ACE.Legal.Min, ACE.Legal.Max) -- give any spawning issues time to iron themselves out
	self.Legal               = true
	self.LegalIssues         = ""
	self.FuseTime            = 0
	self.OverrideFuse        = false		-- Override disabled by default
	self.ROFLimit            = 0			-- Used for selecting firerate

	self.IsMaster            = true		-- needed?
	self.OTWarnings	         = {} --Used to remember all the one time warnings.
	self.AmmoLink            = {}
	self.CrewLink            = {}
	self.HasGunner           = false
	self.RequiresGunner      = false
	self.LoaderCount         = 0
	self.CurAmmo             = 1
	self.Sequence            = 1
	self.GunClass            = "MG"

	self.Heat                = ACE.AmbientTemp
	self.IsOverheated        = false

	self.BulletData          = {}
	self.BulletData.Type     = "Empty"
	self.BulletData.PropMass = 0
	self.BulletData.ProjMass = 0

	self.Inaccuracy          = 1
	self.KERecoil			 = 0
	self.LastThink           = 0

	self.CanLegalCheck		= true

	self:CallOnRemove("ACE_Points", function(ent)
		if ACE.PointsInputChanged then ACE.PointsInputChanged(ent, "gun-removed") end
	end)
end

-- Forward declaration: defined inside the spawn-path do-block where the
-- input tables live, used by ENT:Update outside that block.
local SelectGunInputs

do
	local Inputs = {
		Fire        = "Fire (Shoots a bullet if loaded. Hold to keep shooting.)",
		Unload      = "Unload (Unloads the current shell from the gun. Leaving the gun empty.)",
		Reload      = "Reload (Reloads the current weapon, according to the active ammo it has.)",
		FuseTime    = "Fuse Time (Defines the required time for shell self-detonation in seconds. \nThis only work with SM, HE & HEAT rounds. \nNote that this is not really accurate.)",
		ROFLimit    = "ROFLimit (Limits the Gun's rate of fire to the specified value in Rounds Per Minute. \nUsing a number of 0 or less will disable the firerate limit.)",
	}
	local Outputs = {
		Ready           = "Ready (Returns if the gun is ready to fire.)",
		AmmoCount       = "AmmoCount (Returns the total ammo this gun can shoot.)",
		Entity          = "Entity [ENTITY]",
		ShotsLeft       = "Shots Left (Returns the number of shots in the gun.)",
		FireRate        = "Fire Rate (Returns the Rate of Fire of this gun)",
		MuzzleWeight    = "Muzzle Weight (Returns the muzzle weight)",
		MuzzleVelocity  = "Muzzle Velocity (Returns the muzzle velocity)" ,
		Heat            = "Heat (Returns the gun's temperature.)",
		OverHeat        = "OverHeat (Is the gun overheating?)"
	}

	local Inputs_Fuse = {
		Inputs.Fire,
		Inputs.Unload,
		Inputs.Reload,
		Inputs.FuseTime,
		Inputs.ROFLimit
	}
	local Inputs_NoFuse = {
		Inputs.Fire,
		Inputs.Unload,
		Inputs.Reload,
		Inputs.ROFLimit
	}
	local Inputs_Fuse_noreload = {
		Inputs.Fire,
		Inputs.Unload,
		Inputs.FuseTime,
		Inputs.ROFLimit
	}
	local Inputs_NoFuse_noreload = {
		Inputs.Fire,
		Inputs.Unload,
		Inputs.ROFLimit
	}
	local Outputs_Default = {
		Outputs.Ready,
		Outputs.AmmoCount,
		Outputs.Entity,
		Outputs.ShotsLeft,
		Outputs.FireRate,
		Outputs.MuzzleWeight,
		Outputs.MuzzleVelocity,
		Outputs.Heat,
		Outputs.OverHeat
	}

	-- Shared between spawn and retune: magazine support decides whether a
	-- manual Reload port exists, caliber decides the Fuse Time port (30mm
	-- threshold). Assigned to the file-scope forward declaration so
	-- ENT:Update — outside this block — can reuse it.
	SelectGunInputs = function( hasMag, cal )
		if hasMag then
			return cal >= 3 and Inputs_Fuse or Inputs_NoFuse
		end
		return cal >= 3 and Inputs_Fuse_noreload or Inputs_NoFuse_noreload
	end

	--List of ids which no longer stay on ACE. Useful to replace them with the closest counterparts
	local BackComp = {
		["20mmHRAC"]     = "20mmRAC",
		["30mmHRAC"]     = "30mmRAC",
		["40mmGLSingle"] = "40mmSL",
		["105mmSB"]      = "100mmSBC",
		["120mmSB"]      = "120mmSBC",
		["140mmSB"]      = "140mmSBC",
		["170mmSB"]      = "170mmSBC"

	}

	local rapidgun = {
		RAC = true,
		MG  = true,
		AC  = true,
		SA  = true,
		HMG = true
	}

	--- Resolves a gun id plus optional spec suffix into everything the spawn
	-- and in-place-update paths need. Centralized so both flows interpret
	-- ids identically: key suffixes in the id, GunOpts from the tool, legacy
	-- rewrites (BackComp), the alias chain, migration fallback and envelope
	-- clamping. Resolution precedence: GunOpts wins over parameters embedded
	-- in the id, which win over alias defaults.
	-- @return string|nil Id processed base id (after legacy rewrites)
	-- @return table|nil Lookup resolved gun def
	-- @return table|nil ClassData class table of the resolved gun
	-- @return table|nil Limits scalability envelope, when scalable
	-- @return table|nil Stats derived stats at the effective spec
	-- @return number|nil CalMM effective caliber in millimeters
	-- @return number|nil BoreLen effective bore length in calibers
	function ACE.ResolveGunSpec(Id, GunOpts, BackComp)
		-- Parameterized ids ("120mmC@140x55") arrive whole from dupes; the spawn
		-- tool passes only the suffix through GunOpts ("140x55").
		local KeyCal, KeyLen
		Id, KeyCal, KeyLen = ACE.GunScale.ParseKey(Id)

		-- Resolution order matters and must match the crate factory exactly:
		-- resolve through the modern chain FIRST (exact defs, legacy aliases,
		-- then the suffix-migration fallback), and rewrite through the legacy
		-- BackComp table only when nothing recognizes the id. The migration
		-- layer resolves ids like "105mmSB" at their true caliber, so applying
		-- BackComp first would pin the gun to the rewrite target (100mmSBC)
		-- while the crate factory — which resolves first — builds rounds at
		-- 105mm, breaking ammo links on pasted dupes. BackComp remains the
		-- last resort for ids the migration suffixes don't know ("40mmGLSingle",
		-- missile rewrites).
		if BackComp then
			local Probe = ACE.GunScale.ResolveSpec( Id )
			if not Probe then Id = BackComp[Id] or Id end
		end

		local Lookup, AliasCalMM, AliasLen = ACE.GunScale.ResolveSpec(Id)
		if not Lookup then
			Id = "100mmC"
			Lookup, AliasCalMM, AliasLen = ACE.GunScale.ResolveSpec(Id)
		end
		if not Lookup then return end

		local ClassData = GunClasses[Lookup.gunclass]

		local Limits = ACE.GunScale.Limits(Lookup.id)
		local CalMM, BoreLen
		if Limits then
			local OptCal, OptLen = ACE.GunScale.ParseOpts(GunOpts)
			CalMM, BoreLen = ACE.GunScale.Normalize(Lookup.id, OptCal or KeyCal or AliasCalMM, OptLen or KeyLen or AliasLen)
		end

		local Stats = ACE.GunScale.Stats(Lookup, CalMM and CalMM / 10, BoreLen)
		return Id, Lookup, ClassData, Limits, Stats, CalMM, BoreLen
	end

	function ACE.MakeGun(Owner, Pos, Angle, Id, GunOpts)

		local Gun = ents.Create("acf_gun")
		if not IsValid(Gun) then return false end

		local Id2, Lookup, ClassData, Limits, Stats, CalMM, BoreLen = ACE.ResolveGunSpec(Id, GunOpts, BackComp)
		if not Lookup then return false end
		Id = Id2
		local EffCal = Stats.caliber -- effective caliber in cm

		if Lookup.gunclass == "SL" then
			if not Owner:CheckLimit("_ace_smokelauncher") then return false end
			Owner:AddCount("_ace_smokelauncher", Gun)

		elseif rapidgun[Lookup.gunclass] then
			if not Owner:CheckLimit("_ace_rapidgun") then return false end
			Owner:AddCount("_ace_rapidgun", Gun)

		elseif EffCal >= ACE.LargeCaliber then
			if not Owner:CheckLimit("_ace_largegun") then return false end
			Owner:AddCount("_ace_largegun", Gun)

		else
			if not Owner:CheckLimit("_ace_gun") then return false end
			Owner:AddCount("_ace_gun", Gun)
		end

		Gun:SetAngles(Angle)
		Gun:SetPos(Pos)
		Gun:Spawn()
		Gun:CPPISetOwner(Owner)
		Gun.Id              = Id
		Gun.Caliber         = EffCal
		Gun.Model           = Lookup.model
		Gun.Mass            = Stats.mass
		Gun.Class           = Lookup.gunclass
		Gun.Heat            = ACE.AmbientTemp
		Gun.LinkRangeMul    = math.max(Gun.Caliber / 10,1) ^ 1.2
		Gun.RequiresGunner	= false
		local GunnerExcluded	= Lookup.gunnerexception or false

		-- Scalable-gun state. ScalableSpec marks the ammo-fit rule even at base
		-- spec; IsScalable only when the hull/render actually scales.
		Gun.ScalableSpec   = Limits
		Gun.CaliberMM      = CalMM
		Gun.BoreLength     = BoreLen
		Gun.MuzVelMod          = Stats.mvmod
		Gun.ChamberLen     = Stats.chamberLen
		Gun.PropLimit      = Stats.propLimit
		Gun.GunScaleVec    = Stats.scale
		Gun.GunOpts        = Limits and ACE.GunScale.OptString(Lookup.id, CalMM, BoreLen) or nil
		Gun.GunKey         = Limits and ACE.GunScale.Key(Lookup.id, CalMM, Limits.lenmin < Limits.lenmax and BoreLen or nil) or Id

		Gun.noloaders	= ClassData.noloader or nil

		Gun.Inaccuracy = ClassData.spread

		if not GunnerExcluded and (Gun.Caliber * 10) > ACE.LargeGunsThreshold and ACE.LargeGunsRequireGunners ~= 0 then --If the caliber is large enough it requires a gunner.
			Gun.RequiresGunner = true
		end

		if ClassData.color then
			Gun:SetColor(Color(ClassData.color[1],ClassData.color[2],ClassData.color[3], 255))
		end

		Gun.PGRoFmod	= Lookup.rofmod and math.max(0.01, Lookup.rofmod) or 1 --per gun rof
		Gun.maxrof = Stats.maxrof or Lookup.maxrof
		Gun.CurrentShot = 0
		Gun.MagSize	= 1

		--IDK why does this has been broken, giving it sense now
		--to cover guns that uses magazines
		if Lookup.magsize then

			Gun.MagSize = math.max(Gun.MagSize, Stats.magsize or Lookup.magsize)

		end

		-- Magazine guns get a manual Reload port, crate-fed guns do not;
		-- caliber past the 30mm threshold adds the Fuse Time port. Shared
		-- with the retune path through SelectGunInputs.
		Gun.Inputs = WireLib.CreateInputs( Gun, SelectGunInputs( Lookup.magsize ~= nil, Gun.Caliber ) )

		Gun.Outputs = WireLib.CreateOutputs( Gun, Outputs_Default )

		Wire_TriggerOutput(Gun, "Entity", Gun)

		Gun.MagReload = 0
		if Lookup.magreload then
			Gun.MagReload = math.max(Gun.MagReload, Stats.magreload or Lookup.magreload )
		end

		Gun.MinLengthBonus    = 0.5 * 3.1416 * (Gun.Caliber / 2) ^ 2 * Stats.chamberLen

		Gun.Muzzleflash       = Lookup.muzzleflash or ClassData.muzzleflash
		Gun.RoFmod            = ClassData.rofmod
		Gun.RateOfFire        = 1 --updated when gun is linked to ammo
		Gun.Sound             = Lookup.sound or ClassData.sound
		Gun.DefaultSound      = Gun.Sound
		Gun.SoundPitch        = 100
		if Limits and Stats.calscale ~= 1 and ACE.GunScale.SoundPitch then
			-- Bigger guns sound deeper.
			Gun.SoundPitch = math.Clamp( math.Round( 100 / math.sqrt( Stats.calscale ) ), 60, 140 )
		end
		Gun.AutoSound         = ClassData.autosound and (Lookup.autosound or ClassData.autosound) or nil
		Gun.CurrentRecoil     = 0

		Gun:SetNWInt( "Caliber", Gun.Caliber )
		Gun:SetNWString( "WireName", Limits and ACE.GunScale.DisplayName( Lookup, CalMM, BoreLen ) or Lookup.name )
		Gun:SetNWString( "Class", Gun.Class )
		Gun:SetNWString( "ID", Gun.Id )
		Gun:SetNWString( "GunKey", Gun.GunKey )
		Gun:SetNWString( "Muzzleflash", Gun.Muzzleflash )
		Gun:SetNWString( "Sound", Gun.Sound )
		Gun:SetNWInt( "SoundPitch", Gun.SoundPitch )

		Gun:SetModel( Gun.Model )

		Gun:PhysicsInit( SOLID_VPHYSICS )
		Gun:SetMoveType( MOVETYPE_VPHYSICS )
		Gun:SetSolid( SOLID_VPHYSICS )

		if Stats.calscale ~= 1 or Stats.lenscale ~= 1 then
			-- Scaled hull: rebuild the convexes from the base physics mesh.
			local Phys = Gun:GetPhysicsObject()
			if IsValid( Phys ) then
				Gun.ScaleData = {
					Mesh     = Phys:GetMeshConvexes(),
					Scale    = Stats.scale,
					Material = "metal",
				}

				if Stats.split and Stats.lenscale ~= 1 then
					-- Piecewise tube stretch: the registry carries the
					-- breech/tube joint, the bore direction and the tube
					-- length, all in bind space. Only the tube side of the
					-- mesh stretches; the breech keeps the uniform caliber
					-- scale.
					Gun.ScaleData.Split    = Stats.split
					Gun.ScaleData.LenScale = Stats.lenscale

					Gun.TubeSplit    = Stats.split
					Gun.TubeLenScale = Stats.lenscale

					-- Tube tip measured along the bore: the muzzle is never
					-- mapped past it, so authored attachments that sit ahead
					-- of the mesh can't float the muzzle flash.
					local Tip
					for _, group in pairs( Gun.ScaleData.Mesh ) do
						for _, vertex in pairs( group ) do
							local v = istable( vertex ) and vertex.pos or vertex
							if isvector( v ) then
								local t = ( v - Stats.split.joint ):Dot( Stats.split.bore )
								if not Tip or t > Tip then Tip = t end
							end
						end
					end
					Gun.TubeTip = Tip

					-- Cache the bind muzzle before the bones move: once the
					-- rig slides, GetAttachment already reports the stretched
					-- position and UpdateMuzzlePoint would apply it twice.
					local AttachName = ACE.GunScale.ResolveBarrel( Gun )
					local AttachId = AttachName and Gun:LookupAttachment( AttachName ) or 0
					local Attach = AttachId > 0 and Gun:GetAttachment( AttachId )
					if Attach and Attach.Pos then
						Gun.MuzzleBindPos = Gun:WorldToLocal( Attach.Pos )
						Gun.MuzzleBindAtt = AttachId
					end

					-- Stretch the render tube via the rig's `tube`/`muzzledev`
					-- bones; bone manipulations set server-side network to
					-- every client on their own.
					ACE.GunScale.ApplyBarrelBones( Gun, Stats.lenscale, Stats.split )
				end

				Gun.IsScalable = true
				Gun:ACE_SetScale( Gun.ScaleData )
			end
		end

		Gun:UpdateMuzzlePoint()

		local longbarrel = Lookup.barrels or ClassData.barrels or ClassData.longbarrel
		if longbarrel ~= nil then
			timer.Simple(0.25, function() --need to wait until after the property is actually set
				if not IsValid(Gun) then return end
				Gun:UpdateMuzzlePoint()
			end)
		end

		local phys = Gun:GetPhysicsObject()
		if IsValid( phys ) then
			phys:SetMass( Gun.Mass )
			Gun.ModelInertia = 0.99 * phys:GetInertia() / phys:GetMass() -- giving a little wiggle room
		end

		Gun:UpdateOverlayText()

		Owner:AddCleanup("acemenu", Gun)

		ACE.Activate(Gun, 0)

		return Gun

	end
end

list.Set( "ACFCvars", "acf_gun", {"id", "gunopts"} )
duplicator.RegisterEntityClass("acf_gun", ACE.MakeGun, "Pos", "Angle", "Id", "GunOpts")

-- The acemenu tool's left-click update path (same-class entity under the
-- crosshair) calls ENT:Update with the spawn argument table, player first.
ENT.CanUpdate = true

--- Retunes this gun in place to a new id/spec, preserving position, angle,
-- constraints, wire connections and compatible ammo links. With scalable
-- guns the common case is not a model swap but a retune — same class, new
-- caliber or bore length — so the entity rebuilds itself from the resolved
-- spec exactly as it would at spawn, minus the spawn-only state.
-- @param ArgTable table { player, pos, angle, id, gunopts } as passed by the acemenu tool
-- @return boolean success
-- @return string message
function ENT:Update( ArgTable )
	if not istable( ArgTable ) then return false, "Bad update arguments" end

	local ply     = ArgTable[1]
	local Id      = ArgTable[4]
	local GunOpts = ArgTable[5]

	if not IsValid( ply ) then return false, "No player" end
	if not isstring( Id ) then return false, "No gun id" end

	-- Retuning mid-fire would silently eat the in-flight cycle; same guard
	-- ACF-3 uses on its update path.
	if self.Firing then return false, "Stop firing before updating the gun" end

	-- Captured before the spec assignments overwrite them: the chambered
	-- round and the caliber it was chambered for.
	local OldCaliber  = self.Caliber
	local Chambered   = ( self.BulletData and self.BulletData.Type ~= "Empty" ) and self.BulletData or nil

	-- Ownership guard, same spirit as other ACE tools: the contraption's
	-- owner retunes it, nobody else.
	if CPPI and self.CPPIGetOwner then
		local owner = self:CPPIGetOwner()
		if IsValid( owner ) and owner ~= ply and not ply:IsAdmin() then
			return false, "You can only update your own guns"
		end
	end

	-- Clean the input the way the tool convars deliver it.
	if isstring( GunOpts ) and GunOpts == "" then GunOpts = nil end

	-- Legacy rewrites, same table the spawn path uses.
	local BackComp = ACE.BackCompGun or {}
	local NewId, Lookup, ClassData, Limits, Stats, CalMM, BoreLen = ACE.ResolveGunSpec( Id, GunOpts, BackComp )
	if not Lookup then return false, "Unknown gun id" end

	-- Quota categories mirror the spawn path in MakeGun. A retune can move a
	-- gun across category lines (a small gun becoming a large one), so the
	-- target category must be validated and the sandbox count registration
	-- migrated — otherwise retunes bypass the spawn quotas entirely.
	local function QuotaCategory( classid, effcal )
		if classid == "SL" then return "_ace_smokelauncher" end
		if classid == "RAC" or classid == "MG" or classid == "AC" or classid == "SA" or classid == "HMG" then return "_ace_rapidgun" end
		if effcal >= ACE.LargeCaliber then return "_ace_largegun" end
		return "_ace_gun"
	end
	local oldcat = QuotaCategory( self.Class, self.Caliber )
	local newcat = QuotaCategory( Lookup.gunclass, Stats.caliber )
	if oldcat ~= newcat then
		if not ply:CheckLimit( newcat ) then return false, "Retuning would exceed your quota for that gun category" end
		local key  = ply:UniqueID()
		local objs = g_SBoxObjects and g_SBoxObjects[ key ]
		if objs and objs[ oldcat ] then
			for k, v in pairs( objs[ oldcat ] ) do
				if v == self then objs[ oldcat ][ k ] = nil break end
			end
		end
		ply:AddCount( newcat, self )
	end

	-- From here: apply the resolved spec in place. These assignments mirror
	-- the spawn path field for field — anything spec-dependent must be
	-- overwritten, anything positional or relational must not be touched.
	self.Id              = NewId
	self.Caliber         = Stats.caliber
	self.Model           = Lookup.model
	self.Mass            = Stats.mass
	self.Class           = Lookup.gunclass
	self.LinkRangeMul    = math.max( self.Caliber / 10, 1 ) ^ 1.2

	local GunnerExcluded = Lookup.gunnerexception or false
	self.RequiresGunner  = false
	if not GunnerExcluded and ( self.Caliber * 10 ) > ACE.LargeGunsThreshold and ACE.LargeGunsRequireGunners ~= 0 then
		self.RequiresGunner = true
	end

	self.ScalableSpec    = Limits
	self.CaliberMM       = CalMM
	self.BoreLength      = BoreLen
	self.MuzVelMod           = Stats.mvmod
	self.ChamberLen      = Stats.chamberLen
	self.PropLimit       = Stats.propLimit
	self.GunScaleVec     = Stats.scale
	self.GunOpts         = Limits and ACE.GunScale.OptString( Lookup.id, CalMM, BoreLen ) or nil
	self.GunKey          = Limits and ACE.GunScale.Key( Lookup.id, CalMM, Limits.lenmin < Limits.lenmax and BoreLen or nil ) or NewId

	self.noloaders       = ClassData.noloader or nil
	self.Inaccuracy      = ClassData.spread
	self.PGRoFmod        = Lookup.rofmod and math.max( 0.01, Lookup.rofmod ) or 1
	self.maxrof          = Stats.maxrof or Lookup.maxrof

	self.MagSize         = 1
	if Lookup.magsize then
		self.MagSize = math.max( self.MagSize, Stats.magsize or Lookup.magsize )
	end

	-- Wire inputs are spec-dependent, same selection as the spawn path:
	-- magazine support decides whether a manual Reload port exists, caliber
	-- decides the Fuse Time port (30mm threshold). Adjust in place rather
	-- than recreating so wiring on the common ports (Fire, Unload, ROFLimit)
	-- keeps its connections across the retune.
	if WireLib and WireLib.AdjustInputs and SelectGunInputs then
		self.Inputs = WireLib.AdjustInputs( self, SelectGunInputs( Lookup.magsize ~= nil, self.Caliber ) )
	end

	self.MagReload       = 0
	if Lookup.magreload then
		self.MagReload = math.max( self.MagReload, Stats.magreload or Lookup.magreload )
	end

	self.MinLengthBonus  = 0.5 * 3.1416 * ( self.Caliber / 2 ) ^ 2 * Stats.chamberLen
	self.Muzzleflash     = Lookup.muzzleflash or ClassData.muzzleflash
	self.RoFmod          = ClassData.rofmod
	self.Sound           = Lookup.sound or ClassData.sound
	self.DefaultSound    = self.Sound
	self.SoundPitch      = 100
	if Limits and Stats.calscale ~= 1 and ACE.GunScale.SoundPitch then
		self.SoundPitch = math.Clamp( math.Round( 100 / math.sqrt( Stats.calscale ) ), 60, 140 )
	end
	self.AutoSound       = ClassData.autosound and ( Lookup.autosound or ClassData.autosound ) or nil

	-- Fire/reload state resets as if freshly spawned; the tube may now be a
	-- different length and any in-flight cycle is meaningless.
	self.CurrentShot     = 0
	self.CurrentRecoil   = 0
	self.Reloading       = nil
	self.Magazine        = 0
	self.NextFire        = CurTime()
	self.BulletData      = { Type = "Empty", PropMass = 0, ProjMass = 0 }
	self.Heat            = ACE.AmbientTemp

	-- The chambered round survives when it genuinely fits the new spec: the
	-- caliber must be unchanged (a 120mm shell never belongs in a rebored
	-- chamber, longer or shorter tube notwithstanding) and the round type
	-- must pass the same blacklist the crate-link reconciliation re-runs.
	if Chambered and Stats.caliber == OldCaliber then
		local Blacklist   = ACE.AmmoBlacklist[ Chambered.Type ] or {}
		local Fam         = ( ACE.Classes.GunClass[ self.Class ] or {} ).ammofamily
		local blacklisted = table.HasValue( Blacklist, self.Class ) or ( Fam and table.HasValue( Blacklist, Fam ) )
		local fits        = true
		if self.ScalableSpec then fits = ACE.GunScale.AmmoFits( self, Chambered ) end
		if not blacklisted and fits then self.BulletData = Chambered end
	end

	if ClassData.color then
		self:SetColor( Color( ClassData.color[1], ClassData.color[2], ClassData.color[3], 255 ) )
	end

	self:SetNWInt( "Caliber", self.Caliber )
	self:SetNWString( "WireName", Limits and ACE.GunScale.DisplayName( Lookup, CalMM, BoreLen ) or Lookup.name )
	self:SetNWString( "Class", self.Class )
	self:SetNWString( "ID", self.Id )
	self:SetNWString( "GunKey", self.GunKey )
	self:SetNWString( "Muzzleflash", self.Muzzleflash )
	self:SetNWString( "Sound", self.Sound )
	self:SetNWInt( "SoundPitch", self.SoundPitch )

	-- Model and physics. PhysicsInit rebuilds the physics object from the
	-- model's BASE collision mesh — required even when the model does not
	-- change, because the scaled hull replaces convexes and re-reading the
	-- live object would double-apply the scale. Frozen state survives the
	-- rebuild: builders keep tanks frozen while retuning them.
	local WasFrozen
	do
		local oldphys = self:GetPhysicsObject()
		WasFrozen = IsValid( oldphys ) and not oldphys:IsMotionEnabled()
	end
	-- Attachment ids are model-local: the same numeric id means different
	-- positions on different models, so the muzzle bind cache must not
	-- survive a model swap (an unscaled gun keeps its cached muzzle
	-- otherwise — e.g. 12.7mm muzzle at 37 units read on a 40mm muzzle
	-- at 96 units when both models call it attachment 1).
	if self:GetModel() ~= self.Model then
		self:SetModel( self.Model )
		self.MuzzleBindPos = nil
		self.MuzzleBindAtt = nil
	end
	self:PhysicsInit( SOLID_VPHYSICS )
	self:SetMoveType( MOVETYPE_VPHYSICS )
	self:SetSolid( SOLID_VPHYSICS )

	-- Reset barrel-bone manipulations from any previous spec before the new
	-- ones apply; a retune back to base length must zero them explicitly.
	local WasScaled = self.IsScalable or false
	if self.IsScalable then
		ACE.GunScale.ApplyBarrelBones( self, 1, ACE.GunScale.BarrelInfo( self.Model ) )
		self.IsScalable = nil
		self.TubeSplit = nil
		self.TubeLenScale = nil
		self.TubeTip = nil
		self.MuzzleBindPos = nil
		self.MuzzleBindAtt = nil
		self.ScaleData = nil
	end

	if Stats.calscale ~= 1 or Stats.lenscale ~= 1 then
		local Phys = self:GetPhysicsObject()
		if IsValid( Phys ) then
			self.ScaleData = {
				Mesh     = Phys:GetMeshConvexes(),
				Scale    = Stats.scale,
				Material = "metal",
			}

			if Stats.split and Stats.lenscale ~= 1 then
				self.ScaleData.Split    = Stats.split
				self.ScaleData.LenScale = Stats.lenscale
				self.TubeSplit    = Stats.split
				self.TubeLenScale = Stats.lenscale

				local Tip
				for _, group in pairs( self.ScaleData.Mesh ) do
					for _, vertex in pairs( group ) do
						local v = istable( vertex ) and vertex.pos or vertex
						if isvector( v ) then
							local t = ( v - Stats.split.joint ):Dot( Stats.split.bore )
							if not Tip or t > Tip then Tip = t end
						end
					end
				end
				self.TubeTip = Tip

				local AttachName = ACE.GunScale.ResolveBarrel( self )
				local AttachId = AttachName and self:LookupAttachment( AttachName ) or 0
				local Attach = AttachId > 0 and self:GetAttachment( AttachId )
				if Attach and Attach.Pos then
					self.MuzzleBindPos = self:WorldToLocal( Attach.Pos )
					self.MuzzleBindAtt = AttachId
				end

				ACE.GunScale.ApplyBarrelBones( self, Stats.lenscale, Stats.split )
			end

			self.IsScalable = true
			self:ACE_SetScale( self.ScaleData )
		end
	end

	-- Returning all the way to pivot sends no scale packet on its own, so
	-- without an explicit reset clients keep the old render matrix, collision
	-- hull and cached tube split. The server hull is already correct — the
	-- PhysicsInit above rebuilt the base mesh — this is purely a client sync.
	if WasScaled and not self.IsScalable and ACE.NetworkScaleReset then
		ACE.NetworkScaleReset( self )
	end

	local phys = self:GetPhysicsObject()
	if IsValid( phys ) then
		phys:SetMass( self.Mass )
		self.ModelInertia = 0.99 * phys:GetInertia() / phys:GetMass()
		if WasFrozen then phys:EnableMotion( false ) end
	end

	-- The hull just changed size while the damage model caches its surface
	-- area — without invalidation the retuned gun keeps the old spec's
	-- health and armor numbers. Recalc mode preserves the damage fraction.
	if self.ACE then
		self.ACE.Area = nil
		ACE.Activate( self, 1 )
	end

	self:UpdateMuzzlePoint()
	self:UpdateOverlayText()

	-- Ammo links survive when the crate still fits the new spec; anything
	-- incompatible drops, since silently keeping it would fail at fire time.
	local involved
	if self.AmmoLink then
		local kept = {}
		involved = {}
		for _, crate in ipairs( self.AmmoLink ) do
			if IsValid( crate ) then
				involved[#involved + 1] = crate
				local fits = true
				if self.ScalableSpec and crate.BulletData then
					fits = ACE.GunScale.AmmoFits( self, crate.BulletData )
				end
				-- The round-type blacklist is a link-time check, so a retune
				-- must re-run it: without this, linking APFSDS to an autoloader
				-- and retuning into a plain cannon would smuggle a round past
				-- the class restriction (the exploit family ACF-3's blanket
				-- unlink-on-update guards against).
				if fits then
					local Blacklist = ACE.AmmoBlacklist[ crate.RoundType ] or {}
					local Fam = ( ACE.Classes.GunClass[ self.Class ] or {} ).ammofamily
					if table.HasValue( Blacklist, self.Class ) or ( Fam and table.HasValue( Blacklist, Fam ) ) then
						fits = false
					end
				end
				if fits then
					kept[#kept + 1] = crate
				elseif crate.Master then
					for i, gun in ipairs( crate.Master ) do
						if gun == self then table.remove( crate.Master, i ) break end
					end
				end
			end
		end
		self.AmmoLink = kept
	end

	-- Retuning rewrites the pricing inputs (muzzle-velocity multiplier, linked
	-- round, caliber) without firing any link/unlink event, so the cached
	-- contraption totals would never recompute on their own. Invalidate with
	-- everyone involved: the gun plus every crate that was linked either side
	-- of the reconciliation.
	if ACE.PointsInputChanged then
		local affected = { self }
		if involved then for _, crate in ipairs( involved ) do affected[#affected + 1] = crate end end
		ACE.PointsInputChanged( affected, "gun-updated" )
	end

	return true, "Gun updated to " .. ( Limits and ACE.GunScale.DisplayName( Lookup, CalMM, BoreLen ) or Lookup.name )
end

-- Resolves the muzzle offset in LOCAL space. QC attachments do not follow the
-- render-matrix scale used on scalable guns, so the base attachment position
-- is scaled by the same vector the hull/render use instead.
function ENT:UpdateMuzzlePoint()

	local AttachName = ACE.GunScale.ResolveBarrel( self )
	local AttachId = AttachName and self:LookupAttachment( AttachName ) or 0
	local Muzzle = AttachId > 0 and self:GetAttachment( AttachId ) or nil

	if Muzzle and Muzzle.Pos then
		-- Cache the bind-space position per attachment: on rigs where the
		-- muzzle attachment rides the sliding muzzledev bone, later reads
		-- already include the stretch and mapping them would apply it twice.
		if not self.MuzzleBindPos or self.MuzzleBindAtt ~= AttachId then
			self.MuzzleBindPos = self:WorldToLocal( Muzzle.Pos )
			self.MuzzleBindAtt = AttachId
		end
		local LocalPos = self.MuzzleBindPos

		if self.TubeSplit then
			self.Muzzle = ACE.GunScale.MapPoint( LocalPos, self.GunScaleVec or Vector( 1, 1, 1 ),
				self.TubeSplit, self.TubeLenScale )

			if self.TubeTip then -- don't let the flash sit ahead of the stretched tip
				local t = ( LocalPos - self.TubeSplit.joint ):Dot( self.TubeSplit.bore )
				if t > self.TubeTip then
					local capped = LocalPos - self.TubeSplit.bore * ( t - self.TubeTip )
					self.Muzzle = ACE.GunScale.MapPoint( capped, self.GunScaleVec or Vector( 1, 1, 1 ), self.TubeSplit, self.TubeLenScale )
				end
			end
		else
			self.Muzzle = LocalPos * ( self.GunScaleVec or Vector( 1, 1, 1 ) )
		end
	end

	self:SetNWVector( "ACE_Muzzle", self.Muzzle or Vector() )

end

function ENT:UpdateOverlayText()

	local roundType = self.BulletData.Type

	if self.BulletData.Tracer and self.BulletData.Tracer > 0 then
		roundType = roundType .. "-T"
	end

	local isEmpty = self.BulletData.Type == "Empty"

	local clipLeft	= isEmpty and 0 or (self.MagSize - self.CurrentShot)
	local ammoLeft	= (self.Ammo or 0) + clipLeft
	local isReloading	= not isEmpty and CurTime() < self.NextFire and (self.MagSize == 1 or (self.LastLoadDuration > self.ReloadTime))
	local gunStatus	= isReloading and "reloading" or (clipLeft .. " in gun")

	local text = roundType .. " - " .. ammoLeft .. (ammoLeft == 1 and " shot left" or " shots left ( " .. gunStatus .. " )")

	text = text .. "\nRounds Per Minute: " .. math.Round( self.RateOfFire or 0, 2 )

	if self.ScalableSpec and self.CaliberMM then
		text = text .. string.format( "\nSpec: %gmm L%g - %d kg", self.CaliberMM, self.BoreLength or 0, math.Round( self.Mass ) )
	end

	if ACE.GetGunFirepowerReadout then
		local readout = ACE.GetGunFirepowerReadout(self)
		if readout then
			text = text .. "\nFirepower: " .. string.Comma(math.Round(readout.Points)) .. " pts"
			local roundLine = readout.Round and ACE.GetRoundLethalityLine
				and ACE.GetRoundLethalityLine(readout.Round, true)
			if roundLine then text = text .. "\nBest Round: " .. roundLine end
			if readout.MinimumApplied then
				text = text .. "\nWeapon Minimum Applied: " .. string.Comma(math.Round(readout.Points)) .. " pts"
			end
			local floorLine = ACE.GetRateFloorLine and ACE.GetRateFloorLine(readout, true)
			if floorLine then text = text .. "\n" .. floorLine end
		end
	end

	text = text .. "\nTemp: " .. math.Round(self.Heat) .. " °C / 200 °C"

	if #self.CrewLink > 0 then
		text = text .. "\n\nHas Gunner: " .. (self.HasGunner and "Yes" or "No")
		text = text .. ( self.noloaders and "" or "\nTotal Loaders: " .. self.LoaderCount  )
	end

	if self.IsOverheated then
		text = text .. "\nWarning: Overheated"
	end

	if not self.Legal then
		text = text .. "\n\nNot legal, disabled for " .. math.ceil(self.NextLegalCheck - ACE.CurTime) .. "s\nIssues: " .. self.LegalIssues
	end

	self:SetOverlayText( text )


end

local function IsInRetDist( enta, entb, Distance )
	if not IsValid(enta) or not IsValid(entb) then return end
	return ACE.InDist( enta:GetPos(), entb:GetPos(), Distance )
end

local BreakSoundTbl = {
	ace_crewseat_gunner = "physics/metal/metal_canister_impact_hard",
	ace_crewseat_loader = "physics/metal/metal_canister_impact_hard",
	acf_ammo = "physics/metal/metal_box_impact_bullet",
}

local function BreakGunLink( Gun, LinkedEnt )
	Gun:Unlink( LinkedEnt )
	Gun:EmitSound( (BreakSoundTbl[LinkedEnt:GetClass()] or "physics/metal/metal_box_impact_bullet" ) .. tostring(math.random(1, 3)) .. ".wav", 100, 100)
end

function ENT:Link( Target )

	if not IsValid( Target ) then
		return false, "Target not a valid entity!"
	end

	if not Target.Legal then
		return false, "This entity is illegal!"
	end

	-- CrewLink
	-- the gunner
	if Target:GetClass() == "ace_crewseat_gunner" then

		--Don't link if it's already linked
		for _, v in pairs( self.CrewLink ) do
			if v == Target then
				return false, "That crewseat is already linked to this gun!"
			end
		end

		--Don't link if it's too far from this gun
		if not IsInRetDist( self, Target, CrewLinkDistBase * self.LinkRangeMul ) then
			return false, "That crewseat is too far to be linked to this gun!"
		end

		--Don't link if it's already linked
		if self.HasGunner then
			return false, "The gun already has a gunner!"
		end

		table.insert( self.CrewLink, Target )
		table.insert( Target.Master, self )

		self.HasGunner = true
		Target.LinkedGun = self
		RefreshGunRateOfFire(self)

		if ACE.PointsInputChanged and not self._ACEPointsSuppress and (not Target or not Target._ACEPointsSuppress) then
			ACE.PointsInputChanged({ self, Target }, "gunner-linked")
		end
		return true, "Link successful!"

	-- the loader
	elseif Target:GetClass() == "ace_crewseat_loader" then

		-- Don't link if it's already linked
		for _, v in pairs( self.CrewLink ) do
			if v == Target then
				return false, "That crewseat is already linked to this gun!"
			end
		end

		--Don't link if it's too far from this gun
		if not IsInRetDist( self, Target, CrewLinkDistBase * self.LinkRangeMul ) then
			return false, "That crewseat is too far to be linked to this gun!"
		end

		if not self.HasGunner then --IK there is going to be an exploit to delete the gunner after placing a loader but idk how to fix *shrugs* --NO LONGER
			return false, "You need a gunner before you can have a loader!"
		end

		if self.noloaders then
			return false, "This gun cannot have a loader!"
		end

		table.insert( self.CrewLink, Target )
		table.insert( Target.Master, self )

		self.LoaderCount = self.LoaderCount + 1
		Target.LinkedGun = self
		RefreshGunRateOfFire(self)

		if ACE.PointsInputChanged and not self._ACEPointsSuppress and (not Target or not Target._ACEPointsSuppress) then
			ACE.PointsInputChanged({ self, Target }, "loader-linked")
		end
		return true, "Link successful!"

	--Ammo Link
	elseif Target:GetClass() == "acf_ammo" then

		-- Don't link if it's already linked
		for _, v in pairs( self.AmmoLink ) do
			if v == Target then
				return false, "That crate is already linked to this gun!"
			end
		end

		-- Dont't link if it's too far from this gun
		if not IsInRetDist( self, Target, AmmoLinkDistBase * self.LinkRangeMul ) then
			return false, "That crate is too far to be connected with this gun!"
		end

		-- Don't link if it's a refill crate
		if Target.RoundType == "Refill" then
			return false, "Refill crates cannot be linked!"
		end

		-- Don't link if it's not the right ammo type. Scalable guns match on
		-- caliber/chamber/propellant; legacy guns keep the exact-id rule.
		local AmmoFits, Reason = ACE.GunScale.AmmoFits( self, Target.BulletData )
		if not AmmoFits then
			return false, Reason
		end

		-- Don't link if it's a blacklisted round type for this gun.
		-- Classes sharing an ammo family inherit the family's restrictions
		-- (drum and breech autoloaders blacklist identically, as the legacy
		-- per-caliber defs did when both were gunclass AL).
		local Blacklist = ACE.AmmoBlacklist[ Target.RoundType ] or {}
		local Fam = (ACE.Classes.GunClass[self.Class] or {}).ammofamily

		if table.HasValue( Blacklist, self.Class ) or (Fam and table.HasValue( Blacklist, Fam )) then
			return false, "That round type cannot be used with this gun!"
		end

		table.insert( self.AmmoLink, Target )
		table.insert( Target.Master, self )

		if self.BulletData.Type == "Empty" and self.FirstLoad then
			timer.Simple(0, function()
				AttemptFirstLoad(self, Target)
			end)
		end

		RefreshGunRateOfFire(self, Target)
		Wire_TriggerOutput( self, "Muzzle Weight", math.floor( Target.BulletData.ProjMass * 1000 ) )
		Wire_TriggerOutput( self, "Muzzle Velocity", math.floor( Target.BulletData.MuzzleVel * ( self.MuzVelMod or 1 ) * ACE.VelScale ) )

		if ACE.PointsInputChanged and not self._ACEPointsSuppress and (not Target or not Target._ACEPointsSuppress) then
			ACE.PointsInputChanged({ self, Target }, "gun-ammo-linked")
		end
		return true, "Link successful!"

	else
		return false, "Guns can only be linked to ammo crates or crew seats!"
	end

end

function ENT:Unlink( Target )

	local Success = false
	for Key,Value in pairs(self.AmmoLink) do
		if Value == Target then
			table.remove(self.AmmoLink,Key)
			Success = true
		end
	end
	for Key,Value in pairs(self.CrewLink) do
		if Value == Target then
			if Target:GetClass() == "ace_crewseat_gunner" then
				self.HasGunner = false
			elseif Target:GetClass() == "ace_crewseat_loader" then
				self.LoaderCount = self.LoaderCount - 1
			end

			Target.LinkedGun = nil

			table.remove(self.CrewLink,Key)
			Success = true
		end
	end

	if Success then
		RefreshGunRateOfFire(self)
		if ACE.PointsInputChanged and not self._ACEPointsSuppress and (not Target or not Target._ACEPointsSuppress) then
			ACE.PointsInputChanged({ self, Target }, "gun-unlinked")
		end
		return true, "Unlink successful!"
	else
		return false, "That entity is not linked to this gun!"
	end

end

function ENT:CanProperty( _, property )

	if property == "bodygroups" then
		-- Any barrel-variant setup (legacy longbarrel, class/def barrels, or a
		-- scalable def) needs the muzzle re-resolved once the property lands.
		timer.Simple(0.25, function()
			if IsValid(self) then self:UpdateMuzzlePoint() end
		end)
	end

	return true

end

function ENT:TriggerInput(iname, value)
	if iname == "Unload" and value > 0 and not self.Reloading then
		-- Triggered to unload ammo
		self:UnloadAmmo()
	elseif iname == "Fire" and value > 0 and ACE.GunfireEnabled and self.Legal then
		-- Triggered to fire if conditions are met
		if self.NextFire < CurTime() then
			-- Check if it's time to fire
			self.User = ACE.GetWeaponUser(self, self.Inputs.Fire.Src)
			if not IsValid(self.User) then
				self.User = self:CPPIGetOwner()
			end
			self:FireShell()
			self:Think()
			self.Firing = true
		end
	elseif iname == "Fire" and value <= 0 then
		-- Triggered to stop firing
		self.Firing = false
	elseif iname == "Reload" and value ~= 0 then
		-- Triggered to start reloading
		self.Reloading = true
	elseif iname == "Fuse Time" then
		-- Set the fuse time if value is greater than 0
		if value > 0 then
			self.FuseTime = value
			self.OverrideFuse = true
		else
			self.FuseTime = 0
			self.BulletData.FuseLength = 0
			self.OverrideFuse = false
		end
	elseif iname == "ROFLimit" then
		-- Set the rate of fire limit if value is greater than 0
		local lowestROF = 0.1
		local oldLimit = self.ROFLimit
		if value > 0 then
			self.ROFLimit = math.max(value, lowestROF) -- Limit the rate of fire
		else
			self.ROFLimit = 0
		end

		if oldLimit ~= self.ROFLimit then
			RefreshGunRateOfFire(self)
			if ACE.PointsInputChanged then
				ACE.PointsInputChanged(self, "gun-rof-limit")
			end
		end
	end
end



function ENT:Heat_Function()

	--print(DeltaTime)

	self.Heat = ACE.HeatFromGun( self , self.Heat, self.DeltaTime )
	Wire_TriggerOutput(self, "Heat", math.Round(self.Heat))

	-- TODO: instead of breaking the gun by heat, decrease accurancy and jam it
	local OverHeat = math.max(self.Heat / 200, 0) --overheat will start affecting the gun at 200° celcius. STILL unrealistic, weird
	if OverHeat > 1 and self.Caliber < 10 then  --leave the low calibers to damage themselves only

		self.IsOverheated = true
		Wire_TriggerOutput(self,"OverHeat", 1)

		--local phys = self:GetPhysicsObject()
		--local Mass = phys:GetMass()

		--[[
		HitRes = ACE.Damage(self, {
			Kinetic = (1 * OverHeat) * (1 + math.max(Mass - 300, 0.1)),
			Momentum = 0,
			Penetration = (1 * OverHeat) * (1 + math.max(Mass - 300, 0.1))
		}, 2, 0, self:CPPIGetOwner())

		if HitRes.Kill then
			ACE.HEKill( self, VectorRand() , 0)
		end
		]]--

	else
		self.IsOverheated = false
		Wire_TriggerOutput(self,"OverHeat", 0)
	end

end

function ENT:TrimDistantCrates()

	for _, Crate in pairs(self.AmmoLink) do
		if IsValid( Crate ) and Crate.Load and not IsInRetDist( self, Crate, AmmoLinkDistBase * self.LinkRangeMul ) then
			BreakGunLink( self, Crate )
		end
	end

end

function ENT:TrimDistantCrewSeats()
	for _, Seat in pairs(self.CrewLink) do
		if IsValid( Seat ) and not IsInRetDist( self, Seat, CrewLinkDistBase * self.LinkRangeMul ) then
			BreakGunLink( self, Seat )
		end
	end
end

--[[
	function ENT:TrimInvalidLoaders()

		local Crewmates = table.Copy(self.CrewLink)

		if self.LoaderCount > 0 and not self.HasGunner then
			for k, Crew in pairs(Crewmates) do

				PrintTable(Crewmates)

				if IsValid(Crew) then
					print("Removing loader...")
					if Crew:GetClass() == "ace_crewseat_loader" then
						self:Unlink( Crew )
					end
				end
			end
		end
	end
]]

function ENT:Think()

	--Legality check part
	if ACE.CurTime > self.NextLegalCheck then

		-- check gun is legal
		self.Legal, self.LegalIssues = ACE.CheckLegal(self, self.Model, math.Round(self.Mass,2), self.ModelInertia, nil, true)
		self.NextLegalCheck = ACE.Legal.NextCheck(self.legal)

		-- check the seat is legal
		local seat = IsValid(self.User) and self.User:GetVehicle() or nil

		if IsValid(seat) then
			local legal, issues = ACE.CheckLegal(seat, nil, nil, nil, nil, false)
			if not legal then
				self.Legal = false
				self.LegalIssues = self.LegalIssues .. "\nSeat not legal: " .. issues
			end
		end

		self:UpdateOverlayText()

		if not self.Legal and self.Firing then self:TriggerInput("Fire", 0) end

	end

	-- IDK how an object can break this bad but it did. Hopefully this fixes the 1 in a million bug
	local PhysObj = self:GetPhysicsObject()
	if not IsValid(PhysObj) then return end

	self.DeltaTime = CurTime() - self.LastThink

	self:Heat_Function()

	local Time = CurTime()
	if self.LastSend + 1 <= Time then

		local Ammo = 0

		--UnlinkDistance
		for _, Crate in pairs(self.AmmoLink) do
			if IsValid( Crate ) and Crate.Load and Crate.Legal then

			if IsInRetDist( self, Crate, AmmoLinkDistBase * self.LinkRangeMul ) then
					Ammo = Ammo + (Crate.Ammo or 0)
				else
					BreakGunLink( self, Crate )
				end
			end
		end

		self:TrimDistantCrewSeats()

		self.Ammo = Ammo
		self:UpdateOverlayText()

		Wire_TriggerOutput(self, "AmmoCount", Ammo)


		local isEmpty = self.BulletData.Type == "Empty"
		if self.MagSize then
			Wire_TriggerOutput(self, "Shots Left", isEmpty and 0 or (self.MagSize - self.CurrentShot))
		else
			Wire_TriggerOutput(self, "Shots Left", isEmpty and 0 or 1)
		end

		self:SetNWString("GunType", self.Id)
		self:SetNWInt("Ammo",Ammo)
		self:SetNWString("Type", self.BulletData.Type)
		self:SetNWFloat("Mass", self.BulletData.ProjMass * 100)
		self:SetNWFloat("Propellant", self.BulletData.PropMass * 1000)
		self:SetNWFloat("FireRate", self.RateOfFire)

		self.LastSend = Time

	end

	if self.NextFire <= Time then
		if self.BulletData.Type and self.BulletData.Type ~= "Empty" then
			self.Ready = true
			Wire_TriggerOutput(self, "Ready", 1)
		else
			self.Ready = false
			Wire_TriggerOutput(self, "Ready", 0)
		end

		if self.MagSize and self.MagSize == 1 then
			self.CurrentShot = 0
		end

		if self.Firing then
			--print("Fire!")
			self:FireShell()
		elseif self.Reloading then
			--print("Reloading!")
			self:ReloadMag()
			self.Reloading = false
		end
	end

	self.LastThink = ACE.CurTime
	self:NextThink(Time)

	if self.CurrentRecoil > 0 then
		local Dir = -self:GetForward()
		--local MuzzlePos		= self:LocalToWorld(self.Muzzle)
		--local MuzzlePos		= self:GetForward() * self.Muzzle.x + self:GetRight()  * self.Muzzle.y + self:GetUp() * self.Muzzle.z
		--local MuzzlePos		= self:GetPos()
		ACE.KEShove(self, self:GetPos() , Dir , self.KERecoil * self.CurrentRecoil )

		self.CurrentRecoil = math.max(self.CurrentRecoil - self.DeltaTime / 0.5,0) --Divided by time to dissipate recoil. Currently 0.5
		--self.CurrentRecoil = 0
	end

	return true

end

function ENT:ReloadMag()
	if self.IsUnderWeight == nil then
		self.IsUnderWeight = true
	end
	if ( (self.CurrentShot > 0) and self.IsUnderWeight and self.Ready and self.Legal ) then
		if ( ACE.RoundTypes[self.BulletData.Type] ) then		--Check if the roundtype loaded actually exists
			self:LoadAmmo(self.MagReload, false)
			self:EmitSound("weapons/357/357_reload4.wav", 68, 100)
			self.CurrentShot = 0
			Wire_TriggerOutput(self, "Ready", 0)
		else
			self.CurrentShot = 0
			self.Ready = false
			Wire_TriggerOutput(self, "Ready", 0)
			self:LoadAmmo(false, true)
		end
	end
end

do

	local FSTable = {
		APFSDS  = true,
		HEATFS  = true,
		HEFS	= true,
		THEATFS = true
	}

	function ENT:GetInaccuracy()

		local SpreadScale = ACE.SpreadScale
		local IaccMult = 1

		if self.ACE.Health and self.ACE.MaxHealth then
			IaccMult = math.Clamp(((1 - SpreadScale) / 0.5) * ((self.ACE.Health / self.ACE.MaxHealth) - 1) + 1, 1, SpreadScale)
		end

		-- Increased FS accuracy. Hardcoded.
		if FSTable[self.BulletData.Type] then
			IaccMult = IaccMult * 0.25
		end

		-- No gunner = more inaccuracy
		if not self.HasGunner then
			IaccMult = IaccMult * 1.5
		end

		local coneAng = self.Inaccuracy * ACE.GunInaccuracyScale * IaccMult

		return coneAng
	end

end

do

	function ENT:ChooseLoader()

		local highestStaminaLoader = nil
		local highestStamina = 0

		for _, crewEnt in ipairs(self.CrewLink) do
			if crewEnt:GetClass() == "ace_crewseat_loader" and crewEnt.Legal then
				local stamina = crewEnt.Stamina
				if stamina >= highestStamina then
					highestStamina = stamina
					highestStaminaLoader = crewEnt
				end
			end
		end

		return highestStaminaLoader
	end


	local FusedRounds = {
		HE	= true,
		HEFS	= true,
		HESH	= true,
		HEAT	= true,
		THEAT	= true,
		SM	= true,
		CHE	= true,
		CHEAT	= true,
		CAP	= true
	}

	function ENT:FireShell()

		local CanDo = hook.Run("ACE_FireShell", self, self.BulletData )
		if CanDo == false then return end

		if self.IsUnderWeight == nil then
			self.IsUnderWeight = true
		end

		if self.RequiresGunner and not self.HasGunner then
			local HasWarned = self.OTWarnings.WarnedGunner or false
			--self.OTWarnings
			if not HasWarned then
				--print("No")
				ACE.ChatMessagePly( self:CPPIGetOwner() , "[ACE] Your gun is above [" .. ACE.LargeGunsThreshold .. " mm] and requires a gunner to operate.", Color( 255, 0, 0 ))
				self.OTWarnings.WarnedGunner = true
			end
			return
		end

		ACE.DoContraptionLegalCheck(self)

		local bool = true

		-- An empty gun reports Ready = 0 (correct for wire), but it must still be
		-- able to attempt a reload when fired, otherwise it stays locked empty once
		-- its crate runs dry. Letting it through here lands in the else branch below,
		-- which calls LoadAmmo to pull a round from any active crate.
		local isEmpty = self.BulletData.Type == "Empty"

		if ( bool and self.IsUnderWeight and (self.Ready or isEmpty) and self.Legal ) then

			local Blacklist = {}
			if not ACE.AmmoBlacklist[self.BulletData.Type] then
				Blacklist = {}
			else
				Blacklist = ACE.AmmoBlacklist[self.BulletData.Type]
			end

			if ( ACE.RoundTypes[self.BulletData.Type] and not table.HasValue( Blacklist, self.Class ) and not ( (ACE.Classes.GunClass[self.Class] or {}).ammofamily and table.HasValue( Blacklist, (ACE.Classes.GunClass[self.Class] or {}).ammofamily ) ) ) then	--Check if the roundtype loaded actually exists

				self.HeatFire = true  --Used by Heat

				local MuzzlePos		= self:LocalToWorld(self.Muzzle)
				local MuzzleVec		= self:GetForward()

				local coneAng		= math.tan(math.rad(self:GetInaccuracy()))
				local randUnitSquare	= (self:GetUp() * (2 * math.random() - 1) + self:GetRight() * (2 * math.random() - 1))
				local spread			= randUnitSquare:GetNormalized() * coneAng * (math.random() ^ (1 / math.Clamp(ACE.GunInaccuracyBias, 0.5, 4)))
				local ShootVec		= (MuzzleVec + spread):GetNormalized()

				self:MuzzleEffect( MuzzlePos, MuzzleVec )

				local Parent = ACE.GetPhysicalParent(self)
				local ParentVelocity = IsValid(Parent) and Parent:GetVelocity() or vector_origin

				-- The projectile must start at the physical muzzle. Ballistics adds traceback
				-- compensation while tracing, so shifting this origin by vehicle motion is incorrect.
				self.BulletData.Pos = MuzzlePos
				self.BulletData.Flight = ShootVec * self.BulletData.MuzzleVel * 39.37 + ParentVelocity
				self.BulletData.Owner = self.User
				self.BulletData.Gun = self

				local Contraption = self:CFW_GetContraption()
				local BulletFilter = Contraption and Contraption.BulletFilter
				self.BulletData.Filter = BulletFilter or { self }

				--local Cal = self.Caliber

				--using fusetime via wire will override the ammo fusetime!
				if FusedRounds[self.BulletData.Type] and FusedRounds[self.BulletData.Type] and self.OverrideFuse then
					self.BulletData.FuseLength = self.FuseTime
				end

				self.CreateShell = ACE.RoundTypes[self.BulletData.Type].create
				self:CreateShell( self.BulletData )

				self.CurrentRecoil = 1

				self.Ready = false
				self.CurrentShot = math.min(self.CurrentShot + 1, self.MagSize)

				if (self.CurrentShot >= self.MagSize) and (self.MagSize > 1) then
					self:LoadAmmo(self.MagReload, false)
					self:EmitSound("weapons/357/357_reload4.wav",68,100)
					timer.Simple(self.LastLoadDuration, function() if IsValid(self) then self.CurrentShot = 0 end end)
				else
					self:LoadAmmo(false, false)
				end
				Wire_TriggerOutput(self, "Ready", 0)

			else
				self:EmitSound("weapons/shotgun/shotgun_empty.wav", 68, 100)
				self.CurrentShot = 0
				self.Ready = false
				Wire_TriggerOutput(self, "Ready", 0)
				self:LoadAmmo(false, true)
			end
		end

	end
end

function ENT:FindNextCrate()

	local MaxAmmo = #self.AmmoLink
	local AmmoEnt = nil
	local i = 0

	while i <= MaxAmmo and not (AmmoEnt and AmmoEnt:IsValid() and AmmoEnt.Ammo > 0) do -- need to check ammoent here? returns if found

		self.CurAmmo = self.CurAmmo + 1
		if self.CurAmmo > MaxAmmo then self.CurAmmo = 1 end

		AmmoEnt = self.AmmoLink[self.CurAmmo]
		if AmmoEnt and AmmoEnt:IsValid() and AmmoEnt.Ammo > 0 and AmmoEnt.Load and AmmoEnt.Legal then
			return AmmoEnt
		end
		AmmoEnt = nil

		i = i + 1
	end

	return false
end

function ENT:LoadAmmo( AddTime, Reload )

	self:TrimDistantCrates()

	local AmmoEnt = self:FindNextCrate()
	local curTime = CurTime()

	if AmmoEnt and AmmoEnt.Legal then
		AmmoEnt.Ammo = AmmoEnt.Ammo - 1
		-- Copy the round so the gun can apply its own bore-length muzzle velocity
		-- factor without mutating the crate's canonical BulletData.
		self.BulletData = table.Copy( AmmoEnt.BulletData )
		self.BulletData.Crate = AmmoEnt:EntIndex()
		if ( self.MuzVelMod or 1 ) ~= 1 then
			self.BulletData.MuzzleVel = self.BulletData.MuzzleVel * self.MuzVelMod
		end

		local ReloadTime, Loader = GetGunReloadTime(self, AmmoEnt.BulletData, AmmoEnt.RoFMul)
		self.ReloadTime = ReloadTime
		if IsValid(Loader) then Loader:DecreaseStamina() end

		Wire_TriggerOutput(self, "Loaded", self.BulletData.Type)

		self.RateOfFire = (60 / self.ReloadTime)
		Wire_TriggerOutput(self, "Fire Rate", self.RateOfFire)
		Wire_TriggerOutput(self, "Muzzle Weight", math.floor(self.BulletData.ProjMass * 1000) )
		Wire_TriggerOutput(self, "Muzzle Velocity", math.floor(self.BulletData.MuzzleVel * ACE.VelScale) )

		self.KERecoil = (self.BulletData.PropMass * 39.37) * (GetConVar("ace_recoilpush"):GetFloat() or 1) * 375

		self.NextFire = curTime + self.ReloadTime
		local reloadTime = self.ReloadTime

		if AddTime then
			reloadTime = reloadTime + AddTime
		end
		if self.FirstLoad then
			self.FirstLoad = false
			reloadTime = 0.1
		end

		if Reload then
			-- Send the effective ready time: a FirstLoad gun is ready in 0.1s, and the client's
			-- Animate(LoadOnly) holds the reload pose for ~75% of the received magnitude.
			self:ReloadEffect(reloadTime)
		end

		self.NextFire = curTime + reloadTime
		self.LastLoadDuration = reloadTime

		self:Think()
		return true
	else
		self.BulletData = {}
			self.BulletData.Type = "Empty"
			self.BulletData.PropMass = 0
			self.BulletData.ProjMass = 0

		Wire_TriggerOutput(self, "Loaded", "Empty")

		self.NextFire = curTime + 0.5
		self:Think()
	end
	return false

end

function ENT:UnloadAmmo()

	if not self.BulletData or not self.BulletData.Crate then return end
	if not self.Ready then
		if (self.NextFire-CurTime()) < 0 then return end -- see above; preventing spam
		if self.MagSize > 1 and self.CurrentShot >= self.MagSize then return end -- prevent unload in middle of mag reload
	end

	local Crate = Entity( self.BulletData.Crate )
	if Crate and Crate:IsValid() and self.BulletData.Type == Crate.BulletData.Type then
		Crate.Ammo = math.min(Crate.Ammo + 1, Crate.Capacity)
	end

	self.Ready = false
	Wire_TriggerOutput(self, "Ready", 0)
	self:EmitSound("weapons/shotgun/shotgun_empty.wav", 68, 100)

	local unloadtime = self.ReloadTime / 2 -- base time to swap a fully loaded shell out
	if self.NextFire < CurTime() then -- unloading in middle of reload
		unloadtime = math.min(unloadtime, math.max(self.ReloadTime - (self.NextFire - CurTime()), 0) )
	end
	self:LoadAmmo( unloadtime, true )

end

function ENT:MuzzleEffect()

	local Effect = EffectData()
		Effect:SetEntity( self )
		Effect:SetScale( self.BulletData.PropMass )
		Effect:SetMagnitude( self.ReloadTime )
		Effect:SetSurfaceProp( ACE.RoundTypes[self.BulletData.Type].netid  )	--Encoding the ammo type into a table index
	util.Effect( "ACE_MuzzleFlash", Effect, true, true )

	if self.AutoSound and self.Sound ~= "" then
		timer.Simple(0.6, function()
			self:EmitSound(self.AutoSound, 73, math.random(84, 86))
		end )
	end
end

function ENT:ReloadEffect( EffectTime )

	local Effect = EffectData()
		Effect:SetEntity( self )
		Effect:SetScale( 0 )
		Effect:SetMagnitude( EffectTime or self.ReloadTime )
		Effect:SetSurfaceProp( ACE.RoundTypes[self.BulletData.Type].netid  )	--Encoding the ammo type into a table index
	util.Effect( "ACE_MuzzleFlash", Effect, true, true )

end

function ENT:PreEntityCopy()

	local info = {}
	local entids = {}
	for _, Value in pairs(self.AmmoLink) do				--First clean the table of any invalid entities
		if not Value:IsValid() then
			table.remove(self.AmmoLink, Value)
		end
	end
	for _, Value in pairs(self.AmmoLink) do				--Then save it
		table.insert(entids, Value:EntIndex())
	end
	for _, Value in pairs(self.CrewLink) do				--First clean the table of any invalid entities
		if not Value:IsValid() then
			table.remove(self.CrewLink, Value)
		end
	end
	for _, Value in pairs(self.CrewLink) do				--Then save it
		table.insert(entids, Value:EntIndex())
	end
	info.entities = entids
	if info.entities then
		duplicator.StoreEntityModifier( self, "ACFAmmoLink", info )
	end

	--Wire dupe info
	self.BaseClass.PreEntityCopy( self )

end

function ENT:PostEntityPaste( Player, Ent, CreatedEntities )
	local pointSources = { self }
	self._ACEPointsSuppress = true

	local AmmoLink = Ent.EntityMods and (Ent.EntityMods.ACEAmmoLink or Ent.EntityMods.ACFAmmoLink)
	if AmmoLink and AmmoLink.entities then

		if AmmoLink.entities and table.Count(AmmoLink.entities) > 0 then

			for _, AmmoID in pairs(AmmoLink.entities) do

				local Ammo = CreatedEntities[ AmmoID ]

				if IsValid(Ammo) then
					pointSources[#pointSources + 1] = Ammo

					if Ammo:GetClass() == "acf_ammo" then
						self:Link( Ammo )
					elseif Ammo:GetClass() == "ace_crewseat_gunner" then
						self:Link( Ammo )
					elseif Ammo:GetClass() == "ace_crewseat_loader" then
						if not self.noloaders then
							self:Link( Ammo )
						end
					end
				end
			end
		end

		Ent.EntityMods.ACEAmmoLink = nil
		Ent.EntityMods.ACFAmmoLink = nil
	end

	self._ACEPointsSuppress = nil

	--Wire dupe info
	self.BaseClass.PostEntityPaste( self, Player, Ent, CreatedEntities )
	if ACE.PointsInputChanged then
		ACE.PointsInputChanged(pointSources, "gun-links-pasted")
	end
end

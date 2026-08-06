--[[----------------------------------------------------------------------------
	ACE Explosive Reactive Armor core

	Physics model concept by Delectros (STEAM_0:0:144869639), originally
	prototyped in Expression2 ("ACE era concept"): a flyer plate moving across
	the penetrator's path erodes a slice of the rod and shoves it off course.

	This is a corrected, dimensionally-consistent port of that idea. The E2 had
	real errors that are fixed here (kept as comments where relevant):
	  * rod cross-section used circumference (pi*d) instead of area (pi/4*d^2);
	  * engaged plate mass divided by sin(angle) with no guard -> infinite mass
	    for slow plates / fast rods;
	  * remaining rod mass allowed to go negative -> negative penetration;
	  * an underived magic 1.30909 divisor on rod length;
	  * "inertia" defined as mass*velocity*hardness (not inertia).

	The model works in SI and compares two momenta per unit frontal area:
	  * the flyer plate's transverse momentum (rho_plate * thickness * plateVel)
	  * the rod's axial momentum         (rho_rod   * rodLength  * rodVel)
	Their ratio, scaled by a hardness ratio and an obliquity factor, is how much
	of the rod the plate can erode/divert. Every term is a real shell parameter:
	caliber -> rod area, projectile mass + caliber -> rod length, live impact
	speed -> rod velocity, round type -> density/hardness/jet behavior, and the
	hit direction vs the plate's forward -> angle of attack (and the front gate).

	Brick volume uses PhysObj:GetVolume() with a convex-mesh integration fallback
	adapted from ACF-3's volumetric-armor-meshes branch
	(https://github.com/ACF-Team/ACF-3/tree/volumetric-armor-meshes). Credit ACF Team.

	Generations register themselves from lua/acf/shared/armor/era*.lua via
	ACE.ERA.RegisterGeneration.
------------------------------------------------------------------------------]]

ACE = ACE or {}
ACE.ERA = ACE.ERA or {}

local ERA = ACE.ERA

-- Ammo type groups handled specially by reactive armor.
ERA.HEATList   = { HEAT = true, THEAT = true, HEATFS = true, THEATFS = true }
ERA.TandemList = { THEAT = true, THEATFS = true }
ERA.HEList     = { HE = true, HESH = true, Frag = true }

-- Per-type penetrator assumptions. IMPORTANT: ACF derives the `caliber` that
-- reaches the damage code from the projectile's *penetrating* area, so it is
-- already the PENETRATOR caliber -- the thin subcaliber dart for sabots (a min
-- 120mm APFSDS works out to ~25mm here), the full bore for AP. So DiaFrac is 1.0
-- across the board: the rod diameter IS that caliber, no further reduction.
-- Density (kg/m3) cancels in the momentum ratio and only bounds rod length; BHN
-- is the hardness used in the erosion ratio; Vel is a fallback impact speed.
ERA.RodData = {
	AP     = { DiaFrac = 1.0, Density = 7850,  BHN = 1500, Vel = 900  },
	APHE   = { DiaFrac = 1.0, Density = 7850,  BHN = 1200, Vel = 850  },
	HP     = { DiaFrac = 1.0, Density = 7850,  BHN = 900,  Vel = 800  },
	APDS   = { DiaFrac = 1.0, Density = 19250, BHN = 2000, Vel = 1100 },
	HVAP   = { DiaFrac = 1.0, Density = 16600, BHN = 2200, Vel = 1150 },
	APCR   = { DiaFrac = 1.0, Density = 16600, BHN = 2200, Vel = 1150 },
	APFSDS = { DiaFrac = 1.0, Density = 19300, BHN = 3000, Vel = 1500 },
}

ERA.DefaultRod = { DiaFrac = 1.00, Density = 7850, BHN = 1000, Vel = 800 }

-- HEAT jets: a fluid copper (or tantalum, FS) jet. No meaningful hardness, can't
-- be deflected as a body, but is severed very effectively by a moving plate.
-- LenPerPen approximates jet length (m) per metre of stated RHA penetration.
ERA.JetData = {
	HEAT    = { Density = 8960,  Vel = 6000, LenPerPen = 1.4 },
	THEAT   = { Density = 8960,  Vel = 6000, LenPerPen = 1.4 },
	HEATFS  = { Density = 16600, Vel = 7000, LenPerPen = 1.4 },
	THEATFS = { Density = 16600, Vel = 7000, LenPerPen = 1.4 },
}

ERA.FlyerPlateDensity = 7850 -- RHA flyer plates (kg/m3)
ERA.FlyerPlateBHN     = 400

-- Dimensionless normalisation so per-generation efficiencies stay order ~1.
-- Calibrated against a 120mm APFSDS reference at a 30-degree (from surface)
-- sloped hit; tuned via tests/era_math_test.lua balance bands.
ERA.MomentumNorm = 320

-- Larger-diameter cores are stiffer and carry more momentum, so a fat heavy rod
-- resists the flyer plate's lateral impulse and defeats ERA better than a thin
-- one (real long-rod behavior). The momentum ratio already carries a spurious
-- diameter^2 (rod momentum is taken per unit area); an exponent of 3 cancels
-- that and leaves the physically correct ~1/diameter per-length scaling, so the
-- net effect is "fatter core -> less cut". Normalised to a 120mm sabot core
-- (~42mm) so the tuned reference scenario is unchanged. Jets (fluid) are exempt.
ERA.RefRodDiaMM  = 24
ERA.DiaResistExp = 3.0

local pi  = math.pi
local rad = pi / 180

--- Penetrator rod geometry in SI, from real round data.
-- For KE rounds the length follows from projectile mass, the rod cross-section
-- (caliber * DiaFrac) and the assumed core density, clamped to a sane multiple of
-- the rod diameter so odd inputs can't produce absurd rods. For HEAT the "rod" is
-- the jet, whose length scales with stated penetration.
-- @param Type Ammo type string.
-- @param penMM Penetration at impact, mm.
-- @param caliberMM Caliber at impact, mm.
-- @param velMS Live impact speed, m/s (optional).
-- @param projMassKg Live projectile mass, kg (optional).
-- @return number rodLength_m
-- @return number rodArea_m2
-- @return number rodDensity_kgm3
-- @return number rodVel_ms
-- @return number rodBHN
-- @return boolean isJet
function ERA.RodGeometry( Type, penMM, caliberMM, velMS, projMassKg )

	local isJet = ERA.HEATList[Type] or false

	if isJet then
		local jet    = ERA.JetData[Type] or ERA.JetData.HEAT
		local dia    = math.max(caliberMM, 1) / 1000          -- jet "diameter" ~ slug caliber
		local area   = pi * 0.25 * dia * dia
		local length = math.max(penMM, 0) / 1000 * jet.LenPerPen
		return length, area, jet.Density, jet.Vel, 0, true
	end

	local rod   = ERA.RodData[Type] or ERA.DefaultRod
	local dia   = math.max(caliberMM, 1) / 1000 * rod.DiaFrac
	local area  = pi * 0.25 * dia * dia

	local length
	if projMassKg and projMassKg > 0 and area > 0 then
		length = projMassKg / (rod.Density * area)
	else
		-- Fallback: rod length proxied from penetration (longer rods penetrate more).
		length = math.max(penMM, 0) / 1000 * 0.9
	end

	-- Keep the rod between 1x and 30x its diameter.
	length = math.Clamp(length, dia, dia * 30)

	local vel = (velMS and velMS > 0) and velMS or rod.Vel

	return length, area, rod.Density, vel, rod.BHN, false
end

--- Compute how much of an incoming penetrator an ERA brick erodes and deflects.
-- Pure math, no game state -- unit tested standalone (tests/era_math_test.lua).
-- The flyer plate's transverse momentum per unit frontal area is compared to the
-- rod's axial momentum per unit area; that ratio, scaled by a hardness ratio,
-- obliquity, plate length and plate travel, is the eroded fraction of the rod.
-- Angle of attack is the dominant factor (ERA is far stronger at an angle).
-- @param Gen Generation parameter table (see ERA.RegisterGeneration).
-- @param Type Ammo type string (e.g. "APFSDS", "HEAT").
-- @param penMM Penetrator RHA penetration at impact, in mm.
-- @param caliberMM Penetrator caliber at impact, in mm.
-- @param aoaDeg Angle of attack: 0 = face-on (perpendicular), higher = grazing.
-- @param healthRatio Brick health fraction (0..1); damaged bricks react weaker.
-- @param velMS Live impact speed in m/s (optional; falls back to per-type Vel).
-- @param projMassKg Live projectile mass in kg (optional; falls back to a pen proxy).
-- @param plateLenMM Plate length available to bite, mm (optional; from brick face size).
-- @param travelMM Plate travel distance / ERA depth, mm (optional; from brick thickness).
-- @return cutFraction Share of penetration removed (0..1).
-- @return deflect Direction blend toward the surface normal (0..0.35; 0 for jets).
function ERA.ComputeCut( Gen, Type, penMM, caliberMM, aoaDeg, healthRatio, velMS, projMassKg, plateLenMM, travelMM )

	healthRatio = math.Clamp(healthRatio or 1, 0, 1)

	if not penMM or penMM <= 0 then return 0, 0 end
	if not caliberMM or caliberMM <= 0 then return 0, 0 end

	local rodLen, rodArea, rodDens, rodVel, rodBHN, isJet =
		ERA.RodGeometry(Type, penMM, caliberMM, velMS, projMassKg)

	if rodLen <= 0 or rodArea <= 0 then return 0, 0 end

	-- Momentum per unit frontal area (SI: kg*m^-1*s^-1) for plate and rod.
	local plateThick = math.max(Gen.FlyerPlateMM, 0) / 1000
	local plateMom   = ERA.FlyerPlateDensity * plateThick * Gen.PlateVel
	local rodMom     = rodDens * rodLen * rodVel

	if rodMom <= 0 then return 0, 0 end

	-- Obliquity: a grazing rod lets the moving plate sweep a much longer section
	-- of it (this is why ERA is far better at angle). aoa 0 -> x1, grazing -> up
	-- to the cap. Replaces the E2's unguarded 1/sin(relAngle).
	local aoa     = math.Clamp(aoaDeg or 0, 0, 89)
	local obliq   = math.Clamp(1 / math.cos(aoa * rad), 1, Gen.MaxObliquity or 4)

	-- Hardness ratio: a hard rod resists erosion by the (softer) steel plate.
	-- Jets have no hardness, so the term drops out and jet efficiency carries it.
	local hardness = isJet and 1 or (ERA.FlyerPlateBHN / math.max(rodBHN, 1))

	local R = (plateMom / rodMom) * ERA.MomentumNorm * hardness * obliq

	-- Bigger bricks bite better, but only for the heavier generations whose
	-- plates are thick/fast enough to act on a rod. A longer plate (brick face)
	-- sweeps a longer section of the rod; a thicker brick lets the plate(s)
	-- travel further along it (Gen 3 fires both ways, so it scales hardest).
	-- Gen 1's thin plates get PlateLengthScale/TravelScale = 0 -> no benefit,
	-- which is why Gen 1 does essentially nothing to a long rod beyond casing.
	if plateLenMM and plateLenMM > 0 and (Gen.PlateLengthScale or 0) > 0 then
		R = R * math.max(1 + Gen.PlateLengthScale * (plateLenMM / (Gen.RefPlateLenMM or 300) - 1), 0.25)
	end
	if travelMM and travelMM > 0 and (Gen.TravelScale or 0) > 0 then
		R = R * math.max(1 + Gen.TravelScale * (travelMM / (Gen.RefTravelMM or 100) - 1), 0.25)
	end

	-- Diameter resistance: a fatter, stiffer core sheds less of itself to the
	-- plate. Only for solid rods; a jet has no rigidity to resist with.
	if not isJet then
		local rd = ERA.RodData[Type] or ERA.DefaultRod
		local rodDiaMM = caliberMM * rd.DiaFrac
		R = R / math.max((rodDiaMM / ERA.RefRodDiaMM) ^ ERA.DiaResistExp, 0.05)
	end

	local eff   = isJet and Gen.HEATEfficiency or Gen.KEEfficiency
	local floor = isJet and Gen.MinCutHEAT or Gen.MinCutKE
	local cap   = isJet and Gen.MaxCutHEAT or Gen.MaxCutKE

	-- Eroded rod fraction. Floored (a triggered brick always disrupts the rod
	-- some) and capped (a plate cannot erase the whole rod); health scales it.
	-- The E2 instead allowed remaining rod mass to go negative.
	local cut = math.min(cap, math.max(floor, eff * R)) * healthRatio
	cut = math.Clamp(cut, 0, 1)

	-- Inertia-weighted deflection for solid penetrators only: a plate cannot
	-- twist a fluid jet (Delectros keeps jets on course).
	local deflect = 0
	if not isJet then
		deflect = math.Clamp((plateMom / rodMom) * ERA.MomentumNorm * (Gen.DeflectScale or 1) * obliq, 0, 0.35)
	end

	return cut, deflect
end

--- A single representative "effective RHA mm" figure for an ERA generation.
-- Evaluated against a reference threat per damage family at a representative
-- sloped hit. Not used by the live damage path (that runs ComputeCut on the real
-- round); this is purely for display / queries (armor tool, E2, Starfall) so the
-- "actual armor" getters mean something for reactive armor.
-- @param Gen Generation parameter table.
-- @param family "KE" (reference 120mm APFSDS) or "HEAT" (reference 105mm jet).
-- @return number Casing armor plus the reference penetration removed, in mm.
function ERA.EstimateEffectiveArmor( Gen, family )
	-- Reference threats: a 120mm APFSDS for KE, a 105mm HEAT jet for chemical.
	local refType, refPen, refCal, refVel, refMass
	if family == "HEAT" then
		refType, refPen, refCal, refVel, refMass = "HEAT", 450, 110, nil, nil
	else
		refType, refPen, refCal, refVel, refMass = "APFSDS", 550, 120, 1500, 6
	end

	-- Evaluated at a representative 30-degree-from-surface sloped hit (aoa 60).
	local cut = ERA.ComputeCut(Gen, refType, refPen, refCal, 60, 1, refVel, refMass)

	return math.Round((Gen.CasingMM or 0) + cut * refPen, 1)
end

--[[----------------------------------------------------------------------------
	Serverside: brick volume + armor material resolution
------------------------------------------------------------------------------]]
if SERVER then

	ACE.ERABoomPerTick = ACE.ERABoomPerTick or 0

	-- Temporal debug. `ace_era_debug 1` (with `developer 1` clientside) draws each
	-- ERA reaction for a few seconds: the forward/reactive face (green if the hit
	-- landed on it, orange if not), the incoming rod (red), and a readout of
	-- generation, ammo type, angle of attack, trigger and cut/deflect. Handy for
	-- eyeballing the front-face gate and confirming tandem behavior on a test rig.
	CreateConVar("ace_era_debug", 0, FCVAR_NOTIFY, "Draw ACE ERA reaction debug overlays.")
	local DebugCon = GetConVar("ace_era_debug")

	--- @return boolean True if ERA reaction debug overlays are enabled.
	function ERA.DebugEnabled() return DebugCon ~= nil and DebugCon:GetBool() end

	--- Draw one ERA reaction as temporal debugoverlay primitives.
	-- @param Entity The ERA brick / prop that was hit.
	-- @param forward World-space forward (reactive face normal).
	-- @param hitDir World-space travel direction of the round (may be nil).
	-- @param Type Ammo type string.
	-- @param frontHit True if the hit landed on the forward hemisphere.
	-- @param triggered True if the brick detonated.
	-- @param cut Eroded penetration fraction (0..1).
	-- @param deflect Deflection blend factor.
	-- @param aoaDeg Angle of attack in degrees.
	function ERA.DrawDebug( Entity, forward, hitDir, Type, frontHit, triggered, cut, deflect, aoaDeg )
		local pos  = Entity:WorldSpaceCenter()
		local life = 6
		debugoverlay.Line(pos, pos + forward * 24, life, frontHit and Color(0, 255, 0) or Color(255, 180, 0), true)
		if isvector(hitDir) then
			debugoverlay.Line(pos - hitDir * 24, pos, life, Color(255, 0, 0), true)
		end
		debugoverlay.Text(pos + forward * 28, string.format(
			"ERA %s | %s | AoA %.0f | front:%s trig:%s | cut %.0f%% defl %.2f",
			Entity.GenId or (Entity.ACF and Entity.ACF.Material) or "?",
			tostring(Type), aoaDeg or 0, tostring(frontHit), tostring(triggered),
			(cut or 0) * 100, deflect or 0), life, false)
	end

	--- Print one ERA reaction line to the server console (and the firing player's
	-- console). Same gate as the overlay (`ace_era_debug 1`). This is the readable
	-- "what happened" log the overlay can't give you: round type, whether it hit the
	-- reactive face, whether it triggered, and the penetration BEFORE vs AFTER the
	-- brick -- so you can see exactly how much pen the round has left (e.g. where a
	-- HEAT jet ends up) and how effective the brick was.
	-- @param Gen Generation table.
	-- @param Type Ammo type string.
	-- @param frontHit True if the hit was on the reactive face.
	-- @param triggered True if the brick detonated.
	-- @param penBefore Penetration arriving at the brick, mm.
	-- @param penAfter Penetration leaving the brick (overkill), mm.
	-- @param cut Eroded fraction (0..1).
	-- @param deflect Deflection blend.
	-- @param caliberMM Penetrator caliber, mm.
	-- @param aoaDeg Angle of attack, degrees.
	-- @param Owner The firing player (optional; also gets the line in their console).
	function ERA.LogReaction( Gen, Type, frontHit, triggered, penBefore, penAfter, cut, deflect, caliberMM, aoaDeg, Owner )
		local line
		if triggered then
			line = string.format(
				"[ACE ERA] %s vs %s | front=%s TRIGGERED | pen %d -> %d mm (-%.0f%%) | cal %.0f mm | AoA %.0f deg | casing %d mm | defl %.2f",
				Gen.sname or Gen.id, tostring(Type), frontHit and "yes" or "NO",
				math.Round(penBefore), math.Round(penAfter), (cut or 0) * 100,
				caliberMM or 0, aoaDeg or 0, Gen.CasingMM or 0, deflect or 0)
		else
			line = string.format(
				"[ACE ERA] %s vs %s | front=%s did NOT trigger - inert %d mm casing only | pen %d mm | cal %.0f mm | AoA %.0f deg",
				Gen.sname or Gen.id, tostring(Type), frontHit and "yes" or "NO",
				Gen.CasingMM or 0, math.Round(penBefore), caliberMM or 0, aoaDeg or 0)
		end

		print(line)
		if IsValid(Owner) and Owner:IsPlayer() then
			Owner:PrintMessage(HUD_PRINTCONSOLE, line)
		end
	end

	-- Convex mesh volume integration, adapted from ACF-3 volumetric-armor-meshes
	-- (scalar triple product over each convex's triangles = 6x the volume).
	local function MeshVolume( Phys )

		local Total = 0

		for _, Convex in ipairs( Phys:GetMeshConvexes() ) do
			for I = 1, #Convex, 3 do
				local A = Convex[I].pos
				local B = Convex[I + 1].pos
				local C = Convex[I + 2].pos
				Total = Total + A:Dot(B:Cross(C))
			end
		end

		return math.abs(Total) / 6
	end

	-- Brick volume in liters, cached on the entity. ace_scalability rescales
	-- clear the cache (see ace_era / ace_scalability ACE_SetScale).
	function ERA.GetBrickVolume( Entity )

		if Entity.ACE_ERAVolume then return Entity.ACE_ERAVolume end

		local Phys = Entity:GetPhysicsObject()
		if not IsValid(Phys) then return 0 end

		local Vol = Phys.GetVolume and Phys:GetVolume() or nil

		if not Vol or Vol <= 0 then
			Vol = MeshVolume(Phys)
		end

		local Liters = (Vol or 0) * 16.387064 / 1000 -- source units (in^3) -> liters

		Entity.ACE_ERAVolume = Liters

		return Liters
	end

	--- Brick geometry for the reactive model, in millimetres.
	-- Returns the plate length (the face the rod sweeps across) and the travel
	-- depth (brick thickness along the forward normal = how far the plates fly and
	-- how much filler it holds). Derived from collision bounds, so it works for the
	-- scalable box and for legacy props alike (source units are inches).
	-- @param Entity The ERA brick / prop.
	-- @return number plateLenMM Geometric mean of the reactive face, in mm.
	-- @return number travelMM Brick depth along the forward axis, in mm.
	function ERA.GetBrickGeometry( Entity )
		local size = Entity:OBBMaxs() - Entity:OBBMins()
		local axis = Entity.ERAForwardAxis

		local fwd, a, b
		if axis == "Forward" or axis == "Back" then
			fwd, a, b = size.x, size.y, size.z
		elseif axis == "Right" or axis == "Left" then
			fwd, a, b = size.y, size.x, size.z
		else -- Up / Down / default
			fwd, a, b = size.z, size.x, size.y
		end

		local MM = 25.4 -- inches -> mm
		return math.sqrt(math.max(a, 0) * math.max(b, 0)) * MM, math.max(fwd, 0) * MM
	end

	-- World-space forward (reactive face normal) for an entity. Resolved live from
	-- a stored local axis so it tracks the contraption's orientation. Set by the
	-- ace_era entity and by the armor tool when applying ERA to a prop.
	local AxisGetters = {
		Forward = function(e) return e:GetForward() end,
		Back    = function(e) return -e:GetForward() end,
		Right   = function(e) return e:GetRight() end,
		Left    = function(e) return -e:GetRight() end,
		Up      = function(e) return e:GetUp() end,
		Down    = function(e) return -e:GetUp() end,
	}
	ERA.AxisGetters = AxisGetters

	function ERA.GetForward( Entity )
		local getter = AxisGetters[Entity.ERAForwardAxis or ""]
		if getter then return getter(Entity) end

		local fwd = Entity.ACF and Entity.ACF.ERAForward
		if isvector(fwd) and fwd:LengthSqr() > 0 then return fwd end
		return Entity:GetForward()
	end

	--- Resolve a hit on an ERA brick: trigger, erode/deflect, or behave as inert
	-- casing. Shared by every generation (RegisterGeneration wires it as the
	-- material's ArmorResolution). Reads hit direction/speed/mass stashed on the
	-- entity by the ballistics path. Returns a HitRes table (Damage, Overkill,
	-- Loss, and optionally ERADeflect) like any other armor material.
	-- @param Gen Generation parameter table.
	-- @param Material The registered material table.
	-- @param Entity The brick / prop being hit.
	-- @param armor Flat armor at the hit, mm.
	-- @param losArmor Line-of-sight armor at the hit, mm.
	-- @param losArmorHealth LOS armor health term from ACF_CalcDamage.
	-- @param maxPenetration Penetration of the round at impact, mm.
	-- @param FrArea Frontal area term.
	-- @param caliber Round caliber, mm.
	-- @param damageMult Damage multiplier for the round type.
	-- @param Type Ammo type string.
	-- @return table HitRes
	function ERA.ArmorResolution( Gen, Material, Entity, armor, losArmor, losArmorHealth, maxPenetration, FrArea, caliber, damageMult, Type )

		local HitRes = {}

		local Health = Entity.ACF.Health / Entity.ACF.MaxHealth

		local isHEAT = ERA.HEATList[Type] or false
		local isHE   = ERA.HEList[Type] or false

		-- Fixed casing: ERA can never act as more base armor than its casing box.
		-- Clamp the flat armor and scale the LOS armor by the same ratio so the
		-- angle relationship is preserved (legacy props may set a thicker value).
		if armor > Gen.CasingMM then
			local ratio = Gen.CasingMM / armor
			armor    = Gen.CasingMM
			losArmor = losArmor * ratio
		end

		-- Hit geometry, from data stashed by the ballistics path (see sv_acfdamage).
		local hitDir   = Entity.ACF.ERAHitDir
		local hitSpeed = Entity.ACF.ERAHitSpeed
		local hitMass  = Entity.ACF.ERAHitProjMass
		local forward  = ERA.GetForward(Entity)

		-- Front-hemisphere gate: ERA only works on its forward face. A hit whose
		-- travel direction runs with the forward normal is coming from behind.
		local facing = 1 -- default: treat as frontal if we somehow lack direction
		local aoaDeg = 60 -- representative slope if direction unknown
		if isvector(hitDir) and hitDir:LengthSqr() > 0 then
			facing = -hitDir:Dot(forward)             -- >0 means hitting the front
			aoaDeg = math.deg(math.acos(math.Clamp(math.abs(facing), 0, 1)))
		end

		local FrontHit = facing > 0

		-- Did the brick trigger? A rear or side hit never triggers (inert casing
		-- only). HEAT jets nearly always do; kinetic rounds need enough caliber and
		-- penetration. HE blast triggers ONLY a sensitive generation (Gen 1) -- that
		-- is its historical weakness; insensitive Gen 2/3 cassettes ignore HE. A
		-- wrecked brick on the front can sympathetically cook off.
		local Triggered
		if not FrontHit then
			Triggered = false
		elseif isHE then
			Triggered = Gen.HESensitive or false
		elseif isHEAT then
			Triggered = maxPenetration >= Gen.MinTriggerPenHEAT
		else
			Triggered = caliber >= Gen.MinTriggerCaliber and maxPenetration >= Gen.MinTriggerPen
		end

		if FrontHit and Health < 0.15 then
			Triggered = true
		end

		local plateLen, travel = ERA.GetBrickGeometry(Entity)
		local DebugOwner = (CPPI and Entity:CPPIGetOwner()) or NULL

		if not Triggered and ERA.DebugEnabled() then
			ERA.DrawDebug(Entity, forward, hitDir, Type, FrontHit, false, 0, 0, aoaDeg)
			ERA.LogReaction(Gen, Type, FrontHit, false, maxPenetration, maxPenetration, 0, 0, caliber, aoaDeg, DebugOwner)
		end

		if Triggered then

			-- An HE-sensitive brick simply cooks off; an HE blast is not a coherent
			-- penetrator the plate can erode, so there is no meaningful cut here.
			local cut, deflect
			if isHE then
				cut, deflect = 0, 0
			else
				cut, deflect = ERA.ComputeCut(Gen, Type, maxPenetration, caliber, aoaDeg, Health, hitSpeed, hitMass, plateLen, travel)
			end

			if ERA.DebugEnabled() then
				ERA.DrawDebug(Entity, forward, hitDir, Type, FrontHit, true, cut, deflect, aoaDeg)
				ERA.LogReaction(Gen, Type, FrontHit, true, maxPenetration, math.max(maxPenetration * (1 - cut), 0.01), cut, deflect, caliber, aoaDeg, DebugOwner)
			end

			-- Tandem-resistant cassettes survive a tandem precursor and keep
			-- reacting (layered elements), at a fraction of their effect.
			local Survives = Gen.TandemResistant and ERA.TandemList[Type] and Health > 0.5

			if Survives then
				Entity.ACF.Health = Entity.ACF.Health * 0.35
				-- Shield the brick from its own blast: ACF_HEFind skips Exploding ents.
				Entity.Exploding = true
				timer.Simple(0.05, function()
					if IsValid(Entity) then Entity.Exploding = nil end
				end)
				HitRes.Damage = 0
			else
				-- Important to remove the ent before the explosions begin.
				Entity:Remove()
				HitRes.Damage = 9999999999999
			end

			HitRes.Overkill = math.max(maxPenetration * (1 - cut), 0.01) -- remaining penetration
			HitRes.Loss     = math.Clamp(cut, 0, 0.98)                   -- energy share eaten by the plate

			if deflect > 0 then
				HitRes.ERADeflect = deflect -- applied to Bullet.Flight in ACF_RoundImpact
			end

			ACE.ERABoomPerTick = ACE.ERABoomPerTick + 1

			if not timer.Exists("ACE_ERA_Reset") then
				timer.Create("ACE_ERA_Reset", 0.01, 1, function()
					ACE.ERABoomPerTick = 0
				end )
			end

			-- Only allow 3 bricks to really detonate per tick. The rest can kill
			-- themselves (existing chain explosion throttle).
			if ACE.ERABoomPerTick > 3 then return HitRes end

			-- Explosive filler scales with the brick's real volume, so scalable /
			-- odd-shaped bricks behave instead of using a thickness setting.
			local Liters   = ERA.GetBrickVolume(Entity)
			local HEWeight = math.Clamp(Liters * Gen.FillFraction * 1.6, 0.5, 100) -- kg PE, #nonukespls
			local Radius   = ACE_CalculateHERadius( HEWeight )
			local Owner    = (CPPI and Entity:CPPIGetOwner()) or NULL
			local EntPos   = Entity:GetPos()

			ACF_HE( EntPos , vector_up , HEWeight , HEWeight , Owner , Entity, Entity, 0.1 ) --ERABOOM

			-- Inefficient back-spall: shredded casing plus the chunk of the round the
			-- plate just defeated. These fragments are tumbling end-over-end (not
			-- nose-on), so they get a big blunt caliber and a deliberately tiny KE --
			-- they pepper exposed crew / optics at point blank but cannot defeat real
			-- armor. Sent down the round's own travel line (ACF_Spall scatters them).
			if ACF.Spalling then
				local SpallDir = (isvector(hitDir) and hitDir:LengthSqr() > 0) and hitDir or forward
				local FragKE   = math.Clamp(Liters * 150, 40, 1200) -- intentionally low
				ACF_Spall( EntPos, SpallDir, { Entity }, FragKE, 8, Gen.CasingMM, Owner, "RHA" )
			end

			--util.Effect not working during MP workaround. Waiting a while fixes the issue.
			timer.Simple(0.001, function()
				local Flash = EffectData()
					Flash:SetOrigin( EntPos )
					Flash:SetNormal( -vector_up )
					Flash:SetRadius( math.Round(math.max(Radius / 39.37 * 0.125, 1),2) )
				util.Effect( "ACF_Scaled_Explosion", Flash )
			end)

			return HitRes
		else

			-- Brick did not trigger (HE, rear/side hit, or under-threshold): it
			-- behaves like RHA at a fraction of its casing thickness.
			local curve         = Material.NCurve
			local effectiveness = Material.Neffectiveness
			local resiliance    = Material.Nresiliance

			armor    = armor ^ curve
			losArmor = losArmor ^ curve

			-- Breach probability
			local breachProb = math.Clamp((caliber / armor / effectiveness - 1.3) / (7 - 1.3), 0, 1)

			-- Penetration probability
			local penProb = (math.Clamp(1 / (1 + math.exp(-43.9445 * (maxPenetration / losArmor / effectiveness - 1))), 0.0015, 0.9985) - 0.0015) / 0.997;

			-- Breach chance roll
			if breachProb > math.random() and maxPenetration > armor then

				HitRes.Damage   = FrArea * resiliance * damageMult -- Inflicted Damage
				HitRes.Overkill = maxPenetration - armor           -- Remaining penetration
				HitRes.Loss     = armor / maxPenetration           -- Energy loss in percents

				return HitRes

			-- Penetration chance roll
			elseif penProb > math.random() then

				local Penetration = math.min( maxPenetration, losArmor * effectiveness)

				HitRes.Damage   = ( ( Penetration / losArmorHealth / effectiveness ) ^ 2 * FrArea * resiliance * damageMult )
				HitRes.Overkill = ( maxPenetration - Penetration )
				HitRes.Loss     = Penetration / maxPenetration

				return HitRes

			end

			-- Projectile did not breach nor penetrate armor
			local Penetration = math.min( maxPenetration , losArmor * effectiveness )

			HitRes.Damage   = ( Penetration / losArmorHealth / effectiveness ) * FrArea * resiliance * damageMult
			HitRes.Overkill = 0
			HitRes.Loss     = 1

			return HitRes

		end

	end

end

ERA.Generations = ERA.Generations or {}

--- Build and register an armor material (and spawn-menu entry) from a generation
-- parameter table. Keeps every field the rest of ACE expects on a material (armor
-- tool, point costs, E2/Starfall getters) so a generation behaves like any other
-- armor type outside of its reactive behavior.
-- @param Gen Generation parameter table (id, sname, name, desc, CasingMM,
--   FlyerPlateMM, PlateVel, trigger thresholds, efficiencies, etc.).
-- @return table The registered material table.
function ERA.RegisterGeneration( Gen )

	local Material = {}

	Material.id    = Gen.id
	Material.name  = Gen.name
	Material.sname = Gen.sname
	Material.desc  = Gen.desc
	Material.year  = Gen.year

	Material.massMod = Gen.massMod
	Material.curve   = Gen.curve or 0.95

	--All effectiveness values multiply the Line of Sight armor values of armor.
	--All Resiliance values are damage multipliers. Higher = more damage. Lower = less damage.
	Material.effectiveness     = Gen.effectiveness
	Material.HEATeffectiveness = Gen.HEATeffectiveness

	Material.resiliance     = 1
	Material.HEATresiliance = 1

	-- Used when ERA fails to detonate. Acts like RHA at 25% of casing thickness. Used by HE.
	Material.NCurve         = 1
	Material.Neffectiveness  = 0.25
	Material.Nresiliance     = 1

	-- Kept for external readers (E2/Starfall); live trigger logic uses Gen.MinTrigger*.
	Material.APSensorFactor   = Gen.APSensorFactor or 4
	Material.HEATSensorFactor = Gen.HEATSensorFactor or 16

	Material.spallresist = 1
	Material.spallmult   = 0
	Material.ArmorMul    = 1
	Material.NormMult    = 1

	Material.Stopshock = true

	-- ERA-specific metadata, surfaced to the armor tool, menu and E2/SF getters.
	Material.IsERA          = true
	Material.ERAGeneration  = Gen.generation
	Material.CasingMM       = Gen.CasingMM
	Material.TandemResistant = Gen.TandemResistant or false

	if SERVER then

		Material.IsExplosive = true -- core reduces these explosions vs other explosive mats (anti chain-reaction).

		Material.HEATList = ERA.HEATList
		Material.HEList   = ERA.HEList

		function Material.ArmorResolution( Entity, armor, losArmor, losArmorHealth, maxPenetration, FrArea, caliber, damageMult, Type )
			return ERA.ArmorResolution( Gen, Material, Entity, armor, losArmor, losArmorHealth, maxPenetration, FrArea, caliber, damageMult, Type )
		end

	end

	ERA.Generations[Gen.id] = Gen
	ACE.ArmorTypes[Material.id] = Material

	-- Register a spawn-menu entry so the ace_era box can be built from the ACF
	-- menu (LeftClick resolves ACF.Weapons[type][id].ent). The generation id is
	-- the spawn id, so each generation is its own selectable entry.
	ACF.Weapons = ACF.Weapons or {}
	ACF.Weapons.Armor = ACF.Weapons.Armor or {}
	ACF.Weapons.Armor[Gen.id] = {
		ent   = "ace_era",
		type  = "Armor",
		id    = Gen.id,
		name  = Gen.name,
		desc  = Gen.desc,
		gen   = Gen.generation,
	}

	return Material
end

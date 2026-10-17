-- sv_engine_links.lua
-- Linking and unlinking: gearboxes, fuel tanks and batteries, radiators, heaters, crew seats, and the periodic link checks.
-- Included by init.lua; ENT is the acf_engine entity table.

local FuelLinkDistBase = 512

-------------------------- Periodic Link Engine checks --------------------------
do
	-- Checks the current ropes linked to this engine complies with the requirements to be valid.
	function ENT:CheckRopes()

		for _, Link in pairs( self.GearLink ) do

			local Ent = Link.Ent
			local OutPos = self:LocalToWorld( self.Out )
			local InPos = Ent:LocalToWorld( Ent.In )

			-- make sure it is not stretched too far
			if OutPos:Distance( InPos ) > Link.RopeLen * 1.5 then
				self:Unlink( Ent )
			end

			-- make sure the angle is not excessive
			if not self:Checkdriveshaft( Ent ) then
				self:Unlink( Ent )
				local soundstr =  "physics/metal/metal_box_impact_bullet" .. tostring(math.random(1, 3)) .. ".wav"
				self:EmitSound(soundstr,500,100)
			end
		end

	end

	-- Check fueltanks are within the range with the engine.
	function ENT:CheckFuel()
		for _,tank in pairs(self.FuelLink) do
			if self:GetPos():Distance(tank:GetPos()) > FuelLinkDistBase then
				self:Unlink( tank )
				local soundstr =  "physics/metal/metal_box_impact_bullet" .. tostring(math.random(1, 3)) .. ".wav"
				self:EmitSound(soundstr,500,100)
				self:UpdateOverlayText()
			end
		end

		self:TestDriverDistance()

	end


	--[[
	--HARDCODED. USE MODELDEFINITION INSTEAD
	local TransAxialGearboxes = {
		["models/engines/transaxial_l.mdl"] = true,
		["models/engines/transaxial_m.mdl"] = true,
		["models/engines/transaxial_s.mdl"] = true,
		["models/engines/transaxial_t.mdl"] = true --mhm acf extras invading...
	}
	]]

	-- make sure the angle is not excessive
	function ENT:Checkdriveshaft( NextEnt )
		local InPos = NextEnt:LocalToWorld( NextEnt.In ) 	--gearbox to connect to engine
		local OutPos = self:LocalToWorld( self.Out ) 		--the engine output

		local MaxAngle = 0.7 --magic number to define the max tolerance of link between gearboxes
		local Direction = self.IsTrans and -self:GetRight() or self:GetForward() --transaxial like turbines. Forward is for conventional engines like a V8
		local DrvAngle 	= ( OutPos - InPos ):GetNormalized():Dot( Direction )

		--Check if the link is right from engine's perspective
		if DrvAngle < MaxAngle then
			return false
		--else
			--[[ --Disabled since this could break several builds. When we have more junctions, this could be enforced.
			--Now, do the same, but from gearbox's perspective this time.
			Direction 	= TransAxialGearboxes[ NextEnt:GetModel() ] and -NextEnt:GetForward() or -NextEnt:GetRight()
			DrvAngle 	= ( InPos - OutPos ):GetNormalized():Dot( Direction )

			if DrvAngle < MaxAngle then
				return false
			end
			]]
		end

		return true
	end
end

-------------------------- Link Logic --------------------------
do

	local AllowedEnts = {
		acf_gearbox = true,
		acf_fueltank = true,
		ace_radiator = true,
		ace_engine_heater = true,
		ace_crewseat_driver = true,
	}

	function ENT:Link( Target )

		if not IsValid( Target ) or not AllowedEnts[Target:GetClass()] then
			print(Target:GetClass())
			return false, "You can only link gearboxes, fueltanks, radiators, heaters or crewseats!"
		end

		-- Gear links
		if Target:GetClass() == "acf_gearbox" then
			return self:LinkGearbox( Target )
		end
		-- Fuel links
		if Target:GetClass() == "acf_fueltank" then
			return self:LinkFuel( Target )
		end
		-- Radiator links
		if Target:GetClass() == "ace_radiator" then
			return self:LinkRadiator( Target )
		end
		-- Heater links
		if Target:GetClass() == "ace_engine_heater" then
			return self:LinkHeater( Target )
		end
		-- Crew links
		if Target:GetClass() == "ace_crewseat_driver" then
			return self:LinkCrew( Target )
		end
	end

	function ENT:Unlink( Target )

		if not IsValid( Target ) or not AllowedEnts[Target:GetClass()] then
			return false, "You can only unlink gearboxes, fueltanks, radiators, heaters or crewseats!"
		end

		-- Gear links
		if Target:GetClass() == "acf_gearbox" then
			return self:UnlinkGearbox( Target )
		end
		-- Fuel links
		if Target:GetClass() == "acf_fueltank" then
			return self:UnlinkFuel( Target )
		end
		-- Radiator links
		if Target:GetClass() == "ace_radiator" then
			return self:UnlinkRadiator( Target )
		end
		-- Heater links
		if Target:GetClass() == "ace_engine_heater" then
			return self:UnlinkHeater( Target )
		end
		-- Crew links
		if Target:GetClass() == "ace_crewseat_driver" then
			return self:UnlinkCrew( Target )
		end
	end

	function ENT:LinkGearbox( Target )

		-- Check if target is already linked
		for _, Link in pairs( self.GearLink ) do
			if Link.Ent == Target then
				return false, "This gearbox is already linked to this engine!"
			end
		end

		-- make sure the angle is not excessive
		if not self:Checkdriveshaft( Target ) then
			return false, "Cannot link due to excessive driveshaft angle!"
		end

		local InPos = Target:LocalToWorld( Target.In ) 	--gearbox to connect to engine
		local OutPos = self:LocalToWorld( self.Out ) 	--the engine output

		local Rope = nil
		if self:CPPIGetOwner():GetInfoNum( "ace_mobility_rope_links", 1) == 1 then
			Rope = ACE.CreateLinkRope( OutPos, self, self.Out, Target, Target.In )
		end

		local Link = {
			Ent 	= Target, 						-- Linked Gearbox
			Rope 	= Rope, 						-- Rope
			RopeLen = ( OutPos - InPos ):Length(), 	-- The length between the Engine Point to the Gearbox Point
			ReqTq 	= 0 							-- Possibly the requested torque from the gearbox to the engine?
		}

		table.insert( self.GearLink, Link )
		table.insert( Target.Master, self )

		return true, "Link successful!"
	end

	function ENT:UnlinkGearbox( Target )

		for Key, Link in pairs( self.GearLink ) do

			if Link.Ent == Target then

				-- Remove any old physical ropes leftover from dupes
				for _, Rope in pairs( constraint.FindConstraints( Link.Ent, "Rope" ) ) do
					if Rope.Ent1 == self or Rope.Ent2 == self then
						Rope.Constraint:Remove()
					end
				end

				if IsValid( Link.Rope ) then
					Link.Rope:Remove()
				end

				table.remove( self.GearLink,Key )
				table.RemoveByValue( Target.Master, self )

				return true, "Unlink successful!"
			end
		end

		return false, "That gearbox is not linked to this engine!"
	end

	function ENT:LinkCrew( Target )

		if not Target.Legal then
			return false, "The driver seat is illegal!"
		end

		if self.HasDriver then
			return false, "The engine already has a driver!"
		end

		table.insert( self.CrewLink, Target )
		table.insert( Target.Master, self )

		Target.LinkedEngine = self
		self.LinkedDriver = Target
		self.HasDriver = true
		self.CanUseSeatDriver = false --Driver specified. Seat can no longer be used as driver.
		self:UpdateOverlayText()

		return true, "Link successful!"
	end

	function ENT:UnlinkCrew( Target )

		self.HasDriver = false
		self:UpdateOverlayText()

		for Key,Value in pairs(self.CrewLink) do
			if Value == Target then
				Target.LinkedEngine = nil
				table.remove(self.CrewLink,Key)
				return true, "Unlink successful!"
			end
		end
	end

	function ENT:LinkFuel( Target )

		-- A battery linked to a piston or rotary engine feeds its starter.
		if Target.FuelType == "Electric" and self.FuelType ~= "Electric" then
			return self:LinkStarterBattery( Target )
		end

		if not (self.FuelType == "Multifuel" and Target.FuelType ~= "Electric") and self.FuelType ~= Target.FuelType then
			return false, "Cannot link because fuel type is incompatible."
		end

		if Target.NoLinks then
			return false, "This fuel tank doesn\'t allow linking."
		end

		for _, Value in pairs(self.FuelLink) do
			if Value == Target then
				return false, "That fuel tank is already linked to this engine!"
			end
		end

		if self:GetPos():Distance( Target:GetPos() ) > FuelLinkDistBase then
			return false, "The fuel tank is too far away."
		end

		table.insert( self.FuelLink, Target )
		table.insert( Target.Master, self )
		self.NextFeedScan = 0

		return true, "Link successful!"
	end

	function ENT:UnlinkFuel( Target )

		for Key, Value in pairs( self.FuelLink ) do
			if Value == Target then
				table.remove( self.FuelLink, Key )
				self.NextFeedScan = 0
				return true, "Unlink successful!"
			end
		end

		if table.HasValue( self.BatteryLink, Target ) then
			table.RemoveByValue( self.BatteryLink, Target )
			table.RemoveByValue( Target.Master, self )
			self:UpdateOverlayText()
			return true, "Starter battery unlinked."
		end

		return false, "That fuel tank is not linked to this engine!"
	end

	--- Links a battery to feed this engine's starter motor. Piston and rotary engines only:
	-- turbines and electric motors start without one.
	-- @param Target acf_fueltank holding Electric fuel.
	-- @return boolean, string Success and message.
	function ENT:LinkStarterBattery( Target )
		if self.EngineType == "Turbine" or self.EngineType == "GroundTurbine" then
			return false, "Turbines start without a starter battery."
		end
		if Target.NoLinks then
			return false, "This battery doesn\'t allow linking."
		end
		if table.HasValue( self.BatteryLink, Target ) then
			return false, "That battery already feeds this engine's starter!"
		end
		if self:GetPos():Distance( Target:GetPos() ) > FuelLinkDistBase then
			return false, "The battery is too far away."
		end

		table.insert( self.BatteryLink, Target )
		table.insert( Target.Master, self )
		self:UpdateOverlayText()

		return true, "Battery linked to the starter."
	end
end

function ENT:LinkRadiator( Target )

	for _, Value in pairs(self.RadLink) do
		if Value == Target then
			return false, "That radiator is already linked to this engine!"
		end
	end

	if self:GetPos():Distance( Target:GetPos() ) > FuelLinkDistBase then
		return false, "The radiator is too far away."
	end

	table.insert( self.RadLink, Target )
	table.insert( Target.Master, self )

	return true, "Link successful!"
end

function ENT:UnlinkRadiator( Target )

	for Key, Value in pairs( self.RadLink ) do
		if Value == Target then
			table.remove( self.RadLink, Key )
			-- The radiator must forget this engine too, or it keeps sharing its cooling with it.
			table.RemoveByValue( Target.Master, self )
			if Target.Circuits then Target.Circuits[self] = nil end
			return true, "Unlink successful!"
		end
	end

	return false, "That radiator is not linked to this engine!"
end

--- Links a coolant heater (entities/ace_engine_heater) to this engine. A heater heats one
-- engine; electric motors and turbines take none.
-- @param Target Entity ace_engine_heater.
-- @return boolean Success.
-- @return string Message for the owner.
function ENT:LinkHeater( Target )
	if self.EngineType == "Electric" or self.EngineType == "Turbine" or self.EngineType == "GroundTurbine" then
		return false, "Only piston and rotary engines take a heater."
	end
	if table.HasValue( self.HeaterLink, Target ) then
		return false, "That heater is already linked to this engine!"
	end
	if IsValid( Target.Master[1] ) then
		return false, "That heater already heats another engine."
	end
	if self:GetPos():Distance( Target:GetPos() ) > FuelLinkDistBase then
		return false, "The heater is too far away."
	end

	table.insert( self.HeaterLink, Target )
	Target.Master = { self }

	return true, "Link successful!"
end

--- Unlinks a coolant heater from this engine.
-- @param Target Entity ace_engine_heater.
-- @return boolean Success.
-- @return string Message for the owner.
function ENT:UnlinkHeater( Target )
	if not table.HasValue( self.HeaterLink, Target ) then
		return false, "That heater is not linked to this engine!"
	end
	table.RemoveByValue( self.HeaterLink, Target )
	table.RemoveByValue( Target.Master, self )
	Target.HeatW, Target.HeatBlockW, Target.HeatOilW = 0, 0, 0
	return true, "Unlink successful!"
end

--- Recomputes this engine's link to a gearbox after either end's link points moved (an engine
-- or gearbox updated in place): length and rope.
-- @param Box Entity A linked acf_gearbox.
-- @return boolean False when the link is now at too steep an angle (the caller unlinks it).
function ENT:RefreshGearLink( Box )
	for _, Link in pairs( self.GearLink ) do
		if Link.Ent == Box and IsValid( Box ) then
			Link.RopeLen = ( self:LocalToWorld( self.Out ) - Box:LocalToWorld( Box.In ) ):Length()
			ACE.RedrawLinkRope( Link, self, self.Out, Box, Box.In )
			return self:Checkdriveshaft( Box )
		end
	end
	return true
end

--- Recomputes this engine's gearbox links after it was updated in place. Links now at too
-- steep an angle are unlinked, as the periodic check (ENT:CheckRopes) would.
-- @return number Links unlinked.
function ENT:RefreshLinks()
	local Broken = {}
	for _, Link in pairs( self.GearLink ) do
		if IsValid( Link.Ent ) and not self:RefreshGearLink( Link.Ent ) then
			Broken[#Broken + 1] = Link.Ent
		end
	end
	for _, Box in ipairs( Broken ) do
		self:Unlink( Box )
	end
	return #Broken
end

--- Links this engine's fuel tanks, batteries and heaters again under its current rules, after it
-- was updated to another engine: a battery feeds a motor or a piston engine's starter, a tank of
-- the wrong fuel or a heater on a motor is dropped.
-- @return table Names of what could not be linked again.
function ENT:RelinkSupplies()
	local Supplies, Heaters = {}, {}
	for _, Tank in pairs( self.FuelLink ) do Supplies[#Supplies + 1] = Tank end
	for _, Bat in pairs( self.BatteryLink ) do Supplies[#Supplies + 1] = Bat end
	for _, Heater in pairs( self.HeaterLink ) do Heaters[#Heaters + 1] = Heater end

	for _, Tank in ipairs( Supplies ) do
		if IsValid( Tank ) then
			table.RemoveByValue( self.FuelLink, Tank )
			table.RemoveByValue( self.BatteryLink, Tank )
			if Tank.Master then table.RemoveByValue( Tank.Master, self ) end
		end
	end
	for _, Heater in ipairs( Heaters ) do
		if IsValid( Heater ) then self:UnlinkHeater( Heater ) end
	end

	local Dropped = {}
	for _, Tank in ipairs( Supplies ) do
		if IsValid( Tank ) and not self:LinkFuel( Tank ) then
			Dropped[#Dropped + 1] = Tank.FuelType == "Electric" and "a battery" or "a " .. string.lower( Tank.FuelType or "fuel" ) .. " tank"
		end
	end
	for _, Heater in ipairs( Heaters ) do
		if IsValid( Heater ) and not self:LinkHeater( Heater ) then
			Dropped[#Dropped + 1] = "a heater"
		end
	end
	self.NextFeedScan = 0

	return Dropped
end

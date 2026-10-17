-- sv_engine_crew.lua
-- Driver seat lookup, driver distance and crew legality.
-- Included by init.lua; ENT is the acf_engine entity table.

function ENT:FindSeatForDriver()

	local MaxDist = 348749.3 --Max distance to link driver seats. (15 meters * 39.37)^2 = 348749.3
	local closestDist = math.huge
	local SeatEnt = nil

	local EngContraption = self:CFW_GetContraption()

	for _, ent in pairs( ACE.critEnts ) do


		local eclass = ent:GetClass()

		if eclass ~= "prop_vehicle_prisoner_pod" then continue end

		local epos = ent:GetPos()
		local spos = self:GetPos()
		local SqDist = spos:DistToSqr( epos )

		if SqDist > MaxDist then continue end --Outside link range. Continue.

		if EngContraption ~= ent:CFW_GetContraption() then continue end --Seatent isn't on the same contraption as the engine. Ignore it.

		if SqDist < closestDist then
			SeatEnt = ent
			closestDist = SqDist
		end
	end

	if SeatEnt then
		self.HasSeatDriver = true
		self.LinkedDriver = SeatEnt
	end

end

function ENT:TestDriverDistance()

	if not IsValid(self.LinkedDriver) then
		--print("DRIVER ENT NOT VALID")
		self.HasSeatDriver = false
		self.HasDriver = false
		self.LinkedDriver = nil
		return
	end

	local epos = self.LinkedDriver:GetPos()
	local spos = self:GetPos()
	local SqDist = spos:DistToSqr( epos )

	local MaxDist = 348749.3 --Max distance to link driver seats. (15 meters * 39.37)^2 = 348749.3
	if SqDist > MaxDist then

		--local sqrtMaxDist = math.sqrt(MaxDist)
		--local sqrtDist = math.sqrt(SqDist)
		--print("Unlinked due to exceeding maxdist")
		--print("SquaredDist: " .. SqDist)
		--print("Dist: " .. sqrtDist)
		--print("MaxDistance: " .. sqrtMaxDist)
		--print("Exceeded by: " .. (sqrtDist-sqrtMaxDist))
		--print(self.LinkedDriver)


		self.HasDriver = false
		self.HasSeatDriver = false
		self.LinkedDriver = nil
		local soundstr =  "physics/metal/metal_box_impact_bullet" .. tostring(math.random(1, 3)) .. ".wav"
		self:EmitSound(soundstr,500,100)
	end


end

function ENT:IllegalCrewSeatRemove(crewEntities)
	for _, crewEnt in ipairs(crewEntities) do
		if not crewEnt.Legal then
			self:Unlink(crewEnt)
		end
	end
end

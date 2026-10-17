-- sv_engine_dupe.lua
-- Duplicator support: what is saved on copy and restored on paste.
-- Included by init.lua; ENT is the acf_engine entity table.

-------------------------- Duplicator related stuff --------------------------
do
	function ENT:PreEntityCopy()

		--Link Saving
		local info = {}
		local entids = {}
		for Key, Link in pairs( self.GearLink ) do				--First clean the table of any invalid entities
			if not IsValid( Link.Ent ) then
				table.remove( self.GearLink, Key )
			end
		end
		for _, Link in pairs( self.GearLink ) do				--Then save it
			table.insert( entids, Link.Ent:EntIndex() )
		end

		info.entities = entids
		if info.entities then
			duplicator.StoreEntityModifier( self, "GearLink", info )
		end

		--fuel tank link saving
		local fuel_info = {}
		local fuel_entids = {}
		for _, Value in pairs(self.FuelLink) do				--First clean the table of any invalid entities
			if not Value:IsValid() then
				table.remove(self.FuelLink, Value)
			end
		end
		for _, Value in pairs(self.FuelLink) do				--Then save it
			table.insert(fuel_entids, Value:EntIndex())
		end
		-- Starter batteries are saved with the fuel tanks; pasting relinks them through
		-- ENT:LinkFuel, which sends batteries to the starter.
		for _, Value in ipairs(self.BatteryLink) do
			if IsValid(Value) then table.insert(fuel_entids, Value:EntIndex()) end
		end

		fuel_info.entities = fuel_entids
		if fuel_info.entities then
			duplicator.StoreEntityModifier( self, "FuelLink", fuel_info )
		end

		--fuel tank link saving
		local rad_info = {}
		local rad_entids = {}
		for _, Value in pairs(self.RadLink) do				--First clean the table of any invalid entities
			if not Value:IsValid() then
				table.remove(self.RadLink, Value)
			end
		end
		for _, Value in pairs(self.RadLink) do				--Then save it
			table.insert(rad_entids, Value:EntIndex())
		end

		rad_info.entities = rad_entids
		if rad_info.entities then
			duplicator.StoreEntityModifier( self, "RadLink", rad_info )
		end

		-- Heater link saving
		local HeaterIds = {}
		for _, Heater in ipairs( self.HeaterLink ) do
			if IsValid( Heater ) then table.insert( HeaterIds, Heater:EntIndex() ) end
		end
		if next( HeaterIds ) then
			duplicator.StoreEntityModifier( self, "HeaterLink", { entities = HeaterIds } )
		else
			duplicator.ClearEntityModifier( self, "HeaterLink" )
		end

		--driver seat link saving
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
			duplicator.StoreEntityModifier( self, "CrewLink", info )
		end

		--Wire dupe info
		self.BaseClass.PreEntityCopy( self )

	end

	function ENT:PostEntityPaste( Player, Ent, CreatedEntities )

		--Link Pasting
		if Ent.EntityMods and Ent.EntityMods.GearLink and Ent.EntityMods.GearLink.entities then
			local GearLink = Ent.EntityMods.GearLink
			if GearLink.entities and next(GearLink.entities) then
				timer.Simple( 0, function() -- this timer is a workaround for an ad2/makespherical issue https://github.com/nrlulz/ACF/issues/14#issuecomment-22844064
					for _,ID in pairs(GearLink.entities) do
						local Linked = CreatedEntities[ ID ]
						if IsValid( Linked ) then
							self:Link( Linked )
						end
					end
				end )
			end
			Ent.EntityMods.GearLink = nil
		end
		--fuel tank link Pasting
		if Ent.EntityMods and Ent.EntityMods.FuelLink and Ent.EntityMods.FuelLink.entities then
			local FuelLink = Ent.EntityMods.FuelLink
			if FuelLink.entities and next(FuelLink.entities) then
				for _,ID in pairs(FuelLink.entities) do
					local Linked = CreatedEntities[ ID ]
					if IsValid( Linked ) then
						self:Link( Linked )
					end
				end
			end
			Ent.EntityMods.FuelLink = nil
		end
		--radiator link Pasting
		if Ent.EntityMods and Ent.EntityMods.RadLink and Ent.EntityMods.RadLink.entities then
			local RadLink = Ent.EntityMods.RadLink
			if RadLink.entities and next(RadLink.entities) then
				for _,ID in pairs(RadLink.entities) do
					local Linked = CreatedEntities[ ID ]
					if IsValid( Linked ) then
						self:Link( Linked )
					end
				end
			end
			Ent.EntityMods.RadLink = nil
		end
		-- Heater link pasting
		local HeaterMod = Ent.EntityMods and Ent.EntityMods.HeaterLink
		if HeaterMod and istable( HeaterMod.entities ) then
			for _, ID in pairs( HeaterMod.entities ) do
				local Linked = CreatedEntities[ ID ]
				if IsValid( Linked ) and Linked:GetClass() == "ace_engine_heater" then
					self:Link( Linked )
				end
			end
			Ent.EntityMods.HeaterLink = nil
		end
		--ace_crewseat_gunner
		if Ent.EntityMods and Ent.EntityMods.CrewLink and Ent.EntityMods.CrewLink.entities then
			local CrewLink = Ent.EntityMods.CrewLink
			if CrewLink.entities and next(CrewLink.entities) then
				for _,ID in pairs(CrewLink.entities) do
					local Linked = CreatedEntities[ ID ]
					if IsValid( Linked ) then
						self:Link( Linked )
					end
				end
			end
			Ent.EntityMods.CrewLink = nil
		end
		--Wire dupe info
		self.BaseClass.PostEntityPaste( self, Player, Ent, CreatedEntities )
	end
end

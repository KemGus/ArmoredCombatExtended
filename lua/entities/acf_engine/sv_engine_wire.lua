-- sv_engine_wire.lua
-- What the engine shows and takes from outside: overlay text, wire inputs and the menu settings.
-- Included by init.lua; ENT is the acf_engine entity table.

function ENT:UpdateOverlayText()

	local pbmin = self.PeakMinRPM
	local pbmax = self.PeakMaxRPM

	local DriverBoost = self.HasDriver and ACE.DriverTorqueBoost or 1

	local PowerKW = math.Round( self.peakkw * DriverBoost )
	local PowerHP = math.Round( self.peakkw * DriverBoost * 1.34 )
	local TorqueNm = math.Round( self.BaseTorque * DriverBoost )
	local TorqueFtLb = math.Round( self.BaseTorque * DriverBoost * 0.73 )

	local text = "Power: " .. PowerKW .. " kW / " .. PowerHP .. " hp at " .. math.Round(self.PeakKwRPM) .. " RPM\n"
	text = text .. "Torque: " .. TorqueNm .. " Nm / " .. TorqueFtLb .. " ft-lb at " .. math.Round(self.PeakTqRPM) .. " RPM\n"
	text = text .. "Powerband: " .. (math.Round(pbmin / 10) * 10) .. " - " .. (math.Round(pbmax / 10) * 10) .. " RPM\n"
	text = text .. "Redline: " .. self.LimitRPM .. " RPM\n\n"
	-- The three parts the cooling model tracks (ACE.EngineThermalThink).
	local function temp(C) return math.Round(C) .. " °C / " .. math.Round(C * (9 / 5) + 32) .. " °F" end
	if self.AirCooled then
		-- Finned cylinders: no coolant, the oil is the only liquid.
		text = text .. "Air-cooled\n"
		text = text .. "Cylinder heads: " .. temp(self.BlockHeat or self.Heat) .. "\n"
		text = text .. "Oil: " .. temp(self.Heat) .. "\n"
		text = text .. "Air through the fins: " .. math.Round((self.FinAirSpeed or 0) * 3.6) .. " km/h\n"
	else
		text = text .. "Coolant: " .. temp(self.Heat) .. "\n"
		if self.OilHeat then
			text = text .. "Oil: " .. temp(self.OilHeat) .. "\n"
		end
		text = text .. "Block: " .. temp(self.BlockHeat or self.Heat) .. "\n"
	end
	if self.BuiltinCoreFrontM2 then
		text = text .. "Built-in radiator: " .. math.Round(self.BuiltinCoreFrontM2, 2) .. " m^2 face, " .. math.Round(self.BuiltinCoreDepthM * 100) .. " cm deep\n"
	end
	if self.ReverseInput and self.FuelType == "Electric" then
		text = text .. "Direction: reverse\n"
	end
	if self.CoolantBoiling then
		text = text .. "Coolant boiling - block at " .. math.Round(self.BlockHeat or self.Heat) .. " °C\n"
	end
	if self.OilOverheating and self.OilHeat then
		text = text .. "Oil overheating - " .. math.Round(self.OilHeat) .. " °C\n"
	end

	--if self.FuelLink and #self.FuelLink > 0 then
	if self.HasFuel then
		text = text .. "\nSupplied with " .. (self.EngineType == "Electric" and "Batteries" or "Fuel")
	end
	-- Starter: which battery feeds it, and why it is not cranking when it is not.
	if next(self.BatteryLink or {}) then
		text = text .. "\nStarter: linked battery"
	elseif self.StarterPack then
		text = text .. "\nStarter battery: " .. math.Round(ACE.Mobility.Battery.StarterPackSOC(self.StarterPack) * 100) .. "%"
	end
	if self.StarterWasCut then
		text = text .. "\nStarter overheated - cooling down"
	elseif self.StarterWasFlat then
		text = text .. "\nStarter battery flat"
	elseif self.StarterWasPreheating then
		text = text .. "\nPreheating (glow plugs)"
	end

	if self.HasDriver then
		text = text .. "\nDriver Provided (" .. (ACE.DriverTorqueBoost * 100 - 100) .. "% boost)"
	end

	if not self.Legal then
		text = text .. "\nNot legal, disabled for " .. math.ceil(self.NextLegalCheck - ACE.CurTime) .. "s\nIssues: " .. self.LegalIssues
	end

	self:SetOverlayText( text )

end

function ENT:TriggerInput( iname, value )

	if iname == "Exhaust" then
		ACE.EngineSound.SetExhaust( self, value )
		return
	end

	if iname == "Reverse" then
		-- Selects the direction the motor controller drives in; ENT:MobilityDesc hands it to the
		-- motor model, which brakes a motor still turning the old way before driving it.
		self.ReverseInput = value ~= 0
		self:UpdateOverlayText()
		return
	end

	if (iname == "Throttle") then
		self.Throttle = math.Clamp(value,0,100) / 100
		-- Electric motors take -100..0 as a regenerative braking command.
		self.RegenCommand = math.Clamp(-value, 0, 100) / 100
	elseif (iname == "Active") then
		if (value > 0 and not self.Active and self.Legal) then
			--make sure we have fuel
			local HasFuel
			local HasDriver

			for _,fueltank in pairs(self.FuelLink) do
				if fueltank.Fuel > 0 and fueltank.Active and fueltank.Legal then HasFuel = true break end
			end

			self.HasFuel = HasFuel == true
			if not self.RequiresDriver then
				HasDriver = true
			else
				if self.HasDriver or self.HasSeatDriver then
					HasDriver = true
				elseif self.CanUseSeatDriver then
					self:FindSeatForDriver()
					if IsValid(self.LinkedDriver) then
						HasDriver = true
					end
				end
			end
			--RequiresDriver
			if (HasFuel or ACE.EnginesRequireFuel == 0) and HasDriver then
				self.Active = true
				ACE.EngineSound.Start( self )
				self:ACFInit()
			else

				if not HasFuel then
					local HasWarned = self.OTWarnings.WarnedFuel or false
					--self.OTWarnings
					if not HasWarned then
						ACE.SendEngineHint( self:CPPIGetOwner() , "[ACE] Your engine requires fuel to work and that it be activated BEFORE the engine.", Color( 255, 0, 0 ))
						self.OTWarnings.WarnedFuel = true
					end
				end

				if not HasDriver then
					local HasWarned = self.OTWarnings.WarnedDriver or false
					--self.OTWarnings
					if not HasWarned then
						ACE.SendEngineHint( self:CPPIGetOwner() , "[ACE] Your engine is above [" .. ACE.LargeEngineThreshold .. " hp] requiring a driver to work.", Color( 255, 0, 0 ))
						self.OTWarnings.WarnedDriver = true
					end
				end

			end
			ACE.DoContraptionLegalCheck(self)
		elseif (value <= 0 and self.Active) then
			self.Active = false
			if self.MobState then ACE.Mobility.Engine.Stop(self.MobState) end
			ACE.EngineSound.Stop( self )
			Wire_TriggerOutput( self, "Torque", 0 )
			Wire_TriggerOutput( self, "Power", 0 )
			Wire_TriggerOutput( self, "Fuel Use", 0 )
		end
	end
end

--- This engine's settings as the ACE menu takes them (ACE.CopyToMenu).
-- @return table Id and Starter (the starter and cooling setup).
function ENT:GetMenuSettings()
	return {
		Id = self.Id,
		Starter = table.Copy( self.StarterSetup or {} ),
	}
end

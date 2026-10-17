-- sv_engine_think.lua
-- The engine's per-tick work: Think, mass ratio, and the drivetrain description and read-back.
-- Included by init.lua; ENT is the acf_engine entity table.

local FeedFlush = 0.1 -- s; how often the fuel burned is taken from the tanks (ENT:FlushFeed)

function ENT:Think()

	if ACE.HasDefaultActiveInputState(self) and not ACE.IsDefaultActiveInputWired(self) then
		local active = ACE.GetDefaultActiveInputState(self)

		if self.Active ~= active then
			self:TriggerInput("Active", active and 1 or 0)
		end
	end

	if ACE.CurTime > self.NextLegalCheck then
		self.Legal, self.LegalIssues = ACE.CheckLegal(self, self.Model, math.Round(self.Weight,2), self.ModelInertia, true, true)
		self.NextLegalCheck = ACE.Legal.NextCheck(self.legal)
		self:CheckRopes()
		self:CheckFuel()
		self:CalcMassRatio()

		self:UpdateOverlayText()
		self.NextUpdate = ACE.CurTime + 1

		self:IllegalCrewSeatRemove(self.CrewLink)

		if not self.Legal and self.Active then
			self:TriggerInput("Active",0) -- disable if not legal and active
			self.LockOnActive = true
		else
			-- Restore the requested state after a legality lockdown.
			if self.LockOnActive then
				self.LockOnActive = false
				self:TriggerInput("Active", ACE.GetDefaultActiveInputState(self) and 1 or 0)
			end
		end
	end

	-- when not legal, update overlay displaying lockout and issues
	if not self.Legal and ACE.CurTime > self.NextUpdate then
		self:UpdateOverlayText()
		self.NextUpdate = ACE.CurTime + 1
	end

	Wire_TriggerOutput(self, "EngineHeat", self.Heat)
	Wire_TriggerOutput(self, "Oil Temp", self.OilHeat or 0)
	Wire_TriggerOutput(self, "Block Temp", self.BlockHeat or self.Heat)

	if ACE.CurTime >= (self.NextFeedFlush or 0) then
		self:FlushFeed(ACE.CurTime - (self.LastFeedFlush or ACE.CurTime))
		self.LastFeedFlush = ACE.CurTime
		self.NextFeedFlush = ACE.CurTime + FeedFlush
	end

	if ACE.CurTime > self.NextUpdate then

		self.TotalFuel = self:GetMaxFuel()
		self.HasFuel = self.TotalFuel > 0
		Wire_TriggerOutput(self, "Total Fuel", self.TotalFuel)

		self:UpdateOverlayText()
		self.NextUpdate = ACE.CurTime + 0.5
	end

	if self.Active then
		self:CalcRPM()
	end

	-- The drivetrain keeps running with the engine off so brakes, engine braking and a stopped
	-- engine holding the car in gear all still work.
	if next(self.GearLink) then
		self.MobDt = math.Clamp(CurTime() - self.LastThink, engine.TickInterval() * 0.5, 0.1)
		ACE.Mobility.Tick(self, self.MobDt)
	elseif self.MobCtrlStarted then
		-- Unlinked: stop driving the wheels it used to.
		ACE.Mobility.StopController(self)
	end

	-- Cooling runs whether or not the engine is on: a stopped engine still cools down.
	ACE.EngineThermalThink(self)

	self.LastThink = ACE.CurTime
	self:NextThink( ACE.CurTime )
	return true

end

-- specialized calcmassratio for engines
function ENT:CalcMassRatio()

	local Mass = 0
	local PhysMass = 0
	local Check = nil

	-- get the shit that is physically attached to the vehicle
	local PhysEnts = ACE.GetAllPhysicalConstraints( self )

	-- get the wheels directly connected to the drivetrain
	local Wheels = ACE.GetLinkedWheels(self)

	-- check if any wheels aren't in the physicalconstraint tree
	for _,Ent in pairs( Wheels ) do
		if not PhysEnts[Ent] then -- WE GOT EM BOIS
			Check = Ent
			Wheels[Ent] = nil -- manual removal, idk how table.remove would handle indexing by ent. probably not well. indexing by entity sucks, please use ent id.
			break
		end
	end

	-- if there's a wheel that's not in the engine constraint tree, use it as a start for getting physical constraints
	if IsValid(Check) then -- sneaky bastards trying to get away with remote engines...  NOT ANYMORE
		table.Merge(PhysEnts, Wheels) -- I mean, they'll still be remote... but they wont get free extra power from calcmass not seeing the contraption it's powering
		ACE.GetAllPhysicalConstraints( Check, PhysEnts ) -- no need for assignment here
	end

	-- add any parented but not constrained props you sneaky bastards
	local AllEnts = table.Copy( PhysEnts )
	for _, v in pairs( PhysEnts ) do
		table.Merge( AllEnts, ACE.GetAllChildren( v ) )
	end

	for _, v in pairs( AllEnts ) do

		if not IsValid( v ) then continue end

		local phys = v:GetPhysicsObject()
		if not IsValid( phys ) then continue end

		Mass = Mass + phys:GetMass()

		if PhysEnts[ v ] then
			PhysMass = PhysMass + phys:GetMass()
		end

	end

	--phys / parented
	--total: 6000 kgs
	--5000/1000 = 5 ratio
	--1000/5000 = 0.2 ratio
	--local Tmass = PhysMass + Mass

	self.MassRatio = PhysMass / Mass
	self.PhysMass = PhysMass
	self.TotalMass = Mass
	--self.MassRatio = 1 / (Tmass/10000)
	--self.MassRatio = (PhysMass ^ 0.9225) / Mass

	Wire_TriggerOutput( self, "Mass", math.Round( Mass, 2 ) )
	Wire_TriggerOutput( self, "Physical Mass", math.Round( PhysMass, 2 ) )

end

-- Builds this engine's part of the drivetrain description. Called by ACE.Mobility.Tick.
function ENT:MobilityDesc(Ctx)
	local Tank = self.Active and self.MobTank or nil
	local Spec = ACE.Mobility.EngineSpec(self, IsValid(Tank) and Tank.FuelType or nil)

	local Gearboxes = {}
	local Assisted = false
	for _, Link in pairs(self.GearLink) do
		local Box = Link.Ent
		if IsValid(Box) and Box.Legal then
			Gearboxes[#Gearboxes + 1] = ACE.Mobility.GearboxDesc(Box, Ctx)
			Assisted = Assisted or ACE.Mobility.IsAssisted(Box)
		end
	end

	local Running = self.Active and self.Legal

	local Desc = self.MobDesc or {}
	self.MobDesc = Desc
	Desc.Spec, Desc.State = Spec, self.MobState
	Desc.Throttle = Running and self.Throttle or 0
	if self.FuelType == "Electric" and (self.RegenCommand or 0) > 0 then
		Desc.Throttle = Running and -self.RegenCommand or 0
	end
	Desc.HasFuel = Running and (IsValid(Tank) or ACE.EnginesRequireFuel == 0)
	Desc.NoStall = Assisted
	-- Damage and the driver boost. Parented mass is handled at the road by ACE.Mobility.Tick.
	Desc.TorqueMul = self.PeakTorque / self.BaseTorque
	Desc.Gearboxes = Gearboxes
	if self.FuelType == "Electric" and self.MobState then
		-- Regenerative braking needs somewhere to put the charge, and a battery only takes as
		-- much as its CC-CV charge acceptance allows: nothing once every linked battery is full.
		if not self.ChargeFeed then self:ScanFeed() end
		self.MobState.RegenLimitW = self.ChargeAcceptSum or 0
		self.MobState.Direction = self.ReverseInput and -1 or 1
	end
	-- Belt-driven accessories such as a radiator fan.
	-- Radiators add their fan load between Thinks; MobilityApply holds it for every physics step
	-- until the next.
	Desc.AccessoryTorque = self.MobAccessory or self.AccessoryTorque or 0
	if self.MobState and Spec.Kind ~= "electric" and Spec.Kind ~= "turbine" then
		-- The starter setup, the temperatures a start depends on, what the starter motor runs on
		-- this tick (engine_model.lua, starter) and the alternator recharging its battery.
		self:StarterModelInputs(Spec, self.MobState)
		self.MobState.StarterSupply = self:StarterSupply(Spec)
		Desc.AccessoryTorque = Desc.AccessoryTorque + self:AlternatorTorque(Spec, self.MobState)
	end
	return Desc
end

-- The in-step drivetrain: the physics engine calls this inside every step for the wheels this
-- engine's motion controller holds (see ACE.Mobility.PhysicsStep).
function ENT:PhysicsSimulate(Phys, Dt)
	ACE.Mobility.PhysicsStep(self, Phys, Dt)
	return vector_origin, vector_origin, SIM_NOTHING
end

-- Reads back the solve: fuel burned, heat made, RPM and torque outputs, and stalls.
function ENT:MobilityApply()
	local Desc = self.MobDesc
	local State = self.MobState
	if not Desc or not State then return end
	self.MobAccessory = self.AccessoryTorque or 0
	self.AccessoryTorque = 0

	local RPM = State.W * 30 / math.pi
	-- Only electric motors turn backwards; RPM and sound follow the speed either way.
	self.FlyRPM = self.FuelType == "Electric" and math.abs(RPM) or math.max(RPM, 0)
	self.Torque = Desc.AvgTorque or 0

	local Dt = self.MobDt or engine.TickInterval()
	local Tank = self.MobTank
	local FuelKg = Desc.FuelKg or 0
	if self.Active and IsValid(Tank) and FuelKg > 0 then
		local Used
		if self.FuelType == "Electric" then
			Used = FuelKg / 3.6e6 -- electric "fuel" is energy: J to kWh
		else
			Used = FuelKg / (ACE.FuelDensity[Tank.FuelType] or 0.745) -- kg to litres
		end
		self:DrawFuel(Used)
		Wire_TriggerOutput(self, "Fuel Use", math.Round(60 * Used / Dt, 3))
	elseif self.Active and FuelKg < 0 and self.FuelType == "Electric" then
		-- Regenerative braking: the motor returned energy, which charges a battery with room.
		local Charged = -FuelKg / 3.6e6
		self:ChargeFuel(Charged)
		Wire_TriggerOutput(self, "Fuel Use", -math.Round(60 * Charged / Dt, 3))
	else
		-- Drawing nothing (a motor at rest, or no tank): without this the last value stayed up.
		Wire_TriggerOutput(self, "Fuel Use", 0)
	end
	if self.FuelType ~= "Electric" then self:StarterApply(State, Dt) end

	if (Desc.HeatJ or 0) > 0 then
		self.HeatGeneration = Desc.HeatJ / 1000 / Dt -- kJ/s, shown in the menu
		ACE.EngineThermalInput(self, Desc)
	end

	-- Over-revving: the limiter only cuts fuel, so a missed downshift can still drag the engine
	-- far past redline through the wheels. Past ~110% valves float and hit pistons.
	local Over = self.FlyRPM / self.LimitRPM - 1.1
	if Over > 0 and self.ACE and self.ACE.Health then
		self.ACE.Health = math.max(self.ACE.Health - self.ACE.MaxHealth * Over * Dt, 0)
		if self.ACE.Health <= 0 and self.Active then self:TriggerInput("Active", 0) end
	end

	if self.Active and State.Stalled then
		State.Stalled = false
		self.Active = false
		self.Stalled = true
		Wire_TriggerOutput(self, "Stalled", 1)
		ACE.EngineSound.Stop( self )
	end

	-- Signed: a motor driving backwards has negative torque and speed, positive power.
	local Power = self.Torque * (self.FuelType == "Electric" and RPM or self.FlyRPM) / 9548.8
	Wire_TriggerOutput(self, "Torque", math.Round(self.Torque))
	Wire_TriggerOutput(self, "Power", math.Round(Power))
	Wire_TriggerOutput(self, "RPM", math.Round(self.FlyRPM))

	-- Also called while off: the sound follows the crank as it spins down, and the starter is heard.
	ACE.EngineSound.Update( self, self.FlyRPM, self.Active and self.Throttle or 0 )
end

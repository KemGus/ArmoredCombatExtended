-- sv_engine_fuel.lua
-- Fuel feed (tank scan, burn, charge) and the per-tick RPM step that draws on it.
-- Included by init.lua; ENT is the acf_engine entity table.

local FeedRescan = 0.5 -- s; how often the fuel feed's tanks and shares are rebuilt (ENT:ScanFeed)

function ENT:GetMaxFuel()
	local TFuel = 0

	for _, Tank in pairs(self.FuelLink) do
		if not IsValid(Tank) then continue end
		if not Tank.Active then continue end

		TFuel = TFuel + Tank.Fuel
	end

	return TFuel
end

-- Checks if the fuel tank is valid, has fuel, is active and was not marked as illegal.
local function IsValidfueltank( Tank )
	return IsValid(Tank) and Tank.Fuel > 0 and Tank.Active and Tank.Legal
end

--[[
	Fuel feed. All linked tanks feed the engine together, as a crossfeed system does: liquid fuel
	is drawn from each in proportion to what it holds, so they run dry together and the weight
	stays balanced. Batteries are wired in parallel: each gives current in proportion to its
	conductance (capacity over internal resistance, held back by its BMS derate) and to how far
	its open-circuit voltage stands above an empty cell's, so fuller and larger packs give more
	and the packs even out (an estimated stand-in for solving the parallel circuit). Regenerative
	braking charges every battery in proportion to the charge it accepts.

	The tank list and the shares are rebuilt every FeedRescan seconds, and the fuel burned is
	added up and taken from the tanks every FeedFlush seconds (constants at the top of the file),
	so the per-tick cost does not grow with the number of tanks.
]]

-- Rebuilds the tanks feeding the engine and their shares.
function ENT:ScanFeed()
	local Battery = ACE.Mobility.Battery
	local EmptyV = Battery.OCV(0)
	local Feed, Charge = self.Feed or {}, self.ChargeFeed or {}
	local NFeed, NCharge = 0, 0
	local DerateSum, CapSum, AcceptSum = 0, 0, 0
	for _, Tank in ipairs(self.FuelLink) do
		if IsValid(Tank) then
			local State = Tank.BatteryState
			if IsValidfueltank(Tank) then
				local Share = Tank.Fuel
				if State then
					local SOC = Tank.Fuel / math.max(Tank.Capacity, 1e-6)
					local Derate = Battery.DischargeDerate(State)
					local Cap = Tank.NominalCapacity * Battery.Health(State)
					Share = Cap / Battery.Resistance(State) * Derate * math.max(Battery.OCV(SOC) - EmptyV, 0.01)
					DerateSum = DerateSum + Cap * Derate
					CapSum = CapSum + Cap
				end
				NFeed = NFeed + 1
				Feed[NFeed] = Tank
				Tank.FeedShare = Share
			end
			if State and Tank.ChargeAcceptW then
				local Accept = Tank:ChargeAcceptW()
				if Accept > 0 then
					NCharge = NCharge + 1
					Charge[NCharge] = Tank
					Tank.ChargeShare = Accept
					AcceptSum = AcceptSum + Accept
				end
			end
		end
	end
	for I = NFeed + 1, #Feed do Feed[I] = nil end
	for I = NCharge + 1, #Charge do Charge[I] = nil end
	self.Feed, self.ChargeFeed = Feed, Charge
	-- The packs' BMS limits add up: the bank gives the capacity-weighted share of full power.
	self.FeedDerate = CapSum > 0 and DerateSum / CapSum or 1
	self.ChargeAcceptSum = AcceptSum
	self.NextFeedScan = ACE.CurTime + FeedRescan
end

--- Burns fuel from the engine's tanks (all of them together, see ScanFeed).
-- @param Amount number Litres of fuel, or kWh for batteries.
function ENT:DrawFuel(Amount)
	self.FeedPending = (self.FeedPending or 0) + Amount
end

--- Stores regenerated energy in the engine's batteries, shared by their charge acceptance.
-- @param KWh number Energy at the terminals, kWh.
function ENT:ChargeFuel(KWh)
	self.ChargePending = (self.ChargePending or 0) + KWh
end

-- Takes the fuel added up since the last flush (Dt seconds ago) from the tanks.
function ENT:FlushFeed(Dt)
	local Draw, Store = self.FeedPending or 0, self.ChargePending or 0
	self.FeedPending, self.ChargePending = 0, 0
	if Dt <= 0 then return end

	local Feed = self.Feed
	if Draw > 0 and Feed then
		local Sum = 0
		for I = 1, #Feed do
			local Tank = Feed[I]
			if IsValid(Tank) and Tank.Fuel > 0 then Sum = Sum + Tank.FeedShare end
		end
		if Sum > 0 then
			for I = 1, #Feed do
				local Tank = Feed[I]
				if IsValid(Tank) and Tank.Fuel > 0 then
					local Part = Draw * Tank.FeedShare / Sum
					if Tank.BatteryState then
						Tank:DrawEnergy(Part, Dt) -- the battery also loses its resistive heat
					else
						Tank.Fuel = math.max(Tank.Fuel - Part, 0)
						if Tank.Fuel <= 0 then self.NextFeedScan = 0 end
					end
				end
			end
		end
	end

	local Charge = self.ChargeFeed
	local AcceptSum = self.ChargeAcceptSum or 0
	if Store > 0 and Charge and AcceptSum > 0 then
		for I = 1, #Charge do
			local Tank = Charge[I]
			if IsValid(Tank) then Tank:StoreEnergy(Store * Tank.ChargeShare / AcceptSum, Dt) end
		end
	end
end

-- Per-tick checks that decide whether the engine may run: fuel, driver, legality, heat and
-- damage. Torque and RPM come from the drivetrain solve in ace/server/sv_mobility.lua.
function ENT:CalcRPM()

	if ACE.CurTime >= (self.NextFeedScan or 0) then self:ScanFeed() end
	-- The first feeding tank stands for the fuel type the engine burns.
	local Tank = self.Feed[1]
	if Tank ~= nil and not IsValidfueltank(Tank) then
		self:ScanFeed()
		Tank = self.Feed[1]
	end
	self.MobTank = Tank

	if IsValid(Tank) then
		self.HasFuel = true
	else
		self.HasFuel = false
		Wire_TriggerOutput(self, "Fuel Use", 0)

		if ACE.EnginesRequireFuel == 1 then
			self:TriggerInput( "Active", 0 ) --shut off if no fuel and requires it
			return
		end
	end

	ACE.DoContraptionLegalCheck(self)

	if self.RequiresDriver and not (self.HasDriver or self.HasSeatDriver) then
		self:TriggerInput( "Active", 0 ) --shut off if no driver and requires it
		return
	end

	-- Damage lowers the torque an engine can make; a driver boosts it. TorqueScale sets how
	-- quickly damage bites for this engine type.
	local DriverBoost = self.HasDriver and ACE.DriverTorqueBoost or 1 --Seat drivers dont give hp boost.
	self.TorqueMult = math.Clamp(((1 - self.TorqueScale) / 0.5) * ((self.ACE.Health / self.ACE.MaxHealth) - 1) + 1, self.TorqueScale, 1)
	-- An overheated engine also loses torque (ACE.EngineThermalThink).
	self.PeakTorque = self.BaseTorque * self.TorqueMult * DriverBoost * (self.ThermalDerate or 1)
	-- A hot battery pack is held back by its management system (battery_model.lua).
	if self.FuelType == "Electric" and IsValid(Tank) then
		self.PeakTorque = self.PeakTorque * (self.FeedDerate or 1)
	end

	local HealthRatio = self.ACE.Health / self.ACE.MaxHealth
	if HealthRatio < 0.995 then
		if HealthRatio > 0.025 then
			local PhysObj = self:GetPhysicsObject()
			local Mass = PhysObj:GetMass()
			ACE.Damage(self, {
				Kinetic = (1 + math.max(Mass / 2, 20) / 2.5) * 5 * self.Throttle / 100,
				Momentum = 0,
				Penetration = (1 + math.max(Mass / 2, 20) / 2.5) * 5 * self.Throttle / 100
			}, 2, 0, self:CPPIGetOwner())

			if math.Rand(0,1) > 0.99 * HealthRatio * 1.2 then
				self:EmitSound( "ambient/materials/door_hit1.wav", 120, math.random(45,100)  ) --npc/strider/strider_step4.wav
			end

		else
			--Turns Off due to massive damage
			self:TriggerInput("Active", 0)
		end
	end
end

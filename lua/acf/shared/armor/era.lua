
local BaseMaterial = {
	name = "Explosive Reactive Armor",
	sname = "ERA",
	desc = "An explosive composite sandwiched between 2 plates. When penetrated the plate detonates damaging or even destroying the incoming shell degrading its performance. This material is heavy compared to RHA and unlike other materials, will damage anything near the detonation. Explosive rounds can make short work of this material.",
	year = 1955,
	massMod = 2,
	curve = 0.95,
	resiliance = 1,
	HEATresiliance = 1,
	NCurve = 1,
	Neffectiveness = 0.25,
	Nresiliance = 1,
	APSensorFactor = 4,
	HEATSensorFactor = 16,
	spallresist = 1,
	spallmult = 0,
	ArmorMul = 1,
	NormMult = 1,
	Stopshock = true,
	IsExplosive = true
}

if SERVER then
	ACE.ERABoomPerTick = 0 --Used to count how many bricks are being detonated per tick

	BaseMaterial.HEATList = {
		HEAT = true,
		THEAT = true,
		HEATFS = true,
		THEATFS = true,
	}
	BaseMaterial.HEList = {
		HE = true,
		HESH = true,
		Frag = true,
	}

	function BaseMaterial.ArmorResolution(self, Entity, armor, losArmor, losArmorHealth, maxPenetration, FrArea, caliber, damageMult, Type)
		local HitRes = {}
		local curve = self.curve
		local effectiveness = self.effectiveness
		local resiliance = self.resiliance
		local sensor = self.APSensorFactor
		local blastArmor = effectiveness * losArmor * (Entity.ACF.Health / Entity.ACF.MaxHealth)
		if self.HEATList[Type] then
			blastArmor = self.HEATeffectiveness * losArmor
			resiliance = self.HEATresiliance
			sensor = self.HEATSensorFactor
		elseif self.HEList[Type] then
			blastArmor = self.Neffectiveness * armor
			resiliance = self.Nresiliance
			sensor = 1
		end
		if not self.HEList[Type] and maxPenetration > (blastArmor / sensor) or (Entity.ACF.Health / Entity.ACF.MaxHealth) < 0.15 then
			Entity:Remove()
			HitRes.Damage = 9999999999999
			HitRes.Overkill = math.Clamp(maxPenetration - blastArmor, 0, 1)
			HitRes.Loss = math.Clamp(blastArmor / maxPenetration, 0, 0.98)
			ACE.ERABoomPerTick = ACE.ERABoomPerTick + 1
			if not timer.Exists("ACE_ERA_Reset") then
				timer.Create("ACE_ERA_Reset", 0.01, 1, function() ACE.ERABoomPerTick = 0 end)
			end
			if ACE.ERABoomPerTick > 3 then return HitRes end
			local HEWeight = math.Min(armor * 0.2, 200)
			local Radius = ACE_CalculateHERadius(HEWeight)
			local Owner = (CPPI and Entity:CPPIGetOwner()) or NULL
			local EntPos = Entity:GetPos()
			ACF_HE(EntPos, vector_up, HEWeight, HEWeight, Owner, Entity, Entity, 0.1)
			timer.Simple(0.001, function()
				local Flash = EffectData()
				Flash:SetOrigin(EntPos)
				Flash:SetNormal(-vector_up)
				Flash:SetRadius(math.Round(math.max(Radius / 39.37 * 0.125, 1), 2))
				util.Effect("ACF_Scaled_Explosion", Flash)
			end)
			return HitRes
		else
			curve = self.NCurve
			effectiveness = self.Neffectiveness
			resiliance = self.Nresiliance
			armor = armor ^ curve
			losArmor = losArmor ^ curve
			local breachProb = math.Clamp((caliber / armor / effectiveness - 1.3) / (7 - 1.3), 0, 1)
			local penProb = (math.Clamp(1 / (1 + math.exp(-43.9445 * (maxPenetration / losArmor / effectiveness - 1))), 0.0015, 0.9985) - 0.0015) / 0.997
			if breachProb > math.random() and maxPenetration > armor then
				HitRes.Damage = FrArea * resiliance * damageMult
				HitRes.Overkill = maxPenetration - armor
				HitRes.Loss = armor / maxPenetration
				return HitRes
			elseif penProb > math.random() then
				local Penetration = math.min(maxPenetration, losArmor * effectiveness)
				HitRes.Damage = ((Penetration / losArmorHealth / effectiveness) ^ 2 * FrArea * resiliance * damageMult)
				HitRes.Overkill = (maxPenetration - Penetration)
				HitRes.Loss = Penetration / maxPenetration
				return HitRes
			end
			local Penetration = math.min(maxPenetration, losArmor * effectiveness)
			HitRes.Damage = (Penetration / losArmorHealth / effectiveness) * FrArea * resiliance * damageMult
			HitRes.Overkill = 0
			HitRes.Loss = 1
			return HitRes
		end
	end
end

-- Kontakt-1
local K1 = table.copy(BaseMaterial)
K1.id = "ERA-K1"
K1.name = "Kontakt-1 ERA"
K1.sname = "ERA-K1"
K1.desc = "First generation ERA. Effective against HEAT rounds, but offers no protection against kinetic penetrators. High chance of chain reaction."
K1.year = 1982
K1.APPerformance = 0
K1.HEATPerformance = 0.8
K1.ChainReactionChance = 0.5
K1.Casing = 3
ACE.ArmorTypes[K1.id] = K1

-- Kontakt-5
local K5 = table.copy(BaseMaterial)
K5.id = "ERA-K5"
K5.name = "Kontakt-5 ERA"
K5.sname = "ERA-K5"
K5.desc = "Second generation ERA. Offers protection against both HEAT and kinetic penetrators. Reduced chain reaction chance."
K5.year = 1985
K5.APPerformance = 0.3
K5.HEATPerformance = 0.6
K5.ChainReactionChance = 0.25
K5.Casing = 15
ACE.ArmorTypes[K5.id] = K5

-- Relikt
local Relikt = table.copy(BaseMaterial)
Relikt.id = "ERA-Relikt"
Relikt.name = "Relikt ERA"
Relikt.sname = "ERA-Relikt"
Relikt.desc = "Third generation ERA. Superior protection against both HEAT and tandem-charge kinetic penetrators. Very low chain reaction chance."
Relikt.year = 2006
Relikt.APPerformance = 0.5
Relikt.HEATPerformance = 0.7
Relikt.ChainReactionChance = 0.1
Relikt.Casing = 20
ACE.ArmorTypes[Relikt.id] = Relikt

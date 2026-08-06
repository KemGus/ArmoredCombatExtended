-- Gen 2 heavy ERA (Kontakt-5 family).
-- Reactive model concept by Delectros (STEAM_0:0:144869639), see sh_ace_era.lua.

ACE.ERA.RegisterGeneration({
	id         = "ERA2",
	generation = 2,
	sname      = "ERA Gen 2 (Heavy)",
	name       = "Explosive Reactive Armor - Gen 2 (Heavy)",
	desc       = "Heavy reactive cassettes with thick flyer plates, able to bite into long-rod penetrators as well as jets.\n\nREACTS TO: HEAT jets, kinetic rounds above 20mm, only on the FORWARD face.\nSTRONG VS: HEAT; noticeably degrades APFSDS/APDS, best on sloped mounts.\nWEAK VS: tandem warheads, HE (insensitive - never triggers), side/rear hits.\n\nFixed ~5mm casing. Each cassette is single use.",
	year       = 1986,

	massMod = 2.2,
	curve   = 0.95,
	effectiveness     = 2.2,
	HEATeffectiveness = 10,

	CasingMM     = 5,
	FlyerPlateMM = 6,
	PlateVel     = 700,
	MaxObliquity = 4,
	Density      = 2.8,  -- kg/litre (thicker plates than Gen 1); sets scalable box mass
	HESensitive  = false, -- heavy cassette, insensitive to HE / small-arms

	-- Recommended brick size (inches), approximating a real Kontakt-5 built-in
	-- module (~305 x 152 x 100 mm - heavier and thicker than Kontakt-1).
	RecommendedSize = { L = 12, W = 6, H = 4 },

	MinTriggerCaliber = 10, -- dart caliber; autocannon darts (~13mm) still trigger
	MinTriggerPen     = 60,
	MinTriggerPenHEAT = 10,

	KEEfficiency = 1.0,  MinCutKE   = 0.10, MaxCutKE   = 0.35,
	HEATEfficiency = 2.6,  MinCutHEAT = 0.50, MaxCutHEAT = 0.90,

	-- Heavy one-way plates travel forward into the rod. Bigger bricks bite more:
	-- longer face = longer plate, thicker brick = further plate travel.
	PlateLengthScale = 0.5, TravelScale = 0.4, RefPlateLenMM = 300, RefTravelMM = 100,

	FillFraction = 0.30,
	DeflectScale = 1.2,

	TandemResistant = false,
})

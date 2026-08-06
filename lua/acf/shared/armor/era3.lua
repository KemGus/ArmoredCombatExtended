-- Gen 3 modern ERA (Relikt family).
-- Reactive model concept by Delectros (STEAM_0:0:144869639), see sh_ace_era.lua.

ACE.ERA.RegisterGeneration({
	id         = "ERA3",
	generation = 3,
	sname      = "ERA Gen 3 (Modern)",
	name       = "Explosive Reactive Armor - Gen 3 (Modern)",
	desc       = "Modern layered cassettes with delayed elements. Insensitive sensor ignores autocannon fire, and the layered design keeps reacting after a tandem precursor strike.\n\nREACTS TO: HEAT jets, kinetic rounds above 35mm, only on the FORWARD face.\nSTRONG VS: HEAT including tandem warheads, long-rod penetrators.\nWEAK VS: HE (insensitive - never triggers), autocannons stripping un-triggered bricks, side/rear hits.\n\nFixed ~6mm casing. Survives one tandem precursor at reduced strength; otherwise single use.",
	year       = 2006,

	massMod = 2.0,
	curve   = 0.95,
	effectiveness     = 2.6,
	HEATeffectiveness = 12,

	CasingMM     = 6,
	FlyerPlateMM = 6,
	PlateVel     = 750,
	MaxObliquity = 4,
	Density      = 3.0,  -- kg/litre (dense layered cassette + bidirectional plates); sets scalable box mass
	HESensitive  = false, -- modern insensitive cassette

	-- Recommended brick size (inches), approximating a real Relikt element
	-- (~356 x 152 x 127 mm - longer cassettes with bidirectional plates).
	RecommendedSize = { L = 14, W = 6, H = 5 },

	MinTriggerCaliber = 16, -- insensitive: autocannon darts (~13mm) don't trigger, tank darts (~25mm) do
	MinTriggerPen     = 100,
	MinTriggerPenHEAT = 15,

	KEEfficiency = 1.3,  MinCutKE   = 0.15, MaxCutKE   = 0.45,
	HEATEfficiency = 3.2,  MinCutHEAT = 0.55, MaxCutHEAT = 0.93,

	-- Bidirectional plates travel BOTH ways, so size pays off hardest here.
	PlateLengthScale = 0.7, TravelScale = 0.6, RefPlateLenMM = 300, RefTravelMM = 100,

	FillFraction = 0.28,
	DeflectScale = 1.3,

	TandemResistant = true,
})

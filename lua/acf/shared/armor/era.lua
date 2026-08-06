-- Gen 1 light ERA (Blazer / Kontakt-1 family).
-- Reactive model concept by Delectros (STEAM_0:0:144869639), see sh_ace_era.lua.

ACE.ERA.RegisterGeneration({
	id         = "ERA",
	generation = 1,
	sname      = "ERA Gen 1 (Light)",
	name       = "Explosive Reactive Armor - Gen 1 (Light)",
	desc       = "Light reactive bricks: a thin explosive sandwich that detonates and throws its plates into the incoming warhead.\n\nREACTS TO: HEAT jets, kinetic rounds, even HE / heavy MG fire (it is SENSITIVE), only on the FORWARD face.\nSTRONG VS: single-charge HEAT.\nWEAK VS: kinetic rounds (small effect), tandem warheads, side/rear hits. Thin 3mm cover - easy to strip with autocannon.\n\nFixed ~3mm casing. Each brick is single use.",
	year       = 1982,

	massMod = 1.6,
	curve   = 0.95,
	effectiveness     = 1.2, -- display / point-cost estimate vs KE
	HEATeffectiveness = 8,

	CasingMM     = 3,    -- fixed RHA-equivalent casing thickness (the thin steel cover)
	FlyerPlateMM = 3,    -- steel flyer plate thrown by the charge
	PlateVel     = 450,  -- m/s
	MaxObliquity = 4,
	Density      = 2.4,  -- kg/litre of real brick volume (thin steel + filler); sets scalable box mass
	HESensitive  = true, -- Kontakt-1 is famously sensitive: HE / 12.7-14.5mm can set it off

	-- Recommended brick size (inches), approximating a real Kontakt-1 element
	-- container (~251 x 132 x 70 mm). Used as the tool's initial size.
	RecommendedSize = { L = 10, W = 5, H = 3 },

	-- Sensor: what wakes the brick up. Gen 1 reacts to almost anything that hits
	-- the front (it is sensitive). Caliber here is the PENETRATOR (dart)
	-- caliber the damage code reports (~25mm for a tank APFSDS, ~13mm for an
	-- autocannon dart), not the gun caliber.
	MinTriggerCaliber = 5,
	MinTriggerPen     = 25,
	MinTriggerPenHEAT = 10,

	-- Cut tuning: floor = min disruption when triggered, cap = max share of pen removed.
	-- Gen 1 (Kontakt-1 class) does essentially NOTHING to a long rod - its thin
	-- plates can't bite a sabot, so KE is capped to a token amount (casing only).
	KEEfficiency = 0.2, MinCutKE   = 0,      MaxCutKE   = 0.03,
	HEATEfficiency = 3.4, MinCutHEAT = 0.45, MaxCutHEAT = 0.85,

	-- Thin plates: brick size barely helps vs KE (no plate-length / travel bonus).
	PlateLengthScale = 0, TravelScale = 0,

	FillFraction = 0.25, -- share of real brick volume that is explosive filler
	DeflectScale = 1.0,

	TandemResistant = false,
})

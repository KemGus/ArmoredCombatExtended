-- Common rounds. caliber in mm (real bullet diameter, not the name), projMass in grams, muzzleVel in m/s
-- (typical published figures). penMul lifts penetration to the level of ACE's own weapons: ACE's formula
-- treats every bullet as soft lead, so steel-core rifle rounds get 1.7, other rifles 1.3, pistols 2.5.
local RegisterRound = ACE.SmallArms.RegisterRound

RegisterRound("9x19",     { caliber = 9,    projMass = 8,   muzzleVel = 360, penMul = 2.5 })
RegisterRound(".45ACP",   { caliber = 11.43, projMass = 15, muzzleVel = 260, penMul = 2.5 })
RegisterRound(".357",     { caliber = 9.1,  projMass = 10.2, muzzleVel = 440, penMul = 2.5 })
RegisterRound(".44Mag",   { caliber = 10.9, projMass = 15.6, muzzleVel = 440, penMul = 2.5 })
RegisterRound(".50AE",    { caliber = 12.7, projMass = 19.4, muzzleVel = 470, penMul = 2.5 })
RegisterRound("4.6x30",   { caliber = 4.65, projMass = 2,   muzzleVel = 735, penMul = 2 })
RegisterRound("5.45x39",  { caliber = 5.6,  projMass = 3.4, muzzleVel = 880, penMul = 1.7 })
RegisterRound("5.56x45",  { caliber = 5.7,  projMass = 4,   muzzleVel = 940, penMul = 1.3 })
RegisterRound("7.62x39",  { caliber = 7.9,  projMass = 7.9, muzzleVel = 715, penMul = 1.7 })
RegisterRound("7.62x51",  { caliber = 7.82, projMass = 9.5, muzzleVel = 850, penMul = 1.3 })
RegisterRound("7.62x54R", { caliber = 7.92, projMass = 9.6, muzzleVel = 830, penMul = 1.7 })
RegisterRound(".338LM",   { caliber = 8.6,  projMass = 16.2, muzzleVel = 915, penMul = 1.3 })
RegisterRound("9x18",     { caliber = 9.27, projMass = 6.1, muzzleVel = 315, penMul = 2.5 })
RegisterRound(".44Russian", { caliber = 10.9, projMass = 15.9, muzzleVel = 230, penMul = 2.5 })
RegisterRound(".454",     { caliber = 11.5, projMass = 15.6, muzzleVel = 520, penMul = 2.5 })
RegisterRound(".500SW",   { caliber = 12.7, projMass = 22.7, muzzleVel = 600, penMul = 2 })
RegisterRound("5.7x28",   { caliber = 5.7,  projMass = 2,   muzzleVel = 715, penMul = 2 })
RegisterRound("9x39",     { caliber = 9.25, projMass = 16,  muzzleVel = 290, penMul = 2.5 })
RegisterRound(".300BLK",  { caliber = 7.82, projMass = 7.1, muzzleVel = 680, penMul = 1.5 })
RegisterRound(".44-40",   { caliber = 10.8, projMass = 13,  muzzleVel = 380, penMul = 2.5 })
RegisterRound(".30-30",   { caliber = 7.8,  projMass = 9.7, muzzleVel = 720, penMul = 1.3 })
RegisterRound(".30-06",   { caliber = 7.82, projMass = 9.7, muzzleVel = 880, penMul = 1.3 })
RegisterRound("7.92x57",  { caliber = 8.2,  projMass = 12.8, muzzleVel = 760, penMul = 1.3 })
RegisterRound(".408CT",   { caliber = 10.4, projMass = 27.2, muzzleVel = 900, penMul = 1.3 })
RegisterRound(".50BMG",   { caliber = 12.95, projMass = 42, muzzleVel = 890, penMul = 1.3 })
-- One 00 buckshot pellet; shotguns fire one per pellet.
RegisterRound("12ga_00",  { caliber = 8.4,  projMass = 3.5, muzzleVel = 400 })

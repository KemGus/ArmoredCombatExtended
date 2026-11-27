# Scalable guns — the plan in two stages

This document describes where the scalable-guns feature is going and why.
Written for review before stage 2 is implemented. Nothing here is committed yet.

## The one-paragraph version

Today ACE has a long hand-written list of gun definitions: 37mm cannon, 50mm
cannon, 75mm cannon ... each with its own stats. Stage 1 (already built) lets any
of these guns be scaled in caliber and barrel length at spawn time. Stage 2 (the
goal) deletes the ladder: each gun *class* becomes a single definition, and the
player simply dials caliber and length numerically — the way ACF-3 does it, but
keeping the barrel-length axis that ACF-3 does not have.

## Stage 1 — additive scaling (BUILT, live on the test server)

Every existing gun def keeps its exact current stats. On top of it, a gun can be
spawned scaled: `120mmC` at 140mm caliber with L/55 barrel, for example.

- Nothing existing changes. Old dupes paste identically. This is purely additive.
- The barrel scales by stretching only the tube part of the model — the breech
  stays sized by caliber alone. 42 models were re-rigged for this.
- Verified: physics hulls, muzzle positions, bone positions match the math
  exactly server-side; renders show identical breeches across barrel lengths.

What is left in stage 1 (small batch, approved but not yet implemented):

1. Six more classes get caliber-only scaling (no length axis):
   anti-tank rifle, heavy machinegun, grenade launcher, flare launcher,
   rotary autocannon, smoke launcher. Each is one line of config.
   Plain machineguns (MG) stay fixed-caliber.
2. Gun display name shows the effective caliber: a gun dialed to 40mm says
   "40mm ...", with the barrel length appended when scaled (the "L28" example).
   The spawn menu preview must update this live when sliders move.
3. Menu fix: drum autoloaders (AL) and breech autoloaders (BAL) are currently
   merged into one "Autoloader" menu entry, but they are two different weapon
   lines. They must be split into two separate menu entries.
4. Ammo-crate linking check: a gun at exactly base caliber must accept a plain
   unscaled crate.

## Stage 2 — the ACF-3-style migration (NOT built, this is the spec)

The ladder of hand-written per-caliber guns is deleted. Each class becomes one
entry with numeric envelopes. Stats come from scaling laws, not hand tuning.

### Class table

Caliber minimums stay at whatever the lowest currently-existing caliber is
(user decision). MBT guns (cannon, smoothbore, both autoloaders) scale up to
200mm. Other classes keep their current maximums.

| class | caliber mm | length axis | notes |
|---|---|---|---|
| Cannon (C) | 37–200, base 120 | L/30–70, base 45 | |
| Smoothbore (SBC) | 100–200, base 120 | yes | mass calibrated so 125mm lands ~2.5t (real 2A46M-5) |
| Drum autoloader | 50–200, base 120 | yes | SPLIT from breech — own class and menu entry; rifled/smooth bore dropdown |
| Breech autoloader | 50–200, base 120 | yes | SPLIT from drum — own class and menu entry; rifled/smooth bore dropdown |
| Short cannon (SC) | 37–170 | fixed short | class identity is the short barrel |
| Howitzer (HW) | 75–406 | yes | keeps current huge top end |
| Semiauto (SA) | 25–76 | fixed 45 | |
| Autocannon (AC) | 20–50 | fixed | |
| Mortar (MO) | 50–380 | fixed | |
| ATR, HMG, GL, FGL, RAC, SL | current extents | none | caliber only |
| MG | fixed | none | stays as today |

### How stats scale

- Mass: the gun is two parts. The breech scales with caliber cubed
  (it is a solid chunk of steel). The barrel is a tube: its weight grows with
  length, but slowly, because the tube is thin near the muzzle. Real-world
  anchor: the Rh-120 going from L/44 to L/55 added 25% barrel length but only
  13% barrel weight and 11% total weight. The formula's one knob (tubefrac =
  0.44) is calibrated to reproduce exactly that.
- Mass calibration: a 125mm smoothbore should weigh about 2.5 tonnes like the
  real 2A46M-5. Current ACE numbers are light, so base masses scale up a bit.
- Shell size grows with caliber, propellant with caliber cubed — so cost and
  reload follow automatically through the existing points system.
- Muzzle velocity grows with barrel length (existing kernel law).

### The three open decisions, written out properly

#### Decision A — should small guns keep some minimum weight?

Under pure cubic scaling, weight is proportional to caliber cubed. Problem:
that makes small guns far lighter than they are today. Example, cannon class:
today the 50mm weighs 380kg. Pure cubic from the 120mm base gives it 152kg —
60% lighter. Small rapid-fire cannons becoming very light is a real balance
change: they are easy to spam already.

The alternative is a small change to the formula that stays a formula: a fixed
fraction of the gun (about 15%) does not scale at all. Think of it as the part
a human loader or the mechanism needs regardless of caliber — the handles, the
breech block geometry, the mount interface. With that term, the 50mm lands at
about 440kg instead of 152kg — close to today's 380kg, no balance shock.

Both options are still "one clean law, no hand-written ladder". The question is
only whether the law is one term (pure cubic, small guns get much lighter) or
two terms (cubic plus fixed part, small guns stay roughly as heavy as today).
DEVIN'S RECOMMENDATION: two terms.

DECIDED: two terms, and the fixed fraction is a tunable variable per class
("weight boost ratio"), not a hardcoded constant — so balance can adjust how
much small guns keep without touching the law itself.

#### Decision B — one model per class, or a few cosmetic choices?

ACF-3 keeps exactly one model per class. Every cannon looks identical except
size. They deleted the old per-caliber model files from the addon entirely
(old dupes are auto-translated to the new model — the compat is in the code,
not the files).

We just re-rigged 42 models. Under stage 2 we only need one per class — the
rigging work is not wasted because it is what makes scaling look correct
(breech stays put, only the tube stretches). But some model families look
genuinely different — the old `tankgun` line vs the modern `tankgun_new` line,
for example. We could keep 1–2 alternates per class as a purely cosmetic
dropdown: same stats, different look. Everything else gets deleted, which is
also a large download-size win.

DECIDED: keep cosmetic alternates — but the exact keep/delete list is chosen
by the user from a picture gallery of every model per class before anything is
deleted. Nothing is removed until that list is confirmed.

Additional modelling task (user requirement): rifled vs smoothbore bore for the
autoloader lines. The BAL (tankgun_new) models have a smooth bore interior; the
AL (tankgun_al) models show rifling inside the barrel. Target: a dropdown choice
of rifled/smooth bore per autoloader. This needs Blender work — either a
smoothed bore variant of the AL models or a bodygroup. OPEN QUESTION: is the
rifled/smooth choice purely cosmetic, or should it carry the gameplay
difference that today separates the C (rifled) and SBC (smoothbore) classes?

#### Decision C — finish the small stage-1 batch first, or go straight to stage 2?

The stage-1 leftover batch (six caliber-only classes, effective-caliber
naming, the AL/BAL menu split, the crate-linking check) is small and useful in
BOTH worlds: the naming, the menu split and the linking are needed in stage 2
exactly the same way. Doing it first also means you can playtest it in-game
right now while stage 2 is being built.

DECIDED: finish the stage-1 batch first, then build stage 2.

### Backwards compatibility in stage 2 (summary)

- Every retired gun id (`120mmC` and friends) becomes an entry in an alias
  table pointing at class + caliber. Spawning by old id gives the matching gun.
- Old dupes paste working guns; their retired models are translated onto the
  new base model, same as ACF-3 does.
- A gun spawned by an old id keeps reporting that id, so E2/SF chips that
  compare `gun.Id` strings keep working.
- Ammo linking is numeric caliber equality — same as stage 1.
- Points need no migration: cost already derives from the round dimensions.
- `year` is dropped from gun data entirely (user decision — not worth it).

### The balance review artifact

Before merge, a script generates a table: every legacy caliber, old stats vs
new stats (weight, shell size, muzzle velocity, points cost). That table is
the thing to review — the migration ships only after a human signs off on it.

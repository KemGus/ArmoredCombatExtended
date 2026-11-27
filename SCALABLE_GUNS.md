# Scalable guns — as built

This document describes the scalable-guns feature as it actually shipped on
`feat/scalable-guns`. It replaces the original two-stage plan; both stages are
now implemented.

## The one-paragraph version

ACE's 84 hand-written per-caliber gun definitions are replaced by 16 unified
scalable classes. Each class is a single definition with numeric caliber and
bore-length envelopes; players dial both continuously in the spawn menu and
stats derive from physical scaling laws calibrated against real gun data.
Legacy content — dupes, saves, E2/SF chips, ammo crates — keeps working through
a generated alias layer.

## Classes

15 legacy classes plus the new breech-autoloader class. The shortcannon class
was folded into Cannon (a short cannon is just a cannon at short bore length;
the mass law reproduces the old shortcannon weights within ~6%). Drum (AL) and
breech (BAL) autoloaders are separate classes sharing one ammo family — both
feed from the same crates — and appear in the menu as one entry with a
mechanism dropdown.

Caliber minimums are the lowest authored caliber per class; maximums are the
authored max, except MBT guns (C/SBC/AL/BAL) which extend to 200mm. Caliber-only
classes (machineguns, launchers, mortars, etc.) have a locked length axis.

## The scaling laws

Each class has a pivot (base caliber + base length) at which stats match the
old authored values exactly. Off-pivot:

```
mass = base × [ 0.08 + 0.92 × ( 0.56·cs³ + 0.44·cs²·ls ) ]
```

- `cs` = caliber ratio, `ls` = bore-length ratio.
- The breech/mechanism scales cubically with caliber (0.56 term); the tube
  scales with caliber² × length (0.44 term). tubefrac 0.44 is calibrated from
  Rheinmetall's Rh-120 L/44→L/55 data (+25% length = only +13% barrel mass).
- The 0.08 overhead floor is mechanism mass that cannot shrink; calibrated
  against real guns (KwK 36 37mm = 195kg, KwK 39 50mm = 435kg, KwK 40 75mm
  = 750kg).
- Muzzle velocity scales as `ls^0.35` (length only).
- ROF cap scales as `(basecal/cal)^0.7`; drum magazine reload as `cs^0.7`;
  magazine size inverse-square-root — reproducing the retired ladder's shape.
- Rounds scale automatically: shell dimensions × cs, propellant capacity × cs³.
  ACE points derive from round data, so firepower costs scale with no extra
  wiring. Measured curve across the cannon ladder (AP, sustained-rate costing):
  37mm → 70pts, 75mm → 385, 120mm → 770 (peak), 140mm → 735, 170mm → 694.
  Note the decline past the 120 pivot — a property of sustained-rate costing,
  flagged as an open balance question in the PR.

## Identity and compatibility

- `.Id` (networked) is the compatibility identity: guns pasted from old dupes
  report their legacy id (`"120mmC"`); new spawns report the class id.
- `.GunKey` (networked) is the canonical identity: `"C@140x55"` = class +
  caliber mm + length. Dupes round-trip through it losslessly.
- All 84 legacy ids resolve through a generated alias table
  (`ace_legacy_gun_aliases.lua`) into class + authored caliber/length. This
  applies to guns AND ammo crates: a crate keyed `140mmC` builds 140mm rounds.
- Ancient `BackComp` ids rewrite before alias resolution, as before.
- Third-party addons indexing `ACE.Weapons.Guns["120mmC"]` directly get nil —
  the ladder ids are gone from the table. Everything must resolve through the
  alias-aware helpers.

## Security model

Every input path — menu spawn, dupe paste, keyed ids, round creation — funnels
through server-side normalization which hard-clamps caliber and length into
the class envelope. Client input is a request; the envelope only exists
server-side. Tested: a 250mm request clamps to 200mm.

## Rendering and collision

One model per class; per-caliber variants deleted (62 models). Models carry
rebuilt barrel-bone rigs: uniform caliber scale applies to the whole entity,
then the tube section stretches axially for length. Collision hulls rebuild
piecewise from the same registry data (`GunScale.BarrelJoints`): vertices
behind the breech/tube joint keep the uniform scale, tube vertices displace
along the bore proportionally, capped at the tube end. Verified numerically:
hull stretch matches prediction exactly (e.g. SBC L/48→L/70: 91.6 units
predicted, 91.6 measured).

Known behaviors:

- The muzzle brake has no collision on any gun (hull ends 18-33 units short
  of the visual muzzle). This is pre-existing ACE authoring, unchanged; length
  scaling makes it more visible. Documented in the PR as accepted behavior.
- The visual tube-bone pivot sits near the model origin while the hull seam
  sits at the measured joint — a seam mismatch of a few units at extreme
  lengths. Cosmetic; a rig-pipeline refinement is on the follow-up list.

## Tests

- GLuaTest live suite: 14/14 (dupe round-trips, keyed ammo, crate linking incl.
  legacy-keyed crates, envelope clamping, autoloader mechanisms).
- Offline LuaJIT integration (real loader chain): 46/46 — alias resolution,
  pivot invariance, 2A46 calibration (125mm smoothbore ≈ 2.5t), overhead floor.
- Kernel selftest: 125/125.

## Follow-ups not in this PR

- Rifled/smoothbore cosmetic dropdown for tank guns (needs Blender work).
- Muzzle-brake collision (procedural extension or .phy re-authoring).
- Rig bone-pivot refinement (visual seam at extreme lengths).

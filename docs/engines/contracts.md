# Custom engines: contracts (P0)

The interfaces every package builds against. A package may not change them; it files an
objection instead (plan §10). Numbers marked *estimated* are placeholders until P2/P5 set them
from sourced data.

All new code lives in the `ACE.` namespace. Everything in sections 1–6 is **pure**: shared
realm, no entities, no `net`, no globals beyond `ACE.*`, deterministic, and it must load in
vanilla Lua 5.1 / LuaJIT so `python tests/run_luajit_tests.py` can test it (same rule as
`ACE.Manufacturing`).

## 1. The stats table (`Spec`)

What the engine entity runs on. Today the entity reads the definition table directly
(`acf_engine/init.lua:125-152`, `Lookup.*`). From P4 it reads a `Spec` instead, with **the same
field names**, so `ApplyEngine` changes `Lookup` to `Spec` and nothing else.

| Field | Unit | Today from | Notes |
|---|---|---|---|
| `id` | | definition id | custom engines: `"ace_custom"` |
| `name` | | | custom: generated, e.g. "4.0L V8 Petrol Turbo" |
| `model` | path | | from `ACE.EngineModel.Resolve`, part 1 |
| `weight` | kg | | |
| `torque` | N·m | | peak |
| `peakpower` | kW | | |
| `peakpowerrpm`, `peaktqrpm`, `idlerpm`, `peakminrpm`, `peakmaxrpm`, `limitrpm` | rpm | | |
| `flywheelmass` | kg | | entity keeps `Inertia = flywheelmass * π²` |
| `flywheeloverride` | | | |
| `iselec`, `istrans` | bool | | |
| `fuel` | | | `ACE.FuelDensity` key |
| `enginetype` | | | `ACE.Efficiency` / `ACE.TorqueScale` key |
| `torquecurve` | 13 points, 0–1 | | always filled; same format as today |
| `sound`, `pitch` | | | |
| `CoolingArea` | m² | | thermal model |
| `motorvolume` | in³ | | |

New fields, absent on stock engines:

| Field | Meaning |
|---|---|
| `motortype` | id passed to `ACE.DefineMotorType`, e.g. `"Piston"` |
| `output` | `"Shaft"` (default) or `"Thrust"` |
| `thrust` | N, `Thrust` types only |
| `displacement` | L, piston types |
| `params` | copy of the clamped `Params` the spec was built from (dupes store this) |
| `parts`, `hull` | from `ACE.EngineModel.Resolve` (section 5) |
| `capped` | list of `{ stat, from, to, rule }` for every cap that changed something (section 4) |
| `real` | the uncapped, unbalanced figures (`torque`, `peakpower`, `weight`), for the menu and the realism report |

## 2. `Params`

The inputs of a custom engine, as the menu, dupes and design mode exchange them.

```lua
Params = {
	Type = "Piston",  -- motor type id
	V    = 1,         -- params version of that type; Resolve upgrades older versions
	-- type-specific fields, e.g. for Piston:
	Layout = "V", Cylinders = 8, Bore = 101.6, Stroke = 92.0, -- mm
	Strokes = 4, Fuel = "Petrol", Aspiration = "NA", Cooling = "Liquid",
}
```

- Each motor type declares its fields in `Def.Params` as
  `{ Name, Kind = "number"|"enum"|"bool", Min, Max, Step, Default, Options, Unit, Desc }`.
  The advanced editor is generated from this list; no per-type menu code.
- `ACE.EngineSpec.ClampParams( Params )` fills defaults, drops unknown keys and clamps to
  Min/Max/Options. Every path (menu, dupe paste, E2, foreign compat) goes through it on the
  **server**. The client's numbers are never trusted.
- Dupes store `Params` only, never stats. Pasting re-resolves, so a balance change reaches old
  dupes and an edited dupe can't carry 1e9 torque.

Piston fields and limits (*estimated*, set in P5): Layout I/V/B/W/R/Single/Wankel; Cylinders 1–16
(R: 3–28, odd); Bore 30–200 mm; Stroke 30–250 mm; Strokes 2/4; Fuel Petrol/Diesel/Multifuel;
Aspiration NA/Turbo/Supercharged; Cooling Air/Fins/Liquid.

## 3. `ACE.DefineMotorType( Id, Def )`

```lua
ACE.DefineMotorType( "Piston", {
	Name    = "Piston engine",
	Output  = "Shaft",                         -- or "Thrust"
	Params  = { ... },                         -- section 2
	Resolve = function( Params ) return Spec end,     -- clamped Params in, Spec fields out
	Design  = { Options = function( Targets ) return { Params, ... } end }, -- section 7, optional
	Model   = function( Params ) return Parts, Hull end, -- optional; default = section 5 lookup
	Sound   = function( Params ) return Path, Pitch end, -- optional
	Cost    = function( Spec ) return Bill end,       -- section 6, optional; default = $/kW fallback
	Caps    = { KWPerKg = n, KWPerHullL = n, NmPerDispL = n }, -- section 4, any may be nil
} )
```

Module: `lua/ace/shared/mobility/engine_spec.lua` (not under `lua/ace/shared/engines/`: the
definitions selftest loads every file there as an engine definition). It defines
`ACE.DefineMotorType`, `ACE.MotorTypes`, `ACE.EngineSpec`, `ACE.EngineCaps`, `ACE.EngineBalance`.

- Registering the same id twice replaces it (reload-safe) and logs once.
- Missing `Resolve`, `Params` or an `Output` other than Shaft/Thrust is an error at
  registration, not at spawn.
- `ACE.MotorTypes[ Id ]` holds the registered definitions. Addons register from shared autorun
  after ACE loads; a hook `ACE_MotorTypesReady` fires once all of ACE's own types are in.

## 4. `ACE.EngineSpec.Resolve( Def, Params )`

The only place an engine's stats are made.

1. **Fixed engine** (`Def` given, `Params` nil): returns a `Spec` built from `Def`. For stock
   engines this must be field-for-field identical to what the entity reads today (P4's locked
   benchmark is the P1 dump).
2. **Custom engine** (`Params` given): `ClampParams`, then `ACE.MotorTypes[ Params.Type ].Resolve`,
   then the caps, then the balance multiplier, then the model and cost.
3. **Foreign engine** (an id ACE didn't define, e.g. ACF Customs or ACF-Extra): treated as
   fixed, then caps.

**Caps (ACE rules).** Every non-stock spec passes through them, so a small engine can't make
huge torque:

- `KWPerKg` (peak kW / weight), `KWPerHullL` (peak kW / hull volume in litres) and, when the
  spec has `displacement` (L), `NmPerDispL`. Limits come from the type's `Caps`, else
  `ACE.EngineCaps[ Type ]`; a nil limit is not checked.
- A cap that is exceeded scales `torque` and `peakpower` down together (the rpm figures stay).
- Limits are set in P5 from the P2 real-engine data: the highest real figure for that class plus
  a margin (*estimated* 20 %). They are constants in `ACE.EngineCaps`, each with its source.
- A capped stat is scaled down, never refused, and recorded in `Spec.capped`. The menu and the
  paste notice show it.

**Balance multiplier:** one per fuel type, `ACE.EngineBalance[ Fuel ]`, default 1. Applied
after the caps. `Spec.real` keeps the figures from before it.

## 5. `ACE.EngineModel.Resolve( Spec )`

```lua
local Parts, Hull = ACE.EngineModel.Resolve( Spec )
-- Parts = { { Model = "models/...", Pos = Vector, Ang = Angle, Scale = Vector }, ... }
-- Hull  = { Mins = Vector, Maxs = Vector }  -- physics, source units
```

- Phase 1 (P6) always returns one part: the model for that layout and cylinder count, scaled
  per axis (length by cylinders per bank, width and height by bore).
- Callers must loop over `Parts` and never assume one model, so segment models later only change
  this function and the client draw.
- In the pure tests `Vector` and `Angle` are plain `{ x, y, z }` / `{ p, y, r }` tables; the GMod
  wrapper converts them.

## 6. Cost

Two numbers, both shown in the menu.

- **Manufacturing price ($)**, `ACE.Manufacturing.EngineCost( Spec )`. A bill of materials:
  materials by mass split × $/kg, labour hours × $/h, bought-in parts, then the production-volume
  multiplier. It returns
  `{ Materials, Labour, Parts, Volume, Total }` so the Mfg. Cost popup can show the breakdown. The
  old `EngineCost( hp, fuelType )` signature stays as a fallback for engines without a mass split.
  Constants go in `ACE.ManuCost`, each with a P16 source and allowed range.
- **ACE points**, `ACE.Points.EngineCost( Spec )`. Power plus terms for power/kg, power/volume and
  efficiency (P7). The old `EngineCost( hp )` keeps working. The stock points test must stay within
  its margin.

A motor type's `Cost` overrides the bill of materials (electric: copper, magnets, inverter).

## 7. Design mode

```lua
Targets = {
	Type = "Piston", Fuel = "Petrol",
	PowerKW = 150, RPMMin = 1500, RPMMax = 6500,   -- any may be nil
	Weights = { Size = 0.5, Mass = 0.5, Price = 0.5, Efficiency = 0.5, Reliability = 0.5 }, -- 0–1
	Fixed = { Layout = "V" },                       -- params the player locked
}
local Results = ACE.EngineDesign.Solve( Targets )
-- { { Params = ..., Spec = ..., Score = 0.91, Misses = { "PowerKW" } }, ... }  best 3
```

- The solver only picks `Params`. Stats always come from `Resolve`, so design mode can't make an
  engine the editor couldn't.
- A target it can't reach is listed in `Misses` with the closest value; it never fakes it.

## 8. Networking and dupes

- Client → server: `Params` only (menu spawn, editor update).
- Server → client: the entity networks `Spec` fields the HUD/menu need, as today.
- Duplicator: engines store `Params` (custom) or the id (fixed), plus `ACE_SpecVersion`.
- Foreign classes (ACF Customs) are registered in `lua/ace/server/compat/<addon>.lua` and
  converted to an ACE engine on paste (plan §4).

## 9. Tests that lock these contracts

- `tests/lua/engine_spec_selftest.lua` (picked up by `run_luajit_tests.py`): registration errors, ClampParams, fixed passthrough,
  caps recorded in `Spec.capped`, Thrust spec has no gearbox output.
- The P1 harness dump (`tests/harness/engine_dump.lua`, `before.json`) is the benchmark for P4's
  stock passthrough.
- P2 reference data → `lua/tests/ace/data/real_engines.lua` with calibration/hold-out split (P5).

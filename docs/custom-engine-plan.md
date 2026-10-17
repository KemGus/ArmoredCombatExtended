# Custom engines: plan

Status: planning, nothing built yet. Written 2026-10-17 on branch `mobility-realism`.

Goals:

1. Custom engines: the builder picks layout, cylinder count, bore, stroke, 2/4-stroke, fuel and
   cooling, instead of choosing from fixed small/medium/large items.
2. A menu where custom engines can be built, saved and loaded, next to a folder of predefined
   engines.
3. Dupes saved with ACF Customs (https://github.com/bouletmarc/ACF_CustomMod) paste into ACE
   without ACF Customs installed, and obey ACE's rules once pasted.
4. ACE and ACF-Extra (https://github.com/ClockEFFX/ACF-Extra) installed together do not conflict.
5. Stats that can be checked against real engines, so people can port real engines into ACE.
6. Tidier engine code.

---

## 1. Models

How a model can follow the cylinder count:

- **Uniform scaling** (the whole model bigger or smaller) changes size only. The cylinder count
  stays what the model shows.
- **Stretching along the crank axis** works for engines that are a row of cylinders: inline, V,
  boxer, X, W, VR. Length follows cylinders per bank, and width and height follow the bore. ACE's
  scaler already takes a per-axis scale (`lua/ace/shared/sh_ace_scalable.lua`, scale is an
  L/W/H vector), and the collision hull scales with it. Detail stretches too, so extreme
  stretches look wrong.
- **Radials and rotaries** add cylinders or rotors around a circle, so each count needs its own
  model.
- **Built from parts:** the client draws a repeated cylinder-segment model N times plus front and
  rear caps, and physics uses one scaled hull.

### Decision

- **Now:** for the chosen layout and cylinder count, use an existing model with that count. Where
  none exists, stretch the nearest one along the crank. Scale by bore.
- **Not now, but kept possible:** built-from-parts models. The code must not assume one engine =
  one model. Model choice goes through one function, `ACE.EngineModel.Resolve( Spec )`, which
  returns a list of parts (model, position, scale) plus a hull size. Phase 1 always returns one
  part. Segment models later only change that function and the client draw, not the engine
  entity, its stats or its dupes.

### Cutting models

New engines need one model per layout and cylinder count, not small/medium/large, so the size
variants become dupe-only. They stay in the addon (old dupes need them) but are hidden from the
menu, the same as the legacy gearboxes (`lua/ace/shared/gearboxes/scalable.lua`). Nothing is
removed from ACE.

---

## 2. Stats from parameters

Builder inputs: layout, cylinders, bore, stroke, 2- or 4-stroke, fuel, aspiration, cooling type,
and later mixture (lean/rich) and boost.

| Stat | From | Kind |
|---|---|---|
| Displacement | Vd = π/4 · bore² · stroke · cylinders | exact geometry |
| Peak torque | T = BMEP · Vd / (4π) for 4-stroke, / (2π) for 2-stroke | exact definition of BMEP; the BMEP *value* per fuel/aspiration is the tuned part |
| Power | P = T · ω | exact |
| Redline | rpm = v_piston · 60 / (2 · stroke) | exact relation; the piston speed *limit* is the tuned part |
| Mass | displacement × layout factor | fitted |
| Flywheel inertia, idle | fitted to engines of similar displacement | fitted |

Cooling types (RDC's idea), mapped onto ACE's thermal model
(`lua/ace/shared/mobility/thermal_model.lua`):

- Air cooled: keeps itself cool even when stationary, unless boosted.
- Cooling fins: sheds some heat, not enough when stationary. Suits fast vehicles.
- Liquid cooled: needs radiators.

### Proving the stats are realistic

Only three numbers in the model are tuned: BMEP per fuel and aspiration, the piston-speed limit,
and the mass factor. Everything else is geometry or a definition, so it is exact. The proof
therefore checks those three against real engines:

1. **Reference table** `lua/tests/ace/data/real_engines.lua`: real engines (car, truck, tank,
   aircraft, motorcycle) with their published bore, stroke, cylinders, stroke type, fuel,
   aspiration, peak torque, rated rpm and dry mass. Every row carries a link to the source it
   came from. No row without a source.
2. **Test** that builds each one as an ACE custom engine and compares ACE's torque, redline and
   mass to the published figures, failing outside a tolerance (start at ±15 %).
3. **Report**: the test prints a table (real vs ACE, % off) that can be pasted into a PR or the
   wiki, so anyone can read it without trusting the code.
4. The BMEP and piston-speed values used are written next to the textbook or datasheet they come
   from. Until sourced they are marked *estimated* in code and docs.

Porting a real engine then means typing its datasheet bore, stroke, cylinder count and layout;
the comparison table shows how close ACE gets.

**Game balance stays separate from realism.** Where ACE needs an engine weaker or stronger than
real life, that is one visible multiplier per fuel type, not a hidden change to the formulas. The
report shows both the realistic and the in-game figure.

**Parity with stock engines:** once the formulas pass the real-engine test, stock ACE engines may
be rescaled so a stock 5.7 L V8 and a custom 5.7 L V8 come out the same. That changes existing
dupes' performance, so it is its own decision and its own commit, with a before/after table.

---

## 3. Custom engine menu

- **Predefined engines:** engines shipped with ACE, defined as normal engine definition files
  with their custom parameters, shown in a "Predefined" folder of the engine menu.
- **Custom engine editor:** an entry "Custom engine" in the menu. Every input change updates a
  live readout: displacement, torque and power curve, redline, mass, heat, plus a warning when a
  value sits outside what the real-engine table covers.
- **Saving:** saved engines are files in the player's `data/ace/engines/` folder, listed in a
  "Saved" folder with save, rename, duplicate and delete. A saved engine is just the parameter
  table, so it can be shared as a file.
- **Dupes** store the parameters, not a reference to the saved file, so a dupe works on any
  server without the file.
- **Server rules:** the server checks every parameter against ACE's limits when spawning, no
  matter what the client sent.

The editor needs to work very well, so it gets its own design pass and testing on a real client
(the harness can't run one).

### Simple design mode

For players who know what they want but not what bore and stroke are.

- **They enter targets:** motor type and fuel (e.g. petrol piston engine), power, rpm range,
  optionally torque and aspiration.
- **They set importance sliders:** small size, low weight, low price, fuel efficiency,
  reliability / low heat. Each 0 to 1.
- **ACE designs it:** a solver tries the motor type's options (layouts, cylinder counts, bore and
  stroke steps, for a piston engine), runs each through the same stats function as advanced mode,
  and scores how far it lands from the targets plus the slider priorities. It shows the best 3,
  with what each trades away ("2 % short on power, 30 % lighter").
- **Not happy:** move the sliders and it redesigns live, or press "Tweak" to open the result in
  the advanced editor with every value filled in.
- The solver only *picks parameters*. It can't make anything the advanced editor couldn't, so it
  can't get around ACE's rules, and the server never needs to trust it.
- If no design reaches the targets (a 1000 hp engine that must be tiny), it says which target
  failed and the closest it got, instead of quietly returning something else.
- Each motor type supplies its own option list for the solver (section 6), so design mode works
  for electric motors and turbines too, not just piston engines.

---

## 4. ACF Customs dupe compatibility

Compatibility means dupes saved with ACF Customs entities paste into ACE with ACF Customs
**not** installed. ACE registers ACF Customs' entity classes with the duplicator and builds ACE
entities from the saved fields. It is basic compatibility: the dupe spawns with its models and
dimensions and works under ACE's rules, and that's it.

### ACE rules apply

ACF Customs engines must not be overpowered. A small engine can't keep its saved 231321 Nm.

- `acf_engine_custom` ids map to an ACE custom engine of the matching layout and displacement,
  so their stats come from ACE's formulas, not from ACF Customs' numbers.
- `acf_engine_maker` stores raw torque, rpm and weight with no displacement. ACE takes the
  model and the weight, works out the largest engine that model's size and that weight allow, and
  caps torque, rpm and flywheel at what that engine could produce under ACE rules. Saved values
  below the cap are kept.
- Turbo and supercharger boost obeys the same caps once those parts exist.
- The player gets one chat notice per paste listing what was capped or skipped.

### What ACF Customs dupes contain

From its `duplicator.RegisterEntityClass` calls:

| ACF Customs class | Saved fields | Becomes in ACE |
|---|---|---|
| `acf_engine_custom` | Id only. 24 ids such as `1.6-I4R` (`lua/acf/shared/customs/enginecustom.lua`) | ACE custom engine via a compat table (id → layout, cylinders, displacement) |
| `acf_engine_maker` | Id `Maker`, Mod1–Mod13: name, sound, model, fuel, engine type, torque, idle, peak min rpm, peak max rpm, limit rpm, flywheel mass, weight, is-electric | ACE custom engine, capped as above |
| `acf_gearbox_manual`, `_auto`, `_cvt`, `_air` | Id + Gear1–Gear9, Gear0 | ACE scalable gearboxes via an id → family / gear count / size table |
| `acf_rads` | Id | `ace_radiator` |
| `acf_turbo` | Id, Mods1 (boost), Mods2 (blow-off sound) | future turbo part; until then skipped with a notice |
| `acf_supercharger` | Id, Mods1 | future supercharger part; until then skipped |
| `acf_nos`, `acf_chips`, `acf_engine_flywheel` | modifiers | skipped with a notice |

Links are entity modifiers `GearLink`, `FuelLink`, `ExtraLink` and `RadiatorLink`
(`acf_engine_maker.lua:1450-1507`). ACE already reads `GearLink` and `FuelLink`. `RadiatorLink`
maps onto ACE's radiator link, and `ExtraLink` waits for the boost parts.

### Models

ACF Customs has **no license file**, which by default means all rights reserved: we can't ship
its models without the author's permission. Until then, a model the player doesn't have gets a
stand-in model of the same layout. Most of its 83 models are the ACF-Extra set anyway, so once
ACF-Extra's models are in, most of these resolve.

---

## 5. ACF-Extra alongside ACE

Permission to use ACF-Extra's models: granted (user, 2026-10-17).

Today, installing ACF-Extra on ACE works: none of its 93 engine ids clash with ACE's, and ACE
loads its old-format definitions from `lua/acf/shared/` (`lua/ace/shared/sh_ace_loader.lua:457`).

Problems start when ACE ships ACF-Extra's models **and** changes their stats (they are far too
strong now), and a player has both installed:

| Conflict | Cause | Fix |
|---|---|---|
| Same engine id, two stat sets | both addons define the id; whichever loads last wins, so the server's stats depend on load order | ACE never reuses ACF-Extra's ids. ACE's versions get ACE ids; the ACF-Extra ids are left to ACF-Extra |
| Same model path, different file | game mounts one; the other addon gets the wrong shape | ACE's copies go to its own folder (`models/ace/engines/...`); a shared path is kept only where the file is byte-identical |
| ACF-Extra's own strong engines still spawnable | ACF-Extra loaded on ACE | ACE applies the same caps it uses for ACF Customs engines to any engine definition not from ACE, so foreign engines can't exceed what ACE would give that displacement |
| Rescaled stock engines | parity pass in section 2 | one commit with a before/after table |

Already found: `emotor-standalone-tiny.mdl` and `flywheelclutcht.mdl` exist in both with
**different** files. These two are moved to ACE's own folder as part of this work (old dupes keep
working through a model remap).

---

## 6. Motor types: piston, electric, turbine and whatever comes next

Custom design isn't only for piston engines. Electric motors and turbines get the same treatment,
and adding a new kind (ACF-Extra's pulsejet, a cold gas thruster) should be one file.

### A motor type is one definition

```lua
ACE.DefineMotorType( "Piston", {
	Name   = "Piston engine",
	Output = "Shaft",              -- "Shaft": torque into a gearbox. "Thrust": force on the entity
	Params = { ... },              -- the inputs and their limits; drives the advanced editor
	Resolve = function( Params ) end, -- parameters -> stats (torque curve, mass, size, fuel use, heat)
	Design  = { Options = function( Targets ) end }, -- candidate parameters for design mode
	Model   = function( Params ) end, -- parts + hull, see section 1
	Sound   = function( Params ) end,
	Cost    = function( Stats, Params ) end, -- section 7
} )
```

- **Piston:** bore, stroke, cylinders, layout, strokes, fuel, aspiration, cooling (section 2).
- **Electric:** rated power, rated and max rpm, voltage class, cooling. Torque flat up to rated
  rpm, then falling with constant power, which is how real electric motors behave. Uses ACE's
  battery and grid.
- **Turbine:** shaft power and output rpm, with slow spool-up, high idle fuel use and lots of
  heat. Needs the turbine model (user is asking for it).
- **Pulsejet, cold gas thruster, rockets:** `Output = "Thrust"`. They push the entity directly
  instead of driving a gearbox, so they skip gearbox links. A cold gas thruster needs a gas tank
  instead of fuel. Not built by us now, but the `Thrust` path is designed in from the start so an
  addon can add them without touching ACE's code.

### The old way keeps working

Today's custom engines, as the wiki documents them
(https://acegmod.com/wiki/your-first-custom-engines and
https://acegmod.com/wiki/custom-engine-types), are fixed `ACF_DefineEngine` tables plus the
`ACF.Efficiency` / `ACF.TorqueScale` / `ACF.EngineHPMult` / `ACF.GenericTorqueCurves` entries.
Those keep working exactly as now. A motor type is the new, extra way.

### Documentation

Once built, two new wiki pages in the same "Custom Engines" folder and the same style as the two
above: "Designing engines in the menu" (players) and "Adding a motor type" (addon makers, with the
pulsejet as the worked example). The two existing pages get a line pointing to them.

---

## 7. Cost: manufacturing price and ACE points

Two different numbers, kept separate:

- **Manufacturing price** (money, in $): keeps the existing system's place, `ACE.Manufacturing`
  (`lua/ace/shared/sh_ace_manufacturing.lua`), the "Mfg. Cost" line the armor tool shows, but
  replaces how engines are priced.

### Manufacturing price, rebuilt

**Today:** peak hp × a $/hp rate per fuel (`ACE.ManuCost.engine_per_hp`: Petrol 250,
Diesel 350, Multifuel 500, Electric 400). The fuel isn't what costs money; the rate is a stand-in
for "engines of this kind are built heavier and with pricier parts" (a diesel has a stronger block
for its higher compression and a high-pressure injection pump; an electric motor needs an
inverter). As a stand-in it is crude: a heavy low-revving diesel and a light high-revving one with
the same power cost the same, and nothing about the build counts.

**New:** price = what goes into it, as a bill of materials plus work:

| Part | From |
|---|---|
| Materials | engine mass split by material (cast iron or aluminium block and heads, forged steel crank and rods, ...) × $/kg per material |
| Machining and assembly | hours (base + per cylinder + per valve train/bank) × labour $/h |
| Bought-in parts | fuel system by fuel (carburettor, petrol injection, diesel high-pressure injection), ignition, turbo/supercharger, radiator/fans for liquid cooling, inverter for electric, ... |
| Overhead and volume | one multiplier for low-volume military production vs mass production |

- Each line's numbers come from a **research package** (P16 below): sourced material prices,
  labour rates and published engine production costs, every figure linked, or marked *estimated*.
- **Check:** the formula is tested against real engines whose build or unit cost is published
  (benchmark set from P16), within a tolerance.
- **Production volume** matters most (a mass-produced car engine vs a hand-built tank engine can
  differ ten times). Recommendation: price everything as low-volume military production, because
  ACE builds combat vehicles; one constant in `ACE.ManuCost` if a server wants otherwise.
- All constants live in `ACE.ManuCost`, so a server owner retunes one table. The pure model still
  loads in plain Lua 5.1, as the file requires. Each motor type supplies its own bill of
  materials; a type without one falls back to the old $/hp so nothing is free.
- **ACE points** (balance): what the engine is worth in combat. Today that is only peak power
  (`ACE.Points.EngineCost`, `lua/ace/shared/sh_ace_points_model.lua:262`, kEng × hp). With
  custom engines, power alone lets players make a tiny, light engine with the same power for the
  same points. So points become power **plus** what makes an engine better in a fight: power per
  kg, power per volume, and fuel efficiency.
- A stock engine must cost the same points before and after, within a small margin; the test
  compares every stock engine. Fitting the new terms to keep that is part of the work.
- Each motor type supplies its own `Cost` function, so an addon's pulsejet gets priced too. A
  type without one falls back to the power-based points, so nothing is ever free.
- The menu shows both numbers live while designing, and design mode's "low price" slider uses
  the price.

---

## 8. Code layout

### ACE now

- Engine definitions are split per family: `lua/ace/shared/engines/*.lua` (20 files), the same
  split as ACF-3.
- Drivetrain and thermal physics are separate modules (`lua/ace/shared/mobility/`).
- The monolith is `lua/entities/acf_engine/init.lua`: 1981 lines, 41 functions covering spawn,
  update, links, fuel and battery, starter, damage, sound, overlay and dupe.

### ACF-3 (read from source, ACF-Team/ACF-3 at 6173764)

- Engines and engine types are classes in an inheritance system (`ACF.Classes.DefineClass`,
  `lua/acf/core/classes/new.lua`), one file per family in `lua/acf/entities/engines/`.
- One generic entity registration with lifecycle hooks (`ACF.Entities.AutoRegister`,
  `lua/acf/core/entities/registration.lua`). The engine entity is 899 + 196 + 30 lines.
- Old dupes are fixed by numbered patches (`ACF.Entities.RegisterCompatPatch`,
  `lua/acf/compatibility/acf3/engines.lua`).
- **No scalable engines.** The source says so outright (`lua/entities/acf_engine/shared.lua:4`).

### Proposal

1. **Keep `ACE.DefineEngine` tables.** Dupes, E2 and other addons depend on the ids. ACF-3's
   class system would be a rewrite with no gameplay gain.
2. **One spec resolver:** `ACE.EngineSpec.Resolve( Def, Params )` turns a fixed engine *or* a
   custom one into the same stats table, like `ACE.GearboxSize.Resolve` does for gearboxes.
   `ApplyEngine` reads only the resolved stats. The ACE-rules caps (section 4) live here too, so
   every engine, whatever its source, passes through them.
3. **One model resolver:** `ACE.EngineModel.Resolve( Spec )` returning parts + hull (section 1).
4. **Split `acf_engine/init.lua` by job:** spawn/update/dupe, links, fuel and battery, starter,
   damage and sound. No behaviour change, in its own commit, done first.
5. **A compatibility folder with one file per foreign addon:** `lua/ace/server/compat/acf_customs.lua`
   holding the duplicator registrations and id tables from section 4.

---

## 9. Order of work

1. Split `acf_engine/init.lua` (no behaviour change).
2. Engine spec resolver and `ACE.DefineMotorType`, with the existing fixed engines going through
   it unchanged (test: every stock engine's stats and points identical before and after). The
   `Thrust` output path is stubbed and tested here even though nothing uses it yet.
3. Real-engine reference table and test (section 2), sourced, before any custom engine ships.
4. Piston motor type: parameters, stats, model resolver, phase 1 models.
5. Custom engine menu: predefined, saved, advanced editor (section 3).
6. Design mode solver and its sliders (section 3).
7. Points and price (section 7), with the stock-engine points test.
8. Electric motor type, then turbine (needs the model).
9. ACE-rules caps for foreign engines; ACF Customs compat: engines, engine maker, gearboxes,
   radiators.
10. ACF-Extra models into ACE's own folder, with ACE ids and stats.
11. Stock engine parity pass (separate decision).
12. Boost parts (turbo, supercharger), then ACF Customs' `acf_turbo` / `acf_supercharger` compat.
13. Wiki pages (section 6), written against the finished code.
14. Built-from-parts models, if a modeler is available.

## 10. Work packages for subagent workflows

The order of work above, cut into packages that agents can run. Each package is one workflow run
on its own branch off `mobility-realism`, in its own worktree, with a fixed brief and a check
that decides whether it's done.

### Rules for every package

- Branch `engines/<package>` off `mobility-realism`; never commits to `mobility-realism`
  itself. I review each branch and merge it; pushing only when the user says.
- Must pass glualint and `python tests/run_luajit_tests.py`. New pure-Lua code gets LuaJIT
  tests; entity code gets a gmodkit harness check (`gmodkit status` first, the server is shared).
- Anything that needs a game client (menus, model looks, sounds) ends with a short list of what
  the user has to check in-game; the agent can't.
- Every number from outside (real engine data, prices) carries a source link, or is marked
  *estimated*. A second agent re-reads each source and confirms the number.

### Who does what

| Role | Who | Does | Never does |
|---|---|---|---|
| Orchestrator | Opus (me, in this session) | writes the contracts (P0), every package brief (what to build, how, which files), **writes the tests and benchmarks before the work starts**, runs the workflows, reviews and merges branches, explains results to the user | implements packages itself, beyond P0 and small fixes in review |
| Implementer | Sonnet | builds one package against its brief until the locked tests pass; files objections | edits locked tests or benchmark data |
| Reviewer | Sonnet (a different agent from the implementer) | reads the diff against the brief and the style rules, re-runs the tests, reports problems | fixes things itself |
| Researcher | Sonnet | finds real-world numbers with sources (engine data, prices) | uses a number it hasn't read in the source |
| Verifier | Sonnet (a different agent from the researcher) | re-opens each source and confirms or rejects each number | trusts the researcher's summary |
| Clerk | Haiku | exactly-specified mechanical work: extract tables from a repo, hash files, dump stats of every stock engine before/after, run harness commands and return raw output, format report tables | anything needing judgement |
| Decider | the user | approves contracts, benchmark changes, balance calls (parity, points), in-game checks | |

Opus only takes a package itself when it is the hard maths (P5 calibration, P8 solver); a Haiku
reviewer checks it (user's call, 2026-10-17: cheaper, and the locked tests carry most of the weight).
To save tokens, a Haiku reviewer is also the default wherever an automated check already covers
correctness (P1, P3, data packages); Sonnet reviews only judgement-heavy code (P4, P9, P11).

### Haiku's coding jobs

Haiku writes code when the brief fixes every decision, so the job is copying, translating or
filling a template:

- Moving functions verbatim between files from a move map (P1).
- Turning verified research JSON into Lua data files with a given layout (P2, P16).
- Generating the ACF Customs id → ACE mapping table and the per-class duplicator registrations
  from a template (P11).
- The model remap table for moved ACF-Extra files (P12).
- LDoc headers from a signature list, localization strings, menu label tables.

Every Haiku code job is followed by an automated check (lint, tests, "function bodies identical
to before") and a Sonnet reviewer.

### Example: P1, split `acf_engine/init.lua`

| Step | Who | Does | Passes when |
|---|---|---|---|
| 1 | Haiku | runs the harness script I wrote: spawn every stock engine, link, start, rev, dupe and paste; writes the state dump `before.json` | dump exists, 0 Lua errors |
| 2 | Sonnet (planner) | reads the file, proposes the move map: each of the 41 functions → target file, plus the include order | I approve the map |
| 3 | Haiku | moves functions exactly per the map; no edits inside function bodies | check script: every function body byte-identical to before; nothing lost or doubled |
| 4 | Sonnet (reviewer) | reads the diff: upvalues and locals still reachable, include order right, style rules | no blocking findings, else back to step 3 (max 2 rounds, then me) |
| 5 | Haiku | runs the same harness script; writes `after.json` | `after.json` identical to `before.json`, 0 Lua errors |
| 6 | me | read the result and objections, merge | |

### Example: P11, ACF Customs dupes

| Step | Who | Does | Passes when |
|---|---|---|---|
| 1 | Haiku | extracts from the ACF Customs clone: every engine id with its stats, every gearbox id, all `RegisterEntityClass` signatures, into JSON | check script re-reads the Lua and counts match (24 engines, ...) |
| 2 | Sonnet (verifier) | spot-checks 20 % of the rows against the source files | no mismatches |
| 3 | Haiku | generates `lua/ace/server/compat/acf_customs_tables.lua` from the JSON with my template | lint passes; table test |
| 4 | Sonnet (implementer) | writes the conversion: class registrations, engine → ACE custom engine, engine maker caps, gearbox mapping, link modifiers, the chat notice | my locked tests pass: caps hold for the test cases, every id maps |
| 5 | Sonnet (reviewer, another agent) | diff against brief: no ACF Customs stats leak past the caps, ACE namespace, LDoc | no blocking findings, else back to step 4 (max 2 rounds) |
| 6 | Haiku | pastes the test dupes saved with ACF Customs on the harness, returns raw output: spawned entities, their stats, links, errors | output reaches me unedited |
| 7 | me | compare to expected; merge or send back | |

### Tests and benchmarks: set first, locked, not to be gamed

1. **Before any package starts**, I write its checks: LuaJIT tests, harness scripts, and for the
   realism packages the benchmark data (from the verified research). They are committed on the
   package branch first and listed as locked paths in the brief.
2. **Locked means:** the workflow checks the implementer's diff; any change to a locked path
   fails the package, whatever the reason.
3. **Objections instead of edits.** Every implementer returns a structured result with an
   `objections` field: "this benchmark row looks wrong because …, source …". An objection
   doesn't block or excuse the work. I check it against the sources; if it holds, the user
   decides whether the benchmark changes, and the package re-runs against the new one.
4. **No fitting to the test.** The realism benchmarks are split:
   - a **calibration set** the implementer sees and may tune against;
   - a **hold-out set** only the orchestrator runs. A formula that hits the calibration set but
     misses the hold-out is overfitted and goes back.
5. **Constants must stay physical.** Every tuned constant (BMEP, piston speed, $/kg, labour rate)
   has a sourced allowed range, and a test fails if a constant leaves it. So a fit can't be
   "fixed" by setting BMEP to something no real engine has.
6. **Unchanged means unchanged.** For refactors (P1, P4) the benchmark is a Haiku-made dump of
   every stock engine before the change; after must be byte-identical.

### Packages

| # | Package | Needs | Implementer | Checks (written by me first) |
|---|---|---|---|---|
| P0 | **Contracts**: stats table, `Params`, `ACE.DefineMotorType`, `ACE.EngineSpec.Resolve`, `ACE.EngineModel.Resolve` | none | me | user agrees with the doc |
| P1 | **Split `acf_engine/init.lua`**, no behaviour change | none | Sonnet; Haiku makes the before/after dumps | every stock engine spawned, linked, run, duped on the harness; dumps identical |
| P2 | **Real-engine reference data** (~30: car, truck, tank, aircraft, motorcycle, electric, turbine) | none | Sonnet researchers per class, Sonnet verifiers per row | each row source-confirmed; I split calibration / hold-out |
| P3 | **Model inventory**: every engine model in ACE and ACF-Extra, layout, cylinders, size, hash, clashes | none | Haiku | table complete, hashes match |
| P16 | **Manufacturing cost research**: material $/kg, labour $/h, engine material splits, bought-in part prices, published unit costs of real engines (benchmark) | none | Sonnet researchers, Sonnet verifiers | each figure source-confirmed; allowed ranges per constant |
| P4 | **Resolver + motor type registry**, stock passthrough, `Thrust` stub | P0, P1 | Sonnet | stock dump identical; thrust stub test |
| P5 | **Piston motor type**, calibrated to P2 | P2, P4 | Opus, Sonnet reviews | calibration + hold-out within tolerance; constants inside ranges; report table |
| P6 | **Model resolver**, phase 1 | P0, P3 | Sonnet | every layout × count resolves; harness spawns each |
| P7 | **Points and price**: new points terms; bill-of-materials price | P4, P5, P16 | Sonnet, Opus reviews | stock points within margin; price vs P16 benchmark; constants inside ranges |
| P8 | **Design mode solver** | P5 | Opus, Sonnet reviews | hits target cases; reports impossible ones |
| P9 | **Menu**: editor, design mode, predefined/saved | P5, P8 | Sonnet | user's in-game checklist |
| P10 | **Electric**, then **turbine** (needs model) | P2, P4 | Sonnet | their P2 rows within tolerance |
| P11 | **Foreign engine caps + ACF Customs compat** | P5 | Haiku extracts id tables; Sonnet | saved ACF Customs dupes paste on harness and obey caps |
| P12 | **ACF-Extra models** into ACE's folder, ACE ids, remap | P3, P5 | Haiku moves/lists; Sonnet | both addons on harness: no clash, old dupes paste |
| P13 | **Stock engine parity** | P5, P7 | Sonnet | user approves before/after table |
| P14 | **Boost parts** | P5, P7 | own plan later | |
| P15 | **Wiki pages** | P9, P10 | Sonnet | user reviews text |

### Waves

- **Wave 1, in parallel:** P0 (me), P1, P2, P3, P16. None depends on another.
- **Wave 2:** P4, then P5, P6 and P10-electric in parallel.
- **Wave 3:** P7, P8, P11, P12 in parallel.
- **Wave 4:** P9 (menu), then P13, P15. P14 later, separately.

The research packages (P2, P16) use more agents than the default workflow size (under 5); they
need the size raised for those runs, or are split into several smaller runs.

## 11. Open items

- ACF Customs model permission (no license file, so not usable until the author agrees).
- Turbine model: the user is asking for it.
- Source the BMEP, piston-speed and mass values (step 3), and the price figures (P16).

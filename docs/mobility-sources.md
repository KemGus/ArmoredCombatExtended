# Mobility model: sources

Where every number in the mobility model comes from. Each constant is marked:

- **Sourced**: taken from, or computed from, the cited document.
- **Fitted**: least-squares fit to data from the cited documents. The fit is described next to it.
- **Estimated**: an engineering assumption with no direct source. These are the ones to
  replace when better data turns up.

Curves are resampled by `tools/mobility_torque_curves.py`, which holds the raw data points.
Digitised charts were read from rendered PDF pages. Expect about ±1% error on those points.

## References

### Engine friction, pumping and general engine theory

- **[Heywood]** J. B. Heywood, *Internal Combustion Engine Fundamentals*, 2nd ed., McGraw-Hill, 2018.
  Ch. 2 (mean effective pressure), 9-10 (combustion pressures), 12 (energy balance),
  13 (friction and pumping), App. D (fuel properties). *These chapter citations were not
  re-checked against the book during this pass.*
- **[Chen-Flynn]** S. K. Chen, P. F. Flynn, "Development of a Single Cylinder Compression
  Ignition Research Engine", SAE 650733, 1965. Source of the FMEP = A + B·pmax + C·Sp + D·Sp² form.
- **[Tadros 2025]** M. Tadros et al., "Engine Optimization Model for Accurate Prediction of
  Friction Model in Marine Dual-Fuel Engine", *Algorithms*, 2025.
  https://strathprints.strath.ac.uk/93447/ . Quoted for the 0.004-0.006 range of the Chen-Flynn
  load coefficient. Taken from the search summary; the paper was not read in full.
- **[x-engineer]** "Mechanical efficiency and friction mean effective pressure (FMEP)",
  x-engineer.org. Source of the earlier SI constants (A 0.3, B 0.006, C 0.05, D 0.00085, with Sf = ω·S/2).
  Those constants had no cited origin, so they were **replaced** by the fits below.

### Measured engine data (full-load and motoring torque)

- **[EPA-Mazda20]** US EPA NVFEL, *2014 Mazda 2.0L SKYACTIV Engine LEV III Fuel - ALPHA Map Package*, 2018.
  https://www.epa.gov/sites/default/files/2018-04/2014-mazda-2-0l-skyactiv-engine-lev-3-fuel-alpha-map-package-03-29-18.zip
  (the Tier 2 package has the same engine file:
  https://www.epa.gov/sites/default/files/2018-04/2014-mazda-2.0l-skyactiv-engine-tier-2-fuel-alpha-map-package-03-29-18.zip)
- **[EPA-LV3]** US EPA NVFEL, *2014 Chevrolet 4.3L EcoTec3 LV3 Engine Tier 2 Fuel - ALPHA Map Package*, 2018.
  https://www.epa.gov/sites/default/files/2018-12/2014-chevrolet-4-3l-ecotec-lv3-engine-tier-2-fuel-alpha-map-package-10-25-18.zip
  The WOT curve inside is GM's published curve (GM media release "Silverado V6", 2013-06-19).
- **[EPA-LCV]** US EPA NVFEL, *2013 Chevrolet 2.5L Ecotec LCV Engine - ALPHA Map Package*, 2018.
  https://www.epa.gov/sites/default/files/2018-04/2013-chevrolet-2-5l-ecotec-lcv-engine-reg-e10-fuel-alpha-map-package-03-05-18.zip
- **[EPA-A25A]** US EPA NVFEL, *2018 Toyota 2.5L A25A-FKS Engine Tier 2 Fuel - ALPHA Map Package*, 2020.
  https://www.epa.gov/sites/default/files/2020-08/2018-toyota-2.5l-a25a-fks-engine-tier2-fuel-alpha-map-package-dated-07-30-20.zip
- **[EPA-L15B7]** US EPA NVFEL, *2016 Honda 1.5L L15B7 Engine Tier 2 Fuel - ALPHA Map Package*, 2019.
  https://www.epa.gov/sites/default/files/2019-02/2016-honda-1-5l-l15b7-engine-tier-2-fuel-alpha-map-package-02-04-19.zip
- **[EPA-N57]** US EPA NVFEL, *2015 BMW 3.0L N57 Engine Diesel Fuel - ALPHA Map Package*, 2018.
  https://www.epa.gov/sites/default/files/2018-12/2015-bmw-3-0-l-n57-engine-diesel-fuel-alpha-map-package-06-11-18.zip
- **[EPA-TNGA]** US EPA, *ALPHA Engine Generation Toyota TNGA 2.5L*, 2017-01-12.
  https://www.epa.gov/sites/default/files/2017-01/documents/process-gen-engine-fuel-consumption-map-toyota-tnga.pdf
  Also lists EPA gasoline "MTE_GASOLINE" at 43.31 MJ/kg.
- **[EPA-F150doc]** US EPA, *2015 Ford F150 2.7L EcoBoost Engine Tier 2 Fuel Mapping Process*, 2016-06-20
  (`engine.inertia_kgm2 = 0.13`, "estimated from engine displacement").
  https://www.epa.gov/sites/default/files/2020-01/documents/2015-ford-f150-2.7l-engine-tier2-fuel-mapping-process-2016-06-20.pdf
- **[EPA-Ricardo]** US EPA, *Process for Generating Engine Fuel Consumption Map: Ricardo Cooled EGR
  Boost 24-Bar Standard Car Engine*, 2016 (1.04 L, `engine.inertia_kgm2 = 0.075`).
  https://www.epa.gov/sites/default/files/2016-11/documents/procs-gen-eng-fuel-cons-map-ricardo-cool-egr-boost.pdf
- **[EPA-maps]** US EPA, *Combining Data into Complete Engine ALPHA Maps* (index of the packages above).
  https://www.epa.gov/vehicle-and-fuel-emissions-testing/combining-data-complete-engine-alpha-maps
- **[VECTO]** European Commission, VECTO (Vehicle Energy Consumption calculation TOol), source
  and generic vehicles, https://code.europa.eu/vecto/vecto . Read through the public GitHub
  mirror https://github.com/NSEE/VECTO_BR. Files used:
  `Generic Vehicles/Declaration Mode/Group5_Tractor_4x2/325kW.vfld` and `Engine_325kW_12.7l.veng`,
  `Generic Vehicles/Declaration Mode/Group2_RigidTruck_4x2/175kW.vfld` and `Engine_175kW_6.8l.veng`,
  `VectoCore/VectoCore/Models/Declaration/DeclarationData.cs` (class `Engine`, inertia constants).
- **[Scania DC13]** Scania, *Super 13-litre engine* brochure, p. 5 (DC13 torque/power curves).
  https://www.scania.com/content/dam/www/market/master/campaigns/super-exp/downloads/brochures/Scania-Super-13-litre-engine-brochure.pdf
  Used only as a check: full torque from 900 to about 1,300 rpm, then constant power to 1,800 rpm,
  which is the shape of the VECTO 325 kW curve.
- **[Kubota D1105]** Kubota, *D1105-E3B (3000 rpm)* engine data sheet.
  https://engine.kubota.com/en/products/product_pdf/23_pdf_1.pdf

### Military engines

- **[TM 9-2815-220-24]** US Army, *Maintenance Manual, AVDS-1790-2CA, 2DA, 2DR*, via
  https://automotiveenginemechanics.tpub.com/TM-9-2815-220-24/ (pages 0059, 0060, 0267, 0268):
  735-780 gross hp @ 2,400 rpm; gross torque 1,770-1,842 lb·ft @ 1,800 and 1,609-1,707 lb·ft @
  2,400; idle 675-725 rpm; bore = stroke 5.75 in; 149.1 cu in per cylinder; CR 16:1.
- **[RENK AVDS]** RENK America, *AVDS-1790-2CAU Engine* and *AVDS-1790 Series Engine* data sheets, 2023.
  https://www.renk.com/en/products/vehicles/engines/avds-1790 (29.3 L, 146 × 146 mm, 12 cyl, 2,313 kg dry;
  gross torque chart for the 2CAU, 5AR and 8DR).
- **[TM 9-1731B]** War Department, *TM 9-1731B Ordnance Maintenance: Ford Tank Engines (Models
  GAA, GAF and GAN)*, 1945. https://www.theshermantank.com/wp-content/uploads/2015/12/TM9-1731B-OM-Ford-Tanks-Engines-Models-GAA-GAF-and-GAN.pdf
  Par. 4 data: 500 hp @ 2,600, 1,050 lb·ft @ 2,200, 5.4 × 6 in, 1,100 cu in. Fig. 10: engine power curve.
- **[V-2]** "В-2", ru.wikipedia.org (cites *Танк Т-34-85. Руководство по матчасти*):
  38,880 cm³, 150 mm bore, 180/186.7 mm stroke, 500 hp @ 1,800 rpm, 2,160 N·m @ 1,200 rpm, 2,050 rpm maximum.
  https://ru.wikipedia.org/wiki/В-2
- **[Series 71]** "Detroit Diesel Series 71", en.wikipedia.org: 4.25 × 5 in, 71 cu in per cylinder,
  two-stroke. https://en.wikipedia.org/wiki/Detroit_Diesel_Series_71
- **[FI AGT1500]** Forecast International, *Industrial & Marine Turbine Forecast: Honeywell
  AGT1500*, January 2008. https://www.forecastinternational.com/archive/disp_pdf.cfm?DACH_RECNO=180 :
  1,500 shp at 3,000 rpm output; 3,754 N·m at 3,000 rpm; power turbine 22,500 rpm reduced to 3,000;
  power-turbine rotor inertia 0.141 kg·m², gas-producer rotor 0.074 kg·m²; SFC 0.30 kg/kWh at full power.
- **[GTW]** Gas Turbine World, "On the move: gas turbines for land-based propulsion":
  AGT1500 peak torque 5,355 N·m @ 1,000 rpm. https://gasturbineworld.com/land-based-propulsion-systems/
- **[GM small-block]** "General Motors small-block engine", en.wikipedia.org: the LV3 4.3 L V6 "is
  based on the Generation V small-block V8 architecture" (92 mm stroke, as the 5.3 L L83).
  https://en.wikipedia.org/wiki/General_Motors_small-block_engine

### Electric motors

- **[ORNL-2013]** Oak Ridge National Laboratory, *Traction Drive and Gearing Design Comparisons for Multiple
  Manufacturers and Models*, ORNL/TM-2013/482, 2013. https://info.ornl.gov/sites/publications/files/Pub46325.pdf
  (2012 LEAF motor: 80 kW, 10,400 rpm maximum).
- **[Gao 2019]** Z. Gao et al., "Evaluation of electric vehicle component performance over
  eco-driving cycles", *Energy* 172 (2019) 823-839, doi:10.1016/j.energy.2019.02.017,
  https://www.osti.gov/servlets/purl/1494893 . Table 1: motor maximum torque 280 / 700 / 874 N·m
  with rotor inertia 0.03 / 0.06 / 0.08 kg·m².

### Torque converter, gears, clutch, tyres (cited by the code; not re-verified in this pass)

- **[SAE J643]** SAE J643, *Hydrodynamic Drive Test Code*: K = N/√T and TR vs SR convention.
- **[Naunheimer]** H. Naunheimer et al., *Automotive Transmissions*, 2nd ed., Springer 2011, §6.3.
- **[Kotwicki]** A. J. Kotwicki, "Dynamic Models for Torque Converter Equipped Vehicles", SAE 820393, 1982.
- **[Shigley]** Budynas & Nisbett, *Shigley's Mechanical Engineering Design*, §16-8 (clutch energy).

## Torque curves

All curves have 13 points from idle (first) to the engine's limit RPM (last), normalised to
peak. ACE samples them with Catmull-Rom (`ACE.CalcCurve`, `Engine.SampleCurve`).

| Curve (ace_engine_properties.lua) | Engine | Source | Range used | Notes |
|---|---|---|---|---|
| `SkyactivI4` | Mazda 2.0 L SKYACTIV-G, NA I4 | [EPA-Mazda20], measured | 600-6,563 rpm | Idle 600 rpm from the package. Data starts at 1,039 rpm; idle torque extrapolated linearly (0.56 of peak) |
| `LV3V6` | GM 4.3 L LV3, NA pushrod V6 | [EPA-LV3] (GM curve) | 560-5,500 rpm | Idle 560 from the package; 560-800 rpm extrapolated |
| `GAA` | Ford GAA 18.0 L V8 tank engine | [TM 9-1731B] fig. 10, digitised | 1,000-2,800 rpm | Checked against the par. 4 data (1,050 lb·ft @ 2,200; 500 hp @ 2,600). Idle not published, so the curve starts at 1,000 rpm |
| `AVDS` | AVDS-1790-2CAU, turbo V12 tank diesel | [RENK AVDS] chart, digitised; idle from [TM 9-2815-220-24] | 700-2,400 rpm | Chart covers 1,400-2,400 rpm; 700-1,400 rpm extrapolated linearly (0.41 at idle). The VECTO truck curves give 0.50-0.56 at idle, so it is in the same range |
| `Vecto325` | VECTO generic 325 kW 12.7 L truck diesel | [VECTO] 325kW.vfld | 600-1,800 rpm (idle to rated) | Tabulated from idle |
| `Vecto175` | VECTO generic 175 kW 6.9 L truck diesel | [VECTO] 175kW.vfld | 600-1,950 rpm | Tabulated from idle |
| `N57` | BMW N57 3.0 L turbo diesel | [EPA-N57], measured | 1,001-4,620 rpm | Idle is 550 rpm, but boost builds between 1,000 and 1,250 rpm and a straight line below that is meaningless. The curve starts at the first measured point |
| `D1105` | Kubota D1105 1.1 L NA IDI diesel | [Kubota D1105] chart, digitised | 1,600-3,000 rpm | Checked against the table (71.5 N·m @ 2,200; 18.5 kW @ 3,000). Idle not published |
| `AeroTurbine`, `GroundTurbine`, AGT1500 def | free power turbine | [GTW] + [FI AGT1500] | idle at 14% / 20% / 830 of 3,000 rpm | Straight line through 5,355 N·m @ 1,000 and 3,754 N·m @ 3,000 rpm. That torque falls linearly with speed at fixed gas-generator output is the standard free-turbine approximation. It is **estimated** for turbines other than the AGT1500 |
| `PMMotor` | 2012 Nissan LEAF motor | [ORNL-2013], [Gao 2019] | 0-10,400 rpm | Constant 280 N·m to 80 kW / 280 N·m = 2,729 rpm, then constant power. The constant-power shape is the textbook PM-motor envelope and is **estimated**, not a measured map |

Layout → curve. Petrol comes from `ACE.GenericTorqueCurves`, and Diesel/Multifuel reciprocating
engines from `ACE.GenericDieselTorqueCurves`. `ACE.GetEngineTorqueCurve(Def)` picks the table.

| enginetype | Petrol | Diesel / Multifuel | Why |
|---|---|---|---|
| Single, I2, V2 | SkyactivI4 | D1105 (I2) | **Estimated mapping**: no public motorcycle full-load data found |
| I3, I4, V4, B4 | SkyactivI4 | D1105 (I3), N57 (I4, V4), AVDS (B4) | car-size NA petrol; small diesels; B4 multifuels are military |
| I5, I6, B6, V6, V8, V10, V12, GenericPetrol | LV3V6 | Vecto175 (I5, V6, V8), Vecto325 (I6), AVDS (B6, V10, V12) | LV3 is from the Gen V V8 family [GM small-block] |
| Wankel | SkyactivI4 | - | **Estimated mapping**: no public rotary full-load data found |
| Racing | SkyactivI4 | - | **Estimated mapping**: no public racing-engine full-load data found |
| Radial | GAA | AVDS | **Estimated mapping**: R975 and GAA both powered the M4, but no R975 curve was found |
| GenericDiesel | AVDS | AVDS | most GenericDiesel engines are tank V12s |

Fuel no longer reshapes curves. `ACE.PerFuelTorqueCurveMul` is kept as empty tables for
addons that read it. The old diesel multiplier {1, 1.64, 1.43, 1.12, 0.9, 0.89, 0.93} had no source.

## Rotating inertia (engine_model.lua `estimateInertia`, `Engine.Build`)

| Kind | Formula [kg·m²] | Status | Data points |
|---|---|---|---|
| diesel ≤ 3.2 L | 0.4·V | Sourced [VECTO] `SmallEngineDisplacementInertia` 400 kg/m³ | |
| diesel 3.2-5 L | 0.989·V − 1.885 | Sourced [VECTO] (manual gearbox) | |
| diesel > 5 L | 1.3 + 0.41 + 0.27·V | Sourced [VECTO] (clutch 1.3 + base 0.41 + 270 kg/m³) | VECTO generics: 12.74 L → 5.15, 6.87 L → 3.57 |
| petrol / rotary | 0.046 + 0.026·V | Fitted to [EPA-TNGA] 2.5 L 0.095, [EPA-F150doc] 2.694 L 0.13 and [EPA-Ricardo] 1.04 L 0.075 | EPA estimated the first two from similar engines and displacement. The Ricardo value was backed out of a simulated WOT transient. Anything above 2.7 L is **extrapolated**, e.g. 18 L gives 0.51, and no large petrol figure exists to check it |
| electric | 0.03·(T/280)^0.86 | Fitted to [Gao 2019] table 1 | 280 → 0.03, 700 → 0.06 (fit 0.066), 874 → 0.08 |
| turbine | 7.93·(T/5355)·(3000/limit rpm) | AGT1500 point sourced ([FI AGT1500]: 0.141 × 7.5² = 7.93 kg·m² at the output). Scaling to other turbines is **estimated** (same stored energy per unit power) | |

Definitions with their own `inertia`: AGT1500 7.93 ([FI AGT1500]), Electric-Tiny-NoBatt 0.03 ([Gao 2019], LEAF-class motor).

## engine_model.lua constants

| Constant | Value | Status / source |
|---|---|---|
| SI friction A, B, C, D | 0.173 bar, 0.005, 0.0462 bar·s/m, 0.0021 bar·s²/m² | **Fitted.** The motoring MEP 0.953 + 0.0462·Sp + 0.0021·Sp² was fitted to 19 closed-throttle points in [EPA-Mazda20], [EPA-LCV], [EPA-A25A], [EPA-L15B7] and [EPA-LV3] (rms 12%). Old values: 0.3, 0.006, 0.05, 0.00085 with Sf = ω·S/2 [x-engineer] |
| Diesel friction A, B, C, D | 0.445, 0.005, 0, 0.0136 | **Fitted.** 0.905 + 0.0136·Sp² fitted to the [VECTO] 12.7 L and 6.9 L motoring curves plus [EPA-N57] (12 points, rms 22%, set by the spread between the two VECTO engines). VECTO gives no stroke, so the fit assumes 160 mm for the 12.74 L engine (Scania DC13 / Volvo D13 class, 130-131 × 158-160 mm) and 125 mm for the 6.87 L engine (**estimated**). Old values: 0.4, 0.005, 0.05, 0.00085 |
| Rotary friction | same as SI | **Estimated**: no rotary data. Old values: 0.45, 0.006, 0.06, 0.001 |
| Piston speed | Sp = 2·S·N (mean piston speed) | Definition in [Chen-Flynn]. The old code used ω·S/2, which is π/2 × the mean piston speed |
| B (all) | 0.005 | Middle of the 0.004-0.006 range in [Tadros 2025]. Only the split of the fitted constant depends on it |
| PmaxIdle SI / diesel / rotary | 6 / 42 / 6 bar | **Derived**: polytropic compression p·rc^n. SI: 0.3 bar manifold, rc 10, n 1.3. Diesel: 1 bar, rc 16, n 1.35. The rc and n values are typical, so this is **estimated**. Old values: 15 / 40 / 12 |
| PmaxFull SI / diesel / rotary | 60 / 150 / 55 bar | [Heywood] ch. 9-10 typical values, **not re-verified** |
| PumpClosed / PumpOpen SI | 0.75 / 0.15 bar | [Heywood] 13.2: exhaust ≈ 1.05 bar minus idle manifold ≈ 0.3 bar. **Estimated split**: only the total motoring MEP is fitted to data |
| PumpClosed / PumpOpen diesel | 0.25 / 0.2 bar | **Estimated** (unthrottled). The total motoring MEP is fitted |
| EtaIndicated SI / diesel / rotary | 0.36 / 0.45 / 0.30 | [Heywood] 5.7 typical, **not re-verified**. Rotary is **estimated** |
| EtaIndicated turbine | 0.28 (was 0.25) | **Sourced**: [FI AGT1500] 0.30 kg/kWh at full power, 3.6/(0.30·42.8) = 0.28 |
| EtaIndicated electric | 0.9 | **Estimated** |
| CoolantFrac | 0.28 / 0.25 / 0.30 / 0.02 / 0.08 | [Heywood] table 12.1 for SI and diesel, **not re-verified**. The others are **estimated** |
| LHV petrol (SI, rotary) | 43.3 MJ/kg (was 43.4) | **Sourced**: [EPA-TNGA] EPA test gasoline 43.31 MJ/kg |
| LHV diesel / turbine fuel | 42.6 / 42.8 MJ/kg | [Heywood] App. D, **not re-verified** |
| StallFrac, IdleAuthority | 0.35 / 0.45 SI, 0.4 / 1 diesel | **Estimated** (control behaviour, not physical data) |
| Droop governor band | +6% above limit | **Estimated** |
| SpoolTime, IdleSpool (turbine) | 1.2 s, 0.12 | **Estimated**. [FI AGT1500] gives the gas-producer inertia (0.074 kg·m²), but no spool-up time |
| Turbine / motor friction | 1-2% of peak torque | **Estimated** |
| Idle governor gains | Ki 2.5, Kp 1.5; start integrator 0.15 / 0.2; fast-idle authority 0.6 | **Estimated** (controller tuning) |
| Start: catch speed / cranking time | 130 rpm / 3 s | [Heywood] 7.6 cranking 150-300 rpm, **not re-verified**. The 3 s is **estimated** |
| Starter: free speed / stall torque | 450 rpm / 4 × motoring torque at 0 rpm | **Estimated** |
| Rev-limiter hysteresis | 150 rpm | **Estimated** |
| Unknown displacement BMEP | 10 bar SI / 16 bar diesel | [Heywood] 2.7 typical, **not re-verified** |
| Bore = stroke when no stroke given | square engine | **Estimated** |
| CylindersByCategory Radial | 7 (was 9) | Matches ACE's own "R7" radial definitions |

## torque_converter.lua

| Constant | Value | Status |
|---|---|---|
| Form K = N/√T, TR(SR) | J643 convention | [SAE J643] |
| Coupling point SR | 0.87 | [Naunheimer] §6.3 / [Kotwicki] typical, **not re-verified** |
| Stall torque ratio default | 2.0 (range 1.8-2.4) | same, **not re-verified** |
| K scale 1 + 0.1·SR/0.6 up to SR 0.6, then 1.1/(1−X)^0.75 | shape | **Estimated** fit to the typical curve shape |
| Overrun: stator freewheels, TR 1 | behaviour | [Naunheimer], **not re-verified** |

## vehicle.lua

| Constant | Value | Status |
|---|---|---|
| Ground body J = m·r², cap μ·N·r | physics | Rigid-body identity plus the Coulomb friction limit |
| Assisted clutch engage point 1.3 × idle + 0.45 × throttle × (limit − idle), start 1.1 × idle, quadratic | control law | **Estimated** (centrifugal-clutch behaviour, not data) |

## drivetrain.lua and sv_mobility.lua

| Constant | Value | Status |
|---|---|---|
| Gearbox mesh efficiency default | 0.97 | **Estimated**. Commonly quoted per-mesh efficiency is 0.97-0.99; no source is cited in the code |
| Input shaft inertia default | 0.02 kg·m² (+0.00002 × max torque in sv_mobility) | **Estimated** |
| Spin loss | 0.002 × max torque | **Estimated** |
| Clutch slip heat = torque × slip speed | physics | [Shigley] §16-8 |
| Rolling resistance default | 0.012 | **Estimated** (typical car tyre on asphalt) |
| Surface friction fallback | 0.8 | **Estimated** |
| Brake capacity 1.5·μ·N·r + 10·J | sizing rule | **Estimated** |
| Substeps 8, constraint iterations 6 | numerics | Solver settings, not physical data |

## Named engines (engine definitions)

Only fields with a source were added. `torque` and `weight` were **not** changed. The last
column lists the published values for the maintainers' balance decision.

| ACE id | Real engine | Added / changed | Published values not applied |
|---|---|---|---|
| 21.0-V12 | AVDS-1790-2 | displacement 29.3, cylinders 12, stroke 0.146; **idle 400 → 700** [TM 9-2815-220-24] | torque 2,449 N·m @ 1,800 (ACE 5,340); dry mass 2,313 kg (ACE 1,800); rated 2,400 rpm (ACE limit 2,500, within 4%) |
| 24.8-V12 | AVDS-1790-9A | displacement 29.3, cylinders 12, stroke 0.146 [RENK AVDS] | no -9A rating found |
| 27.0-V12 | "AVDS-1790-1500" | displacement 29.3, cylinders 12, stroke 0.146 [RENK AVDS] | RENK lists up to 1,350 hp for the family |
| 16.5-V12 | V-2-34 | displacement 38.88, cylinders 12, stroke 0.18; **limit 3,500 → 1,800** [V-2] | torque 2,160 N·m @ 1,200 (ACE 1,650). Only two curve points are published, so it keeps the generic AVDS shape. Idle not found |
| 18.0-V8 | Ford GAA | displacement 18.03, cylinders 8, stroke 0.1524, torquecurve (GAA); **limit 3,800 → 2,800** [TM 9-1731B] | torque 1,424 N·m @ 2,200 (ACE 2,187); weight 667 kg with accessories (ACE 850) |
| 6.2-V6 | Detroit Diesel 6V-71 | displacement 6.98, cylinders 6, stroke 0.127 [Series 71] | it is a two-stroke **diesel**. ACE defines it as petrol, and the model has no two-stroke cycle |
| AGT 1500 Large Turbine | Honeywell AGT1500 | inertia 7.93, torquecurve (free-turbine line) [FI AGT1500], [GTW] | peak torque 5,355 N·m (ACE 6,780); 1,134 kg dry (ACE 1,250) |
| Electric-Tiny-NoBatt | 2012 Nissan LEAF motor | inertia 0.03 [Gao 2019] | 280 N·m, 80 kW, 10,400 rpm (ACE 189 N·m, 11,300 rpm) |

The desc of 1.4-B4 ("nazi insects") points at the VW Type 1 family, but no 1.4 L Type 1
existed, so nothing was applied. The 3TD entries in b4.lua are commented out.

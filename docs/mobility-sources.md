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
- **[AVDS-9AR]** "Merkava 3", weaponsystems.net: Teledyne Continental AVDS-1790-9AR, 1,200 hp at
  2,400 rpm, 3,820 N·m at 1,900 rpm. https://weaponsystems.net/system/498-Merkava%203
- **[AVDS-1500]** General Dynamics Land Systems, *The AVDS-1790 1500 Horsepower Engine* (2004):
  "1500 horsepower at 2600 rpm, and 3635 lb.-ft. at 1800 rpm for a 20% torque rise".
  https://archive.org/stream/AVDS17901500HP/AVDS%201790%201500%20HP_djvu.txt
- **[MB 873]** "Leopard 2", en.wikipedia.org, Propulsion: MTU MB 873 Ka-501, 1,500 PS (1.1 MW) at
  2,600 rpm, 4,700 N·m at 1,600-1,700 rpm, 47.7 L 90° V12, twin-turbocharged.
  https://en.wikipedia.org/wiki/Leopard_2 . Wikidata Q130458591: 1,103.25 kW at 2,600 rpm, 47,600 cm³.
  Army Guide: bore 170 mm, stroke 175 mm. http://www.army-guide.com/eng/product150.html
  (grosswald.org gives 4,999 N·m at 2,000 rpm instead, uncited; not used.)
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
- **[Burress 2013]** T. Burress, *Benchmarking State-of-the-Art Technologies*, ORNL, DOE Vehicle
  Technologies AMR 2013 (APE006). https://www.energy.gov/sites/prod/files/2014/03/f13/ape006_burress_2013_o.pdf
  2012 LEAF: 280 N·m / 80 kW verified, 10,390 rpm speed rating, final drive 7.94; motor peak
  efficiency above 97% between 5,000 and 9,000 rpm; inverter above 99%; combined motor+inverter
  above 96% at best, with a wide region above 90%; 80 kW continuous at 7,000 rpm.
- **[EM61]** Nissan EM61 ratings as published by Nissan, quoted in "Nissan EM motor",
  en.wikipedia.org, https://en.wikipedia.org/wiki/Nissan_EM_motor : 280 N·m at 0-2,730 rpm,
  80 kW at 2,730-9,800 rpm, 10,390 rpm maximum.
- **[e-Pedal]** Nissan, "e-Pedal" press release, https://global.nissannews.com/en/releases/e-pedal :
  releasing the accelerator decelerates the (2018) LEAF "at up to 0.2 g".
- **[Koloch 2025]** J. Koloch et al., "From Cell to Pack: Empirical Analysis of the Correlations
  Between Cell Properties and Battery Pack Characteristics of Electric Vehicles", *World Electr.
  Veh. J.* 16 (2025) 484, doi:10.3390/wevj16090484. Pack level: NMC 140-180 Wh/kg, NCA 150-174,
  LFP 125-145; pack volumetric 110-305 Wh/L depending on cell format.

### Batteries (battery_model.lua)

- **[Schmalstieg 2014]** J. Schmalstieg, S. Käbitz, M. Ecker, D. U. Sauer, "A holistic aging
  model for Li(NiMnCo)O2 based 18650 lithium-ion batteries", *J. Power Sources* 257 (2014)
  325-334, doi:10.1016/j.jpowsour.2014.02.012. Sanyo UR18650E (NMC/graphite, 2.05 Ah).
  Calendar tests varied SOC at 50 °C and temperature at 50 % SOC; cycle tests varied depth
  and mean SOC at 35 °C and 1C.
- **[BLAST-Lite]** NREL, BLAST-Lite, `blast/models/nmc111_gr_Sanyo2Ah_2014.py`,
  https://github.com/NREL/BLAST-Lite : the [Schmalstieg 2014] model as code. Capacity:
  calendar α = (7.543·V − 23.75)·10⁶·e^(−6976/T) with loss α·t^0.75 (t in days, T in K);
  cycling β = 7.348·10⁻³·(V − 3.667)² + 7.6·10⁻⁴ + 4.081·10⁻³·DOD with loss β·√Q (Q in Ah
  per cell, counting charge and discharge). Resistance: α_R = (5.270·V − 16.32)·10⁵·e^(−5986/T)
  with t^0.75; β_R = 2.153·10⁻⁴·(V − 3.725)² − 1.521·10⁻⁵ + 2.798·10⁻⁴·DOD, linear in Q.
  Cell 2.15 Ah; OCV table 3.331 V (0 %) to 4.162 V (100 %), from [Schmalstieg 2014] fig. 1 and
  Ecker et al. 2014. Notes that the cycling terms do not depend on temperature or C-rate.
- **[LG M50]** LG Chem INR21700-M50 product specification, as summarised by Battery Design,
  https://www.batterydesign.net/lg-21700-m50/ : 5.0 Ah, 3.63 V nominal, 4.20 V max; DCIR
  30 ± 6 mΩ (30 s, 0.5C); charge 0.7C max at 25-50 °C, charge range 0-50 °C; discharge to
  60 °C; 500 cycles at C/3.
- **[BU-409]** Battery University, "BU-409: Charging Lithium-ion",
  https://batteryuniversity.com/article/bu-409-charging-lithium-ion : CC-CV; table 2, at
  4.20 V/cell the CV stage starts at ~85 % capacity; the charge is complete when the current
  falls to 3-5 % of the Ah rating; standard 1C charge.
- **[Steinhardt 2022]** M. Steinhardt et al., "Meta-analysis of experimental results for heat
  capacity and thermal conductivity in lithium-ion batteries: A critical review", *J. Power
  Sources* 522 (2022) 230829. Full-cell specific heat, medians: cylindrical 912, prismatic
  1,041, pouch 1,168 J/(kg·K); steel housings 480 J/(kg·K).

### Gas turbines (vehicle)

- **[GS M1]** GlobalSecurity.org, *M1 Abrams Main Battle Tank - Specifications*,
  https://www.globalsecurity.org/military/systems/ground/m1-specs.htm : 10 gal/h at basic idle,
  30+ gal/h at tactical idle, 60 gal/h cross-country; 0-20 mph in 7 s (M1). A secondary source;
  no Army TM figure was found.
- **[14 CFR 33.73]** US Code of Federal Regulations, *Power or thrust response*,
  https://www.ecfr.gov/current/title-14/chapter-I/subchapter-C/part-33/subpart-E/section-33.73 :
  a certified turbine engine must go from ≤15% to 95% rated power in not over 5 s. Used only as an
  upper bound on spool-up time.

### Torque converter, gears, clutch, tyres (cited by the code; not re-verified in this pass)

- **[SAE J643]** SAE J643, *Hydrodynamic Drive Test Code*: K = N/√T and TR vs SR convention.
- **[Naunheimer]** H. Naunheimer et al., *Automotive Transmissions*, 2nd ed., Springer 2011, §6.3.
- **[Kotwicki]** A. J. Kotwicki, "Dynamic Models for Torque Converter Equipped Vehicles", SAE 820393, 1982.
- **[Shigley]** Budynas & Nisbett, *Shigley's Mechanical Engineering Design*, §16-8 (clutch energy).

### Engine cooling (thermal_model.lua)

- **[MIT 2.61]** MIT 2.61 *Internal Combustion Engines* lecture notes, lecture 18 "Engine Heat
  Transfer". https://web.mit.edu/2.61/www/Lecture%20notes/Lec.%2018%20Heat%20transf.pdf .
  Heat transfer / fuel energy ∝ BMEP^-0.2 · N^-0.2 (from Nu ∝ Re^0.8); material limits cast iron
  ~400 °C, aluminium ~300 °C, liner oil film ~200 °C; head temperatures at 2000 rpm WOT with
  95 °C coolant (after Heywood fig. 12-20).
- **[Padmaraman 2021]** S. Padmaraman, N. R. Mathivanan, B. R. Ponangi, "Heat Dissipation
  Characteristics of a FSAE Racecar Radiator", *Int. J. Heat and Technology* 39(5), 2021,
  https://doi.org/10.18280/ijht.390531 . ε-NTU cross-flow relation (eq. 8), core discharge
  coefficient 0.75, 1.2 m/s face velocity from a small fan at standstill, tube walls treated as having no
  thermal resistance, 29% of fuel energy to the cooling system.
- **[Kim-Bullard 2002]** N.-H. Kim, C. W. Bullard, "Air-side thermal hydraulic performance of
  multi-louvered fin aluminum heat exchangers", *Int. J. Refrigeration* 25(3), 2002, 390-400.
  j ∝ Re^-0.49, so h grows about as √(face velocity). Taken from abstracts and citing papers.
- **[Shah-Sekulic]** R. K. Shah, D. P. Sekulić, *Fundamentals of Heat Exchanger Design*, Wiley,
  2003. Compact automotive cores 1,000-2,500 m²/m³. *Not re-checked against the book.*
- **[Incropera]** F. P. Incropera et al., *Fundamentals of Heat and Mass Transfer*, table 1.1
  (free convection in gases 2-25 W/(m²·K)) and the cross-flow ε-NTU relation. *Not re-checked.*
- **[Hella]** Hella, *Thermostats, thermoswitches & temperature sender units* brochure.
  https://www.hella.com/hella-za/assets/media_global/HASA_Thermo_Range_Borchure_LRes.pdf :
  a typical wax thermostat starts to open at 78-82 °C and is fully open at 95 °C; expansion tank
  caps relieve at about 1.4 bar.
- **[Cummins QSB5.9]** Cummins India, *C140D5P / C160D5P genset spec sheet (QSB5.9-G1/G2)*.
  https://www.cummins.com/sites/default/files/2023-05/140-160kVA_QSB5.9_Specsheet_Rev-3.pdf :
  184 bhp (137 kW), total coolant 25.6 L (engine and radiator), 50:50 glycol.
- **[V-2]** Wikipedia, "Kharkiv model V-2": cooling system 90-95 L (family of 370-580 kW
  engines), dry weight ~1,000 kg.
- **[FSAE wiki]** "Cooling", https://fswiki.us/Cooling : cooling load 20-60% of the fuel's
  lower heating value depending on engine and throttle.
- **[MEGlobal]** MEGlobal, *Ethylene Glycol Product Guide*: 50% glycol near 90 °C, cp about
  3.5 kJ/(kg·K), density about 1.05 kg/L. *Values from memory of the tables, not re-checked.*
- **[IEC 60085]** Thermal classes of electrical insulation: class H 180 °C.

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
| `PMMotor` | 2012 Nissan LEAF motor | [ORNL-2013], [Gao 2019], [EM61], [Burress 2013] | 0-10,400 rpm | Constant 280 N·m to 80 kW / 280 N·m = 2,729 rpm, then constant power. Nissan rates 80 kW from 2,730 to 9,800 rpm [EM61] and ORNL measured the rating [Burress 2013], so the shape is **sourced** to 9,800 rpm. The last 6% to 10,390 rpm is held at constant power (no data on field-weakening falloff there) |

Sampling rules in `Engine.Build` (engine_model.lua):

- The Catmull-Rom spline overshoots at a flat-to-falling knee (1.6% above peak on `PMMotor`), so
  every sample is clipped to the curve's peak. Curves are normalised to peak, so this only removes
  the overshoot.
- Below idle a piston engine holds its first point. A **free power turbine** instead extends its
  first segment linearly to 0 rpm output (stall), where its torque is highest: the AGT1500 line
  gives 6,155 N·m at stall against 3,754 N·m at 3,000 rpm, a stall ratio of 1.64. Motors are
  defined from 0 rpm already.
- Motors and turbines give no drive torque past `limitrpm` (inverter speed limit, power-turbine
  overspeed governor). The menu graph (`ACE.Mobility.EngineCurveSample`) shows the same
  envelope, and plots turbines from 0 rpm.

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
| EtaIndicated electric | removed (was a flat 0.9) | Replaced by the motor loss model below |
| Motor losses CopperLoss·t² + InverterLoss·t (battery side), IronLoss·w² (shaft drag), ×Prated | 0.03 / 0.065 / 0.037 | **Fitted** by non-negative least squares to seven points read as the shape of the [Burress 2013] LEAF combined map (peak 96%, ≥90% over most of the envelope, ~90% at the peak-torque corner, ~80-85% at 10% torque and 10% speed). Result: peak 95.5%, 91% at the corner, 94.6% at full power and top speed. The seven points are a reading of the summary, not digitised contours, so treat as **estimated to ±2 points of efficiency** |
| Motor bearing drag | 0.2% of peak torque | **Estimated** |
| Regen command | Throttle 0 = none, -100 = the full torque envelope | Behaviour: regen only on a negative throttle, no lift-off regen. For scale, Nissan's e-Pedal (0.2 g on the 2018 LEAF [e-Pedal]) works out at 0.2·9.81·1,700 kg·0.323 m / 8.19 final drive = 131 N·m, about -40 on a 320 N·m motor |
| Regen low-speed fade | 5% of top speed | **Estimated**. The fade speed is where the fitted losses equal the recovered power at regen torque, so below it regen would drain the battery. Real EVs blend in friction brakes there |
| Regen charge limit | the linked battery's CC-CV charge acceptance (`ENT:ChargeAcceptW`) | See Batteries below. The limit is applied to the power reaching the battery; the torque is scaled down linearly when it is exceeded (`Engine.GeneratorLimit`) |
| Direction (Reverse input) | +1 / −1; the inverter commands torque in the selected direction | Behaviour of a four-quadrant drive: a motor turning against the selected direction is braked by that torque (generating, limited like regen) down through zero, then driven the other way. No reversal is instant: the rotor and the vehicle geared to it pass through standstill. Regen on a negative throttle works in either direction |
| CoolantFrac | 0.28 / 0.25 / 0.30 / 0.02 (SI / diesel / rotary / turbine) | [Heywood] table 12.1 for SI and diesel, **not re-verified**. The others are **estimated**. Motors put all of their losses (copper, inverter, core, bearings) into the engine's heat instead |
| LHV petrol (SI, rotary) | 43.3 MJ/kg (was 43.4) | **Sourced**: [EPA-TNGA] EPA test gasoline 43.31 MJ/kg |
| LHV diesel / turbine fuel | 42.6 / 42.8 MJ/kg | [Heywood] App. D, **not re-verified** |
| StallFrac, IdleAuthority | 0.35 / 0.45 SI, 0.4 / 1 diesel | **Estimated** (control behaviour, not physical data) |
| Droop governor band | +6% above limit | **Estimated** |
| IdleSpool (turbine) | 0.09 (was 0.12) | **Derived**: [GS M1] 10 gal/h basic idle = 30 kg/h JP-8 (0.80 kg/L), against 0.30 kg/kWh × 1,119 kW = 336 kg/h at full power [FI AGT1500]: 9%. The same fraction is used for every ACE turbine (**estimated** for the others) |
| Turbine fuel flow | IdleSpool..1 × full-power flow, full flow = peak power / (EtaIndicated · LHV) | Fuel follows the gas generator, not the output shaft, so a stalled output at full throttle burns full-power fuel. Linear in spool between the two sourced points is **estimated**. Peak power is now the curve's real maximum; the old formula used PeakTorque × LimitW / 2, which on the AGT1500 was 27% below the curve's power and so under-burned by the same amount |
| SpoolTime (turbine) | 1.2 s | **Estimated**, bounded by [14 CFR 33.73]: idle (9%) to 95% power takes 2.9 × 1.2 = 3.5 s, inside the 5 s allowed. [FI AGT1500] gives the gas-producer inertia (0.074 kg·m²) but no spool-up time. The discrete update uses 1 − exp(−Δt/τ), exact for any step, so it is tickrate independent (tested at 16-528 Hz) |
| Turbine friction | 1-2% of peak torque | **Estimated** |
| Idle governor gains | Ki 2.5, Kp 1.5; start integrator 0.15 / 0.2; fast-idle authority 0.6 | **Estimated** (controller tuning) |
| Start: catch speed / cranking time | 130 rpm / 3 s | [Heywood] 7.6 cranking 150-300 rpm, **not re-verified**. The 3 s is **estimated** |
| Starter: free speed / stall torque | 450 rpm / 4 × motoring torque at 0 rpm | **Estimated** |
| Rev-limiter hysteresis | 150 rpm | **Estimated** |
| Unknown displacement BMEP | 10 bar SI / 16 bar diesel | [Heywood] 2.7 typical, **not re-verified** |
| Bore = stroke when no stroke given | square engine | **Estimated** |
| CylindersByCategory Radial | 7 (was 9) | Matches ACE's own "R7" radial definitions |

## Batteries (acf_fueltank with Electric fuel)

ACE's battery is a **Li-ion (NMC-class) traction pack**, energy counted in kWh; the engine
draws battery power in watts (`State.FuelRate`, negative while regenerating) and
`ENT:MobilityApply` converts joules to kWh.

| Quantity | ACE value | Check against [Koloch 2025] |
|---|---|---|
| `ACE.LiIonED` | 0.27 kWh per litre of fill | Fill is 0.4774 of the box volume, so 129 Wh per litre of box: inside the 110-305 Wh/L pack range, at its low end |
| `ACE.FuelDensity.Electric` | 1.35 kg per litre of fill | 200 Wh/kg of fill. With the 1 mm steel walls a 20 in cube is 16.7 kWh in 96 kg = 174 Wh/kg, inside the 140-180 Wh/kg NMC pack range. Small boxes come out lower, very large ones approach 200 |

Both constants were left unchanged: they already describe a modern Li-ion pack. A lead-acid
battery (30-40 Wh/kg) would need a separate fuel type.

When every linked battery is empty the engine switches off (`ACE.EnginesRequireFuel`), like an
EV at 0% charge; regen cannot recover a flat pack because the motor is off. Regen charges the
first linked battery that accepts charge (`ENT:GetChargeTank`).

### Battery model (lua/ace/shared/mobility/battery_model.lua)

Each battery is one lumped thermal mass with resistive losses, CC-CV charging, BMS temperature
limits and wear. Wear is kept only on the entity (`BatteryState`), so a duplicated or pasted
battery is new. Heat follows `ace_heat_timescale` like engine coolant; calendar wear runs on
real time; cycle wear follows charge throughput, so it is independent of any time scale.

| Quantity | Value | Source / status |
|---|---|---|
| Resistive loss | P_loss = Loss1C · R · P² / E_nom, Loss1C = 0.03 Ω × 5 A / 3.63 V = 0.041 | **Sourced**: [LG M50] DCIR, capacity, voltage. Taken from the stored energy on discharge and from the input on charge, and heats the cells |
| Cell heat capacity | 912 J/(kg·K) on the fill mass (1.35 kg/L); housing 480 J/(kg·K) | [Steinhardt 2022] |
| Cooling | natural convection, h = 10 W/(m²·K) on the box's outer area, exact exponential step | [Incropera] range 2-25; 10 as for the engine skin, **Estimated**. A pack worked hard with no radiator stays hot for a long time |
| Liquid loop (radiators linked to the battery) | cold plate h = 300 W/(m²·K) over a third of the outer area, in series with the radiators' air side at a loop flow of 10 L/min water-glycol (583 W/K); a shared radiator is split equally between everything linked to it; its fan runs off the battery above 30 °C cells | Plate h inside the 100-1000 range for forced liquid convection [Incropera], plate share and flow (8-15 L/min EV battery pumps) **Estimated**. Coolant heat capacity left out (litres against hundreds of kg of cells). Self-test: a 16.7 kWh pack at 2C for an hour reaches 108 °C uncooled, 43 °C with a 0.15 m² core at 15 m/s |
| CC-CV acceptance | 1C constant current to 85 % charge, then C·(1 − SOC)/0.15 (the exponential CV taper) until it falls below 0.04C, where the pack reads full (99.4 %) | CC rate 1C from [BU-409] (the M50 allows 0.7C continuous, so 1C is at the generous end of a cell rating); CV point and cut-off [BU-409]. Applies to regen, to reverse braking and to Refuel Duty transfers between batteries. The taper shape is the usual first-order approximation, **Estimated** |
| Charge temperature limit | 50 °C, tapering from 45 °C | Limit [LG M50]; 5 K taper **Estimated** |
| Discharge temperature limit | 60 °C, tapering from 55 °C (motor torque × derate) | Limit [LG M50]; 5 K taper **Estimated** |
| Calendar fade and resistance growth | α·t^0.75 and α_R·t^0.75 with the [BLAST-Lite] coefficients, V from the OCV table at the pack's charge, T the cell temperature | **Sourced** [Schmalstieg 2014] / [BLAST-Lite]. Continued step by step in the equivalent-time form, so conditions may change between steps. At 25 °C a year held at 50 % costs 2.4 %, held full 4.4 %, held full at 45 °C 19 % (self-test). Above the tested 50 °C the Arrhenius term is extrapolated |
| Cycle fade and resistance growth | β·√Q and β_R·Q, Q scaled to one 2.15 Ah cell (moving the whole capacity once = 2.15 Ah), DOD = the charge swing of the current half cycle (a run of charging or of discharging), V = OCV at its mid point | **Sourced** coefficients [BLAST-Lite]. Cycle counting by half cycles is a simplification of rainflow counting, **Estimated**. 500 full cycles: 22 % fade, resistance ×1.57; the same throughput in 10 % cycles: 6 % fade (self-test). [LG M50] rates 500 C/3 cycles, and [Schmalstieg 2014]'s cells behave in the same range |
| Capacity | new capacity × (1 − calendar − cycle fade) | The Capacity wire output reports it |
| Outputs | Temperature (°C), Health (% of new capacity) | Batteries only |

Not modelled: discharge power limits by C-rate (a small battery can still feed any motor; it
only heats up doing it), cold-temperature effects (ACE's ambient is 20 °C), lithium plating,
thermal runaway, and SEI decomposition above ~80 °C (the BMS limits stop the cells from heating
themselves that far).

### Built-in radiator of the Electric-Small / -Medium / -Large motors

These models were described as having integrated batteries, which the code never modelled
(they always needed linked batteries). Their housing is much larger than the motor, and that
space is now a radiator core (`ENT:UpdateBuiltinCooler`, `ACE.EngineThermalThink`):

| Quantity | Value | Source / status |
|---|---|---|
| Core volume | housing collision volume (`PhysObj:GetVolume()`) − `motorvolume` | `motorvolume` is the collision-hull volume of the standalone motor model of the same size (emotor-standalone-sml / -mid / -big: 2,796 / 6,634 / 12,960 in³), **measured** from the .phy files. The housings measure 21,952 / 55,986 / 152,957 in³, leaving 19,156 / 49,352 / 139,997 in³ of core (314 / 809 / 2,294 L) |
| Core depth / face | depth = the housing's thinnest side; face = volume / depth | Same geometry rule as the radiator entity (face × depth = the box), **Estimated** for a housing |
| Air side | the radiator entity's model: `Thermal.RadiatorAir` at `Thermal.FaceVelocity` (ram air plus fan) | See thermal_model.lua below |
| Fan | 30 W per litre of core, drawn from the battery while the motor is on and its coolant is above 50 °C | 30 W/L as the radiator entity; 50 °C switch point **Estimated** |

The core is far larger than a motor needs, so these motors run cool at any load: the coolant
flow (`PumpC`), not the core, limits what they reject.

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

## thermal_model.lua (engine cooling)

Two thermal masses per engine, metal (Tb) and coolant (Tc), solved exactly over each step with
the conductances frozen (so the result does not depend on tickrate):

    Cb·dTb/dt = Q_in - Gbc·(Tb - Tc) - Gs·(Tb - Ta)
    Cc·dTc/dt = Gbc·(Tb - Tc) - Σ ε_i·Cmin_i·(Tc - Ta)

Q_in is `HeatRate` from engine_model.lua (fuel share plus friction), rescaled for load and speed.
Each heat exchanger (the engine's built-in cooler and every linked `ace_radiator`) gets a share
of the pump flow through the thermostat and is solved with cross-flow ε-NTU. Coolant above its
boiling point is vented as steam and held there, and film boiling cuts Gbc, so the metal heats
up; hot metal costs torque and, past the damage temperature, health.

| Constant | Value | Status |
|---|---|---|
| Coolant share of fuel energy at part load | × BMEP^-0.2 · N^-0.2 on the full-load share, total ≤ 60% of fuel | [MIT 2.61] scaling, [FSAE wiki] cap |
| Coolant volume | 0.15 L per kW rated (liquid), 0.03 (motor), 0.02 oil (turbine) | **Estimated** from [V-2] 0.16-0.25 and [Cummins QSB5.9] 0.19 L/kW; cars are lower |
| Coolant heat capacity | 3.5 kJ/(kg·K) × 1.05 kg/L (50% glycol) | [MEGlobal], not re-checked |
| Engine metal specific heat | 500 J/(kg·K) (450 motor) | **Estimated** from iron 460, steel 490, aluminium 900, oil 2,000 |
| Metal above coolant at rated heat | 25 K (40 K motor windings, 30 K turbine) | **Estimated**; [MIT 2.61] head temperatures |
| Coolant rise through the engine at rated heat | 7 K (sets pump flow ∝ rpm) | **Estimated** (usual 5-10 K design range) |
| Thermostat | opens 82 °C, fully open 95 °C | [Hella] |
| Boiling point | 120 °C (water at 2 bar abs under a ~1 bar gauge cap) | Steam tables; glycol's rise not credited |
| Film boiling | Gbc × 0.2 above boiling (3 K ramp) | **Estimated** (boiling curve past critical heat flux) |
| Engine skin | h = 10 W/(m²·K), area of a cube of mass / 800 kg/m³ | [Incropera] range, area **Estimated** |
| Radiator air side | h = 85·√(v/5) W/(m²·K), 1,200 m²/m³ of core | [Kim-Bullard 2002] exponent, [Shah-Sekulic] density, 85 **Estimated** |
| Face velocity | fan 4 m/s; ram 0.4 × speed × √(5 cm / depth); still air 0.3 m/s; fan and ram added as pressures | [Padmaraman 2021] discharge 0.75 (halved for installation, **Estimated**); fan 4 m/s from the existing 30 W/L fan power, **Estimated** |
| ε-NTU | cross-flow, both unmixed | [Padmaraman 2021] eq. 8 / [Incropera] |
| Built-in cooling | `ace_engine_builtin_cooling` (default 0.5) × kind multiplier (turbine 3) of rated heat at 100 °C / 20 °C | Gameplay setting: ACE builds may have no radiator entity |
| Built-in radiator core (Electric-Small/-Medium/-Large) | an extra heat exchanger from the housing's spare volume | See Batteries > Built-in radiator |
| Derate | from 150 °C metal (140 petrol) to ×0.6 (×0.5 petrol, ×0.5 motor) at 250 °C (200 motor) | **Estimated** shape |
| Damage | from 200 °C metal (180 motor windings), 0.5% of max health per s per 50 K | Onset [MIT 2.61] oil film limit / [IEC 60085]; rate **Estimated** |

Convars (server, archived): `ace_heat_timescale` (default 2; 1 is real time),
`ace_engine_builtin_cooling` (default 0.5), `ace_engine_overheat_damage` (default 1).
Admins can override any of them for one map from the ACE menu (Server settings > Heat); the
override is saved to `data/ace/heat/<map>.txt` and wins over the convar on that map.
`ace_heat_timescale` is global: engine coolant runs at exactly that many times real time, and
gun barrels, clutches, missile radars and unlinked radiators run at `ace_heat_timescale / 2`
times their tuned speed, so the default leaves them as they were. `ACE.ThermalTimeScale` holds
the live value. `ACE.RadiatorEff` and `ACE.RadiatorHeatCap` no longer affect engines or
radiators.

Results for a BMP-2 class engine (15.8 L diesel, 240 kW, 665 kg) from
`tests/lua/ace_engine_thermal_luajit_selftest.lua`:

| Case | Result |
|---|---|
| Heat to coolant at rated power | 323 kW (the engine model's CoolantFrac plus its friction) |
| Full load, no radiator, default built-in cooling | 120 °C after 408 s real (204 s at timescale 2) |
| Full load, no cooling at all | 120 °C after 156 s real |
| 30 min boiling at full load | metal 240 °C, torque × 0.64, −0.4% health/s |
| Full load, 0.6 m² × 10 cm radiator, standing with fan | 95 °C coolant, 120 °C metal |
| Idle warm-up to 82 °C | 30 min real (15 min at timescale 2); idles at 82 °C |
| Tickrate 16 to 128 | all checkpoints within 1 K |

## Named engines (engine definitions)

Only fields with a source were added. `weight` was **not** changed, and `torque` only where a
rev limit was brought to the real engine's (the V-2-34, Ford GAA and AVDS-1790-2): with the
real limit the old torque made far too much or too little power, so torque was set to give
the published horsepower. The last column lists published values not applied, for the
maintainers' balance decision.

| ACE id | Real engine | Added / changed | Published values not applied |
|---|---|---|---|
| 21.0-V12 | AVDS-1790-2 | displacement 29.3, cylinders 12, stroke 0.146; **idle 400 → 700** [TM 9-2815-220-24]; **torque 5,340 → 2,330**, 752 hp @ 2,400 on the AVDS curve (rated 750 hp @ 2,400) | peak torque 2,449 N·m @ 1,800 (the curve shape puts 2,330 at 1,990); dry mass 2,313 kg (ACE 1,800); rated 2,400 rpm (ACE limit 2,500, within 4%) |
| 24.8-V12 | AVDS-1790-9A(R) | displacement 29.3, cylinders 12, stroke 0.146 [RENK AVDS]; **torque 5,400 → 3,820**, **limit 2,800 → 2,400** [AVDS-9AR]: 1,210 hp @ 2,400 on the AVDS curve (rated 1,200) | dry mass 2,313 kg [RENK AVDS] (ACE 2,100); idle not found (ACE 500) |
| 27.0-V12 | AVDS-1790 1500 hp | displacement 29.3, cylinders 12, stroke 0.146 [RENK AVDS]; **torque 6,630 → 4,928**, **limit 2,800 → 2,600**, torquecurve from the published peak and 20% torque rise (idle to peak **estimated** with the AVDS rise) [AVDS-1500]: 1,500 hp @ 2,600 | dry mass 2,313 kg [RENK AVDS] (ACE 3,150); idle not found (ACE 500) |
| 47.6-V12 | MTU MB 873 Ka-501 (Leopard 2) | **new engine**: torque 4,700, displacement 47.6, cylinders 12, stroke 0.175, limit 2,600 [MB 873]; torquecurve from the two published points (idle to peak **estimated** with the AVDS rise, linear fall from 1,700 to 2,600 rpm) gives 1,103 kW @ 2,600 | dry mass not found in a primary source (ACE 2,200 kg, **estimated**); idle not published (ACE 700) |
| 16.5-V12 | V-2-34 | displacement 38.88, cylinders 12, stroke 0.18; **limit 3,500 → 1,800**; **torque 1,650 → 2,160** (513 hp @ 1,800, rated 500) [V-2] | Only two curve points are published, so it keeps the generic AVDS shape. Idle not found |
| 18.0-V8 | Ford GAA | displacement 18.03, cylinders 8, stroke 0.1524, torquecurve (GAA); **limit 3,800 → 2,800**; **torque 2,187 → 1,424** (498 hp @ 2,600, rated 500) [TM 9-1731B] | weight 667 kg with accessories (ACE 850) |
| 6.2-V6 | Detroit Diesel 6V-71 | displacement 6.98, cylinders 6, stroke 0.127 [Series 71] | it is a two-stroke **diesel**. ACE defines it as petrol, and the model has no two-stroke cycle |
| AGT 1500 Large Turbine | Honeywell AGT1500 | inertia 7.93, torquecurve (free-turbine line) [FI AGT1500], [GTW] | peak torque 5,355 N·m (ACE 6,780); 1,134 kg dry (ACE 1,250) |
| Electric-Tiny-NoBatt | 2012 Nissan LEAF motor | inertia 0.03 [Gao 2019] | 280 N·m, 80 kW, 10,400 rpm (ACE 189 N·m, 11,300 rpm) |

The desc of 1.4-B4 ("nazi insects") points at the VW Type 1 family, but no 1.4 L Type 1
existed, so nothing was applied. The 3TD entries in b4.lua are commented out.

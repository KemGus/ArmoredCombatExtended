# ACE Customs: trailer storyboard (about 75 s)

Style: the thumbnail's look. Flat ACE red (#C81E1E) title cards, white Segoe UI Bold / Bahnschrift
captions, and the faint gear motif. GMod footage fills the frame; the motion graphics sit on top as
lower-thirds, split screens and live gauges. Music is driving and percussive, with cuts on the beat.
No "BeamNG" anywhere. The tagline is **"Every part of the drivetrain is real now."**

Record before/after shots on the same map, with the same dupe and the same camera path:
- "Before" = the stock ACE Workshop version.
- "After" = ACE Customs.

Use `cl_drawhud 0` and a smooth camera (a camera tool, or a slow third-person dolly).

| # | Time | Shot (GMod footage) | Overlay / motion graphics |
|---|------|---------------------|---------------------------|
| 1 | 0-3 s | Black. Cold engine bay at night, frost on the map (`ace_ambient_temp -30`). | A red bar wipes in; the ACE logo stamps in; "Customs" types on. |
| 2 | 3-10 s | Close-up of the starter cranking: it turns slowly, fails, the battery voltage sags. | Gauges: Coolant −30 °C, Battery 12.4 → 9.8 V, "Too cold to start". |
| 3 | 10-16 s | A Rapid Preheater is linked (tool beam); its overlay reads "Heating". A time-lapse needle climbs, then the engine fires and exhaust smoke puffs. | Caption: **Engine heaters - cold starts in seconds.** A timer runs and stops at about 6 s. |
| 4 | 16-24 s | Split screen, the same car taking a tight turn on throttle. Left (before): both wheels turn the same. Right (now): the inside wheel spins up through the open diff. | Header: **BEFORE / NOW**. Each wheel gets a live RPM tag (`acfWheelRPM`). |
| 5 | 24-30 s | The same corner with Diff Lock on (straight push), then the LSD setting. | Chips: OPEN → LSD → LOCKED, with the active one in red. |
| 6 | 30-38 s | A tank pivots on the spot (neutral steer), then steers with the double diff at speed. | Caption: **Tracked steering - double diff, clutch & brake, neutral steer.** |
| 7 | 38-45 s | Manual car launch: the clutch slips, the engine stalls on a bad launch, the starter re-cranks. Then a clean launch. | A clutch-slip bar and an RPM needle; the word "STALL" flashes in red. |
| 8 | 45-51 s | An automatic truck pulling from a stop, then a kickdown shift. | Converter ratio and gear readout; **Torque converter + real automatic shifts.** |
| 9 | 51-57 s | Overheating: a heavy climb at full throttle with steam/smoke, then the radiator fan kicks in and the temperature falls. | A temperature graph line rising to red, then settling. **Radiators, fans, coolant & oil.** |
| 10 | 57-63 s | Menu capture: the engine torque/power graph, the gearbox speed-per-gear chart, and the link visualisation beams. | Cursor highlights; **Engine graphs, real ratios, link checks.** |
| 11 | 63-68 s | A fly-by with engine sound: Doppler, then a cut to first person with a muffled cabin. | A waveform strip; **Multi-bank engine sound.** |
| 12 | 68-72 s | A quick montage of four vehicles: a rock crawler, a truck on a grade, a tank, and a car. | Caption: **Realistic or Assisted - your server, your choice.** |
| 13 | 72-75 s | A hard cut to red; the thumbnail composition builds itself (gears rotate in). | "ACE Customs - on the Workshop now." |

## Before/after shot list (the core of the video)
1. **Corner exit on throttle.** Shows the open diff vs the old behaviour.
2. **Standstill on a slope.** Before, the car creeps; now the brake hold keeps it put.
3. **Coast-down off throttle.** Now engine braking slows the car.
4. **Gear change.** Now there's an RPM drop that matches the ratio, plus a clutch kick.
5. **Cold start at −20 °C.** Before, the engine started instantly; now it cranks. Then the heater fixes it.

## Overlay data sources
- Wire/E2 outputs can drive the on-screen gauges. Have a HUD E2 draw numbers so the overlays use real values, not fakes:
  - `acfWheelRPM`, `acfInputRPM`, `acfClutchSlip`, `acfCoolantTemp`, `acfConverterRatio`, `acfStalled`;
  - the heater's "Heat Output" and "Coolant Temp".
- A cleaner option is to log CSV with the flight recorder (`ace_mobility_log_*`) and animate the gauges in the editor from that data.

## Thumbnail
`ace_customs.png`: 1024×1024, 84 KB (Workshop limit is 1 MB). It uses the ACE wordmark from
`ace_logo_canary.png` and the same red and type treatment as the Canary edition.

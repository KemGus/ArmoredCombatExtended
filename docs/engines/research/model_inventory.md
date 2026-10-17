# Engine model inventory

Sources: ACE, ACF-Extra, ACF Customs (see model_inventory.json for paths).

## Counts per addon

| addon | parser defs | grep defs (line match) | unparsed | layout guessed | layout null | models unique | owned mdl | base-only mdl | missing mdl |
|---|---|---|---|---|---|---|---|---|---|
| ACE | 116 | 119 | 0 | 96 | 20 | 61 | 61 | 0 | 0 |
| ACF-Extra | 99 | 99 | 0 | 96 | 3 | 84 | 71 | 0 | 13 |
| ACF Customs | 188 | 188 | 1 | 164 | 24 | 122 | 67 | 0 | 55 |

Grep-only lines (matched by the line pattern, not parsed as an engine; normally commented-out code):

- ACE: lua/ace/shared/engines/b4.lua:80, lua/ace/shared/engines/b4.lua:95, lua/ace/shared/engines/b4.lua:110
- ACF-Extra: none
- ACF Customs: none

Base game root E:/Programs/Steam/steamapps/common/GarrysMod/garrysmod: no loose models/ folder found, so base-game lookups returned nothing; missing counts are addon-only.

Grep note: ACE: grep; ACF-Extra: grep; ACF Customs: grep

## Model clashes (same path, different md5, addon-owned)

- `models/engines/emotor-standalone-tiny.mdl`: ACE=f9b984cf; ACF Customs=01a3d1f9

Same path, same md5 in more than one addon: 62

## Engine id clashes across addons

- `0.125-I1.2`: ACF Customs, ACF-Extra
- `0.25-I1`: ACE, ACF Customs
- `0.25-I1.2`: ACF Customs, ACF-Extra
- `0.5-I1`: ACE, ACF Customs
- `0.5-I1.2`: ACF Customs, ACF-Extra
- `0.6-V2`: ACE, ACF Customs
- `0.9L-I2`: ACE, ACF Customs
- `1.0L-I4`: ACE, ACF Customs
- `1.1-I3`: ACE, ACF Customs
- `1.2-I3`: ACE, ACF Customs
- `1.2-V2`: ACE, ACF Customs
- `1.3-I1`: ACE, ACF Customs
- `1.3-I1.2`: ACF Customs, ACF-Extra
- `1.3L-R`: ACE, ACF Customs
- `1.4-B4`: ACE, ACF Customs
- `1.5-I4`: ACE, ACF Customs
- `1.6-I4`: ACE, ACF Customs
- `1.8L-V4`: ACE, ACF Customs
- `1.9L-I4`: ACE, ACF Customs
- `10.0-B6`: ACE, ACF Customs
- `11.0-I3`: ACE, ACF Customs
- `11.0-R7`: ACE, ACF Customs
- `110.2-V10HVY`: ACF Customs, ACF-Extra
- `12.0-V6`: ACE, ACF Customs
- `13.0-I12`: ACF Customs, ACF-Extra
- `13.0-V12`: ACE, ACF Customs
- `13.5-I3`: ACE, ACF Customs
- `14.0-V6-D`: ACF Customs, ACF-Extra
- `15.0-I4`: ACE, ACF Customs
- `16.0-I4`: ACE, ACF Customs
- `16.4-W16`: ACF Customs, ACF-Extra
- `17.2-I6`: ACE, ACF Customs
- `18.0-V8`: ACE, ACF Customs
- `19.0-V8`: ACE, ACF Customs
- `2.0L-R`: ACE, ACF Customs
- `2.1-B4`: ACE, ACF Customs
- `2.2-I6`: ACE, ACF Customs
- `2.3-I5`: ACE, ACF Customs
- `2.4-V2`: ACE, ACF Customs
- `2.4L-V6`: ACE, ACF Customs
- `2.6L-Wankel`: ACE, ACF Customs
- `2.8-B6`: ACE, ACF Customs
- `2.8-I3`: ACE, ACF Customs
- `2.9-I5`: ACE, ACF Customs
- `2.9-V8`: ACE, ACF Customs
- `20.0-I6`: ACE, ACF Customs
- `20.3-V10HVY`: ACF Customs, ACF-Extra
- `21.0-V12`: ACE, ACF Customs
- `22.0-V10`: ACE, ACF Customs
- `23.0-V12`: ACE, ACF Customs
- `24.0-R7`: ACE, ACF Customs
- `3.0-I6`: ACE, ACF Customs
- `3.0-V12`: ACE, ACF Customs
- `3.0-V6-D`: ACF Customs, ACF-Extra
- `3.1-I4`: ACE, ACF Customs
- `3.2-B4`: ACE, ACF Customs
- `3.4-I3`: ACE, ACF Customs
- `3.6-V6`: ACE, ACF Customs
- `3.7-I4`: ACE, ACF Customs
- `3.8-I6`: ACE, ACF Customs
- `3.8-R7`: ACE, ACF Customs
- `3.9-I5`: ACE, ACF Customs
- `30.0-I12`: ACF Customs, ACF-Extra
- `32.8-W16`: ACF Customs, ACF-Extra
- `4.0-V12`: ACE, ACF Customs
- `4.1-I5`: ACE, ACF Customs
- `4.3-V10`: ACE, ACF Customs
- `4.4-I12`: ACF Customs, ACF-Extra
- `4.5-V8`: ACE, ACF Customs
- `4.6-V12`: ACE, ACF Customs
- `4.8-I6`: ACE, ACF Customs
- `40.0-I12`: ACF Customs, ACF-Extra
- `5.0-B6`: ACE, ACF Customs
- `5.2-V6`: ACE, ACF Customs
- `5.3-V10`: ACE, ACF Customs
- `5.7-V8`: ACE, ACF Customs
- `50.8-V10HVY`: ACF Customs, ACF-Extra
- `6.0-I12`: ACF Customs, ACF-Extra
- `6.2-V6`: ACE, ACF Customs
- `6.5-I6`: ACE, ACF Customs
- `65.0-I12`: ACF Customs, ACF-Extra
- `7.0-V12`: ACE, ACF Customs
- `7.2-V8`: ACE, ACF Customs
- `7.8-V6-D`: ACF Customs, ACF-Extra
- `7.8-V8`: ACE, ACF Customs
- `8.0-V10`: ACE, ACF Customs
- `8.4-W16`: ACF Customs, ACF-Extra
- `80.0-I12`: ACF Customs, ACF-Extra
- `9.0-V8`: ACE, ACF Customs
- `9.2-V12`: ACE, ACF Customs
- `9.6-I12`: ACF Customs, ACF-Extra
- `900cc-R`: ACE, ACF Customs
- `B10-10.0`: ACF Customs, ACF-Extra
- `B10-3.8`: ACF Customs, ACF-Extra
- `B10-5.0`: ACF Customs, ACF-Extra
- `B12-17.0`: ACF Customs, ACF-Extra
- `B12-4.1`: ACF Customs, ACF-Extra
- `B12-8.0`: ACF Customs, ACF-Extra
- `B8-12.0`: ACF Customs, ACF-Extra
- `B8-3.8`: ACF Customs, ACF-Extra
- `B8-6.0`: ACF Customs, ACF-Extra
- `Electric-Large`: ACE, ACF Customs
- `Electric-Large-NoBatt`: ACE, ACF Customs
- `Electric-Medium`: ACE, ACF Customs
- `Electric-Medium-NoBatt`: ACE, ACF Customs
- `Electric-Small`: ACE, ACF Customs
- `Electric-Small-NoBatt`: ACE, ACF Customs
- `Electric-Tiny-NoBatt`: ACE, ACF Customs
- `R3-1.2`: ACF Customs, ACF-Extra
- `R3-11.0`: ACF Customs, ACF-Extra
- `R3-5.0`: ACF Customs, ACF-Extra
- `R5-19.5`: ACF Customs, ACF-Extra
- `R5-2.1`: ACF Customs, ACF-Extra
- `R5-9.3`: ACF Customs, ACF-Extra
- `R9-18.5`: ACF Customs, ACF-Extra
- `R9-36.5`: ACF Customs, ACF-Extra
- `R9-4.1`: ACF Customs, ACF-Extra
- `Turbine-Ground-Large`: ACE, ACF Customs
- `Turbine-Ground-Medium`: ACE, ACF Customs
- `Turbine-Ground-Small`: ACE, ACF Customs
- `Turbine-Large`: ACE, ACF Customs
- `Turbine-Large-Ground-Trans`: ACE, ACF Customs
- `Turbine-Large-Trans`: ACE, ACF Customs
- `Turbine-Medium`: ACE, ACF Customs
- `Turbine-Medium-Ground-Trans`: ACE, ACF Customs
- `Turbine-Medium-Trans`: ACE, ACF Customs
- `Turbine-Small`: ACE, ACF Customs
- `Turbine-Small-Ground-Trans`: ACE, ACF Customs
- `Turbine-Small-Trans`: ACE, ACF Customs
- `VR4-1.6`: ACF Customs, ACF-Extra
- `VR4-14.8`: ACF Customs, ACF-Extra
- `VR4-6.2`: ACF Customs, ACF-Extra
- `VR6-17.2`: ACF Customs, ACF-Extra
- `VR6-2.2`: ACF Customs, ACF-Extra
- `VR6-4.8`: ACF Customs, ACF-Extra
- `VR8-18.0`: ACF Customs, ACF-Extra
- `VR8-5.7`: ACF Customs, ACF-Extra
- `VR8-9.0`: ACF Customs, ACF-Extra
- `X12-18.6`: ACF Customs, ACF-Extra
- `X12-4.8`: ACF Customs, ACF-Extra
- `X12-42.9`: ACF Customs, ACF-Extra
- `X16-24.8`: ACF Customs, ACF-Extra
- `X16-57.2`: ACF Customs, ACF-Extra
- `X16-6.4`: ACF Customs, ACF-Extra
- `X20-31.0`: ACF Customs, ACF-Extra
- `X20-74.0`: ACF Customs, ACF-Extra
- `X20-8.0`: ACF Customs, ACF-Extra
- `X24-37.2`: ACF Customs, ACF-Extra
- `X24-85.8-X24`: ACF Customs, ACF-Extra
- `X24-9.6`: ACF Customs, ACF-Extra
- `X4-1.6`: ACF Customs, ACF-Extra
- `X4-1.6-2`: ACF Customs, ACF-Extra
- `X4-14.8`: ACF Customs, ACF-Extra
- `X4-6.2`: ACF Customs, ACF-Extra
- `X8-12.4`: ACF Customs, ACF-Extra
- `X8-25.6`: ACF Customs, ACF-Extra
- `X8-3.2`: ACF Customs, ACF-Extra

Duplicate ids within one addon: 8

## Unparsed (1)

- ACF Customs `Maker` lua/acf/shared/customs/enginemaker.lua:4 - required field missing or non-literal missing=['model', 'category', 'fuel', 'enginetype', 'torque', 'idlerpm', 'limitrpm'] non_literal=[]

## Engines

| id | addon | layout | cyl | model | size_mm (x y z) |
|---|---|---|---|---|---|
| 1.4-B4 | ACE | B | 4 | models/engines/b4small.mdl | 527.5x634.0x347.0 |
| 1.7-B4 | ACE | B | 4 | models/engines/b4small.mdl | 527.5x634.0x347.0 |
| 2.1-B4 | ACE | B | 4 | models/engines/b4med.mdl | 731.5x1092.2x482.6 |
| 2.4-B4 | ACE | B | 4 | models/engines/b4med.mdl | 731.5x1092.2x482.6 |
| 3.2-B4 | ACE | B | 4 | models/engines/b4med.mdl | 731.5x1092.2x482.6 |
| 5.9-B4 | ACE | B | 4 | models/engines/b4med.mdl | 731.5x1092.2x482.6 |
| 2.8-B6 | ACE | B | 6 | models/engines/b6small.mdl | 596.5x634.0x347.0 |
| 5.0-B6 | ACE | B | 6 | models/engines/b6med.mdl | 891.5x1092.2x504.6 |
| 5.4-B6 | ACE | B | 6 | models/engines/b6med.mdl | 891.5x1092.2x504.6 |
| 8.3-B6 | ACE | B | 6 | models/engines/b6med.mdl | 891.5x1092.2x504.6 |
| 10.0-B6 | ACE | B | 6 | models/engines/b6large.mdl | 1334.2x1625.6x792.3 |
| 15.8-B6 | ACE | B | 6 | models/engines/b6large.mdl | 1334.2x1625.6x792.3 |
| 20.7-B6 | ACE | B | 6 | models/engines/b6large.mdl | 1334.2x1625.6x792.3 |
| 22.9-B6 | ACE | B | 6 | models/engines/b6xlarge.mdl | 1334.2x1625.6x792.3 |
| 25.9-B6 | ACE | B | 6 | models/engines/b6huge.mdl | 1334.2x1625.6x792.3 |
| 8.9-B6 | ACE | B | 6 | models/engines/b6med.mdl | 891.5x1092.2x504.6 |
| Electric-Small | ACE | - | - | models/engines/emotorsmall.mdl | 1032.0x939.1x439.6 |
| Electric-Medium | ACE | - | - | models/engines/emotormed.mdl | 1421.2x1284.1x596.9 |
| Electric-Large | ACE | - | - | models/engines/emotorlarge.mdl | 1983.8x1794.7x834.0 |
| Electric-Tiny-NoBatt | ACE | - | - | models/engines/emotor-standalone-tiny.mdl | 480.4x378.8x335.0 |
| Electric-Small-NoBatt | ACE | - | - | models/engines/emotor-standalone-sml.mdl | 670.9x568.2x491.7 |
| Electric-Medium-NoBatt | ACE | - | - | models/engines/emotor-standalone-mid.mdl | 894.5x757.6x655.6 |
| Electric-Large-NoBatt | ACE | - | - | models/engines/emotor-standalone-big.mdl | 1118.1x947.0x819.5 |
| 0.8L-I2 | ACE | I | 2 | models/engines/inline2s.mdl | 450.8x281.7x505.6 |
| 0.6L-I2 | ACE | I | 2 | models/engines/inline2s.mdl | 450.8x281.7x505.6 |
| 10.0-I2 | ACE | I | 2 | models/engines/inline2b.mdl | 1126.9x704.2x1264.0 |
| 1.2-I3 | ACE | I | 3 | models/engines/inline3s.mdl | 492.6x286.7x508.6 |
| 3.4-I3 | ACE | I | 3 | models/engines/inline3m.mdl | 739.0x430.0x763.0 |
| 13.5-I3 | ACE | I | 3 | models/engines/inline3b.mdl | 1231.6x716.7x1271.6 |
| 1.1-I3 | ACE | I | 3 | models/engines/inline3s.mdl | 492.6x286.7x508.6 |
| 2.8-I3 | ACE | I | 3 | models/engines/inline3m.mdl | 739.0x430.0x763.0 |
| 11.0-I3 | ACE | I | 3 | models/engines/inline3b.mdl | 1231.6x716.7x1271.6 |
| 1.5-I4 | ACE | I | 4 | models/engines/inline4s.mdl | 661.9x281.0x498.9 |
| 3.7-I4 | ACE | I | 4 | models/engines/inline4m.mdl | 992.9x421.5x748.4 |
| 16.0-I4 | ACE | I | 4 | models/engines/inline4l.mdl | 1654.8x702.5x1247.4 |
| 1.6-I4 | ACE | I | 4 | models/engines/inline4s.mdl | 661.9x281.0x498.9 |
| 3.1-I4 | ACE | I | 4 | models/engines/inline4m.mdl | 992.9x421.5x748.4 |
| 15.0-I4 | ACE | I | 4 | models/engines/inline4l.mdl | 1654.8x702.5x1247.4 |
| 2.3-I5 | ACE | I | 5 | models/engines/inline5s.mdl | 720.3x286.6x507.9 |
| 3.9-I5 | ACE | I | 5 | models/engines/inline5m.mdl | 1080.5x429.9x761.8 |
| 2.9-I5 | ACE | I | 5 | models/engines/inline5s.mdl | 720.3x286.6x507.9 |
| 4.1-I5 | ACE | I | 5 | models/engines/inline5m.mdl | 1080.5x429.9x761.8 |
| 2.2-I6 | ACE | I | 6 | models/engines/inline6s.mdl | 818.6x281.0x504.7 |
| 4.8-I6 | ACE | I | 6 | models/engines/inline6m.mdl | 1227.8x421.5x757.0 |
| 17.2-I6 | ACE | I | 6 | models/engines/inline6l.mdl | 2046.4x702.5x1261.7 |
| 3.0-I6 | ACE | I | 6 | models/engines/inline6s.mdl | 818.6x281.0x504.7 |
| 6.5-I6 | ACE | I | 6 | models/engines/inline6m.mdl | 1227.8x421.5x757.0 |
| 20.0-I6 | ACE | I | 6 | models/engines/inline6l.mdl | 2046.4x702.5x1261.7 |
| 3.8-R7 | ACE | R | 7 | models/engines/radial7s.mdl | 277.4x729.0x719.3 |
| 11.0-R7 | ACE | R | 7 | models/engines/radial7m.mdl | 367.8x972.0x957.0 |
| 24.0-R7 | ACE | R | 7 | models/engines/radial7l.mdl | 548.5x1457.9x1432.3 |
| 8.0-R7 | ACE | R | 7 | models/engines/radial7m.mdl | 367.8x972.0x957.0 |
| 900cc-R | ACE | Wankel | - | models/engines/wankel_2_small.mdl | 373.0x351.2x374.1 |
| 1.3L-R | ACE | Wankel | - | models/engines/wankel_2_med.mdl | 481.1x452.7x482.5 |
| 2.0L-R | ACE | Wankel | - | models/engines/wankel_3_med.mdl | 615.4x452.7x482.5 |
| 2.6L-Wankel | ACE | Wankel | - | models/engines/wankel_4_med.mdl | 751.6x452.7x482.5 |
| 0.25-I1 | ACE | I | 1 | models/engines/1cylsml.mdl | 507.2x284.0x487.4 |
| 0.5-I1 | ACE | I | 1 | models/engines/1cylmed.mdl | 702.2x393.2x672.4 |
| 1.3-I1 | ACE | I | 1 | models/engines/1cylbig.mdl | 897.3x502.5x857.4 |
| 0.9L-I2 | ACE | I | 2 | models/engines/inline2s.mdl | 450.8x281.7x505.6 |
| 1.0L-I4 | ACE | I | 4 | models/engines/inline4s.mdl | 661.9x281.0x498.9 |
| 1.8L-V4 | ACE | V | 4 | models/engines/v4s.mdl | 543.8x611.0x830.9 |
| 1.9L-I4 | ACE | I | 4 | models/engines/inline4s.mdl | 661.9x281.0x498.9 |
| 2.4L-V6 | ACE | V | 6 | models/engines/v6small.mdl | 606.9x610.5x793.6 |
| 2.9-V8 | ACE | V | 8 | models/engines/v8s.mdl | 740.7x611.0x830.9 |
| 3.8-I6 | ACE | I | 6 | models/engines/inline6m.mdl | 1227.8x421.5x757.0 |
| 7.2-V8 | ACE | V | 8 | models/engines/v8m.mdl | 924.3x763.8x1038.6 |
| 5.3-V10 | ACE | V | 10 | models/engines/v10sml.mdl | 834.6x610.5x827.7 |
| 2.4-V10 | ACE | V | 10 | models/engines/v10sml.mdl | 834.6x610.5x827.7 |
| 3.0-V12 | ACE | V | 12 | models/engines/v12s.mdl | 963.3x611.0x830.9 |
| 25.0-V12-Racing | ACE | V | 12 | models/engines/v12l.mdl | 1805.1x1148.5x1561.8 |
| Turbine-Small-Trans | ACE | - | - | models/engines/turbine_s.mdl | 1183.8x371.4x368.0 |
| Turbine-Medium-Trans | ACE | - | - | models/engines/turbine_m.mdl | 1772.6x554.0x545.6 |
| Turbine-Large-Trans | ACE | - | - | models/engines/turbine_l.mdl | 2361.3x736.5x723.2 |
| Turbine-Small | ACE | - | - | models/engines/gasturbine_s.mdl | 1187.5x482.6x635.6 |
| Turbine-Medium | ACE | - | - | models/engines/gasturbine_m.mdl | 1778.0x723.9x950.3 |
| Turbine-Large | ACE | - | - | models/engines/gasturbine_l.mdl | 2368.6x965.2x1265.0 |
| Turbine-Ground-Small | ACE | - | - | models/engines/gasturbine_s.mdl | 1187.5x482.6x635.6 |
| Turbine-Ground-Medium | ACE | - | - | models/engines/gasturbine_m.mdl | 1778.0x723.9x950.3 |
| Turbine-Ground-Large | ACE | - | - | models/engines/gasturbine_l.mdl | 2368.6x965.2x1265.0 |
| Turbine-Small-Ground-Trans | ACE | - | - | models/engines/turbine_s.mdl | 1183.8x371.4x368.0 |
| Turbine-Medium-Ground-Trans | ACE | - | - | models/engines/turbine_m.mdl | 1772.6x554.0x545.6 |
| Turbine-Large-Ground-Trans | ACE | - | - | models/engines/turbine_l.mdl | 2361.3x736.5x723.2 |
| AGT 1500 Large Turbine | ACE | - | - | models/engines/gasturbine_l.mdl | 2368.6x965.2x1265.0 |
| 4.3-V10 | ACE | V | 10 | models/engines/v10sml.mdl | 834.6x610.5x827.7 |
| 8.0-V10 | ACE | V | 10 | models/engines/v10med.mdl | 1041.7x760.0x1034.7 |
| 22.0-V10 | ACE | V | 10 | models/engines/v10big.mdl | 1563.2x1136.5x1555.9 |
| 23.0-V10 | ACE | V | 10 | models/engines/v10big.mdl | 1563.2x1136.5x1555.9 |
| 4.6-V12 | ACE | V | 12 | models/engines/v12s.mdl | 963.3x611.0x830.9 |
| 7.0-V12 | ACE | V | 12 | models/engines/v12s.mdl | 963.3x611.0x830.9 |
| 23.0-V12 | ACE | V | 12 | models/engines/v12l.mdl | 1805.1x1148.5x1561.8 |
| 25.0-V12 | ACE | V | 12 | models/engines/v12l.mdl | 1805.1x1148.5x1561.8 |
| 4.0-V12 | ACE | V | 12 | models/engines/v12s.mdl | 963.3x611.0x830.9 |
| 9.2-V12 | ACE | V | 12 | models/engines/v12m.mdl | 1202.5x763.8x1038.6 |
| 21.0-V12 | ACE | V | 12 | models/engines/v12l.mdl | 1805.1x1148.5x1561.8 |
| 13.0-V12 | ACE | V | 12 | models/engines/v12m.mdl | 1202.5x763.8x1038.6 |
| 16.5-V12 | ACE | V | 12 | models/engines/v8l.mdl | 1386.7x1148.5x1561.8 |
| 24.8-V12 | ACE | V | 12 | models/engines/v12l.mdl | 1805.1x1148.5x1561.8 |
| 27.0-V12 | ACE | V | 12 | models/engines/v12lbig.mdl | 1805.2x1148.5x1561.8 |
| 47.6-V12 | ACE | V | 12 | models/engines/v12lbig.mdl | 1805.2x1148.5x1561.8 |
| 0.6-V2 | ACE | V | 2 | models/engines/v-twins2.mdl | 323.9x571.5x510.6 |
| 1.2-V2 | ACE | V | 2 | models/engines/v-twinm2.mdl | 431.8x762.0x680.8 |
| 2.4-V2 | ACE | V | 2 | models/engines/v-twinl2.mdl | 539.8x952.5x851.0 |
| 1.9L-V4 | ACE | V | 4 | models/engines/v4s.mdl | 543.8x611.0x830.9 |
| 3.3L-V4 | ACE | V | 4 | models/engines/v4m.mdl | 678.1x763.8x1038.6 |
| 3.6-V6 | ACE | V | 6 | models/engines/v6small.mdl | 606.9x610.5x793.6 |
| 6.2-V6 | ACE | V | 6 | models/engines/v6med.mdl | 757.0x760.0x992.0 |
| 5.2-V6 | ACE | V | 6 | models/engines/v6med.mdl | 757.0x760.0x992.0 |
| 12.0-V6 | ACE | V | 6 | models/engines/v6large.mdl | 1135.2x1136.5x1491.7 |
| 15.0-V6 | ACE | V | 6 | models/engines/v6large.mdl | 1135.2x1136.5x1491.7 |
| 5.7-V8 | ACE | V | 8 | models/engines/v8s.mdl | 740.7x611.0x830.9 |
| 9.0-V8 | ACE | V | 8 | models/engines/v8m.mdl | 924.3x763.8x1038.6 |
| 18.0-V8 | ACE | V | 8 | models/engines/v8l.mdl | 1386.7x1148.5x1561.8 |
| 4.5-V8 | ACE | V | 8 | models/engines/v8s.mdl | 740.7x611.0x830.9 |
| 7.8-V8 | ACE | V | 8 | models/engines/v8m.mdl | 924.3x763.8x1038.6 |
| 19.0-V8 | ACE | V | 8 | models/engines/v8l.mdl | 1386.7x1148.5x1561.8 |
| B10-3.8 | ACF-Extra | B | 10 | models/engines/b10small.mdl | 959.1x787.2x404.8 |
| B10-5.0 | ACF-Extra | B | 10 | models/engines/b10medium.mdl | 1133.5x928.1x476.1 |
| B10-10.0 | ACF-Extra | B | 10 | models/engines/b10large.mdl | 1743.8x1421.0x727.0 |
| B12-4.1 | ACF-Extra | B | 12 | models/engines/b12small.mdl | 1088.6x787.2x401.1 |
| B12-8.0 | ACF-Extra | B | 12 | models/engines/b12medium.mdl | 1286.5x928.1x471.8 |
| B12-17.0 | ACF-Extra | B | 12 | models/engines/b12large.mdl | 1979.2x1421.0x722.1 |
| B2-1.2 | ACF-Extra | B | 2 | models/engines/b2s.mdl | 420.9x656.6x533.7 |
| B2-2.3 | ACF-Extra | B | 2 | models/engines/b2m.mdl | 559.0x875.5x711.6 |
| B2-4.6 | ACF-Extra | B | 2 | models/engines/b2l.mdl | 835.4x1313.2x1067.4 |
| B8-3.8 | ACF-Extra | B | 8 | models/engines/b8small.mdl | 830.5x787.2x411.1 |
| B8-6.0 | ACF-Extra | B | 8 | models/engines/b8medium.mdl | 980.3x928.1x483.5 |
| B8-12.0 | ACF-Extra | B | 8 | models/engines/b8large.mdl | 1507.8x1421.0x737.3 |
| 4.4-I12 | ACF-Extra | I | 12 | models/engines/inline12s.mdl | 1641.3x316.1x557.0 |
| 9.6-I12 | ACF-Extra | I | 12 | models/engines/inline12m.mdl | 2186.3x421.5x740.6 |
| 30.0-I12 | ACF-Extra | I | 12 | models/engines/inline12b.mdl | 2731.2x526.9x924.2 |
| 65.0-I12 | ACF-Extra | I | 12 | models/engines/inline12h.mdl | 4366.2x843.0x1474.9 |
| 6.0-I12 | ACF-Extra | I | 12 | models/engines/inline12s.mdl | 1641.3x316.1x557.0 |
| 13.0-I12 | ACF-Extra | I | 12 | models/engines/inline12m.mdl | 2186.3x421.5x740.6 |
| 40.0-I12 | ACF-Extra | I | 12 | models/engines/inline12b.mdl | 2731.2x526.9x924.2 |
| 80.0-I12 | ACF-Extra | I | 12 | models/engines/inline12h.mdl | 4366.2x843.0x1474.9 |
| 2.6-I2 | ACF-Extra | I | 2 | models/engines/inline2m.mdl | - |
| 0.7-I2 | ACF-Extra | I | 2 | models/engines/inline2s.mdl | - |
| 1.8-I2 | ACF-Extra | I | 2 | models/engines/inline2m.mdl | - |
| 7.3-I2 | ACF-Extra | I | 2 | models/engines/inline2b.mdl | - |
| 2.6-I2 | ACF-Extra | I | 2 | models/engines/inline2m.mdl | - |
| 0.7-I2 | ACF-Extra | I | 2 | models/engines/inline2s.mdl | - |
| 1.8-I2 | ACF-Extra | I | 2 | models/engines/inline2m.mdl | - |
| 1.9-I4 | ACF-Extra | I | 4 | models/engines/inline4s.mdl | - |
| 7.3-I2 | ACF-Extra | I | 2 | models/engines/inline2b.mdl | - |
| 3.4-I8 | ACF-Extra | I | 8 | models/engines/i8sml.mdl | 1326.9x374.4x510.2 |
| 5.6-I8 | ACF-Extra | I | 8 | models/engines/i8med.mdl | 1952.4x551.7x748.9 |
| 9.0-I8 | ACF-Extra | I | 8 | models/engines/i8lrg.mdl | 3064.4x867.0x1173.2 |
| 4.0-I8 | ACF-Extra | I | 8 | models/engines/i8sml.mdl | 1326.9x374.4x510.2 |
| 6.0-I8 | ACF-Extra | I | 8 | models/engines/i8med.mdl | 1952.4x551.7x748.9 |
| 11.0-I8 | ACF-Extra | I | 8 | models/engines/i8lrg.mdl | 3064.4x867.0x1173.2 |
| Pulsejet-Small | ACF-Extra | - | - | models/engines/pulsejets.mdl | 1963.4x408.8x353.6 |
| Pulsejet-Medium | ACF-Extra | - | - | models/engines/pulsejetm.mdl | 3268.1x681.4x585.0 |
| Pulsejet-Large | ACF-Extra | - | - | models/engines/pulsejetl.mdl | 4901.2x1022.0x874.4 |
| R3-1.2 | ACF-Extra | R | 3 | models/engines/radial3s.mdl | 250.5x724.3x660.3 |
| R3-5.0 | ACF-Extra | R | 3 | models/engines/radial3m.mdl | 331.9x961.5x880.4 |
| R3-11.0 | ACF-Extra | R | 3 | models/engines/radial3b.mdl | 494.7x1435.9x1320.5 |
| R5-2.1 | ACF-Extra | R | 5 | models/engines/radial5s.mdl | 237.9x773.7x759.1 |
| R5-9.3 | ACF-Extra | R | 5 | models/engines/radial5m.mdl | 317.2x1031.6x1010.0 |
| R5-19.5 | ACF-Extra | R | 5 | models/engines/radial5b.mdl | 475.8x1547.3x1511.8 |
| R9-4.1 | ACF-Extra | R | 9 | models/engines/radial9s.mdl | 253.8x744.7x752.5 |
| R9-18.5 | ACF-Extra | R | 9 | models/engines/radial9m.mdl | 336.3x988.7x1001.2 |
| R9-36.5 | ACF-Extra | R | 9 | models/engines/radial9b.mdl | 501.2x1477.7x1498.6 |
| 0.125-I1.2 | ACF-Extra | I | 1 | models/engines/1cyltiny.mdl | 333.4x174.8x302.8 |
| 0.25-I1.2 | ACF-Extra | I | 1 | models/engines/1cyls.mdl | 400.3x508.0x547.1 |
| 0.5-I1.2 | ACF-Extra | I | 1 | models/engines/1cylm.mdl | 478.0x762.0x660.4 |
| 1.3-I1.2 | ACF-Extra | I | 1 | models/engines/1cylb.mdl | 560.1x863.6x863.6 |
| 0.3-I1D | ACF-Extra | I | 1 | models/engines/1cylsml.mdl | - |
| 0.5-I1D | ACF-Extra | I | 1 | models/engines/1cylmed.mdl | - |
| 1.3-I1D | ACF-Extra | I | 1 | models/engines/1cylbig.mdl | - |
| 0.3-I1D2 | ACF-Extra | I | 1 | models/engines/1cyls.mdl | 400.3x508.0x547.1 |
| 0.5-I1D2 | ACF-Extra | I | 1 | models/engines/1cylm.mdl | 478.0x762.0x660.4 |
| 1.3-I1D2 | ACF-Extra | I | 1 | models/engines/1cylb.mdl | 560.1x863.6x863.6 |
| 20.3-V10HVY | ACF-Extra | V | 10 | models/engines/v10hvys.mdl | 2156.9x1539.4x1339.7 |
| 50.8-V10HVY | ACF-Extra | V | 10 | models/engines/v10hvym.mdl | 2873.7x2052.6x1785.7 |
| 110.2-V10HVY | ACF-Extra | V | 10 | models/engines/v10hvyb.mdl | 4307.4x3078.9x2678.5 |
| 0.8-V2 | ACF-Extra | V | 2 | models/engines/v-twins2.mdl | - |
| 1.6-V2 | ACF-Extra | V | 2 | models/engines/v-twinm2.mdl | - |
| 3.2-V2 | ACF-Extra | V | 2 | models/engines/v-twinl2.mdl | - |
| 14.0-V6-D | ACF-Extra | V | 6 | models/engines/v6large.mdl | - |
| 7.8-V6-D | ACF-Extra | V | 6 | models/engines/v6med.mdl | - |
| 3.0-V6-D | ACF-Extra | V | 6 | models/engines/v6small.mdl | - |
| VR4-1.6 | ACF-Extra | VR | 4 | models/engines/vr4s.mdl | 452.6x450.0x479.0 |
| VR4-6.2 | ACF-Extra | VR | 4 | models/engines/vr4m.mdl | 602.4x600.0x636.6 |
| VR4-14.8 | ACF-Extra | VR | 4 | models/engines/vr4b.mdl | 1054.1x1049.9x1109.3 |
| VR6-2.2 | ACF-Extra | VR | 6 | models/engines/vr6s.mdl | 589.1x420.9x482.9 |
| VR6-4.8 | ACF-Extra | VR | 6 | models/engines/vr6m.mdl | 784.3x561.2x641.7 |
| VR6-17.2 | ACF-Extra | VR | 6 | models/engines/vr6b.mdl | 1372.6x982.0x1118.3 |
| VR8-5.7 | ACF-Extra | VR | 8 | models/engines/vr8s.mdl | 709.8x424.3x497.0 |
| VR8-9.0 | ACF-Extra | VR | 8 | models/engines/vr8m.mdl | 945.2x565.7x660.6 |
| VR8-18.0 | ACF-Extra | VR | 8 | models/engines/vr8b.mdl | 1654.2x990.0x1151.2 |
| 8.4-W16 | ACF-Extra | W | 16 | models/engines/w16s.mdl | 1216.0x860.3x705.2 |
| 16.4-W16 | ACF-Extra | W | 16 | models/engines/w16m.mdl | 1621.4x1145.0x936.0 |
| 32.8-W16 | ACF-Extra | W | 16 | models/engines/w16b.mdl | 2432.1x1714.3x1397.6 |
| X12-4.8 | ACF-Extra | X | 12 | models/engines/x12s.mdl | 829.0x709.1x651.6 |
| X12-18.6 | ACF-Extra | X | 12 | models/engines/x12m.mdl | 1103.2x945.5x864.6 |
| X12-42.9 | ACF-Extra | X | 12 | models/engines/x12b.mdl | 1651.6x1418.2x1290.5 |
| X16-6.4 | ACF-Extra | X | 16 | models/engines/x16s.mdl | 1057.6x709.1x651.6 |
| X16-24.8 | ACF-Extra | X | 16 | models/engines/x16m.mdl | 1408.0x945.5x864.6 |
| X16-57.2 | ACF-Extra | X | 16 | models/engines/x16b.mdl | 2108.8x1418.2x1290.5 |
| X20-8.0 | ACF-Extra | X | 20 | models/engines/x20s.mdl | 1286.2x709.1x651.6 |
| X20-31.0 | ACF-Extra | X | 20 | models/engines/x20m.mdl | 1712.8x945.5x864.6 |
| X20-74.0 | ACF-Extra | X | 20 | models/engines/x20b.mdl | 2566.0x1418.2x1290.5 |
| X24-9.6 | ACF-Extra | X | 24 | models/engines/x24s.mdl | 1514.8x709.4x651.6 |
| X24-37.2 | ACF-Extra | X | 24 | models/engines/x24m.mdl | 2017.6x945.9x864.6 |
| X24-85.8-X24 | ACF-Extra | X | 24 | models/engines/x24b.mdl | 3023.2x1418.9x1290.5 |
| X4-1.6 | ACF-Extra | X | 4 | models/engines/xs.mdl | 260.4x563.6x545.6 |
| X4-6.2 | ACF-Extra | X | 4 | models/engines/xm.mdl | 347.2x751.5x725.3 |
| X4-14.8 | ACF-Extra | X | 4 | models/engines/xb.mdl | 520.8x1127.3x1086.5 |
| X4-1.6-2 | ACF-Extra | X | 4 | models/engines/x4s2.mdl | 373.4x709.1x651.6 |
| X4-6.2 | ACF-Extra | X | 4 | models/engines/x4m2.mdl | 495.4x945.5x864.6 |
| X4-14.8 | ACF-Extra | X | 4 | models/engines/x4b2.mdl | 740.0x1418.2x1290.5 |
| X8-3.2 | ACF-Extra | X | 8 | models/engines/x8s.mdl | 629.5x709.1x651.6 |
| X8-12.4 | ACF-Extra | X | 8 | models/engines/x8m.mdl | 837.1x945.5x864.6 |
| X8-25.6 | ACF-Extra | X | 8 | models/engines/x8b.mdl | 1252.5x1418.2x1290.5 |
| 1.6-I4R | ACF Customs | I | 4 | models/engines/inline4s.mdl | - |
| 1.6-I4R2 | ACF Customs | I | 4 | models/engines/inline4s.mdl | - |
| 2.0-I4R | ACF Customs | I | 4 | models/engines/inline4s.mdl | - |
| 2.0-I4R2 | ACF Customs | I | 4 | models/engines/inline4s.mdl | - |
| 2.2-I4R | ACF Customs | I | 4 | models/engines/inline4s.mdl | - |
| 1.0-I4R2 | ACF Customs | I | 4 | models/engines/inline4s.mdl | - |
| 1.1-I4R2 | ACF Customs | I | 4 | models/engines/inline4s.mdl | - |
| 1.6-I4R3 | ACF Customs | I | 4 | models/engines/inline4s.mdl | - |
| 1.4-I4R3 | ACF Customs | I | 4 | models/engines/inline4s.mdl | - |
| 1.8-I4R3 | ACF Customs | I | 4 | models/engines/inline4s.mdl | - |
| 6.6-I6 | ACF Customs | I | 6 | models/engines/inline6m.mdl | - |
| 6.3-I62 | ACF Customs | I | 62 | models/engines/inline6s.mdl | - |
| 4.1-I62 | ACF Customs | I | 62 | models/engines/inline6s.mdl | - |
| 3.2-V62 | ACF Customs | V | 62 | models/engines/v6small.mdl | - |
| 5.8LS-V8 | ACF Customs | V | 8 | models/engines/v8s.mdl | - |
| 5.4-V8 | ACF Customs | V | 8 | models/engines/v8s.mdl | - |
| 5.6ford-V8 | ACF Customs | V | 8 | models/engines/v8s.mdl | - |
| 6.0heavy-V8 | ACF Customs | V | 8 | models/engines/v8s.mdl | - |
| 5.3f1-V8 | ACF Customs | V | 8 | models/engines/v8s.mdl | - |
| 6.5-V12C | ACF Customs | V | 12 | models/engines/v12s.mdl | - |
| 4.8-V122 | ACF Customs | V | 12 | models/engines/v12s.mdl | - |
| 5.4-V122 | ACF Customs | V | 12 | models/engines/v12s.mdl | - |
| 5.6-V122 | ACF Customs | V | 12 | models/engines/v12s.mdl | - |
| 1.2-I2R2 | ACF Customs | I | 2 | models/engines/v-twinb.mdl | 556.7x863.6x869.9 |
| Maker | ACF Customs | - | - | - | - |
| B10-3.8 | ACF Customs | B | 10 | models/engines/b10small.mdl | 959.1x787.2x404.8 |
| B10-5.0 | ACF Customs | B | 10 | models/engines/b10medium.mdl | 1133.5x928.1x476.1 |
| B10-10.0 | ACF Customs | B | 10 | models/engines/b10large.mdl | 1743.8x1421.0x727.0 |
| B12-4.1 | ACF Customs | B | 12 | models/engines/b12small.mdl | 1088.6x787.2x401.1 |
| B12-8.0 | ACF Customs | B | 12 | models/engines/b12medium.mdl | 1286.5x928.1x471.8 |
| B12-17.0 | ACF Customs | B | 12 | models/engines/b12large.mdl | 1979.2x1421.0x722.1 |
| B8-3.8 | ACF Customs | B | 8 | models/engines/b8small.mdl | 830.5x787.2x411.1 |
| B8-6.0 | ACF Customs | B | 8 | models/engines/b8medium.mdl | 980.3x928.1x483.5 |
| B8-12.0 | ACF Customs | B | 8 | models/engines/b8large.mdl | 1507.8x1421.0x737.3 |
| 4.4-I12 | ACF Customs | I | 12 | models/engines/inline12s.mdl | 1641.3x316.1x557.0 |
| 9.6-I12 | ACF Customs | I | 12 | models/engines/inline12m.mdl | 2186.3x421.5x740.6 |
| 30.0-I12 | ACF Customs | I | 12 | models/engines/inline12b.mdl | 2731.2x526.9x924.2 |
| 65.0-I12 | ACF Customs | I | 12 | models/engines/inline12h.mdl | 4366.2x843.0x1474.9 |
| 6.0-I12 | ACF Customs | I | 12 | models/engines/inline12s.mdl | 1641.3x316.1x557.0 |
| 13.0-I12 | ACF Customs | I | 12 | models/engines/inline12m.mdl | 2186.3x421.5x740.6 |
| 40.0-I12 | ACF Customs | I | 12 | models/engines/inline12b.mdl | 2731.2x526.9x924.2 |
| 80.0-I12 | ACF Customs | I | 12 | models/engines/inline12h.mdl | 4366.2x843.0x1474.9 |
| R3-1.2 | ACF Customs | R | 3 | models/engines/radial3s.mdl | 250.5x724.3x660.3 |
| R3-5.0 | ACF Customs | R | 3 | models/engines/radial3m.mdl | 331.9x961.5x880.4 |
| R3-11.0 | ACF Customs | R | 3 | models/engines/radial3b.mdl | 494.7x1435.9x1320.5 |
| R5-2.1 | ACF Customs | R | 5 | models/engines/radial5s.mdl | 237.9x773.7x759.1 |
| R5-9.3 | ACF Customs | R | 5 | models/engines/radial5m.mdl | 317.2x1031.6x1010.0 |
| R5-19.5 | ACF Customs | R | 5 | models/engines/radial5b.mdl | 475.8x1547.3x1511.8 |
| R9-4.1 | ACF Customs | R | 9 | models/engines/radial9s.mdl | 253.8x744.7x752.5 |
| R9-18.5 | ACF Customs | R | 9 | models/engines/radial9m.mdl | 336.3x988.7x1001.2 |
| R9-36.5 | ACF Customs | R | 9 | models/engines/radial9b.mdl | 501.2x1477.7x1498.6 |
| 0.125-I1.2 | ACF Customs | I | 1 | models/engines/1cyltiny.mdl | 333.4x174.8x302.8 |
| 0.25-I1.2 | ACF Customs | I | 1 | models/engines/1cyls.mdl | 400.3x508.0x547.1 |
| 0.5-I1.2 | ACF Customs | I | 1 | models/engines/1cylm.mdl | 478.0x762.0x660.4 |
| 1.3-I1.2 | ACF Customs | I | 1 | models/engines/1cylb.mdl | 560.1x863.6x863.6 |
| 20.3-V10HVY | ACF Customs | V | 10 | models/engines/v10hvys.mdl | 2156.9x1539.4x1339.7 |
| 50.8-V10HVY | ACF Customs | V | 10 | models/engines/v10hvym.mdl | 2873.7x2052.6x1785.7 |
| 110.2-V10HVY | ACF Customs | V | 10 | models/engines/v10hvyb.mdl | 4307.4x3078.9x2678.5 |
| 14.0-V6-D | ACF Customs | V | 6 | models/engines/v6large.mdl | - |
| 7.8-V6-D | ACF Customs | V | 6 | models/engines/v6med.mdl | - |
| 3.0-V6-D | ACF Customs | V | 6 | models/engines/v6small.mdl | - |
| VR4-1.6 | ACF Customs | VR | 4 | models/engines/vr4s.mdl | 452.6x450.0x479.0 |
| VR4-6.2 | ACF Customs | VR | 4 | models/engines/vr4m.mdl | 602.4x600.0x636.6 |
| VR4-14.8 | ACF Customs | VR | 4 | models/engines/vr4b.mdl | 1054.1x1049.9x1109.3 |
| VR6-2.2 | ACF Customs | VR | 6 | models/engines/vr6s.mdl | 589.1x420.9x482.9 |
| VR6-4.8 | ACF Customs | VR | 6 | models/engines/vr6m.mdl | 784.3x561.2x641.7 |
| VR6-17.2 | ACF Customs | VR | 6 | models/engines/vr6b.mdl | 1372.6x982.0x1118.3 |
| VR8-5.7 | ACF Customs | VR | 8 | models/engines/vr8s.mdl | 709.8x424.3x497.0 |
| VR8-9.0 | ACF Customs | VR | 8 | models/engines/vr8m.mdl | 945.2x565.7x660.6 |
| VR8-18.0 | ACF Customs | VR | 8 | models/engines/vr8b.mdl | 1654.2x990.0x1151.2 |
| 8.4-W16 | ACF Customs | W | 16 | models/engines/w16s.mdl | 1216.0x860.3x705.2 |
| 16.4-W16 | ACF Customs | W | 16 | models/engines/w16m.mdl | 1621.4x1145.0x936.0 |
| 32.8-W16 | ACF Customs | W | 16 | models/engines/w16b.mdl | 2432.1x1714.3x1397.6 |
| X12-4.8 | ACF Customs | X | 12 | models/engines/x12s.mdl | 829.0x709.1x651.6 |
| X12-18.6 | ACF Customs | X | 12 | models/engines/x12m.mdl | 1103.2x945.5x864.6 |
| X12-42.9 | ACF Customs | X | 12 | models/engines/x12b.mdl | 1651.6x1418.2x1290.5 |
| X16-6.4 | ACF Customs | X | 16 | models/engines/X16s.mdl | 1057.6x709.1x651.6 |
| X16-24.8 | ACF Customs | X | 16 | models/engines/X16m.mdl | 1408.0x945.5x864.6 |
| X16-57.2 | ACF Customs | X | 16 | models/engines/X16b.mdl | 2108.8x1418.2x1290.5 |
| X20-8.0 | ACF Customs | X | 20 | models/engines/x20s.mdl | 1286.2x709.1x651.6 |
| X20-31.0 | ACF Customs | X | 20 | models/engines/x20m.mdl | 1712.8x945.5x864.6 |
| X20-74.0 | ACF Customs | X | 20 | models/engines/x20b.mdl | 2566.0x1418.2x1290.5 |
| X24-9.6 | ACF Customs | X | 24 | models/engines/x24s.mdl | 1514.8x709.4x651.6 |
| X24-37.2 | ACF Customs | X | 24 | models/engines/x24m.mdl | 2017.6x945.9x864.6 |
| X24-85.8-X24 | ACF Customs | X | 24 | models/engines/x24b.mdl | 3023.2x1418.9x1290.5 |
| X4-1.6 | ACF Customs | X | 4 | models/engines/xs.mdl | 260.4x563.6x545.6 |
| X4-6.2 | ACF Customs | X | 4 | models/engines/xm.mdl | 347.2x751.5x725.3 |
| X4-14.8 | ACF Customs | X | 4 | models/engines/xb.mdl | 520.8x1127.3x1086.5 |
| X4-1.6-2 | ACF Customs | X | 4 | models/engines/x4s2.mdl | 373.4x709.1x651.6 |
| X4-6.2 | ACF Customs | X | 4 | models/engines/x4m2.mdl | 495.4x945.5x864.6 |
| X4-14.8 | ACF Customs | X | 4 | models/engines/x4b2.mdl | 740.0x1418.2x1290.5 |
| X8-3.2 | ACF Customs | X | 8 | models/engines/x8s.mdl | 629.5x709.1x651.6 |
| X8-12.4 | ACF Customs | X | 8 | models/engines/x8m.mdl | 837.1x945.5x864.6 |
| X8-25.6 | ACF Customs | X | 8 | models/engines/x8b.mdl | 1252.5x1418.2x1290.5 |
| 1.4-B4 | ACF Customs | B | 4 | models/engines/b4small.mdl | - |
| 2.1-B4 | ACF Customs | B | 4 | models/engines/b4small.mdl | - |
| 3.2-B4 | ACF Customs | B | 4 | models/engines/b4med.mdl | - |
| 2.8-B6 | ACF Customs | B | 6 | models/engines/b6small.mdl | - |
| 5.0-B6 | ACF Customs | B | 6 | models/engines/b6med.mdl | - |
| 10.0-B6 | ACF Customs | B | 6 | models/engines/b6large.mdl | - |
| Electric-Small | ACF Customs | - | - | models/engines/emotorsmall.mdl | - |
| Electric-Medium | ACF Customs | - | - | models/engines/emotormed.mdl | - |
| Electric-Large | ACF Customs | - | - | models/engines/emotorlarge.mdl | - |
| Electric-Tiny-NoBatt | ACF Customs | - | - | models/engines/emotor-standalone-tiny.mdl | 480.4x378.8x335.0 |
| Electric-Small-NoBatt | ACF Customs | - | - | models/engines/emotor-standalone-sml.mdl | - |
| Electric-Medium-NoBatt | ACF Customs | - | - | models/engines/emotor-standalone-mid.mdl | - |
| Electric-Large-NoBatt | ACF Customs | - | - | models/engines/emotor-standalone-big.mdl | - |
| Electric-Tiny-NoBatt2 | ACF Customs | - | - | models/engines/emotor-standalone-tiny.mdl | 480.4x378.8x335.0 |
| Electric-Small-NoBatt2 | ACF Customs | - | - | models/engines/emotorsmall2.mdl | 592.5x319.7x364.5 |
| Electric-Medium-NoBatt2 | ACF Customs | - | - | models/engines/emotormed2.mdl | 992.6x535.5x608.9 |
| Electric-Large-NoBatt2 | ACF Customs | - | - | models/engines/emotorlarge2.mdl | 1374.2x741.4x846.5 |
| 1.2-I3 | ACF Customs | I | 3 | models/engines/inline3s.mdl | - |
| 3.4-I3 | ACF Customs | I | 3 | models/engines/inline3m.mdl | - |
| 13.5-I3 | ACF Customs | I | 3 | models/engines/inline3b.mdl | - |
| 1.1-I3 | ACF Customs | I | 3 | models/engines/inline3s.mdl | - |
| 2.8-I3 | ACF Customs | I | 3 | models/engines/inline3m.mdl | - |
| 11.0-I3 | ACF Customs | I | 3 | models/engines/inline3b.mdl | - |
| 1.5-I4 | ACF Customs | I | 4 | models/engines/inline4s.mdl | - |
| 3.7-I4 | ACF Customs | I | 4 | models/engines/inline4m.mdl | - |
| 16.0-I4 | ACF Customs | I | 4 | models/engines/inline4l.mdl | - |
| 1.6-I4 | ACF Customs | I | 4 | models/engines/inline4s.mdl | - |
| 3.1-I4 | ACF Customs | I | 4 | models/engines/inline4m.mdl | - |
| 15.0-I4 | ACF Customs | I | 4 | models/engines/inline4l.mdl | - |
| 2.3-I5 | ACF Customs | I | 5 | models/engines/inline5s.mdl | - |
| 3.9-I5 | ACF Customs | I | 5 | models/engines/inline5m.mdl | - |
| 2.9-I5 | ACF Customs | I | 5 | models/engines/inline5s.mdl | - |
| 4.1-I5 | ACF Customs | I | 5 | models/engines/inline5m.mdl | - |
| 2.2-I6 | ACF Customs | I | 6 | models/engines/inline6s.mdl | - |
| 4.8-I6 | ACF Customs | I | 6 | models/engines/inline6m.mdl | - |
| 17.2-I6 | ACF Customs | I | 6 | models/engines/inline6l.mdl | - |
| 3.0-I6 | ACF Customs | I | 6 | models/engines/inline6s.mdl | - |
| 6.5-I6 | ACF Customs | I | 6 | models/engines/inline6m.mdl | - |
| 20.0-I6 | ACF Customs | I | 6 | models/engines/inline6l.mdl | - |
| 3.8-R7 | ACF Customs | R | 7 | models/engines/radial7s.mdl | - |
| 11.0-R7 | ACF Customs | R | 7 | models/engines/radial7m.mdl | - |
| 24.0-R7 | ACF Customs | R | 7 | models/engines/radial7l.mdl | - |
| 900cc-R | ACF Customs | Wankel | - | models/engines/wankel_2_small.mdl | - |
| 1.3L-R | ACF Customs | Wankel | - | models/engines/wankel_2_med.mdl | - |
| 2.0L-R | ACF Customs | Wankel | - | models/engines/wankel_3_med.mdl | - |
| 0.25-I1 | ACF Customs | I | 1 | models/engines/1cylsml.mdl | - |
| 0.5-I1 | ACF Customs | I | 1 | models/engines/1cylmed.mdl | - |
| 1.3-I1 | ACF Customs | I | 1 | models/engines/1cylbig.mdl | - |
| 0.9L-I2 | ACF Customs | I | 2 | models/engines/inline2s.mdl | - |
| 1.0L-I4 | ACF Customs | I | 4 | models/engines/inline4s.mdl | - |
| 1.8L-V4 | ACF Customs | V | 4 | models/engines/v4s.mdl | - |
| 2.4L-V6 | ACF Customs | V | 6 | models/engines/v6small.mdl | - |
| 1.9L-I4 | ACF Customs | I | 4 | models/engines/inline4s.mdl | - |
| 2.6L-Wankel | ACF Customs | Wankel | - | models/engines/wankel_4_med.mdl | - |
| 2.9-V8 | ACF Customs | V | 8 | models/engines/v8s.mdl | - |
| 3.8-I6 | ACF Customs | I | 6 | models/engines/inline6m.mdl | - |
| 5.3-V10 | ACF Customs | V | 10 | models/engines/v10sml.mdl | - |
| 7.2-V8 | ACF Customs | V | 8 | models/engines/v8m.mdl | - |
| 3.0-V12 | ACF Customs | V | 12 | models/engines/v12s.mdl | - |
| Turbine-Small-Trans | ACF Customs | - | - | models/engines/turbine_s.mdl | - |
| Turbine-Medium-Trans | ACF Customs | - | - | models/engines/turbine_m.mdl | - |
| Turbine-Large-Trans | ACF Customs | - | - | models/engines/turbine_l.mdl | - |
| Turbine-Small | ACF Customs | - | - | models/engines/gasturbine_s.mdl | - |
| Turbine-Medium | ACF Customs | - | - | models/engines/gasturbine_m.mdl | - |
| Turbine-Large | ACF Customs | - | - | models/engines/gasturbine_l.mdl | - |
| Turbine-Ground-Small | ACF Customs | - | - | models/engines/gasturbine_s.mdl | - |
| Turbine-Ground-Medium | ACF Customs | - | - | models/engines/gasturbine_m.mdl | - |
| Turbine-Ground-Large | ACF Customs | - | - | models/engines/gasturbine_l.mdl | - |
| Turbine-Small-Ground-Trans | ACF Customs | - | - | models/engines/turbine_s.mdl | - |
| Turbine-Medium-Ground-Trans | ACF Customs | - | - | models/engines/turbine_m.mdl | - |
| Turbine-Large-Ground-Trans | ACF Customs | - | - | models/engines/turbine_l.mdl | - |
| 4.3-V10 | ACF Customs | V | 10 | models/engines/v10sml.mdl | - |
| 8.0-V10 | ACF Customs | V | 10 | models/engines/v10med.mdl | - |
| 22.0-V10 | ACF Customs | V | 10 | models/engines/v10big.mdl | - |
| 4.6-V12 | ACF Customs | V | 12 | models/engines/v12s.mdl | - |
| 7.0-V12 | ACF Customs | V | 12 | models/engines/v12m.mdl | - |
| 23.0-V12 | ACF Customs | V | 12 | models/engines/v12l.mdl | - |
| 4.0-V12 | ACF Customs | V | 12 | models/engines/v12s.mdl | - |
| 9.2-V12 | ACF Customs | V | 12 | models/engines/v12m.mdl | - |
| 21.0-V12 | ACF Customs | V | 12 | models/engines/v12l.mdl | - |
| 13.0-V12 | ACF Customs | V | 12 | models/engines/v12m.mdl | - |
| 0.6-V2 | ACF Customs | V | 2 | models/engines/v-twins2.mdl | - |
| 1.2-V2 | ACF Customs | V | 2 | models/engines/v-twinm2.mdl | - |
| 2.4-V2 | ACF Customs | V | 2 | models/engines/v-twinl2.mdl | - |
| 3.6-V6 | ACF Customs | V | 6 | models/engines/v6small.mdl | - |
| 6.2-V6 | ACF Customs | V | 6 | models/engines/v6med.mdl | - |
| 12.0-V6 | ACF Customs | V | 6 | models/engines/v6large.mdl | - |
| 5.2-V6 | ACF Customs | V | 6 | models/engines/v6med.mdl | - |
| 5.7-V8 | ACF Customs | V | 8 | models/engines/v8s.mdl | - |
| 9.0-V8 | ACF Customs | V | 8 | models/engines/v8m.mdl | - |
| 18.0-V8 | ACF Customs | V | 8 | models/engines/v8l.mdl | - |
| 4.5-V8 | ACF Customs | V | 8 | models/engines/v8s.mdl | - |
| 7.8-V8 | ACF Customs | V | 8 | models/engines/v8m.mdl | - |
| 19.0-V8 | ACF Customs | V | 8 | models/engines/v8l.mdl | - |

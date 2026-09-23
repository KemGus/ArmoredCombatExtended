"""Builds ACE's generic wide-open-throttle torque curves from published engine data.

Each source below is a real engine's full-load torque curve (rpm, N·m) as published or
measured, with the idle and end speeds that bound it. The curve is resampled at evenly
spaced fractions of idle -> end speed and normalised to its peak, which is the format
ACE torque curves use (lua/ace/shared/engines/ace_engine_properties.lua).

Where the published data starts above the source engine's idle, torque at idle is
extrapolated linearly from the first two published points. Sources that publish no idle
speed, or whose low-speed data cannot be extended by a straight line, start at their first
published point instead (noted per source). Full citations: docs/mobility-sources.md.

Usage: python tools/mobility_torque_curves.py  (prints the Lua tables)
"""

import math

LBFT = 1.3558179483314004  # N·m per lb·ft
RADS = 30 / math.pi         # rpm per rad/s

POINTS = 13


def _rads(speeds, torques):
    return [(w * RADS, t) for w, t in zip(speeds, torques)]


SOURCES = {
    # EPA NVFEL ALPHA map package, 2014 Mazda 2.0L SKYACTIV-G (LEV III fuel), 2018-03-29.
    # Measured WOT; idle 600 rpm (idle_speed_radps table at 0 m/s). NA DOHC I4.
    "mazda_skyactiv_2_0": {
        "idle": 600, "end": 6563,
        "data": _rads(
            [108.82476952035043, 125.25434710085122, 147.17925249755180, 167.87274877382256,
             178.02675702933431, 199.05392852532728, 209.43413999546726, 251.35882821371936,
             261.93490748224548, 303.62720474161677, 335.07905028557599, 366.46752050431354,
             387.60088309421434, 429.29928253128662, 450.25023520898026, 470.17554967926884,
             628.31853071795865, 654.49846949787354, 687.22339297276721],
            [139.16, 148.65, 156.42916666666665, 157.7466666666667, 162.5212121212121,
             182.8, 186.10512820512818, 180.67, 182.4941176470588, 196.8360655737705,
             199.2569230769231, 194.02394366197183, 193.91578947368413, 200.1111111111111,
             197.52808988764053, 198.49552238805958, 184.0, 160.0, 130.0]),
    },
    # EPA NVFEL ALPHA map package, 2014 Chevrolet 4.3L EcoTec3 LV3 (Tier 2 fuel), 2018-08.
    # WOT curve is GM's published curve quoted in the package (lb·ft); idle 560 rpm.
    # NA pushrod V6 of the Gen V small-block family.
    "gm_lv3_4_3": {
        "idle": 560, "end": 5500,
        "data": [(r, t * LBFT) for r, t in zip(
            [800, 1000, 1600, 2000, 2400, 3200, 3600, 3900, 4400, 5100, 5300, 5500],
            [200, 225, 242, 265, 280, 285, 300, 305, 300, 290, 281, 270])],
    },
    # TM 9-1731B (War Department, 1945), fig. 10 "Engine Power Curve", Ford GAA 18.0 L V8.
    # Digitised from the chart; cross-checks: 1,050 lb·ft @ 2,200 (data table) and
    # 500 hp @ 2,600 -> 1,010 lb·ft. The chart starts at 1,000 rpm; idle is not published.
    "ford_gaa": {
        "idle": 1000, "end": 2800,
        "data": [(r, t * LBFT) for r, t in zip(
            [1000, 1200, 1400, 1600, 1800, 2000, 2200, 2400, 2600, 2800],
            [953, 979, 1003, 1022, 1035, 1045, 1049, 1040, 1013, 971])],
    },
    # RENK America AVDS-1790-2CAU data sheet (2023), gross torque chart, 2CAU (588 kW)
    # curve digitised 1,400-2,400 rpm. Idle 700 rpm from TM 9-2815-220-24 (675-725 rpm).
    "avds_1790_2cau": {
        "idle": 700, "end": 2400,
        "data": [(1400, 2130), (1500, 2286), (1600, 2386), (1700, 2458), (1800, 2506),
                 (1900, 2534), (2000, 2530), (2100, 2494), (2200, 2474), (2300, 2430),
                 (2400, 2378)],
    },
    # VECTO generic engine "325kW 12.7l" (Declaration Mode Group 5 tractor), 325kW.vfld;
    # idle 600, rated 1,800 rpm (Engine_325kW_12.7l.veng).
    "vecto_325kw_12_7": {
        "idle": 600, "end": 1800,
        "data": [(600, 1188), (800, 1661), (1000, 2134), (1400, 2134), (1600, 1928),
                 (1800, 1722)],
    },
    # VECTO generic engine "175kW 6.8l" (Group 2 rigid truck), 175kW.vfld; idle 600, rated
    # 1,950 rpm (Engine_175kW_6.8l.veng).
    "vecto_175kw_6_9": {
        "idle": 600, "end": 1950,
        "data": [(600, 478), (800, 666), (1000, 852), (1200, 956), (1600, 956), (1800, 895),
                 (1950, 843.1)],
    },
    # EPA NVFEL ALPHA map package, 2015 BMW 3.0L N57 diesel, 2018-06-11. Measured WOT from
    # 1,001 rpm (idle is 550 rpm). The turbo builds boost between 1,000 and 1,250 rpm, so a
    # straight line below 1,000 rpm is meaningless; the curve starts at the first measured
    # point instead.
    "bmw_n57_3_0": {
        "idle": 1001.4, "end": 4620,
        "data": _rads(
            [104.86433278437430, 130.82390245320809, 157.03473816855254, 183.27052661186670,
             209.42579394107420, 235.64332795083516, 261.79724020641140, 287.99694180323229,
             314.23235953861331, 366.51904060760842, 392.69072150179380, 418.88403152836105,
             460.76027523060725, 483.79828899213766],
            [310.21167, 479.766724, 544.832008, 557.973755, 557.116638, 573.097412,
             575.549072, 575.240173, 564.206482, 527.557129, 480.57547, 444.791504,
             365.259705, 313.079747]),
    },
    # Kubota D1105-E3B (3000 rpm) data sheet, performance curve digitised (SAE J1995 gross
    # intermittent); 71.5 N·m @ 2,200 and 18.5 kW @ 3,000 from the table. NA IDI 3-cyl.
    # The chart starts at 1,600 rpm; idle is not published.
    "kubota_d1105": {
        "idle": 1600, "end": 3000,
        "data": [(1600, 68.0), (1800, 70.1), (2000, 71.1), (2200, 71.5), (2400, 69.7),
                 (2600, 66.9), (2800, 63.1), (3000, 58.9)],
    },
}


def _interp(data, rpm):
    if rpm <= data[0][0]:
        (r0, t0), (r1, t1) = data[0], data[1]
    elif rpm >= data[-1][0]:
        (r0, t0), (r1, t1) = data[-2], data[-1]
    else:
        for (r0, t0), (r1, t1) in zip(data, data[1:]):
            if r0 <= rpm <= r1:
                break
    return t0 + (t1 - t0) * (rpm - r0) / (r1 - r0)


def resample(name, points=POINTS):
    src = SOURCES[name]
    idle, end = src["idle"], src["end"]
    data = sorted(src["data"])
    raw = [_interp(data, idle + (end - idle) * i / (points - 1)) for i in range(points)]
    peak = max(raw)
    return [round(v / peak, 3) for v in raw]


def free_turbine(idle_frac, points=POINTS):
    """Free power turbine at full gas-generator output: torque falls linearly with output
    speed. Line through the AGT1500's published 5,355 N·m @ 1,000 rpm and 3,754 N·m @
    3,000 rpm (Gas Turbine World; Forecast International), expressed per unit of the
    engine's top speed so it applies to any free turbine."""
    t0, t1, n0, n1 = 5355.0, 3754.0, 1000.0, 3000.0
    slope = (t1 - t0) / (n1 - n0)

    def torque(x):  # x = speed / 3000 rpm
        return t0 + slope * (x * n1 - n0)

    raw = [torque(idle_frac + (1 - idle_frac) * i / (points - 1)) for i in range(points)]
    peak = max(raw)
    return [round(v / peak, 3) for v in raw]


def pm_motor(base_frac, points=POINTS):
    """Permanent-magnet traction motor: constant torque to base speed, constant power
    above it. 2012 Nissan LEAF motor: 80 kW and 10,400 rpm (ORNL/TM-2013/482), 280 N·m
    (Gao et al. 2019) -> base speed 2,729 rpm."""
    out = []
    for i in range(points):
        x = i / (points - 1)
        out.append(round(1.0 if x <= base_frac else base_frac / x, 3))
    return out


LEAF_BASE = (80000 / 280 * 30 / math.pi) / 10400  # 0.2624

if __name__ == "__main__":
    for key in SOURCES:
        print(f"{key:20s} = {{{', '.join(str(v) for v in resample(key))}}}")
    print(f"{'agt1500 (idle 830/3000)':20s} = {{{', '.join(str(v) for v in free_turbine(830 / 3000))}}}")
    print(f"{'aero turbine (0.14)':20s} = {{{', '.join(str(v) for v in free_turbine(0.14))}}}")
    print(f"{'ground turbine (0.2)':20s} = {{{', '.join(str(v) for v in free_turbine(0.2))}}}")
    print(f"{'leaf':20s} = {{{', '.join(str(v) for v in pm_motor(LEAF_BASE))}}}")

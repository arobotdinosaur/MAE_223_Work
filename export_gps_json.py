#!/usr/bin/env python3
"""Export GPS (UBX) data for each test to JSON.

Preferred content per record: date/time stamp, lat, lon, altitude, RTK mode
(plus a few other useful fields: fix type, satellite count, h/v accuracy, speed).

Output file naming: <TestName>_<GroupNumber>_gps.json  (the "_gps" suffix keeps
the GPS and IMU exports distinct while preserving the TestName_GroupNumber stem).

Usage:
    python3 export_gps_json.py                 # export every test in TESTS
    python3 export_gps_json.py OceanTest        # export only named test(s)

Requires: pip install pyubx2 pandas
"""
import sys
import json
from pathlib import Path

import pandas as pd
from pyubx2 import UBXReader

# ─────────────────────────── CONFIG ───────────────────────────
GROUP_NUMBER = "Group3"          # EDIT: your group number, e.g. "7"
OUT_DIR      = Path(__file__).parent / "exports"

REPO = Path(__file__).parent

# One entry per test. Edit names/paths as needed. The IMU export script reads
# the same TestName, so keep names consistent between the two scripts.
#
# "window" = (start_s, end_s) in seconds from the GPS log's first epoch, matching
# the USE_WINDOW selection in the corresponding plot_ubx_track*.ipynb notebook.
# Set window=None to export the full log. The IMU export inherits this window
# automatically (it clips to the GPS export's UTC start/end).
TESTS = [
    {"name": "OceanTest",
     "ubx": REPO / "Ocean_Test_Success" / "dataLog00081.ubx",           # confirmed pair (IMU = imuLog00082)
     "window": (800, 3200)},                                            # plot_ubx_track.ipynb
    {"name": "BigPendulum",
     "ubx": REPO / "DATA" / "Big_Outdoor_Pendulum_May4.ubx",            # VERIFY/EDIT path
     "window": (400, 700)},                                             # plot_ubx_track_pendulum.ipynb
    {"name": "FerrisWheel",
     "ubx": REPO / "DATA" / "dataLog00051_ferris_wheel.ubx",            # VERIFY/EDIT path
     "window": (240, 1290)},                                            # plot_ubx_track_ferris_wheel.ipynb
]
# ───────────────────────────────────────────────────────────────

FIX_NAMES = {0: "NoFix", 1: "DR", 2: "2D", 3: "3D", 4: "GNSS+DR", 5: "Time"}
RTK_NAMES = {0: "None", 1: "Float", 2: "Fixed"}


def parse_ubx(path):
    """Merge NAV-PVT + NAV-HPPOSLLH into one row per epoch (keyed by iTOW).

    Same logic as DATA/plot_ubx_track.ipynb: pyubx2 auto-scales lat/lon to
    degrees; height/accuracy fields are raw mm (PVT) or 0.1 mm (HP) integers.
    Uses high-precision HPPOSLLH lat/lon/height when available.
    """
    pvt, hppos = {}, {}
    with open(path, "rb") as f:
        for _, p in UBXReader(f):
            if not hasattr(p, "identity"):
                continue
            iTOW = getattr(p, "iTOW", None)
            if iTOW is None:
                continue
            if p.identity == "NAV-PVT":
                pvt[iTOW] = dict(
                    iTOW=iTOW,
                    year=getattr(p, "year", 0), month=getattr(p, "month", 0),
                    day=getattr(p, "day", 0), hour=getattr(p, "hour", 0),
                    minute=getattr(p, "min", 0), second=getattr(p, "sec", 0),
                    fix_type=getattr(p, "fixType", 0),
                    carrier_solution=getattr(p, "carrSoln", 0),
                    num_sv=getattr(p, "numSV", 0),
                    pdop=getattr(p, "pDOP", 0) / 100.0,
                    speed_ms=getattr(p, "gSpeed", 0) / 1000.0,
                    lat_pvt=float(getattr(p, "lat", 0.0)),
                    lon_pvt=float(getattr(p, "lon", 0.0)),
                    hmsl_pvt=getattr(p, "hMSL", 0) / 1000.0,
                    height_pvt=getattr(p, "height", 0) / 1000.0,
                    h_acc_pvt=getattr(p, "hAcc", 0) / 1000.0,
                    v_acc_pvt=getattr(p, "vAcc", 0) / 1000.0,
                )
            elif p.identity == "NAV-HPPOSLLH":
                lat = float(getattr(p, "lat", 0.0)); lon = float(getattr(p, "lon", 0.0))
                hpLat = float(getattr(p, "latHp", getattr(p, "hpLat", 0.0)))
                hpLon = float(getattr(p, "lonHp", getattr(p, "hpLon", 0.0)))
                hmsl = getattr(p, "hMSL", 0); height = getattr(p, "height", 0)
                hpHMSL = getattr(p, "hMSLHp", getattr(p, "hpHMSL", 0))
                hpHeight = getattr(p, "heightHp", getattr(p, "hpHeight", 0))
                hppos[iTOW] = dict(
                    lat_hp=lat + hpLat, lon_hp=lon + hpLon,
                    hmsl_hp=(hmsl + hpHMSL * 0.1) / 1000.0,
                    height_hp=(height + hpHeight * 0.1) / 1000.0,
                    h_acc_hp=getattr(p, "hAcc", 0) / 10000.0,
                    v_acc_hp=getattr(p, "vAcc", 0) / 10000.0,
                )
    rows = []
    for iTOW in sorted(pvt):
        r = pvt[iTOW]; hp = hppos.get(iTOW, {})
        if hp:
            lat, lon = hp["lat_hp"], hp["lon_hp"]
            hmsl, height = hp["hmsl_hp"], hp["height_hp"]
            h_acc, v_acc, src = hp["h_acc_hp"], hp["v_acc_hp"], "HP"
        else:
            lat, lon = r["lat_pvt"], r["lon_pvt"]
            hmsl, height = r["hmsl_pvt"], r["height_pvt"]
            h_acc, v_acc, src = r["h_acc_pvt"], r["v_acc_pvt"], "PVT"
        # high-resolution UTC: NAV-PVT whole second + sub-second from iTOW
        dt = pd.Timestamp(year=r["year"], month=r["month"], day=r["day"],
                          hour=r["hour"], minute=r["minute"], second=r["second"],
                          tz="UTC") + pd.to_timedelta(iTOW % 1000, unit="ms")
        rows.append({
            "datetime":            dt.isoformat(),
            "lat":                 round(lat, 8),
            "lon":                 round(lon, 8),
            "altitude_msl_m":      round(hmsl, 4),
            "altitude_ellipsoid_m": round(height, 4),
            "rtk_mode":            RTK_NAMES.get(r["carrier_solution"], str(r["carrier_solution"])),
            "carrier_solution":    r["carrier_solution"],
            "fix_type":            r["fix_type"],
            "fix_name":            FIX_NAMES.get(r["fix_type"], str(r["fix_type"])),
            "num_sv":              r["num_sv"],
            "h_acc_m":             round(h_acc, 4),
            "v_acc_m":             round(v_acc, 4),
            "speed_ms":            round(r["speed_ms"], 4),
            "pdop":                round(r["pdop"], 2),
            "pos_source":          src,
            "iTOW_ms":             int(iTOW),
        })
    return rows


def export_test(test):
    ubx = Path(test["ubx"])
    if not ubx.exists():
        print(f"  !! SKIP {test['name']}: file not found -> {ubx}")
        return
    print(f"  parsing {ubx.name} ...")
    records = parse_ubx(ubx)
    if not records:
        print(f"  !! SKIP {test['name']}: no GPS epochs parsed")
        return

    # t_s = seconds from the FULL log's first epoch (matches the notebooks, which
    # compute t_s on the whole log before applying USE_WINDOW), then clip.
    itow0 = records[0]["iTOW_ms"]
    for r in records:
        r["t_s"] = round((r["iTOW_ms"] - itow0) / 1000.0, 3)
    window = test.get("window")
    if window:
        lo, hi = window
        records = [r for r in records if lo <= r["t_s"] <= hi]
        if not records:
            print(f"  !! SKIP {test['name']}: no epochs in window {window} s")
            return

    rtk_counts = {}
    for r in records:
        rtk_counts[r["rtk_mode"]] = rtk_counts.get(r["rtk_mode"], 0) + 1

    obj = {
        "test_name":     test["name"],
        "group_number":  GROUP_NUMBER,
        "sensor":        "GPS",
        "source_file":   str(ubx),
        "n_records":     len(records),
        "window_s":      list(window) if window else None,
        "start_time":    records[0]["datetime"],
        "end_time":      records[-1]["datetime"],
        "rtk_mode_counts": rtk_counts,
        "field_units": {
            "datetime": "ISO-8601 UTC", "t_s": "s from full-log first epoch",
            "lat": "deg", "lon": "deg",
            "altitude_msl_m": "m above MSL", "altitude_ellipsoid_m": "m above ellipsoid",
            "h_acc_m": "m", "v_acc_m": "m", "speed_ms": "m/s", "iTOW_ms": "GPS ms-of-week",
        },
        "records": records,
    }

    OUT_DIR.mkdir(parents=True, exist_ok=True)
    out = OUT_DIR / f"{test['name']}_{GROUP_NUMBER}_gps.json"
    with open(out, "w") as f:
        json.dump(obj, f, indent=2)
    print(f"  -> {out.name}  ({len(records)} records, "
          f"{records[0]['datetime']} .. {records[-1]['datetime']}, RTK {rtk_counts})")


def main():
    wanted = set(sys.argv[1:])
    tests = [t for t in TESTS if not wanted or t["name"] in wanted]
    if wanted and not tests:
        print(f"No matching tests for {wanted}. Available: {[t['name'] for t in TESTS]}")
        return
    print(f"Exporting GPS JSON for: {[t['name'] for t in tests]}  (group {GROUP_NUMBER})")
    for t in tests:
        export_test(t)
    print("done.")


if __name__ == "__main__":
    main()

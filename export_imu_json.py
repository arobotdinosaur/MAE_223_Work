#!/usr/bin/env python3
"""Export IMU (CSV) data for each test to JSON, clipped to the SAME time period
as the corresponding GPS log.

Time alignment: the IMU CSV and the UBX log both carry absolute UTC timestamps,
so we clip the IMU rows to the [start_time, end_time] window of the matching GPS
export. Run export_gps_json.py FIRST so that window is available; if the GPS JSON
is missing we fall back to exporting the IMU file's full range (with a warning).

Output file naming: <TestName>_<GroupNumber>_imu.json

Usage:
    python3 export_imu_json.py                  # export every test in TESTS
    python3 export_imu_json.py OceanTest         # export only named test(s)

Requires: pip install pandas
"""
import sys
import json
from pathlib import Path

import pandas as pd

# ─────────────────────────── CONFIG ───────────────────────────
GROUP_NUMBER = "Group3"          # EDIT: must match export_gps_json.py
OUT_DIR      = Path(__file__).parent / "exports"
G            = 9.81              # m/s² (accel is logged in milli-g)
DECIMATE     = 1                 # keep every Nth row (1 = keep all)

REPO = Path(__file__).parent

# One entry per test. "name" must match the GPS export so the time window can be
# looked up; "imu" is the IMU CSV for that test.
TESTS = [
    {"name": "OceanTest",
     "imu": REPO / "Ocean_Test_Success" / "imuLog00082.csv"},           # confirmed pair (GPS = dataLog00081)
    {"name": "BigPendulum",
     "imu": REPO / "DATA" / "imuLog00024.csv"},                         # pairs with Big_Outdoor_Pendulum_May4.ubx
    {"name": "FerrisWheel",
     "imu": REPO / "DATA" / "imuLog00051_ferris_wheel.csv"},            # VERIFY/EDIT path
]
# ───────────────────────────────────────────────────────────────


def load_gps_window(test_name):
    """Return (start, end) UTC Timestamps from the GPS export, or None."""
    gps_json = OUT_DIR / f"{test_name}_{GROUP_NUMBER}_gps.json"
    if not gps_json.exists():
        return None
    meta = json.load(open(gps_json))
    return pd.Timestamp(meta["start_time"]), pd.Timestamp(meta["end_time"])


def export_test(test):
    csv = Path(test["imu"])
    if not csv.exists():
        print(f"  !! SKIP {test['name']}: file not found -> {csv}")
        return

    df = pd.read_csv(csv)
    df["time"] = pd.to_datetime(df["Timestamp"], format="%Y/%m/%d %H:%M:%S.%f",
                                errors="coerce", utc=True)
    # Drop pre-sync rows: the RTC boots at the year-2000 default before the GPS
    # time-sync lands, which would otherwise corrupt the time window.
    n_pre = int((df["time"].dt.year < 2001).sum())
    df = df[df["time"].dt.year >= 2001].reset_index(drop=True)

    window = load_gps_window(test["name"])
    if window:
        start, end = window
        df = df[(df["time"] >= start) & (df["time"] <= end)].reset_index(drop=True)
        win_note = f"clipped to GPS window {start.isoformat()} .. {end.isoformat()}"
    else:
        win_note = ("NO GPS JSON found — exported FULL IMU range "
                    "(run export_gps_json.py first to clip to the test window)")

    if DECIMATE > 1:
        df = df.iloc[::DECIMATE].reset_index(drop=True)
    if df.empty:
        print(f"  !! SKIP {test['name']}: no IMU rows in the time window")
        return

    t0 = df["time"].iloc[0]
    records = []
    for _, r in df.iterrows():
        records.append({
            "datetime": r["time"].isoformat(),
            "t_s":      round((r["time"] - t0).total_seconds(), 4),
            "AccX_ms2": round(r["AccX"] / 1000.0 * G, 5),   # milli-g -> m/s²
            "AccY_ms2": round(r["AccY"] / 1000.0 * G, 5),
            "AccZ_ms2": round(r["AccZ"] / 1000.0 * G, 5),
            "GyrX_dps": round(float(r["GyrX"]), 5),         # deg/s
            "GyrY_dps": round(float(r["GyrY"]), 5),
            "GyrZ_dps": round(float(r["GyrZ"]), 5),
            "MagX": round(float(r["MagX"]), 4),             # raw counts
            "MagY": round(float(r["MagY"]), 4),
            "MagZ": round(float(r["MagZ"]), 4),
            "Temp_C": round(float(r["Temp"]), 3) if "Temp" in df.columns else None,
        })

    obj = {
        "test_name":    test["name"],
        "group_number": GROUP_NUMBER,
        "sensor":       "IMU",
        "source_file":  str(csv),
        "n_records":    len(records),
        "n_presync_dropped": n_pre,
        "decimate":     DECIMATE,
        "start_time":   records[0]["datetime"],
        "end_time":     records[-1]["datetime"],
        "time_window":  win_note,
        "field_units": {
            "datetime": "ISO-8601 UTC", "t_s": "s since first record",
            "AccX_ms2/AccY_ms2/AccZ_ms2": "m/s² (converted from logged milli-g)",
            "GyrX_dps/GyrY_dps/GyrZ_dps": "deg/s",
            "MagX/MagY/MagZ": "raw magnetometer counts", "Temp_C": "°C",
        },
        "records": records,
    }

    OUT_DIR.mkdir(parents=True, exist_ok=True)
    out = OUT_DIR / f"{test['name']}_{GROUP_NUMBER}_imu.json"
    with open(out, "w") as f:
        json.dump(obj, f, indent=2)
    print(f"  -> {out.name}  ({len(records)} records; dropped {n_pre} pre-sync; {win_note})")


def main():
    wanted = set(sys.argv[1:])
    tests = [t for t in TESTS if not wanted or t["name"] in wanted]
    if wanted and not tests:
        print(f"No matching tests for {wanted}. Available: {[t['name'] for t in TESTS]}")
        return
    print(f"Exporting IMU JSON for: {[t['name'] for t in tests]}  (group {GROUP_NUMBER})")
    for t in tests:
        export_test(t)
    print("done.")


if __name__ == "__main__":
    main()

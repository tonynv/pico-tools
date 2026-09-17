#!/usr/bin/env python3
"""Basic health check for a PicoScope 4225A.

Captures a short block on Channel A (blue) and Channel B (red) and prints
min / max / mean voltage for each. Close PicoScope 7 before running.

Usage:
    source ~/picoscope-env/bin/activate
    python tools/test_channels.py              # ±20 V, 100 ms capture
    python tools/test_channels.py --range 5V   # smaller range for an AA battery
    python tools/test_channels.py --plot       # also save capture.png
"""
import argparse
import ctypes
import sys
import time

import numpy as np
from picosdk.constants import PICO_STATUS
from picosdk.functions import adc2mV, assert_pico_ok
from picosdk.ps4000a import ps4000a as ps

NUM_SAMPLES = 10_000
CHANNELS = {"A": "PS4000A_CHANNEL_A", "B": "PS4000A_CHANNEL_B"}


def open_scope():
    handle = ctypes.c_int16()
    status = ps.ps4000aOpenUnit(ctypes.byref(handle), None)
    # USB-powered scopes can report a power-source status that just needs acknowledging.
    if status in (PICO_STATUS["PICO_POWER_SUPPLY_NOT_CONNECTED"],
                  PICO_STATUS["PICO_USB3_0_DEVICE_NON_USB3_0_PORT"]):
        status = ps.ps4000aChangePowerSource(handle, status)
    if status != PICO_STATUS["PICO_OK"]:
        sys.exit(f"Could not open scope (status {status}). "
                 "Is it plugged in, and is PicoScope 7 closed?")
    return handle


def capture(handle, range_name, duration_s):
    range_key = f"PS4000A_{range_name.upper()}"
    if range_key not in ps.PS4000A_RANGE:
        sys.exit(f"Unknown range {range_name}. Try e.g. 1V, 5V, 20V, 50V.")
    range_idx = ps.PS4000A_RANGE[range_key]

    for name in CHANNELS.values():
        assert_pico_ok(ps.ps4000aSetChannel(
            handle, ps.PS4000A_CHANNEL[name], 1,
            ps.PS4000A_COUPLING["PS4000A_DC"], range_idx, 0.0))

    # No trigger: capture immediately.
    assert_pico_ok(ps.ps4000aSetSimpleTrigger(
        handle, 0, ps.PS4000A_CHANNEL["PS4000A_CHANNEL_A"], 0, 2, 0, 0))

    # 4000A timebase: sample interval = (timebase + 1) * 12.5 ns
    interval_s = duration_s / NUM_SAMPLES
    timebase = max(0, int(round(interval_s / 12.5e-9)) - 1)
    interval_ns = ctypes.c_float()
    max_samples = ctypes.c_int32()
    assert_pico_ok(ps.ps4000aGetTimebase2(
        handle, timebase, NUM_SAMPLES, ctypes.byref(interval_ns),
        ctypes.byref(max_samples), 0))

    buffers = {}
    for label, name in CHANNELS.items():
        buf = (ctypes.c_int16 * NUM_SAMPLES)()
        assert_pico_ok(ps.ps4000aSetDataBuffers(
            handle, ps.PS4000A_CHANNEL[name], ctypes.byref(buf), None,
            NUM_SAMPLES, 0, ps.PS4000A_RATIO_MODE["PS4000A_RATIO_MODE_NONE"]))
        buffers[label] = buf

    assert_pico_ok(ps.ps4000aRunBlock(
        handle, 0, NUM_SAMPLES, timebase, None, 0, None, None))

    ready = ctypes.c_int16(0)
    while not ready.value:
        ps.ps4000aIsReady(handle, ctypes.byref(ready))
        time.sleep(0.01)

    n = ctypes.c_uint32(NUM_SAMPLES)
    overflow = ctypes.c_int16()
    assert_pico_ok(ps.ps4000aGetValues(
        handle, 0, ctypes.byref(n), 0,
        ps.PS4000A_RATIO_MODE["PS4000A_RATIO_MODE_NONE"], 0,
        ctypes.byref(overflow)))

    max_adc = ctypes.c_int16()
    assert_pico_ok(ps.ps4000aMaximumValue(handle, ctypes.byref(max_adc)))

    volts = {label: np.array(adc2mV(buf, range_idx, max_adc))[:n.value] / 1000.0
             for label, buf in buffers.items()}
    t = np.arange(n.value) * interval_ns.value * 1e-9
    return t, volts, overflow.value


def main():
    parser = argparse.ArgumentParser(description=__doc__,
                                     formatter_class=argparse.RawDescriptionHelpFormatter)
    parser.add_argument("--range", default="20V", help="input range, e.g. 5V, 20V (default 20V)")
    parser.add_argument("--duration", type=float, default=0.1, help="capture length in seconds")
    parser.add_argument("--plot", action="store_true", help="save a plot to capture.png")
    args = parser.parse_args()

    handle = open_scope()
    try:
        t, volts, overflow = capture(handle, args.range, args.duration)
    finally:
        ps.ps4000aStop(handle)
        ps.ps4000aCloseUnit(handle)

    print(f"Captured {len(t)} samples over {t[-1] * 1000:.1f} ms at ±{args.range}\n")
    for label, colour, bit in (("A", "blue", 0), ("B", "red", 1)):
        v = volts[label]
        note = "  ** OVER RANGE - use a bigger --range **" if overflow & (1 << bit) else ""
        print(f"Channel {label} ({colour}): min {v.min():7.3f} V   "
              f"max {v.max():7.3f} V   mean {v.mean():7.3f} V{note}")

    if args.plot:
        import matplotlib
        matplotlib.use("Agg")
        import matplotlib.pyplot as plt
        plt.plot(t * 1000, volts["A"], color="tab:blue", label="Channel A")
        plt.plot(t * 1000, volts["B"], color="tab:red", label="Channel B")
        plt.xlabel("Time (ms)")
        plt.ylabel("Voltage (V)")
        plt.legend()
        plt.grid(True, alpha=0.3)
        plt.savefig("capture.png", dpi=120)
        print("\nSaved plot to capture.png")


if __name__ == "__main__":
    main()

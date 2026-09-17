"""Block-mode capture from a PicoScope 4225A using Pico's ps4000a driver."""
import ctypes
import time
from dataclasses import dataclass

import numpy as np

CHANNELS = {"A": "PS4000A_CHANNEL_A", "B": "PS4000A_CHANNEL_B"}
DEFAULT_SAMPLES = 10_000


class ScopeError(RuntimeError):
    """Raised when the driver is missing or the scope cannot be used."""


def _driver():
    """Import the Pico driver bindings, turning a missing native library into a clear error."""
    try:
        from picosdk.constants import PICO_STATUS
        from picosdk.functions import adc2mV, assert_pico_ok
        from picosdk.ps4000a import ps4000a
    except ImportError as err:  # picosdk not installed
        raise ScopeError(f"Python package missing: {err.name}. Run: pip install pico-tools") from err
    except Exception as err:  # CannotFindPicoSDKError / CannotOpenPicoSDKError while loading libps4000a
        raise ScopeError(
            "The PicoScope ps4000a driver (libps4000a) was not found. "
            "Install it with setup_pico_tools.sh from https://github.com/tonynv/pico-tools"
        ) from err
    return ps4000a, PICO_STATUS, adc2mV, assert_pico_ok


def range_names():
    """Input ranges the 4000A driver accepts, e.g. ['10MV', ..., '20V', ...]."""
    ps, *_ = _driver()
    prefix = "PICO_X1_PROBE_"
    return [k[len(prefix):] for k, v in ps.PICO_CONNECT_PROBE_RANGE.items()
            if isinstance(k, str) and k.startswith(prefix) and k != prefix + "RANGES"]


@dataclass
class Capture:
    """One block of samples from Channel A and B."""

    time_s: np.ndarray
    volts: dict
    range_name: str
    overflow: int

    def over_range(self, channel):
        return bool(self.overflow & (1 << list(CHANNELS).index(channel)))


class Scope:
    """Open PicoScope 4000A-series unit. Use as a context manager."""

    def __init__(self):
        self._ps, self._status, self._adc2mv, self._ok = _driver()
        self.handle = ctypes.c_int16()
        status = self._ps.ps4000aOpenUnit(ctypes.byref(self.handle), None)
        # USB-powered scopes can report a power-source status that just needs acknowledging
        if status in (self._status["PICO_POWER_SUPPLY_NOT_CONNECTED"],
                      self._status["PICO_USB3_0_DEVICE_NON_USB3_0_PORT"]):
            status = self._ps.ps4000aChangePowerSource(self.handle, status)
        if status != self._status["PICO_OK"]:
            raise ScopeError(f"Could not open the scope (status {status}). "
                             "Is it plugged in, and is PicoScope 7 closed?")

    def __enter__(self):
        return self

    def __exit__(self, *exc):
        self.close()

    def close(self):
        if self.handle is not None:
            self._ps.ps4000aStop(self.handle)
            self._ps.ps4000aCloseUnit(self.handle)
            self.handle = None

    def _timebase_for(self, interval_s, samples):
        """Pick the timebase whose sample interval is closest to interval_s."""
        interval_ns = ctypes.c_float()
        max_samples = ctypes.c_int32()

        def actual(tb):
            status = self._ps.ps4000aGetTimebase2(self.handle, tb, samples, ctypes.byref(interval_ns),
                                                  ctypes.byref(max_samples), 0)
            return interval_ns.value * 1e-9 if status == self._status["PICO_OK"] else None

        # Sample interval grows linearly with (timebase + 1): estimate, then correct once
        tb = max(0, round(interval_s / 12.5e-9) - 1)
        got = actual(tb)
        if got:
            tb = max(0, round((tb + 1) * interval_s / got) - 1)
        if actual(tb) is None:
            raise ScopeError(f"No timebase available for a {interval_s * 1e6:.1f} µs sample interval")
        return tb, interval_ns.value * 1e-9

    def capture(self, range_name="20V", duration_s=0.1, samples=DEFAULT_SAMPLES):
        """Capture one block from Channel A and B at the same input range, DC coupled."""
        ps, ok = self._ps, self._ok
        key = f"PICO_X1_PROBE_{range_name.upper()}"
        if key not in ps.PICO_CONNECT_PROBE_RANGE:
            raise ScopeError(f"Unknown range {range_name}. Try one of: {', '.join(range_names())}")
        range_idx = ps.PICO_CONNECT_PROBE_RANGE[key]

        for name in CHANNELS.values():
            ok(ps.ps4000aSetChannel(self.handle, ps.PS4000A_CHANNEL[name], 1,
                                    ps.PS4000A_COUPLING["PS4000A_DC"], range_idx, 0.0))
        # No trigger: capture immediately
        ok(ps.ps4000aSetSimpleTrigger(self.handle, 0, ps.PS4000A_CHANNEL["PS4000A_CHANNEL_A"], 0, 2, 0, 0))

        timebase, interval_s = self._timebase_for(duration_s / samples, samples)

        buffers = {}
        for label, name in CHANNELS.items():
            buf = (ctypes.c_int16 * samples)()
            ok(ps.ps4000aSetDataBuffers(self.handle, ps.PS4000A_CHANNEL[name], ctypes.byref(buf), None,
                                        samples, 0, ps.PS4000A_RATIO_MODE["PS4000A_RATIO_MODE_NONE"]))
            buffers[label] = buf

        ok(ps.ps4000aRunBlock(self.handle, 0, samples, timebase, None, 0, None, None))
        ready = ctypes.c_int16(0)
        while not ready.value:
            ps.ps4000aIsReady(self.handle, ctypes.byref(ready))
            time.sleep(0.01)

        n = ctypes.c_uint32(samples)
        overflow = ctypes.c_int16()
        ok(ps.ps4000aGetValues(self.handle, 0, ctypes.byref(n), 0,
                               ps.PS4000A_RATIO_MODE["PS4000A_RATIO_MODE_NONE"], 0, ctypes.byref(overflow)))
        max_adc = ctypes.c_int16()
        ok(ps.ps4000aMaximumValue(self.handle, ctypes.byref(max_adc)))

        volts = {label: np.asarray(self._adc2mv(buf, range_idx, max_adc))[:n.value] / 1000.0
                 for label, buf in buffers.items()}
        return Capture(time_s=np.arange(n.value) * interval_s, volts=volts,
                       range_name=range_name.upper(), overflow=overflow.value)

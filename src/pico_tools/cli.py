"""pico-tools command line interface."""
import argparse
import sys
import time

from pico_tools import __version__

COLOURS = {"A": "blue", "B": "red"}


def cmd_test(args):
    from pico_tools.scope import Scope

    with Scope() as scope:
        cap = scope.capture(args.range, args.duration)

    print(f"Captured {len(cap.time_s)} samples over {cap.time_s[-1] * 1000:.1f} ms at ±{cap.range_name}\n")
    for ch, v in cap.volts.items():
        note = "  ** OVER RANGE - use a bigger --range **" if cap.over_range(ch) else ""
        print(f"Channel {ch} ({COLOURS[ch]}): min {v.min():7.3f} V   "
              f"max {v.max():7.3f} V   mean {v.mean():7.3f} V{note}")

    if args.plot:
        try:
            import matplotlib
        except ImportError:
            print("\n--plot needs matplotlib: pip install 'pico-tools[plot]'", file=sys.stderr)
            return 1
        matplotlib.use("Agg")
        import matplotlib.pyplot as plt

        for ch, v in cap.volts.items():
            plt.plot(cap.time_s * 1000, v, color=f"tab:{COLOURS[ch]}", label=f"Channel {ch}")
        plt.xlabel("Time (ms)")
        plt.ylabel("Voltage (V)")
        plt.legend()
        plt.grid(True, alpha=0.3)
        plt.savefig(args.plot, dpi=120)
        print(f"\nSaved plot to {args.plot}")
    return 0


def cmd_poll(args):
    from pico_tools.scope import Scope

    print(f"Polling Channel A and B at ±{args.range.upper()} every {args.interval:g} s - Ctrl+C to stop",
          flush=True)
    with Scope() as scope:
        n = 0
        try:
            while args.count == 0 or n < args.count:
                cap = scope.capture(args.range, args.duration)
                cols = []
                for ch, v in cap.volts.items():
                    flag = "!" if cap.over_range(ch) else " "
                    cols.append(f"{ch}: mean {v.mean():7.3f} V  pk-pk {v.max() - v.min():7.3f} V{flag}")
                print(f"{time.strftime('%H:%M:%S')}  " + "   ".join(cols), flush=True)
                n += 1
                if args.count == 0 or n < args.count:
                    time.sleep(args.interval)
        except KeyboardInterrupt:
            print()
    return 0


def build_parser():
    parser = argparse.ArgumentParser(
        prog="pico-tools",
        description="Linux helper tools for the PicoScope 4225A automotive oscilloscope.",
    )
    parser.add_argument("--version", action="version", version=f"%(prog)s {__version__}")
    sub = parser.add_subparsers(dest="command", metavar="COMMAND")

    test = sub.add_parser("test", help="capture Channel A and B and print min / max / mean voltage",
                          description="Capture a short block from Channel A (blue) and Channel B (red). "
                                      "Close PicoScope 7 first.")
    test.add_argument("--range", default="20V", help="input range, e.g. 500MV, 5V, 20V (default: 20V)")
    test.add_argument("--duration", type=float, default=0.1, help="capture length in seconds (default: 0.1)")
    test.add_argument("--plot", nargs="?", const="capture.png", metavar="FILE",
                      help="also save a plot (default file: capture.png)")
    test.set_defaults(func=cmd_test)

    poll = sub.add_parser("poll", help="keep capturing and print a line per reading until Ctrl+C",
                          description="Repeatedly capture Channel A and B and print mean and peak-to-peak "
                                      "voltage. '!' marks a reading that went over range. Close PicoScope 7 first.")
    poll.add_argument("--range", default="20V", help="input range, e.g. 500MV, 5V, 20V (default: 20V)")
    poll.add_argument("--interval", type=float, default=0.5, help="seconds between readings (default: 0.5)")
    poll.add_argument("--duration", type=float, default=0.1, help="capture length per reading in seconds (default: 0.1)")
    poll.add_argument("--count", type=int, default=0, help="stop after this many readings (default: 0 = forever)")
    poll.set_defaults(func=cmd_poll)
    return parser


def main(argv=None):
    parser = build_parser()
    args = parser.parse_args(argv)
    if not getattr(args, "func", None):
        parser.print_help()
        return 1

    from pico_tools.scope import ScopeError

    try:
        return args.func(args)
    except ScopeError as err:
        print(f"Error: {err}", file=sys.stderr)
        return 1
    except KeyboardInterrupt:
        return 130

"""A light per-process CPU stream for Watch it live.

It is pymobiledevice3's own `developer dvt sysmon process monitor threshold` command, so the phone is reached and
chosen exactly as in every other call (USB, Wi-Fi, PYMOBILEDEVICE3_UDID), with two changes to the sampler:
it samples every INTERVAL milliseconds instead of every 500, and asks only for the four attributes Vitals reads
instead of every attribute the phone offers. With the defaults, on the Duo (iOS 27.2.1, 2026-11-19), the
measurement itself kept sysmond near 27% of a core.

Run with the Python that has pymobiledevice3 installed:
    python -m vitals_companion.lightmon INTERVAL_MS THRESHOLD
Prints one JSON object per process per sample, as the original command does.
"""

import sys

KEEP = ("pid", "name", "cpuUsage", "physFootprint")


def main(argv=None):
    argv = list(sys.argv[1:] if argv is None else argv)
    interval_ms = max(1000, int(float(argv[0]))) if argv else 10000
    threshold = argv[1] if len(argv) > 1 else "1"

    from pymobiledevice3.services.dvt.instruments.device_info import DeviceInfo
    from pymobiledevice3.services.dvt.instruments.sysmontap import Sysmontap

    async def create(cls, dvt, interval=None):
        async with DeviceInfo(dvt) as info:
            offered = list(await info.sysmon_process_attributes())
            system = list(await info.sysmon_system_attributes())[:1]
        wanted = [a for a in offered if a in KEEP]
        if "cpuUsage" not in wanted or "name" not in wanted:
            wanted = offered   # an iOS that names these differently: fall back to everything, still slower
        return cls(dvt, wanted, system, interval_ms=interval_ms)

    Sysmontap.create = classmethod(create)

    from pymobiledevice3.__main__ import main as pmd3_main
    sys.argv = ["pymobiledevice3", "developer", "dvt", "sysmon", "process", "monitor", "threshold", str(threshold)]
    return pmd3_main()


if __name__ == "__main__":
    sys.exit(main())

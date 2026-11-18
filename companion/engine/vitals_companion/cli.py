"""vitals-companion: check access, capture, measure around an action, pull logs.

  python3 -m vitals_companion check                      what this Mac can read from the phone (access tier)
  python3 -m vitals_companion probe                      device and battery registry
  python3 -m vitals_companion capture --seconds 300 --out DIR [--events]
  python3 -m vitals_companion snapshot --out FILE        one per-process snapshot (needs Developer Mode)
  python3 -m vitals_companion rates A.json B.json        write rates between two snapshots
  python3 -m vitals_companion around-action --action "Restart" --window 300 --out DIR [--events]
  python3 -m vitals_companion pull logs|sysdiagnose --out DIR [--via pmd3|devicectl]

Global: --wifi (reach the phone without USB), --udid ID (when several phones), --simulate (no phone).
`--events` prints one JSON object per line on stdout (used by the Mac app).
"""

import argparse
import hashlib
import json
import os
import signal
import sys
import time

from .backend import Pmd3CliBackend, DevicectlBackend, SimulatedBackend, BackendError, parse_battery
from .capture import Capture, conditions
from . import rates as R
from . import report
from .redact import redact, collect_ids, redact_text

NOT_SEEN = """The phone was not found over USB. Try these in order:
  1. Unlock the phone and keep it on the Home Screen while connecting.
  2. If the phone asks "Trust This Computer?", tap Trust and enter the passcode.
  3. Use a cable that carries data (some charging cables do not), plugged straight into the Mac, not a hub.
  4. Unplug and plug back in. After a restart the phone can take a minute to appear.
  5. Still nothing: run again with --wifi. It reaches the phone over the network if this Mac was trusted
     before (it may briefly take the phone away from Xcode). On Wi-Fi, results say "connection: wifi"."""

TIER_TEXT = {
    0: "Tier 0, phone only: the Vitals app on the phone reads what iOS shares with apps and the logs you share into it.",
    1: "Tier 1, Mac without Developer Mode: adds the battery registry (cycle count, design and full-charge capacity, "
       "current, charger watts) and a pull of every crash and analytics log. No per-process rates.",
    2: "Tier 2, Mac with Developer Mode: adds live per-process CPU and disk-write rates, which can show what is "
       "writing right now and whether a fix stopped it.",
}


def device_ref(udid):
    """A short, stable handle for one phone, so the Mac app can remember and pass a choice without ever seeing
    or printing the UDID."""
    return hashlib.sha256(("vitals-companion:" + str(udid)).encode()).hexdigest()[:12]


def reachable(args, backend=None):
    """The iPhones this Mac can reach now, one entry per phone: {ref, model, os, connection, _udid}.
    A phone seen over both USB and Wi-Fi is listed once, as USB. Wi-Fi phones only when --wifi is on.
    USB first. `_udid` stays inside the engine; `public()` strips it."""
    b = backend or (SimulatedBackend(speed=getattr(args, "speed", 1.0)) if args.simulate else Pmd3CliBackend())
    by = {}
    for d in b.list_devices() or []:
        udid = d.get("UniqueDeviceID") or d.get("Identifier") or d.get("SerialNumber")
        if not udid:
            continue
        conn = "usb" if str(d.get("ConnectionType", "")).upper() == "USB" else "wifi"
        if conn == "wifi" and not args.wifi:
            continue
        cur = by.get(udid)
        if cur is None or (cur["connection"] == "wifi" and conn == "usb"):
            by[udid] = {"ref": device_ref(udid), "model": d.get("ProductType"), "os": d.get("ProductVersion"),
                        "connection": conn, "_udid": udid}
    return sorted(by.values(), key=lambda e: (e["connection"] != "usb", str(e["model"])))


def public(phone):
    return {k: v for k, v in phone.items() if not k.startswith("_")}


def make_backend(args, phones=None):
    """The backend for the chosen phone: --udid, else the phone --device names, else the first USB phone (else
    the first Wi-Fi one). Without this, several phones made pymobiledevice3 take the first network device, or
    stop at an interactive prompt."""
    if args.simulate:
        b = SimulatedBackend(speed=getattr(args, "speed", 1.0))
        b.phone = public(reachable(args, b)[0])
        return b
    if args.udid:
        return Pmd3CliBackend(udid=args.udid, wifi=args.wifi)
    phones = reachable(args) if phones is None else phones
    device = getattr(args, "device", None)
    pick = next((p for p in phones if p["ref"] == device), None) if device else None
    if device and pick is None:
        raise BackendError("The iPhone chosen in Vitals Companion is not reachable now. Connect it, or choose another.")
    pick = pick or (phones[0] if phones else None)
    if pick is None:
        # Nothing listed: the Wi-Fi route (macOS's own tunnel) can still reach a phone usbmux does not list.
        return Pmd3CliBackend(wifi=args.wifi)
    b = Pmd3CliBackend(udid=pick["_udid"], wifi=pick["connection"] == "wifi")
    b.phone = public(pick)
    return b


def out_json(obj):
    print(json.dumps(obj, indent=1, ensure_ascii=False))


def cmd_check(args):
    """Which tier is available, said plainly, without pushing anyone to turn on Developer Mode."""
    result = {"tier": 0, "connection": None, "developerMode": None, "canRead": [], "cannotRead": [], "explain": []}
    try:
        phones = [] if args.simulate else reachable(args)
        result["devices"] = [public(p) for p in phones]
        try:
            b = make_backend(args, phones)
        except BackendError as e:
            if not getattr(args, "device", None):
                raise
            # The remembered phone is not here: say so and fall back to the preferred one.
            result["chosenMissing"] = True
            args.device = None
            b = make_backend(args, phones)
    except BackendError as e:
        result["explain"] = [str(e), TIER_TEXT[0]]
        out_json(result)
        return 3
    if args.simulate:
        result["devices"] = [b.phone]
    result["chosen"] = (getattr(b, "phone", None) or {}).get("ref")
    devices = result["devices"] or ([{"ConnectionType": "Network"}] if args.wifi else [])
    if not devices:
        result["explain"] = [NOT_SEEN, TIER_TEXT[0]]
        out_json(result)
        return 4
    try:
        info = b.device_info()
    except BackendError as e:
        result["explain"] = [redact_text(str(e)), NOT_SEEN]
        out_json(result)
        return 4
    result["tier"] = 1
    result["connection"] = getattr(b, "transport", None)
    result["device"] = {k: info.get(k) for k in ("ProductType", "ProductVersion")}
    result["canRead"] = ["battery registry", "crash and analytics logs", "system log"]
    dm = getattr(b, "developer_mode", lambda: None)()
    result["developerMode"] = dm
    if dm:
        result["tier"] = 2
        result["canRead"] += ["per-process CPU and disk-write rates", "sysdiagnose"]
    else:
        result["cannotRead"] = ["per-process CPU and disk-write rates (needs Developer Mode)"]
    result["explain"] = [TIER_TEXT[result["tier"]]]
    if result["tier"] == 1:
        result["explain"].append("Most problems can be found at this tier. Developer Mode is only worth it when a "
                                 "finding says live rates would settle it; it lowers some protections, so turn it "
                                 "off again afterwards (Settings > Privacy & Security > Developer Mode).")
    out_json(result)
    return 0


def cmd_devices(args):
    phones = reachable(args)
    out_json({"devices": [public(p) for p in phones], "preferred": phones[0]["ref"] if phones else None})
    return 0


def cmd_probe(args):
    b = make_backend(args)
    info = b.device_info()
    raw = b.battery()
    bat = parse_battery(raw)
    out = {"backend": b.name, "connection": getattr(b, "transport", None),
           "device": {k: info.get(k) for k in ("DeviceName", "ProductType", "ProductVersion", "BuildVersion")},
           "battery": bat, "conditions": conditions(b, bat)}
    out_json(redact(out, collect_ids(info) | collect_ids(raw)))
    return 0


def _emitter(args, holder):
    def emit(event):
        if args.events:
            try:
                sys.stdout.write(json.dumps(event) + "\n")
                sys.stdout.flush()
            except BrokenPipeError:
                if "cap" in holder:
                    holder["cap"].stop()
    return emit


def cmd_capture(args):
    b = make_backend(args)
    holder = {}
    out = os.path.expanduser(args.out or time.strftime("vitals-capture-%Y%m%d-%H%M%S"))
    cap = Capture(b, out, seconds=args.seconds, interval=args.interval, threshold=args.threshold,
                  syslog=args.syslog and not args.no_syslog, crashes=not args.no_crashes, emit=_emitter(args, holder),
                  snapshot_every=args.snapshot_every)
    holder["cap"] = cap
    signal.signal(signal.SIGTERM, lambda *_: cap.stop())
    signal.signal(signal.SIGINT, lambda *_: cap.stop())
    path = cap.run()
    if not args.events:
        print("Capture written to %s\nAirDrop capture.vitalscapture to the phone and open it in Vitals." % path)
    return 0


def cmd_snapshot(args):
    b = make_backend(args)
    raw, at = b.process_snapshot()
    with open(os.path.expanduser(args.out), "w") as f:
        json.dump({"takenAt": at, "processes": redact(raw)}, f)
    norm, _ = R.normalise(raw, at)
    out_json({"saved": args.out, "processes": len(norm), "cpu": R.cpu_summary(norm)})
    return 0


def _load_snapshot(path):
    with open(os.path.expanduser(path)) as f:
        d = json.load(f)
    if isinstance(d, dict) and "processes" in d:
        return R.normalise(d["processes"], d.get("takenAt", 0))[0]
    return R.normalise(d, os.path.getmtime(path))[0]


def cmd_rates(args):
    a, b = _load_snapshot(args.before), _load_snapshot(args.after)
    res = R.compute_rates(a, b)
    rows = [{"process": r["process"], "MBPerMinute": round(r["bytesWrittenPerMinute"] / 1e6, 1), "cpuPercent": r["cpuPercent"],
             "seconds": round(r["to"] - r["from"])} for r in res["rates"][: args.top] if not r["overhead"]]
    out_json({"rates": rows, "resets": res["resets"], "notes": res["notes"], "cpuAfter": R.cpu_summary(b)})
    return 0


def _window(b, seconds, label, emit):
    """Two snapshots `seconds` apart -> (rates, conditions_start, conditions_end, first, last snapshot)."""
    c0 = conditions(b, parse_battery(b.battery()))
    s0, t0 = b.process_snapshot()
    emit({"type": "window", "label": label, "phase": "started", "seconds": seconds})
    time.sleep(seconds)
    s1, t1 = b.process_snapshot()
    c1 = conditions(b, parse_battery(b.battery()))
    n0, n1 = R.normalise(s0, t0)[0], R.normalise(s1, t1)[0]
    res = R.compute_rates(n0, n1, min_seconds=min(20, seconds / 2))
    emit({"type": "window", "label": label, "phase": "done", "rates": len(res["rates"])})
    return res, c0, c1, n0, n1


def cmd_around_action(args):
    """Proof by intervention (plan section 4b): measure, the person does the action, measure again.
    Rates before and after are compared only when conditions match; otherwise the result says so."""
    b = make_backend(args)
    emit = _emitter(args, {})
    if not getattr(b, "developer_mode", lambda: None)():
        out_json({"error": "This needs live rates (tier 2, Developer Mode). " + TIER_TEXT[1]})
        return 5
    before, cb0, cb1, _, before_last = _window(b, args.window, "before", emit)
    emit({"type": "action", "message": "Now: %s. Continue when the phone is back and unlocked." % args.action})
    if not args.events:
        sys.stderr.write("Now: %s. Press Return when the phone is back and unlocked.\n" % args.action)
    if not args.simulate or args.wait:
        sys.stdin.readline()
    if args.simulate:
        b.restart()
    if args.settle:
        time.sleep(args.settle)
    after, ca0, ca1, after_first, _ = _window(b, args.window, "after", emit)
    across = R.compute_rates(before_last, after_first, min_seconds=0)
    mism = R.condition_mismatches(cb0, ca0)
    rows = R.compare_windows(before["rates"], after["rates"])
    result = {"action": args.action, "windowSeconds": args.window, "comparison": rows[: args.top],
              "conditionsBefore": cb0, "conditionsAfter": ca0, "warnings": mism,
              "restartedProcesses": sorted({r["process"] for r in across["resets"]}),
              "verdict": _verdict(rows, mism)}
    if args.out:
        os.makedirs(os.path.expanduser(args.out), exist_ok=True)
        with open(os.path.join(os.path.expanduser(args.out), "around-action.json"), "w") as f:
            json.dump(result, f, indent=1)
    emit({"type": "result", "result": result})
    if not args.events:
        out_json(result)
    return 0


def _verdict(rows, mismatches):
    if not rows:
        return "No process wrote more than 1 MB a minute before or after."
    top = rows[0]
    bm, am = top["beforeMBPerMinute"] or 0, top["afterMBPerMinute"] or 0
    caveat = " Conditions changed (%s), so treat this as indicative." % "; ".join(mismatches) if mismatches else ""
    rose = [r for r in rows if (r["afterMBPerMinute"] or 0) >= 10 and (r["afterMBPerMinute"] or 0) >= 3 * max(r["beforeMBPerMinute"] or 0, 1)]
    also = "".join(" %s rose from %.0f to %.0f MB a minute; watch it." % (r["process"], r["beforeMBPerMinute"] or 0, r["afterMBPerMinute"])
                   for r in rose)
    if bm >= 10 and am <= bm * 0.2:
        return "%s went from %.0f to %.0f MB a minute after the action. The action stopped it, at least for now.%s%s" % (top["process"], bm, am, also, caveat)
    if bm >= 10:
        return "%s still writes %.0f MB a minute (was %.0f). The action did not stop it.%s%s" % (top["process"], am, bm, also, caveat)
    return "Nothing was writing heavily before the action, so this cannot show an effect.%s" % caveat


def cmd_pull(args):
    out = os.path.expanduser(args.out)
    os.makedirs(out, exist_ok=True)
    if args.what == "logs":
        via = args.via
        if via == "auto":
            via = "pmd3"
            try:
                make_backend(args)
            except BackendError:
                via = "devicectl"
        b = DevicectlBackend() if via == "devicectl" and not args.simulate else make_backend(args)
        b.pull_crashes(out)
        n = sum(len(f) for _, _, f in os.walk(out))
        out_json({"saved": out, "files": n, "via": b.name,
                  "next": "Share the folder with the phone (AirDrop) or drop it on Vitals; daily analytics are read first."})
    else:
        make_backend(args).sysdiagnose(out)
        out_json({"saved": out})
    return 0


def main(argv=None):
    p = argparse.ArgumentParser(prog="vitals-companion")
    p.add_argument("--udid", help="device to use when several are connected (never printed)")
    p.add_argument("--device", help="phone to use, by the ref `devices` lists (the Mac app passes this)")
    p.add_argument("--wifi", action="store_true", help="reach the phone over the network (no USB)")
    p.add_argument("--simulate", action="store_true", help="synthetic phone, for testing without a device")
    p.add_argument("--speed", type=float, default=1.0, help="simulated backend only: run faster than real time")
    sub = p.add_subparsers(dest="cmd", required=True)
    sub.add_parser("check", help="what this Mac can read (access tier)")
    sub.add_parser("devices", help="the iPhones this Mac can reach now (model, connection, ref; never the UDID)")
    sub.add_parser("probe", help="device info and battery registry")
    c = sub.add_parser("capture", help="timed capture into a bundle")
    c.add_argument("--seconds", type=float, default=300)
    c.add_argument("--interval", type=float, default=10, help="seconds between readings (default 10; shorter costs the phone more)")
    c.add_argument("--threshold", type=float, default=1, help="only record processes above this CPU %%")
    c.add_argument("--snapshot-every", type=float, default=None, help="extra per-process snapshots every N seconds")
    c.add_argument("--out")
    c.add_argument("--no-syslog", action="store_true", help=argparse.SUPPRESS)   # the default now; kept for old callers
    c.add_argument("--syslog", action="store_true", help="also record syslog (costly to the phone: about 70 MB a minute on the Duo)")
    c.add_argument("--no-crashes", action="store_true")
    c.add_argument("--events", action="store_true", help="stream JSON events on stdout")
    s = sub.add_parser("snapshot", help="one per-process snapshot")
    s.add_argument("--out", required=True)
    r = sub.add_parser("rates", help="write rates between two snapshots")
    r.add_argument("before")
    r.add_argument("after")
    r.add_argument("--top", type=int, default=15)
    a = sub.add_parser("around-action", help="measure, do an action, measure again")
    a.add_argument("--action", required=True)
    a.add_argument("--window", type=float, default=300, help="seconds per measurement window")
    a.add_argument("--settle", type=float, default=0, help="seconds to wait after the action before measuring")
    a.add_argument("--top", type=int, default=10)
    a.add_argument("--out")
    a.add_argument("--events", action="store_true")
    a.add_argument("--wait", action="store_true", help="simulated phone: wait for the newline too (the Mac app's 'your turn')")
    pl = sub.add_parser("pull", help="logs (crash reports and analytics) or a sysdiagnose")
    pl.add_argument("what", choices=["logs", "crashes", "sysdiagnose"])
    pl.add_argument("--out", required=True)
    pl.add_argument("--via", choices=["auto", "pmd3", "devicectl"], default="auto",
                    help="devicectl needs Xcode; pmd3 is bundled with the companion app")
    # --speed (simulator) and --wifi are accepted after the subcommand too, as the Mac app passes them.
    for sp in (c, a):
        sp.add_argument("--speed", type=float, default=argparse.SUPPRESS)
        sp.add_argument("--wifi", action="store_true", default=argparse.SUPPRESS)
    args = p.parse_args(argv)
    if args.cmd == "pull" and args.what == "crashes":
        args.what = "logs"
    try:
        return {"devices": cmd_devices, "check": cmd_check, "probe": cmd_probe, "capture": cmd_capture, "snapshot": cmd_snapshot,
                "rates": cmd_rates, "around-action": cmd_around_action, "pull": cmd_pull}[args.cmd](args)
    except BackendError as e:
        msg = redact_text(str(e))
        sys.stderr.write("error: %s\n" % msg)
        if "not found" in msg.lower() or "no device" in msg.lower() or "connect" in msg.lower():
            sys.stderr.write(NOT_SEEN + "\n")
        return 2


if __name__ == "__main__":
    sys.exit(main())

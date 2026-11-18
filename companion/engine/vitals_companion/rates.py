"""Rates from snapshots (plan section 4b, items 6 to 9).

A `sysmon process single` snapshot gives counters since each process started (diskBytesWritten, ...).
A counter alone says "a lot, at some point"; two timestamped snapshots of the SAME process give a rate.

Rules this module follows:
- Identity is (name, pid, uniqueID, startAbsTime). If any of these changed, or a counter went down, the
  process restarted: that is a new series and no rate is computed across it (a "reset").
- The time base is each process's own `timestamp` when present, else the snapshot time.
- Units are never assumed. Byte counters are bytes (named so in the record). CPU is detected per
  snapshot: sysmon on iOS 27.2 reports percent of one core (values above 1.5 seen on the Duo); if every
  value is at most 1.5 the unit is ambiguous and the result says so.
- The measurement itself costs CPU (sysmond, DTServiceHub, remotepairingdeviced). Those are reported
  separately and left out of whole-phone totals.
- `procAge` and `startAbsTime` are in units this code cannot confirm, so no "running since" date is derived.
"""

from datetime import datetime, timezone

# The measurement itself: sysmond samples, DTServiceHub and remotepairingdeviced carry the developer connection,
# diagnosticd serves syslog and dtfileserviced the file pulls. Left out of "busiest", rates and totals, and
# reported on their own as what measuring cost.
OVERHEAD = ("sysmond", "DTServiceHub", "remotepairingdeviced", "diagnosticd", "dtfileserviced")


def _parse_ts(v):
    if isinstance(v, (int, float)):
        return float(v)
    if isinstance(v, str):
        s = v.strip().replace("Z", "+00:00")
        try:
            d = datetime.fromisoformat(s)
        except ValueError:
            return None
        if d.tzinfo is None:
            d = d.replace(tzinfo=timezone.utc)
        return d.timestamp()
    return None


def cpu_scale(values):
    """Returns (multiplier to percent, note or None)."""
    vals = [v for v in values if isinstance(v, (int, float))]
    if not vals:
        return 1.0, None
    if max(vals) > 1.5:
        return 1.0, None
    return 1.0, "CPU values were all at most 1.5, so it is unclear whether they are percent or fractions; shown as percent."


def normalise(snapshot, taken_at):
    """Raw snapshot (list of dicts) -> (list of process records, notes)."""
    items = snapshot if isinstance(snapshot, list) else (list(snapshot.values()) if isinstance(snapshot, dict) else [])
    items = [p for p in items if isinstance(p, dict)]
    scale, note = cpu_scale([p.get("cpuUsage") for p in items])
    out = []
    for p in items:
        name = p.get("name") or p.get("execName") or p.get("comm")
        if not name:
            continue
        at = _parse_ts(p.get("timestamp"))
        cpu = p.get("cpuUsage")
        cu, cs = p.get("cpuTotalUser"), p.get("cpuTotalSystem")
        out.append({
            # Cumulative CPU time in nanoseconds (sysmon's cpuTotalUser + cpuTotalSystem), when the phone gives it.
            "cpuTimeNs": (cu + cs) if isinstance(cu, (int, float)) and isinstance(cs, (int, float)) else None,
            "name": str(name),
            "pid": p.get("pid"),
            "uniqueID": p.get("uniqueID"),
            "start": p.get("startAbsTime"),
            "at": at if at is not None else float(taken_at),
            "bytesWritten": p.get("diskBytesWritten") if isinstance(p.get("diskBytesWritten"), (int, float)) else None,
            "bytesRead": p.get("diskBytesRead") if isinstance(p.get("diskBytesRead"), (int, float)) else None,
            "cpuPercent": cpu * scale if isinstance(cpu, (int, float)) else None,
            "overhead": str(name) in OVERHEAD,
        })
    return out, ([note] if note else [])


def identity(p):
    return (p["name"], p.get("pid"), p.get("uniqueID"), p.get("start"))


def compute_rates(before, after, min_seconds=20):
    """Two normalised snapshots -> dict(rates=[...], resets=[...], notes=[...]).

    A rate needs the same process in both, at least `min_seconds` apart, with counters that did not go down.
    """
    by_name = {}
    for p in before:
        by_name.setdefault(p["name"], []).append(p)
    rates, resets, notes = [], [], []
    for q in after:
        cands = by_name.get(q["name"], [])
        same = [p for p in cands if identity(p) == identity(q)]
        if not same:
            if cands:
                resets.append({"process": q["name"], "reason": "restarted between snapshots (new pid or start time)"})
            continue
        p = same[0]
        dt = q["at"] - p["at"]
        if dt < min_seconds:
            continue
        if p["bytesWritten"] is None or q["bytesWritten"] is None:
            continue
        if q["bytesWritten"] < p["bytesWritten"]:
            resets.append({"process": q["name"], "reason": "counter went down (counter reset)"})
            continue
        per_min = (q["bytesWritten"] - p["bytesWritten"]) / dt * 60.0
        cpu = [c for c in (p["cpuPercent"], q["cpuPercent"]) if c is not None]
        rates.append({
            "process": q["name"],
            "bytesWrittenPerMinute": per_min,
            "cpuPercent": round(sum(cpu) / len(cpu), 2) if cpu else None,
            "from": p["at"],
            "to": q["at"],
            "overhead": q["overhead"],
        })
    rates.sort(key=lambda r: -r["bytesWrittenPerMinute"])
    if resets:
        notes.append("%d process(es) restarted between snapshots; their counters start a new series." % len(resets))
    return {"rates": rates, "resets": resets, "notes": notes}


def totals(snapshot, min_bytes=1e9):
    """Processes that have written at least `min_bytes` since they started. `since` is left empty: the
    start-time units are not confirmed."""
    out = [{"process": p["name"], "bytesWritten": p["bytesWritten"], "since": None, "at": p["at"]}
           for p in snapshot if p["bytesWritten"] is not None and p["bytesWritten"] >= min_bytes]
    out.sort(key=lambda t: -t["bytesWritten"])
    return out


def cpu_summary(snapshot):
    """Whole-phone CPU (percent of one core) with and without the measurement's own processes."""
    total = sum(p["cpuPercent"] or 0 for p in snapshot)
    overhead = sum(p["cpuPercent"] or 0 for p in snapshot if p["overhead"])
    return {"totalPercent": round(total, 1), "measurementOverheadPercent": round(overhead, 1),
            "withoutOverheadPercent": round(total - overhead, 1)}


def compare_windows(before_rates, after_rates, processes=None, floor_mb=1.0):
    """Before/after an action: per-process write rate change. Processes below `floor_mb` MB/min in both are
    dropped. Returns a list sorted by the biggest drop."""
    b = {r["process"]: r for r in before_rates if not r.get("overhead")}
    a = {r["process"]: r for r in after_rates if not r.get("overhead")}
    names = set(processes) if processes else (set(b) | set(a))
    rows = []
    for n in names:
        bm = b[n]["bytesWrittenPerMinute"] / 1e6 if n in b else None
        am = a[n]["bytesWrittenPerMinute"] / 1e6 if n in a else None
        if (bm or 0) < floor_mb and (am or 0) < floor_mb:
            continue
        rows.append({"process": n, "beforeMBPerMinute": None if bm is None else round(bm, 1),
                     "afterMBPerMinute": None if am is None else round(am, 1),
                     "beforeCPU": b[n]["cpuPercent"] if n in b else None,
                     "afterCPU": a[n]["cpuPercent"] if n in a else None})
    rows.sort(key=lambda r: -((r["beforeMBPerMinute"] or 0) - (r["afterMBPerMinute"] or 0)))
    return rows


CONDITION_KEYS = ("charging", "external", "adapterWatts", "isWireless", "locked", "transport")


def condition_mismatches(before, after):
    """Conditions that differ between two captures, as sentences. Rates taken under different conditions
    (charging vs not, locked vs in use) are not directly comparable."""
    out = []
    labels = {"charging": "charging", "external": "power connected", "adapterWatts": "adapter watts",
              "isWireless": "wireless charging", "locked": "phone locked", "transport": "connection"}
    for k in CONDITION_KEYS:
        x, y = before.get(k), after.get(k)
        if x is None or y is None or x == y:
            continue
        out.append("%s was %s before and %s after" % (labels[k], x, y))
    return out


def readings_average(readings):
    """Per-process CPU averaged over READINGS, not rows.

    `readings` is a list of samples, each a dict {process: cpuPercent} for one moment. A process missing from a
    reading counts as 0 there (the stream leaves out processes under its threshold), so every average divides by
    the number of readings. Dividing by the number of rows instead would overstate anything that only shows up
    now and then. Returns {process: average}, rounded to 0.1.
    """
    n = len(readings)
    if n == 0:
        return {}
    sums = {}
    for r in readings:
        for name, cpu in r.items():
            sums[name] = sums.get(name, 0.0) + (cpu or 0.0)
    return {k: round(v / n, 1) for k, v in sums.items()}


def measurement_cost_between(first, last, first_at, last_at):
    """What the measuring cost, from cumulative CPU time between two snapshots: percent of one core per overhead
    process over the whole window. Unlike the live stream (which leaves out anything under its threshold) this
    counts every nanosecond. A process that restarted in between contributes only its own new series."""
    wall = float(last_at) - float(first_at)
    if wall <= 0:
        return None
    before = {identity(p): p["cpuTimeNs"] for p in first if p["overhead"] and p.get("cpuTimeNs") is not None}
    procs = {}
    seen = False
    for p in last:
        if not p["overhead"] or p.get("cpuTimeNs") is None:
            continue
        seen = True
        b = before.get(identity(p), 0)
        delta = p["cpuTimeNs"] - b if p["cpuTimeNs"] >= b else p["cpuTimeNs"]
        procs[p["name"]] = procs.get(p["name"], 0.0) + delta / 1e9 / wall * 100
    if not seen:
        return None
    procs = {k: round(v, 1) for k, v in procs.items()}
    return {"processes": procs, "totalPercent": round(sum(procs.values()), 1), "seconds": round(wall),
            "method": "cumulative CPU time between the first and last snapshot"}


def measurement_cost(readings):
    """The measurement's own processes, averaged per reading, and their total (percent of one core)."""
    avg = readings_average([{k: v for k, v in r.items() if k in OVERHEAD} for r in readings])
    return {"processes": avg, "totalPercent": round(sum(avg.values()), 1), "readings": len(readings)}

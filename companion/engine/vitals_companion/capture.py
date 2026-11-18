"""A timed capture. Writes one bundle directory:

  <name>/capture.vitalscapture   report-schema JSON (AirDrop this to the phone; Vitals opens it)
  <name>/snapshots/*.json        per-process snapshots with cumulative counters (redacted)
  <name>/processes.ndjson        raw per-second CPU stream
  <name>/battery.ndjson          raw battery registry readings (identifiers redacted)
  <name>/syslog.ndjson           raw syslog (only when asked for: it is the costliest stream to the phone)
  <name>/crashes/                crash reports and analytics pulled at the end (optional)

Per-process WRITE RATES come from two or more snapshots (rates.py), not from a single counter. Conditions
(charging, adapter watts, wireless, lock state, connection) are recorded at the start and the end; when they
differ, the capture says so, because rates under different conditions are not comparable.

What needs which access tier (plan section 4c):
  tier 1, Mac without Developer Mode: device info, battery registry, crash and analytics pull, syslog
  tier 2, Mac with Developer Mode:    per-process CPU and disk-write snapshots and stream, sysdiagnose
Without Developer Mode the capture still runs and says what it could not get.
"""

import json
import os
import threading
import time

from .backend import parse_battery, parse_process_line, BackendError
from . import report, rates as R
from .redact import redact, collect_ids


def conditions(backend, battery):
    c = {"transport": getattr(backend, "transport", None)}
    for k in ("charging", "external", "adapterWatts", "isWireless"):
        if k in battery:
            c[k] = battery[k]
    lock = getattr(backend, "lock_state", None)
    c["locked"] = lock() if callable(lock) else None
    return c


class Capture(object):
    def __init__(self, backend, out_dir, seconds=300, interval=10.0, threshold=1, syslog=False, crashes=True,
                 emit=None, snapshot_every=None, lock_probe=None):
        self.backend = backend
        self.out_dir = out_dir
        self.seconds = seconds
        self.interval = interval
        self.threshold = threshold
        self.want_syslog = syslog
        self.want_crashes = crashes
        self.snapshot_every = snapshot_every
        self.lock_probe = lock_probe
        self.emit = emit or (lambda event: None)
        self.stop_event = threading.Event()
        self.samples = []
        self.process_samples = []
        self.readings = []    # one {process: cpu} per sample of the process stream, overhead included
        self.snapshots = []   # (normalised, taken_at)
        self.notes = []
        self.last_battery = {}
        self.cond = []
        self.ids = set()
        self._lock = threading.Lock()

    def stop(self):
        self.stop_event.set()

    # -- snapshots --------------------------------------------------------------------------------------
    def _snapshot(self, label):
        snap = getattr(self.backend, "process_snapshot", None)
        if snap is None:
            return
        try:
            raw, at = snap()
        except BackendError as e:
            self.notes.append("Per-process snapshot (%s) unavailable: %s" % (label, self._scrub(str(e))))
            self.emit({"type": "warning", "message": "Per-process snapshot unavailable. It needs Developer Mode (tier 2)."})
            return
        norm, notes = R.normalise(raw, at)
        self.notes.extend(notes)
        os.makedirs(os.path.join(self.out_dir, "snapshots"), exist_ok=True)
        with open(os.path.join(self.out_dir, "snapshots", "%s-%d.json" % (label, int(at))), "w") as f:
            json.dump(redact(raw, self.ids), f)
        self.snapshots.append((norm, at))
        self.emit({"type": "snapshot", "label": label, "t": at, "processes": len(norm), "cpu": R.cpu_summary(norm)})

    def _scrub(self, s):
        from .redact import redact_text
        return redact_text(s, self.ids)

    # -- streams ----------------------------------------------------------------------------------------
    def _process_worker(self, path):
        try:
            with open(path, "w") as raw:
                stream = self.backend.process_stream(self.threshold, interval=self.interval)
                last_at = None
                for line in stream:
                    if self.stop_event.is_set():
                        break
                    raw.write(line)
                    now = time.time()
                    # One sample arrives as a burst of lines; a gap of more than 2 s starts the next reading.
                    if last_at is None or now - last_at > 2:
                        with self._lock:
                            self.readings.append({})
                    last_at = now
                    for p in parse_process_line(line):
                        with self._lock:
                            self.readings[-1][p["name"]] = self.readings[-1].get(p["name"], 0) + p["cpu"]
                        if p["name"] in R.OVERHEAD:
                            continue
                        ps = {"takenAt": report.iso(now), "process": p["name"], "cpuPercent": round(p["cpu"], 1)}
                        if p.get("pid") is not None:
                            ps["pid"] = p["pid"]
                        with self._lock:
                            self.process_samples.append(ps)
                        self.emit({"type": "process", "t": now, "name": p["name"], "cpu": p["cpu"]})
        except BackendError as e:
            self.notes.append("Per-process monitoring unavailable: %s" % self._scrub(str(e)))
            self.emit({"type": "warning", "message": "Per-process monitoring unavailable. It needs Developer Mode (tier 2)."})
        except Exception as e:  # keep the capture going without process data
            self.notes.append("Per-process monitoring stopped: %s" % self._scrub(str(e)))

    def _syslog_worker(self, path):
        try:
            with open(path, "w") as raw:
                for line in self.backend.syslog_stream():
                    if self.stop_event.is_set():
                        break
                    raw.write(self._scrub(line))
        except Exception as e:
            self.notes.append("Syslog stopped: %s" % self._scrub(str(e)))

    def _battery(self, raw_file, now):
        try:
            b_raw = self.backend.battery()
        except BackendError as e:
            self.notes.append("Battery read failed at %s: %s" % (report.iso(now), self._scrub(str(e))))
            return None
        self.ids |= collect_ids(b_raw)
        raw_file.write(json.dumps({"t": now, "raw": redact(b_raw, self.ids)}) + "\n")
        b = parse_battery(b_raw)
        self.last_battery = b
        self.samples.append(report.sample(now, b))
        self.emit({"type": "battery", "t": now, "temperatureC": b.get("temperatureC"), "level": b.get("level"),
                   "charging": b.get("charging"), "adapterWatts": b.get("adapterWatts")})
        return b

    # -- run --------------------------------------------------------------------------------------------
    def run(self):
        os.makedirs(self.out_dir, exist_ok=True)
        started = time.time()
        info = self.backend.device_info()
        self.ids |= collect_ids(info)
        devmode = getattr(self.backend, "developer_mode", lambda: None)()
        tier = 2 if devmode else 1
        self.emit({"type": "device", "tier": tier, "developerMode": devmode,
                   "info": {k: info.get(k) for k in ("DeviceName", "ProductType", "ProductVersion")}})
        if not devmode:
            self.notes.append("Developer Mode is %s, so per-process CPU and write rates were not captured (tier 1). "
                              "Battery, logs and analytics were." % ("off" if devmode is False else "unknown"))
        with open(os.path.join(self.out_dir, "battery.ndjson"), "w") as raw:
            first = self._battery(raw, time.time()) or {}
            self.cond.append(conditions(self.backend, first))
            if devmode is not False:
                self._snapshot("start")
            workers = []
            if devmode is not False:
                workers.append(threading.Thread(target=self._process_worker, args=(os.path.join(self.out_dir, "processes.ndjson"),), daemon=True))
            if self.want_syslog:
                workers.append(threading.Thread(target=self._syslog_worker, args=(os.path.join(self.out_dir, "syslog.ndjson"),), daemon=True))
            for w in workers:
                w.start()
            next_snap = started + self.snapshot_every if self.snapshot_every else None
            while not self.stop_event.is_set() and time.time() - started < self.seconds:
                self.stop_event.wait(self.interval)
                now = time.time()
                self._battery(raw, now)
                if next_snap and now >= next_snap and devmode is not False:
                    self._snapshot("mid")
                    next_snap = now + self.snapshot_every
            self.stop_event.set()
            if devmode is not False:
                self._snapshot("end")
            self.cond.append(conditions(self.backend, self.last_battery))
        if self.want_crashes:
            try:
                self.backend.pull_crashes(os.path.join(self.out_dir, "crashes"))
            except BackendError as e:
                self.notes.append("Log pull failed: %s" % self._scrub(str(e)))
        ended = time.time()
        rate_result = self.rates()
        mismatches = R.condition_mismatches(self.cond[0], self.cond[-1]) if len(self.cond) > 1 else []
        if mismatches:
            self.notes.append("Conditions changed during the capture: " + "; ".join(mismatches) + ".")
        with self._lock:
            procs = list(self.process_samples)
            readings = [dict(r) for r in self.readings]
        cost = None
        if len(self.snapshots) >= 2:
            (first, first_at), (last, last_at) = self.snapshots[0], self.snapshots[-1]
            cost = R.measurement_cost_between(first, last, first_at, last_at)
        if cost is None and readings:
            cost = R.measurement_cost(readings)
            cost["method"] = "live readings, averaged per reading (processes under the stream threshold are not seen)"
        if cost:
            self.notes.append("Measuring cost the phone about %.1f%% of one core (%s; %s). That is left out of the results."
                              % (cost["totalPercent"],
                                 ", ".join("%s %.1f%%" % kv for kv in sorted(cost["processes"].items(), key=lambda kv: -kv[1])) or "none seen",
                                 cost["method"]))
            self.emit({"type": "cost", "totalPercent": cost["totalPercent"], "processes": cost["processes"], "method": cost["method"]})
        averages = {k: v for k, v in R.readings_average(readings).items() if k not in R.OVERHEAD}
        doc = report.build(info, self.samples, procs, self.last_battery, started, ended, self.backend.name,
                           [self._scrub(n) for n in self.notes], rates=rate_result, conditions=self.cond, tier=tier,
                           measurement=cost, averages=averages)
        path = os.path.join(self.out_dir, "capture.vitalscapture")
        with open(path, "w") as f:
            json.dump(redact(doc, self.ids), f, indent=1, ensure_ascii=False)
        self.emit({"type": "done", "path": path, "samples": len(self.samples), "processSamples": len(procs),
                   "rates": len(rate_result["rates"]), "tier": tier, "warnings": mismatches})
        return path

    def rates(self):
        """Rates between the first and last snapshot (the longest window), totals from the last."""
        if len(self.snapshots) < 2:
            if self.snapshots:
                self.notes.append("Only one per-process snapshot, so no write rates (a rate needs two).")
            return {"rates": [], "resets": [], "notes": [], "totals": R.totals(self.snapshots[-1][0]) if self.snapshots else [],
                    "cpu": R.cpu_summary(self.snapshots[-1][0]) if self.snapshots else None}
        first, last = self.snapshots[0][0], self.snapshots[-1][0]
        res = R.compute_rates(first, last)
        self.notes.extend(res["notes"])
        res["totals"] = R.totals(last)
        res["cpu"] = R.cpu_summary(last)
        return res

"""Backends: where readings come from.

Pmd3CliBackend runs the `pymobiledevice3` command line (not its Python API, which changes more often).
Commands were checked against the pymobiledevice3 documentation on 2026-11-15:
  usbmux list · lockdown info · diagnostics battery single ·
  developer dvt sysmon process monitor threshold <pct> (NDJSON) · syslog live --format json ·
  crash pull <dir> · developer core-device sysdiagnose <out>
UNVERIFIED (plan section 4, needs the Duo): the exact JSON keys of `diagnostics battery single` and of the
sysmon process stream on iOS 27, whether `--udid` selects a device on every command, and whether per-process
monitoring works without extra setup (the docs say developer services need Developer Mode; on iOS 17.4+ the CLI
brings up a no-root tunnel itself). Every parser here tolerates missing keys.

SimulatedBackend produces believable synthetic data so the engine, the Mac app and the iOS import can be
tested without a phone. Its output is marked as simulated everywhere.
"""

import json
import math
import os
import random
import shutil
import subprocess
import time
from datetime import datetime, timezone


def report_iso(ts):
    return datetime.fromtimestamp(ts, tz=timezone.utc).isoformat()


class BackendError(Exception):
    pass


def parse_battery(raw):
    """Normalises the battery registry from `diagnostics battery single` (IORegistry AppleSmartBattery).

    Key names were checked against a real iPhone Duo on iOS 27.2.1 (2026-11-15): top level CurrentCapacity
    (percent), MaxCapacity (100), CycleCount, Amperage and InstantAmperage (mA, negative when draining),
    Voltage (mV), IsCharging, ExternalConnected; BatteryData.DesignCapacity, FullChargeCapacity and
    NominalChargeCapacity (mAh); AdapterDetails.Watts and IsWireless; ChargerData.SlowChargingReason and
    TimeChargingThermallyLimited. That phone reported NO temperature key, so temperatureC is only filled
    when a Temperature key exists; its scale (hundredths, tenths or degrees) is chosen by magnitude.
    """
    if not isinstance(raw, dict):
        return {"keysUsed": []}
    for nest in ("IORegistry", "battery", "Battery"):
        if isinstance(raw.get(nest), dict):
            raw = raw[nest]
            break
    used = []

    def pick(*names, src=None):
        d = raw if src is None else (raw.get(src) if isinstance(raw.get(src), dict) else {})
        for n in names:
            if n in d and d[n] is not None:
                used.append(n if src is None else src + "." + n)
                return d[n]
        return None

    def num(v):
        return v if isinstance(v, (int, float)) and not isinstance(v, bool) else None

    out = {}
    t = num(pick("Temperature", "BatteryTemperature", "temperature"))
    if t is not None:
        out["temperatureC"] = t / 100.0 if abs(t) > 1000 else (t / 10.0 if abs(t) > 200 else float(t))
    cur = num(pick("CurrentCapacity", "BatteryCurrentCapacity"))
    mx = num(pick("MaxCapacity"))
    if cur is not None:
        if mx is not None and 0 < mx <= 100:
            out["level"] = max(0.0, min(1.0, cur / float(mx)))
        elif cur <= 100:
            out["level"] = cur / 100.0
    charging = pick("IsCharging", "Charging")
    if charging is not None:
        out["charging"] = bool(charging)
    ext = pick("ExternalConnected")
    if ext is not None:
        out["external"] = bool(ext)
    for key, names, src in (("cycleCount", ("CycleCount",), None),
                            ("amperageMilliamps", ("Amperage",), None),
                            ("instantAmperageMilliamps", ("InstantAmperage",), None),
                            ("voltageMillivolts", ("Voltage",), None),
                            ("designCapacity", ("DesignCapacity",), "BatteryData"),
                            ("fullChargeCapacity", ("FullChargeCapacity", "AppleRawMaxCapacity"), "BatteryData"),
                            ("nominalChargeCapacity", ("NominalChargeCapacity",), "BatteryData"),
                            ("adapterWatts", ("Watts",), "AdapterDetails"),
                            ("slowChargingReason", ("SlowChargingReason",), "ChargerData"),
                            ("timeChargingThermallyLimited", ("TimeChargingThermallyLimited",), "ChargerData")):
        v = num(pick(*names, src=src))
        if v is None and src is not None:
            v = num(pick(*names))  # older layouts keep these at the top level
        if v is not None:
            out[key] = v
    wl = pick("IsWireless", src="AdapterDetails")
    if wl is not None:
        out["isWireless"] = bool(wl)
    if out.get("designCapacity") and out.get("fullChargeCapacity"):
        ratio = 100.0 * out["fullChargeCapacity"] / out["designCapacity"]
        # INFERRED: Settings > Battery Health may use a different measure and caps at 100%.
        out["maxCapacityEstimate"] = round(min(100.0, ratio), 1)
        out["fullChargeOverDesignPercent"] = round(ratio, 1)
    out["keysUsed"] = used
    return out


def parse_process_line(line):
    """One NDJSON line from the sysmon process stream -> list of {name, pid, cpu, footprint}.

    The stream may emit one process per line or a list; both are accepted.
    """
    try:
        obj = json.loads(line)
    except ValueError:
        return []
    items = obj if isinstance(obj, list) else [obj]
    out = []
    for p in items:
        if not isinstance(p, dict):
            continue
        name = p.get("name") or p.get("procName") or p.get("execName")
        cpu = p.get("cpuUsage", p.get("cpu"))
        if name is None or not isinstance(cpu, (int, float)):
            continue
        # sysmon on iOS 27.2 reports percent of one core (seen up to 81 on the Duo). Values are kept as
        # given; rates.cpu_scale flags a snapshot whose values are all small enough to be fractions.
        pct = float(cpu)
        out.append({"name": str(name), "pid": p.get("pid"), "cpu": pct,
                    "footprint": p.get("physFootprint")})
    return out


def _run(args, timeout, env=None):
    try:
        return subprocess.run(args, capture_output=True, text=True, timeout=timeout, env=env)
    except subprocess.TimeoutExpired:
        raise BackendError("Timed out after %ds: %s" % (timeout, " ".join(args[1:4])))
    except FileNotFoundError:
        raise BackendError("Not found: %s" % args[0])


class Pmd3CliBackend(object):
    """pymobiledevice3 command line, version 11.55.0 checked locally on 2026-11-15.

    The device is chosen with the PYMOBILEDEVICE3_UDID environment variable rather than `--udid`, so the
    identifier never appears in a command line or a log. `wifi=True` sets PYMOBILEDEVICE3_NATIVE=1, which
    reaches the iOS 17+ tunnel through macOS's own `remoted` (no root, no Xcode). The docs warn it can
    briefly take the device away from Xcode and devicectl. It is the fallback when the phone is not seen
    over USB, e.g. after a restart (that happened on the Duo on 2026-11-15).
    """
    name = "pymobiledevice3"

    def __init__(self, executable=None, udid=None, wifi=False):
        self.exe = executable or os.environ.get("VITALS_PMD3") or shutil.which("pymobiledevice3")
        self.udid = udid
        self.wifi = wifi
        if not self.exe:
            raise BackendError(
                "pymobiledevice3 was not found. The packaged Vitals Companion app bundles it; for development, "
                "create companion/engine/.venv and install it there, or set VITALS_PMD3.")

    @property
    def transport(self):
        return "wifi" if self.wifi else "usb"

    def _env(self):
        env = dict(os.environ)
        if self.udid:
            env["PYMOBILEDEVICE3_UDID"] = self.udid
        if self.wifi:
            env["PYMOBILEDEVICE3_NATIVE"] = "1"
        return env

    def _json(self, *cmd, timeout=60):
        r = _run([self.exe] + list(cmd), timeout, self._env())
        if r.returncode != 0:
            raise BackendError("pymobiledevice3 %s failed: %s" % (" ".join(cmd), r.stderr.strip()[-400:]))
        try:
            return json.loads(r.stdout)
        except ValueError:
            # JSONL (one object per line) is also accepted.
            lines = [l for l in r.stdout.splitlines() if l.strip()]
            try:
                return [json.loads(l) for l in lines]
            except ValueError:
                raise BackendError("Expected JSON from `%s`, got: %s" % (" ".join(cmd), r.stdout[:200]))

    def list_devices(self):
        r = _run([self.exe, "usbmux", "list"], 30)
        try:
            return json.loads(r.stdout)
        except ValueError:
            return []

    def device_info(self):
        return self._json("lockdown", "info")

    def battery(self):
        return self._json("diagnostics", "battery", "single")

    def developer_mode(self):
        """True/False, or None when it cannot be read. Works without Developer Mode (amfi service)."""
        try:
            r = _run([self.exe, "amfi", "developer-mode-status"], 30, self._env())
        except BackendError:
            return None
        out = r.stdout.strip().lower()
        return True if out.startswith("true") else False if out.startswith("false") else None

    def process_snapshot(self):
        """One `developer dvt sysmon process single` snapshot: a list of per-process dicts with cumulative
        counters. Needs Developer Mode (tier 2)."""
        snap = self._json("developer", "dvt", "sysmon", "process", "single", timeout=120)
        return snap, time.time()

    def process_stream(self, threshold=1):
        p = subprocess.Popen([self.exe, "developer", "dvt", "sysmon", "process", "monitor", "threshold", str(threshold)],
                             stdout=subprocess.PIPE, stderr=subprocess.PIPE, text=True, bufsize=1, env=self._env())
        try:
            for line in p.stdout:
                yield line
        finally:
            p.terminate()

    def syslog_stream(self):
        p = subprocess.Popen([self.exe, "syslog", "live", "--format", "json"], stdout=subprocess.PIPE,
                             stderr=subprocess.DEVNULL, text=True, bufsize=1, env=self._env())
        try:
            for line in p.stdout:
                yield line
        finally:
            p.terminate()

    def pull_crashes(self, out_dir):
        """All files from the phone's crash and analytics folder (crash reports, *.diskwrites_resource,
        daily Analytics, Retired/). Works without Developer Mode (tier 1) and without Xcode."""
        r = _run([self.exe, "crash", "pull", out_dir], 900, self._env())
        if r.returncode != 0:
            raise BackendError("crash pull failed: " + r.stderr.strip()[-400:])

    def sysdiagnose(self, out_path):
        r = _run([self.exe, "developer", "core-device", "sysdiagnose", out_path], 1800, self._env())
        if r.returncode != 0:
            raise BackendError("sysdiagnose failed: " + r.stderr.strip()[-400:])


class DevicectlBackend(object):
    """Apple's `xcrun devicectl`, present only when Xcode is installed. Used on 2026-11-15 with Xcode 27.2:
    `list devices`, `device info details|processes|lockState`, `device copy from --domain-type systemCrashLogs`.
    It has no battery or per-process-rate command, so it covers logs, device details and lock state only."""
    name = "devicectl"

    def __init__(self, device=None):
        if not shutil.which("xcrun"):
            raise BackendError("xcrun was not found (Xcode is not installed).")
        self.device = device

    @property
    def transport(self):
        return "usb"

    def _json(self, *cmd, timeout=120):
        import tempfile
        with tempfile.TemporaryDirectory() as d:
            out = os.path.join(d, "out.json")
            args = ["xcrun", "devicectl"] + list(cmd)
            if self.device and cmd[:1] == ("device",):
                args += ["--device", self.device]
            args += ["--json-output", out, "--quiet"]
            r = _run(args, timeout)
            if r.returncode != 0:
                raise BackendError("devicectl %s failed: %s" % (" ".join(cmd[:3]), (r.stderr or r.stdout).strip()[-400:]))
            with open(out) as f:
                return json.load(f)

    def list_devices(self):
        try:
            return self._json("list", "devices").get("result", {}).get("devices", [])
        except BackendError:
            return []

    def device_info(self):
        d = self._json("device", "info", "details").get("result", {})
        # Key paths checked against a real `device info details` (Xcode 27.2, 2026-11-15).
        hw, sw = d.get("hardwareProperties", {}), d.get("deviceProperties", {})
        return {"DeviceName": sw.get("name"),
                "ProductType": hw.get("productType"), "ProductVersion": sw.get("osVersionNumber"),
                "BuildVersion": sw.get("osBuildUpdate"), "DeveloperModeStatus": sw.get("developerModeStatus")}

    def lock_state(self):
        try:
            r = self._json("device", "info", "lockState").get("result", {})
        except BackendError:
            return None
        # Seen: {"passcodeRequired": false, "unlockedSinceBoot": true}. passcodeRequired true = locked.
        v = r.get("passcodeRequired")
        return None if v is None else bool(v)

    def processes(self):
        return self._json("device", "info", "processes").get("result", {}).get("runningProcesses", [])

    def pull_crashes(self, out_dir):
        os.makedirs(out_dir, exist_ok=True)
        args = ["xcrun", "devicectl", "device", "copy", "from", "--domain-type", "systemCrashLogs",
                "--source", ".", "--destination", out_dir]
        if self.device:
            args += ["--device", self.device]
        r = _run(args, 900)
        if r.returncode != 0:
            raise BackendError("devicectl copy failed: " + (r.stderr or r.stdout).strip()[-400:])

    def battery(self):
        raise BackendError("devicectl has no battery command (Xcode 27.2).")


class SimulatedBackend(object):
    """Synthetic phone: warms up, a busy process appears, battery drains. Clearly labelled as simulated."""
    name = "simulated"

    def __init__(self, seed=7, speed=1.0):
        self.rng = random.Random(seed)
        self.start = time.time()
        self.speed = speed

    def _t(self):
        return (time.time() - self.start) * self.speed

    def list_devices(self):
        return [{"Identifier": "SIMULATED-0000", "DeviceName": "Simulated iPhone Duo", "ProductType": "iPhone19,4",
                 "ConnectionType": "USB"}]

    def device_info(self):
        return {"DeviceName": "Simulated iPhone Duo", "ProductType": "iPhone19,4", "ProductVersion": "27.1",
                "BuildVersion": "25B80", "UniqueDeviceID": "SIMULATED-0000", "SerialNumber": "SIMULATEDSERIAL0"}

    def battery(self):
        t = self._t()
        temp = 31.0 + 9.0 * (1 - math.exp(-t / 120.0)) + self.rng.uniform(-0.2, 0.2)
        # Shaped like the real registry. The real Duo had no temperature key; the simulator keeps one so the
        # heat path stays testable, and says so in its generator label.
        return {"Temperature": int(temp * 100), "CurrentCapacity": max(5, int(80 - t / 30.0)), "MaxCapacity": 100,
                "IsCharging": False, "ExternalConnected": False, "CycleCount": 431, "Amperage": -620,
                "InstantAmperage": -655, "Voltage": 3870, "Serial": "SIMULATEDSERIAL",
                "BatteryData": {"DesignCapacity": 4500, "FullChargeCapacity": 3900, "NominalChargeCapacity": 3880},
                "AdapterDetails": {"Watts": 0, "IsWireless": False},
                "ChargerData": {"SlowChargingReason": 0, "TimeChargingThermallyLimited": 0}}

    transport = "usb"
    restarted = False

    def developer_mode(self):
        return True

    def restart(self):
        """Simulates the phone restarting: new pids and start times, counters from zero, churn stops."""
        self.restarted = True
        self.restart_at = self._t()

    def process_snapshot(self):
        t = self._t()
        r = self.restarted
        base = self.restart_at if r else 0.0
        el = t - base
        def proc(name, pid, mb_per_min, cpu, start_written=0.0):
            return {"name": name, "pid": pid + (1000 if r else 0), "uniqueID": pid + (1000 if r else 0),
                    "startAbsTime": 1000 + (int(base) if r else 0), "cpuUsage": cpu,
                    "diskBytesWritten": int(start_written + mb_per_min * 1e6 * el / 60.0), "diskBytesRead": 0,
                    "timestamp": report_iso(self.start + t)}
        if not r:
            procs = [proc("bird", 306, 230, 4.1, 102.4e9), proc("cloudd", 153, 227, 13.0, 115.7e9),
                     proc("nsurlsessiond", 120, 8, 1.2), proc("healthd", 140, 5, 0.8)]
        else:
            procs = [proc("bird", 306, 2.7, 0.2), proc("cloudd", 153, 2.0, 0.4),
                     proc("nsurlsessiond", 120, 1, 0.1), proc("healthd", 140, 33, 3.7)]
        procs += [proc("sysmond", 2722, 0, 27.4), proc("DTServiceHub", 2718, 0, 11.0)]
        return procs, self.start + t

    def process_stream(self, threshold=1):
        while True:
            t = self._t()
            procs = [{"name": "mediaanalysisd", "pid": 211, "cpuUsage": 60 + 30 * math.sin(t / 20.0)},
                     {"name": "SpringBoard", "pid": 34, "cpuUsage": 5 + self.rng.uniform(0, 3)},
                     {"name": "Instagram", "pid": 1402, "cpuUsage": 25 if t > 30 else 2}]
            for p in procs:
                if p["cpuUsage"] >= threshold:
                    yield json.dumps(p) + "\n"
            time.sleep(1.0 / self.speed)

    def syslog_stream(self):
        n = 0
        while True:
            n += 1
            yield json.dumps({"timestamp": datetime.now(timezone.utc).isoformat(), "process": "thermalmonitord",
                              "message": "simulated log line %d" % n}) + "\n"
            time.sleep(0.5 / self.speed)

    def pull_crashes(self, out_dir):
        os.makedirs(out_dir, exist_ok=True)
        with open(os.path.join(out_dir, "SIMULATED-crash.ips"), "w") as f:
            f.write('{"bug_type":"309","name":"Simulated","timestamp":"2027-01-15 08:00:00.00 +0000"}\n{"procName":"Simulated"}\n')

    def sysdiagnose(self, out_path):
        raise BackendError("The simulated backend has no sysdiagnose.")

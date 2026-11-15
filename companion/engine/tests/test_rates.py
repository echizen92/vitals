"""Rates, resets, overhead, conditions, redaction and the before/after flow. Fixtures are synthetic but
shaped like the real iOS 27.2 sysmon snapshot and battery registry (key names only; no real values)."""

import json
import os
import shutil
import tempfile
import unittest

from vitals_companion import rates as R
from vitals_companion.backend import parse_battery, SimulatedBackend
from vitals_companion.capture import Capture
from vitals_companion.redact import redact, redact_text, collect_ids
from vitals_companion import cli


def proc(name, pid, written, cpu, ts, start=1000, uid=None):
    return {"name": name, "pid": pid, "uniqueID": uid if uid is not None else pid, "startAbsTime": start,
            "diskBytesWritten": written, "diskBytesRead": 0, "cpuUsage": cpu, "timestamp": ts}


T0 = "2026-11-15T02:51:48.000000+00:00"
T1 = "2026-11-15T02:56:48.000000+00:00"  # 300 s later


class RateTests(unittest.TestCase):
    def snaps(self):
        a = [proc("bird", 306, 100_000_000_000, 4.0, T0), proc("cloudd", 153, 115_000_000_000, 2.7, T0),
             proc("sysmond", 2722, 0, 27.0, T0), proc("healthd", 140, 5_000, 0.5, T0)]
        b = [proc("bird", 306, 101_150_000_000, 5.4, T1), proc("cloudd", 153, 116_135_000_000, 13.1, T1),
             proc("sysmond", 2722, 0, 26.0, T1), proc("healthd", 999, 10, 0.4, T1, start=5000)]
        return R.normalise(a, 0)[0], R.normalise(b, 0)[0]

    def test_rate_from_two_snapshots(self):
        a, b = self.snaps()
        res = R.compute_rates(a, b)
        bird = next(r for r in res["rates"] if r["process"] == "bird")
        self.assertAlmostEqual(bird["bytesWrittenPerMinute"], 230e6, delta=1e6)
        self.assertAlmostEqual(bird["to"] - bird["from"], 300, delta=0.01)

    def test_restart_is_a_new_series(self):
        a, b = self.snaps()
        res = R.compute_rates(a, b)
        self.assertFalse(any(r["process"] == "healthd" for r in res["rates"]))
        self.assertTrue(any(r["process"] == "healthd" for r in res["resets"]))

    def test_counter_going_down_is_a_reset(self):
        a = R.normalise([proc("x", 1, 500, 1, T0)], 0)[0]
        b = R.normalise([proc("x", 1, 100, 1, T1)], 0)[0]
        res = R.compute_rates(a, b)
        self.assertEqual(res["rates"], [])
        self.assertEqual(res["resets"][0]["reason"], "counter went down (counter reset)")

    def test_too_short_window_gives_no_rate(self):
        a = R.normalise([proc("x", 1, 0, 1, "2026-11-15T00:00:00+00:00")], 0)[0]
        b = R.normalise([proc("x", 1, 10**9, 1, "2026-11-15T00:00:05+00:00")], 0)[0]
        self.assertEqual(R.compute_rates(a, b)["rates"], [])

    def test_overhead_is_separate(self):
        _, b = self.snaps()
        c = R.cpu_summary(b)
        self.assertAlmostEqual(c["measurementOverheadPercent"], 26.0)
        self.assertAlmostEqual(c["withoutOverheadPercent"], c["totalPercent"] - 26.0, places=1)

    def test_ambiguous_cpu_units_are_flagged(self):
        _, notes = R.normalise([proc("x", 1, 0, 0.4, T0), proc("y", 2, 0, 1.1, T0)], 0)
        self.assertTrue(notes and "unclear" in notes[0])
        _, notes = R.normalise([proc("x", 1, 0, 40.0, T0)], 0)
        self.assertEqual(notes, [])

    def test_totals_have_no_invented_start_date(self):
        _, b = self.snaps()
        t = R.totals(b)
        self.assertEqual([x["process"] for x in t], ["cloudd", "bird"])
        self.assertIsNone(t[0]["since"])

    def test_compare_windows_and_conditions(self):
        before = [{"process": "bird", "bytesWrittenPerMinute": 230e6, "cpuPercent": 4, "overhead": False},
                  {"process": "sysmond", "bytesWrittenPerMinute": 0, "cpuPercent": 27, "overhead": True}]
        after = [{"process": "bird", "bytesWrittenPerMinute": 2.7e6, "cpuPercent": 0.2, "overhead": False}]
        rows = R.compare_windows(before, after)
        self.assertEqual(rows[0]["process"], "bird")
        self.assertEqual(rows[0]["afterMBPerMinute"], 2.7)
        m = R.condition_mismatches({"charging": True, "transport": "usb"}, {"charging": False, "transport": "wifi"})
        self.assertEqual(len(m), 2)
        self.assertIn("connection was usb before and wifi after", m)
        self.assertIn("Conditions changed", cli._verdict(rows, m))
        self.assertIn("stopped it", cli._verdict(rows, []))


class RegistryTests(unittest.TestCase):
    REG = {"CurrentCapacity": 91, "MaxCapacity": 100, "CycleCount": 1, "Amperage": 427, "InstantAmperage": 431,
           "Voltage": 4400, "IsCharging": True, "ExternalConnected": True, "Serial": "SERIALXYZ123",
           "BatteryData": {"DesignCapacity": 4000, "FullChargeCapacity": 4120, "NominalChargeCapacity": 4100},
           "AdapterDetails": {"Watts": 15, "IsWireless": False},
           "ChargerData": {"SlowChargingReason": 0, "TimeChargingThermallyLimited": 0}}

    def test_real_shape(self):
        b = parse_battery(self.REG)
        self.assertEqual(b["designCapacity"], 4000)
        self.assertEqual(b["fullChargeCapacity"], 4120)
        self.assertEqual(b["adapterWatts"], 15)
        self.assertFalse(b["isWireless"])
        self.assertEqual(b["maxCapacityEstimate"], 100.0, "capped like Settings")
        self.assertEqual(b["fullChargeOverDesignPercent"], 103.0)
        self.assertNotIn("temperatureC", b, "no temperature key on the real phone: none invented")
        self.assertAlmostEqual(b["level"], 0.91)


class RedactionTests(unittest.TestCase):
    def test_ids_removed_everywhere(self):
        info = {"UniqueDeviceID": "00008150-001A2B3C4D5E6F70", "SerialNumber": "ABCD1234XYZ", "DeviceName": "Phone"}
        ids = collect_ids(info)
        doc = redact({"device": info, "notes": ["failed for 00008150-001A2B3C4D5E6F70 serial ABCD1234XYZ"]}, ids)
        text = json.dumps(doc)
        self.assertNotIn("00008150-001A2B3C4D5E6F70", text)
        self.assertNotIn("ABCD1234XYZ", text)
        self.assertEqual(doc["device"]["DeviceName"], "Phone")
        self.assertEqual(redact_text("udid 0123456789abcdef0123456789abcdef01234567"), "udid [redacted]")


class SimulatedFlowTests(unittest.TestCase):
    def test_capture_has_rates_conditions_and_no_ids(self):
        out = tempfile.mkdtemp()
        try:
            cap = Capture(SimulatedBackend(speed=120), out, seconds=0.6, interval=0.2, syslog=False, crashes=False)
            path = cap.run()
            doc = json.load(open(path))
            text = open(path).read()
            self.assertNotIn("SIMULATED-0000", text)
            self.assertNotIn("SIMULATEDSERIAL", text)
            self.assertNotIn("identifiers", doc["device"])
            self.assertTrue(doc["processRates"], "two snapshots give rates")
            self.assertFalse(any(r["process"] in R.OVERHEAD for r in doc["processRates"]))
            bird = next(r for r in doc["processRates"] if r["process"] == "bird")
            self.assertAlmostEqual(bird["bytesWrittenPerMinute"] / 1e6, 230, delta=5)
            self.assertTrue(doc["processTotals"])
            self.assertEqual(doc["capture"]["accessTier"], 2)
            self.assertEqual(len(doc["capture"]["conditions"]), 2)
            raw = open(os.path.join(out, "battery.ndjson")).read()
            self.assertNotIn("SIMULATEDSERIAL", raw)
        finally:
            shutil.rmtree(out)

    def test_around_action_shows_restart_effect(self):
        out = tempfile.mkdtemp()
        try:
            rc = cli.main(["--simulate", "--speed", "300", "around-action", "--action", "Restart the phone",
                           "--window", "0.5", "--out", out, "--events"])
            self.assertEqual(rc, 0)
            res = json.load(open(os.path.join(out, "around-action.json")))
            top = res["comparison"][0]
            self.assertIn(top["process"], ("bird", "cloudd"))
            self.assertGreater(top["beforeMBPerMinute"], 100)
            self.assertLess(top["afterMBPerMinute"], 10)
            self.assertIn("stopped it", res["verdict"])
            self.assertIn("healthd rose from 5 to 33", res["verdict"])
            self.assertIn("bird", res["restartedProcesses"])
        finally:
            shutil.rmtree(out)


if __name__ == "__main__":
    unittest.main()

import json
import os
import shutil
import tempfile
import unittest

from vitals_companion.backend import parse_battery, parse_process_line, SimulatedBackend
from vitals_companion.capture import Capture
from vitals_companion import report


class ParseTests(unittest.TestCase):
    def test_battery_hundredths(self):
        b = parse_battery({"Temperature": 3050, "CurrentCapacity": 80, "MaxCapacity": 100, "IsCharging": True,
                           "CycleCount": 412, "BatteryData": {"DesignCapacity": 4500, "FullChargeCapacity": 3900}})
        self.assertAlmostEqual(b["temperatureC"], 30.5)
        self.assertAlmostEqual(b["level"], 0.8)
        self.assertTrue(b["charging"])
        self.assertEqual(b["cycleCount"], 412)
        self.assertIn("Temperature", b["keysUsed"])

    def test_battery_scales_and_missing(self):
        self.assertAlmostEqual(parse_battery({"Temperature": 305})["temperatureC"], 30.5)
        self.assertAlmostEqual(parse_battery({"Temperature": 30.5})["temperatureC"], 30.5)
        self.assertNotIn("temperatureC", parse_battery({}))
        self.assertEqual(parse_battery("garbage"), {"keysUsed": []})
        self.assertAlmostEqual(parse_battery({"IORegistry": {"Temperature": 4000}})["temperatureC"], 40.0)

    def test_process_lines(self):
        # Never assume units: values are kept as given (sysmon reports percent of a core on iOS 27.2).
        self.assertEqual(parse_process_line('{"name":"a","pid":1,"cpuUsage":0.5}')[0]["cpu"], 0.5)
        self.assertEqual(parse_process_line('{"name":"a","cpuUsage":42}')[0]["cpu"], 42.0)
        self.assertEqual(len(parse_process_line('[{"name":"a","cpuUsage":1},{"name":"b","cpuUsage":2}]')), 2)
        self.assertEqual(parse_process_line("not json"), [])
        self.assertEqual(parse_process_line('{"pid":3}'), [])

    def test_iso_has_milliseconds(self):
        self.assertEqual(report.iso(1800000000.1234), "2027-01-15T08:00:00.123Z")


class CaptureTests(unittest.TestCase):
    def test_simulated_capture_writes_schema_bundle(self):
        out = tempfile.mkdtemp()
        try:
            events = []
            cap = Capture(SimulatedBackend(speed=20), out, seconds=1.2, interval=0.2, syslog=True, crashes=True, emit=events.append)
            path = cap.run()
            with open(path) as f:
                doc = json.load(f)
            self.assertEqual(doc["schemaVersion"], 1)
            self.assertIn("SIMULATED", doc["generator"])
            self.assertGreater(len(doc["samples"]), 2)
            s = doc["samples"][0]
            self.assertEqual(s["source"], "companion")
            self.assertNotIn("thermal", s, "the companion never invents a thermal state")
            self.assertIn("temperatureC", s)
            self.assertTrue(doc["processSamples"])
            self.assertTrue(any(r["id"] == "battery.temperature" for r in doc["readings"]))
            self.assertTrue(os.path.exists(os.path.join(out, "crashes", "SIMULATED-crash.ips")))
            self.assertTrue(any(e["type"] == "done" for e in events))
        finally:
            shutil.rmtree(out)


if __name__ == "__main__":
    unittest.main()

"""Writes the capture as Vitals report schema v1 (Docs/report-schema.md), so the iOS app can import it."""

from datetime import datetime, timezone

from . import GENERATOR

SCHEMA_VERSION = 1


def iso(ts):
    """ISO 8601 with milliseconds and Z, matching the iOS app's encoder."""
    d = datetime.fromtimestamp(ts, tz=timezone.utc)
    return d.strftime("%Y-%m-%dT%H:%M:%S.") + "%03dZ" % (d.microsecond // 1000)


def charge_state(b):
    if b.get("charging"):
        return "charging"
    if b.get("external") and (b.get("level") or 0) >= 0.99:
        return "full"
    if "charging" in b or "external" in b:
        return "unplugged"
    return "unknown"


def sample(ts, battery):
    """A timeline sample. The companion cannot see iOS's thermal state, so `thermal` is omitted: the app
    treats such samples as temperature-only and never infers a thermal level from degrees."""
    s = {"takenAt": iso(ts), "charge": charge_state(battery), "source": "companion"}
    if "level" in battery:
        s["batteryLevel"] = round(battery["level"], 4)
    if "temperatureC" in battery:
        s["temperatureC"] = round(battery["temperatureC"], 2)
    return s


def reading(rid, label, value, unit, source, ts, area="battery", unverified=True, provenance="measured"):
    r = {"id": rid, "area": area, "label": label, "value": value, "provenance": provenance,
         "source": source, "takenAt": iso(ts), "unverified": unverified}
    if unit:
        r["unit"] = unit
    return r


def _rate(r):
    out = {"process": r["process"], "bytesWrittenPerMinute": round(r["bytesWrittenPerMinute"], 1),
           "from": iso(r["from"]), "to": iso(r["to"])}
    if r.get("cpuPercent") is not None:
        out["cpuPercent"] = r["cpuPercent"]
    return out


def _total(t):
    out = {"process": t["process"], "bytesWritten": t["bytesWritten"], "at": iso(t["at"])}
    if t.get("since"):
        out["since"] = iso(t["since"])
    return out


def build(info, samples, process_samples, battery_last, started, ended, backend_name, notes,
          rates=None, conditions=None, tier=None, measurement=None, averages=None):
    """Device identifiers (UDID, serial) are deliberately NOT written: the capture is meant to be shared."""
    device = {
        "model": info.get("ProductType", "iPhone"),
        "modelIdentifier": info.get("ProductType", "unknown"),
        "osVersion": "iOS " + str(info.get("ProductVersion", "?")),
    }
    if info.get("BuildVersion"):
        device["osBuild"] = info["BuildVersion"]
    src = "Mac companion (%s): battery registry" % backend_name
    readings = []
    b = battery_last or {}
    if "temperatureC" in b:
        readings.append(reading("battery.temperature", "Battery temperature", round(b["temperatureC"], 2), "°C", src, ended))
    if "cycleCount" in b:
        readings.append(reading("battery.cycleCount.companion", "Charge cycles", b["cycleCount"], None, src, ended))
    if "maxCapacityEstimate" in b:
        readings.append(reading("battery.maxCapacity.companion", "Maximum capacity (estimate: full charge ÷ design, capped at 100%)",
                                b["maxCapacityEstimate"], "%", src, ended, provenance="inferred"))
    for key, rid, label, unit in (("designCapacity", "battery.designCapacity", "Design capacity", "mAh"),
                                  ("fullChargeCapacity", "battery.fullChargeCapacity", "Full-charge capacity", "mAh"),
                                  ("amperageMilliamps", "battery.current", "Battery current (negative = draining)", "mA"),
                                  ("adapterWatts", "battery.adapterWatts", "Charger power", "W")):
        if key in b:
            readings.append(reading(rid, label, b[key], unit, src, ended))
    if b.get("timeChargingThermallyLimited"):
        readings.append(reading("battery.thermallyLimited", "Time charging was slowed by heat", b["timeChargingThermallyLimited"],
                                None, src, ended))
    rates = rates or {}
    doc = {
        "schemaVersion": SCHEMA_VERSION,
        "generatedAt": iso(ended),
        "generator": GENERATOR + (" (SIMULATED DATA)" if backend_name == "simulated" else ""),
        "device": device,
        "readings": readings,
        "samples": samples,
        "processSamples": process_samples,
        "processRates": [_rate(r) for r in rates.get("rates", []) if not r.get("overhead")],
        "processTotals": [_total(t) for t in rates.get("totals", [])],
        "imports": [],
        "findings": [],
        "hotSpells": [],
        "hardwareTests": [],
        "redactions": ["Device identifiers (UDID, serial number) removed by the companion."],
        "events": [],
        # Not part of the iOS schema; ignored by the app, kept for people reading the file.
        "capture": {"startedAt": iso(started), "endedAt": iso(ended), "backend": backend_name, "notes": notes,
                    "accessTier": tier, "conditions": conditions or [], "resets": rates.get("resets", []),
                    "wholePhoneCPU": rates.get("cpu"), "batteryKeysUsed": b.get("keysUsed", []),
                    "measurementOverhead": "sysmond, DTServiceHub, remotepairingdeviced, diagnosticd and dtfileserviced are "
                                           "the measurement itself; they are left out of rates, totals and averages.",
                    "measurementCost": measurement,
                    # Percent of one core per process, averaged over readings (a reading without the process counts as 0).
                    "averageCPU": dict(sorted((averages or {}).items(), key=lambda kv: -kv[1])[:30])},
    }
    return doc

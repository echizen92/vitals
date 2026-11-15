# Vitals Companion (Mac)

Reads what an iPhone does not tell its own apps: every crash and analytics log, the battery registry (cycle
count, design and full-charge capacity, current, charger watts), and, with Developer Mode, **which processes are
writing to storage or using the CPU right now**, as rates. Built on
[pymobiledevice3](https://github.com/doronz88/pymobiledevice3).

Licence: **GPL-3.0-or-later** (`LICENSE`), because pymobiledevice3 is GPL-3.0. The iOS app is MIT and contains none of
this code; the two only share a JSON file format (`Docs/report-schema.md`).

## Access tiers (said up front, never pushed)
- **Tier 0, phone only**: the Vitals app with logs shared on the phone. Most findings start here.
- **Tier 1, Mac without Developer Mode**: battery registry and a pull of every log.
- **Tier 2, Mac with Developer Mode**: live per-process rates, before/after an action, sysdiagnose.
`check` tells you which one you have.

## Parts
- `engine/vitals_companion/`: Python 3.9+ package and CLI, standard library only. It runs the `pymobiledevice3`
  command line (or Xcode's `devicectl` for a log pull without anything else installed).
- `MacApp/`: SwiftUI Mac app (`VitalsCompanion` target), designed like the iPhone app (PLAN section 6): the connection in
  plain words on the left, one task at a time on the right (Collect logs, Watch it live, Test a fix), an iPhone menu with
  shortcuts, and a Settings window. Results go to Documents › Vitals unless you choose another folder.

## Packaging (plan 5.13)
Release builds bundle a pinned, self-contained Python runtime with pymobiledevice3 inside the app, so people
install nothing; signed with Developer ID, notarised, offered as a direct download (not the Mac App Store), with
the source and licence notices published. Not built yet (needs the maintainer's Developer ID). For development, use a venv at
`companion/engine/.venv` (git-ignored); the app picks it up automatically.

## Use
```
python3 -m vitals_companion check                          # tier, connection, Developer Mode
python3 -m vitals_companion pull logs --out ~/Desktop/duo-logs        # tier 1; --via devicectl with Xcode
python3 -m vitals_companion capture --seconds 600 --snapshot-every 120 --out ~/Desktop/duo-capture
python3 -m vitals_companion around-action --action "Restart the phone" --window 300 --settle 60
python3 -m vitals_companion snapshot --out a.json ; python3 -m vitals_companion rates a.json b.json
python3 -m vitals_companion --wifi check                   # phone not seen over USB (e.g. after a restart)
python3 -m vitals_companion --simulate capture --seconds 30    # no phone: synthetic, labelled SIMULATED
```
Run from `companion/engine`, or set `PYTHONPATH` to it. AirDrop `capture.vitalscapture` or the logs folder to the
phone and open it in Vitals.

How rates are made: two timestamped snapshots of the same process (name, pid, uniqueID, start time); a restart or a
counter going down starts a new series; `sysmond`, `DTServiceHub` and `remotepairingdeviced` are the measurement
itself and are left out; charging, charger watts, lock state and connection are recorded so before/after
comparisons can say when conditions changed. UDID and serial are removed from everything written.

## Checked and unverified
Checked against the Duo's real files (locally): battery registry key names (no temperature key on that phone),
sysmon snapshot fields, devicectl JSON paths; rates reproduce the diagnostic's figures. Option names checked on
pymobiledevice3 11.55.0. Not yet run against a phone: `check`, Wi-Fi fallback, `amfi developer-mode-status`
output, `around-action` with a real restart (Docs/needs-device.md).

Tests: `cd engine && PYTHONPATH=. python3 -m unittest discover -s tests` (17).

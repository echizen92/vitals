# M10 Mac companion

Updated 2026-11-15 after the real Duo diagnostic (plan 4a, 4b, 4c) and the packaging decision (5.13).

## Built
- **Engine** (`companion/engine/vitals_companion`, Python 3.9+, stdlib only). Commands:
  - `check`: which access tier this Mac has (plan 4c), in plain words, with what the next tier would add.
    Developer Mode is stated up front and never pushed; tier 1 says most problems can be found without it.
    When the phone is not seen over USB it prints the walkthrough (unlock, Trust, data cable, replug, then `--wifi`).
  - `probe`: device and battery registry.
  - `capture`: battery registry every few seconds, a per-process snapshot at the start, the end and optionally
    every N seconds, the per-second CPU stream, syslog, then a log pull. Bundle in `capture.vitalscapture`.
  - `snapshot` / `rates A B`: one snapshot to a file; write rates between two.
  - `around-action`: proof by intervention. Measure a window, the person does the action (restart, iCloud Drive
    off and on, charger), wait to settle, measure again; compare per process, flag condition changes and list
    processes that restarted across the action. Plain verdict ("bird went from 230 to 3 MB a minute…").
  - `pull logs` (alias `crashes`): every crash and analytics file. `--via devicectl` uses Xcode's tool with no
    install; the default uses the bundled pymobiledevice3 so people without Xcode get the same pull.
  - Global `--wifi` (sets `PYMOBILEDEVICE3_NATIVE=1`, macOS's own tunnel, no root) and `--udid` (passed as
    `PYMOBILEDEVICE3_UDID`, so it never appears in a command line).
- **Rates** (`rates.py`, plan 4b items 6 to 9): identity is name + pid + uniqueID + startAbsTime; a changed identity
  or a counter that went down is a new series (reset), never a rate. Each process's own timestamp is the clock.
  Windows under 20 s give no rate. Measurement overhead (`sysmond`, `DTServiceHub`, `remotepairingdeviced`) is
  reported separately and left out of rates and totals. Units are never assumed: CPU is percent of a core when any
  value is above 1.5, otherwise the result says the unit is unclear. `procAge`/`startAbsTime` units are unconfirmed,
  so no "running since" date is derived.
- **Battery registry** parser rewritten to the real key layout (top-level CurrentCapacity, CycleCount, Amperage,
  InstantAmperage, Voltage, IsCharging, ExternalConnected; `BatteryData.DesignCapacity/FullChargeCapacity/
  NominalChargeCapacity`; `AdapterDetails.Watts/IsWireless`; `ChargerData.SlowChargingReason/
  TimeChargingThermallyLimited`). Maximum capacity is an INFERRED estimate (full charge ÷ design, capped at 100%,
  the raw ratio kept beside it): the new Duo reads 103%. The Duo had **no temperature key**, so none is invented.
- **Conditions** per capture (charging, power connected, adapter watts, wireless, lock state when known,
  connection usb/wifi), recorded at start and end; mismatches are written into the notes and the verdict.
- **Redaction** (`redact.py`): UDID, serial, ECID, devicectl identifiers and similar keys are replaced in the
  bundle, raw battery file, snapshots, syslog lines, notes and error messages (whole-token match; a test caught a
  substring bug). The bundle no longer carries a `device.identifiers` block at all.
- **Bundle** now has `processRates`, `processTotals` (the iOS case engine reads both) and, outside the schema,
  `capture.accessTier`, `conditions`, `resets`, `wholePhoneCPU`.
- **devicectl backend**: `list devices`, `device info details|lockState|processes`, `device copy from
  --domain-type systemCrashLogs`. Key paths checked against the real JSON from the diagnostic.
- **Mac app, redesigned to PLAN section 6** (2026-11-15). Files: `CompanionApp.swift` (app, window, iPhone menu,
  Settings), `EngineRunner.swift` (model: job and phase, readings, save folder, AirDrop, announcements),
  `ConnectionColumn.swift`, `Stages.swift`, `Parts.swift`, `PulseHero.swift`.
  - Left column: the pulse hero (absent: dashed phone and flat line; searching: a sweep; connected: the pulse with
    a slow glow; measuring: beating), the connection in words ("Connected, full access", "Connected: logs and
    battery", "No iPhone found" with four steps, or "The measuring engine did not start" with the reason), the
    device ("iPhone Duo · iOS 27.1 · USB"), what this Mac can read, a Wi-Fi switch. Developer Mode is described
    as optional and never pushed.
  - Home: three task cards (Collect logs, Watch it live, Test a fix), each saying what it needs; unavailable ones
    say why and what to do instead.
  - Logs: progress, then the file count, where it was saved, AirDrop to iPhone and Show in Finder.
  - Live: progress with time left, large temperature numeral with a word (normal, warm, hot, very hot: a rough
    guide for battery temperature), battery level and charging, "busiest right now" as settling bars, the
    temperature chart. Finished: the top writer in one sentence, then the bars, then AirDrop and Show in Finder.
  - Test a fix: choose the change, then a three-step track (Before, Your turn, After); a large "Your turn" card
    with the steps for that change and "It's back" (Return); then the verdict first, with friendly names, and
    before/after bars per process ("Down 99%", "Up 7×").
  - Plain language: ProcessGlossary names first ("iCloud Drive"), raw names second (`bird`), the explanation as
    help text and accessibility hint. "Simulated iPhone" and the Python path live in Settings > Advanced; while
    simulated, the title and left column say so.
  - Motion: house springs (VitalsDesign `Motion`), numeric text transitions, bars that settle, the old stage fading
    out before the new one slides in; `motionLevel` from Reduce Motion (or `-reduceMotion` for checking), with
    still variants everywhere; the hero redraws at 30 fps when resting and not at all under Reduce Motion;
    progress redraws once a second.
  - Accessibility: labels and values for the hero, chart (a spoken summary), bars, progress and step track;
    header traits; announcements at each phase ("Your turn. Restart the phone…", the verdict).
  - Mac conventions: iPhone menu with Check Connection ⌘R, Collect Logs ⌘1, Watch Live ⌘2, Test a Fix ⌘3,
    Stop ⌘., Show in Finder ⇧⌘R, All Tasks ⌘0; a single window (900 × 620 minimum); a Settings window with
    General and Advanced tabs; results in Documents › Vitals (changeable), folders named "Logs 2026-11-15 13.05".
  - Engine change for the app: `around-action --wait` makes the simulated phone wait for "It's back" like a real one.

## Verified, and how
- Engine tests: 17, all passing (`companion/engine/tests`): rates from two snapshots, restart and counter resets, short windows,
  overhead split, ambiguous CPU units, totals without invented dates, before/after comparison and verdicts,
  condition mismatches, registry parsing in the real shape, redaction, a simulated capture with rates and no
  identifiers, and a simulated restart through `around-action`.
- **Against the real Duo snapshots, locally** (the private diagnostic files, read on the maintainer's Mac and not copied anywhere): `rates` reproduces the
  diagnostic's hand-worked figures: bird 229.8 and cloudd 227.2 MB/min before the restart, healthd 33.7 MB/min after;
  whole-phone CPU 44.6% of which 31.3% was measurement overhead. One reset was detected across the post-restart pair.
- pymobiledevice3 11.55.0 (the diagnostic's existing venv) checked locally for option names only: `--native`,
  `PYMOBILEDEVICE3_UDID`, `amfi developer-mode-status`, `sysmon process single`.
- Redesigned Mac app built and run with the simulated phone, looked at in dark and light: home, logs finished,
  live running and finished, your turn, result, the engine-missing state, both Settings tabs (the Advanced tab is not kept as a screenshot because it shows a local path), and a dark run with
  `-reduceMotion` (`Docs/screens/m10-mac-*.jpg`). Return triggers "It's back"; the iPhone menu lists all seven
  commands. Fixed on the way: overlapping stages during the change, a departing stage flashing "Collecting logs",
  a grey progress bar (macOS ignores the tint), identical chart labels on short watches, the result below the fold,
  raw names in the verdict, two accent buttons on one result, a 12-hour folder time without AM/PM, and "No iPhone
  found" shown when the real problem was a missing pymobiledevice3.
- Earlier, the first Mac app (now replaced) ran with the simulated phone: access panel; a 1-minute capture with temperature chart, busy
  processes and the "Writing most" rates (`Docs/screens/m10-companion-capture.jpg`); a before/after run with the
  "your turn" card and the result table and verdict (`m10-companion-before-after.jpg`). Bugs found and fixed on the
  way: a cut-off layout (both columns now scroll), `--speed`/`--wifi` rejected after the subcommand, terminal
  wording in the app's prompt, and a verdict that ignored processes whose writing went up (healthd 5 → 33).
- The iOS importer reads the engine's new bundle: `processRates`/`processTotals` decode, and fed to the case engine
  with an iCloud size fact they produce the stuck-sync hypothesis (`CompanionImportTests`, fixture regenerated).

## Not verified
- Redesign: VoiceOver was not walked through (labels, values and announcements are in the code, not heard);
  AirDrop was not sent (no nearby device); motion was judged from stills and a short look, not measured; the
  real-phone states (tier 1 card wording, Wi-Fi after a restart) need the Duo.
- **No new command was run against the phone** (none connected). `check`, Wi-Fi fallback, `developer-mode-status`
  output format, devicectl copy with `--source .`, lock state over pymobiledevice3 (left unknown) and the
  around-action flow on a real restart all wait for the Duo.
- Which commands work with Developer Mode **off** (expected: lockdown info, battery registry, crash pull, syslog)
  is a plan 4c item to record on the device.
- Packaging (5.13): the bundled runtime is designed for, not built. See needs-device.md "Release".

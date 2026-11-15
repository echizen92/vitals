# Needs the physical iPhone Duo

Everything below was built and tested with synthetic fixtures or injected values in the simulator. None of it is
device-verified. Tick items off as they are checked on the Duo (plan §11).

## Setup
- [ ] Register `sg.com.vitals.app`, `sg.com.vitals.app.widgets`, `sg.com.vitals.app.share` and the app group
      `group.sg.com.vitals.app` on team ETR554P9HN; enable NFC Tag Reading for the app id. (§11.6)
- [ ] First device build: confirm signing works for all three targets.

## Probes (M1)
- [ ] Battery level and state are reported (simulator gives none). Check level matches Settings > Battery.
- [ ] Thermal state changes nominal → fair → serious while the phone heats (e.g. camera + charging in the sun),
      and the app takes a sample on each change.
- [ ] Storage values match Settings > General > iPhone Storage (roughly; iOS counts differently).
- [ ] `os_proc_available_memory` returns a plausible value; physical memory matches the Duo's spec.
- [ ] Network probe on Wi-Fi, cellular, with Low Data Mode, with a VPN, and with iCloud Private Relay on:
      does the tunnel heuristic false-positive on Private Relay?
- [ ] Model identifier is `iPhone19,4` (from the simulator profile) and the phone model draws as a Duo.
- [ ] `UIDevice.name` returns "iPhone" (generic) without the device-name entitlement.

## Sampling and heat (M2)
- [ ] Heat the phone (camera + charging, or a game) with Vitals open: samples appear at each thermal change and a
      hot spell is listed with sensible start, duration and drain.
- [ ] Leave the app closed for a day: count `background` samples to see how often iOS grants refresh time.
- [ ] Turn on heat alerts and get hot: does a notification arrive, and how late?
- [ ] Scrub the timeline: selection haptic fires when entering a hot spell.

## Log import (M3)
- [ ] Settings > Privacy & Security > Analytics & Improvements > Analytics Data > a file > Share: Vitals appears
      in the share sheet, says "Saved to Vitals", and the file is read next time the app opens.
- [x] Real analytics record names read from the Duo's own files (2026-11-15, locally, never committed) and used
      as exact names. Maximum capacity is NOT in the analytics file; cycle count is.
- [ ] Share the daily file through the one-share flow (newest daily analytics first) and confirm Vitals reads it
      without the Mac.
- [ ] A `*.cpu_resource*.ips`, a `JetsamEvent*.ips`, an app crash, a hang (if any) and a `panic-full` (if any):
      check process, time and detail. Keep redacted copies as fixtures.
- [ ] Record the real `bug_type` values for cpu_resource, wakeups, hang, panic (diskwrites_resource 145 seen on the
      Duo; analytics day files read).
- [ ] A sysdiagnose (volume up + down + side button, then Analytics Data): time to stream it, memory use, and
      what reports it holds. Does it contain thermal logs worth reading (they are skipped today)?
- [ ] After a real hot spell, share that day's files: do the leads make sense?

## Design and motion (M5)
- [ ] Instruments (Energy Log / Power Profiler) on the Duo: run a check-up and leave the Heat screen open at
      fair/serious for 5 minutes. Record CPU/GPU cost; the field must not visibly heat the phone. (§11.4)
- [ ] Duo drawing: closed shows the outer body with the corner camera; opening turns it into one wide body with a
      crease (no two separate phones); partly open narrows it. Onboarding on the inner display: picture and words
      side by side.
- [ ] Unfold the Duo with Vitals open: the phone drawing should open with the hinge; the check-up should switch to
      scorecard + detail side by side; the Heat screen to two columns. Partly open (book pose): nothing important
      under the fold.
- [ ] 120 Hz: scan sweep and springs look smooth.
- [ ] Release build cold launch time (the Debug simulator spends ~4 s in dyld).

## Widgets (M6)
- [ ] Add all four widgets (Home Screen and Lock Screen). Leave them a day. (§11.3)
- [ ] Count `widget` samples in the Heat timeline (tap a point: the source is shown) to measure real reload cadence.
- [ ] Does the Battery widget show a level? If it shows "—", the extension cannot read `UIDevice.batteryLevel`.
- [ ] Heat the phone: does the Heat widget's state change on its next reload (extension reads thermal state)?
- [ ] Tap each widget: lands on the right screen.

## Hardware tests (M7)
- [ ] Run the whole suite on the Duo. Note anything that misbehaves: earpiece routing, which physical speaker plays
      left/right, the list of microphone data sources, every lens, Camera Control detection, volume detection,
      motion sensors, proximity, Face ID, Bluetooth count, GPS fix, NFC session, flashlight.
- [ ] Both displays and Hinge tests: open/close the phone and confirm the hinge states and angle range reported.
- [ ] Assign the Action button to Vitals' "Run check-up" shortcut; does the Buttons test see it?

## Benchmark and network (M8)
- [ ] Run the benchmark on the Duo (Release build) three times when cool. Record scores and duration; add the
      ranges to `benchmark-baselines.json` (iPhone19,4). Note any heat added.
- [ ] Network test on Wi-Fi and cellular.

## Control and Live Activity (M9)
- [ ] Add the "Run check-up" control to Control Center and the Lock Screen; tapping it opens Vitals and scans.
- [ ] Start a watch session, play a game for 10 minutes: does the Lock Screen / Dynamic Island keep updating? How
      long after locking do updates stop? Is the saved summary sensible?

## Real case and access tiers (plan 4a, 4b, 4c)
- [ ] Tier 0 acceptance on the phone alone: with the stuck-sync day's analytics shared, day one offers the harmless
      restart with its caveat; after the next day's analytics (and the iCloud size fact) the case reads "likely stuck
      iCloud Drive sync" (passes in `DuoCaseTests` with redacted fixtures; not yet on the device).
- [ ] The scheduled re-check reminder (next 09:00) fires and opens the case.
- [ ] Battery screenshot import: Vision reads Settings > Battery (per-app %) and Battery Health (maximum capacity)
      correctly on iOS 27.2, in light and dark, at large text. Note misreads.
- [ ] Sysdiagnose power log: does a sysdiagnose shared to the phone contain per-process hourly energy that Vitals
      could read on the phone (tier 0)? Record the file and format, or "no".
- [ ] Unexpected restart finding: trigger nothing; if one happens naturally, check it is listed with day precision.

## Advice and Optimise (M4b)
- [ ] Every Settings path in `advice.json` (as of iOS 27.2) exists on the Duo with that wording. Fix the
      catalogue where Apple renamed something.
- [ ] App Privacy Report path and wording on iOS 27.2 (Settings > Privacy & Security > App Privacy Report; Data &
      Sensor Access; App Network Activity), and Settings > General > VPN & Device Management.
- [ ] "I did this, measure it": the before/after verdict after a real restart and after offloading an app.

## Quick relief (M4c)
- [ ] Photos clean-up on a real library: scan time and memory for a large library, duplicate and burst detection
      quality, the system delete confirmation, items in Recently Deleted, and the free-space change after
      Recently Deleted is emptied. (Simulator: scan, selection, system confirmation and deletion verified.)
- [x] Shortcuts built and signed with `shortcuts/build.sh` (unqforge at the pinned revision) and bundled.
- [x] Found on the Duo (2026-11-16, build 2): one "Add the Vitals shortcuts" share of five files imported only the
      first, and named it after its file ("Vitals-Cool-down"), so Run (which asks for "Vitals Cool down") failed with
      x-error. Fixed: files named exactly as Run asks ("Vitals Cool down.shortcut"), Undo folded into the same
      shortcut (input text "undo"), three files, an Add button on each row. Build 2 in App Review still has the bug.
- [ ] On the Duo: each row's Add hands its one file to Shortcuts and it is installed as "Vitals Cool down" (with spaces);
      first-run prompts; Run and Undo each take the right branch of the If on Shortcut Input; each action works on
      iOS 27.2 (Low Power Mode, brightness, Always On, restart); `x-success` returns to Vitals.
- [ ] Charge limit: make a "set charge limit" shortcut by hand on the Duo, export it, decompile it with unqforge's
      `tools/decompile.py` to learn the value parameter, then add Protect battery.
- [ ] Shortcuts app is installed and `canOpenURL("shortcuts://")` is true (needs `LSApplicationQueriesSchemes`).

## Mac companion (M10)
- [x] Battery registry key names: read from the Duo's real registry (2026-11-15). No temperature key exists there.
- [x] Rates engine reproduces the diagnostic's figures from the real snapshots (bird 229.8, cloudd 227.2 MB/min).
- [ ] `vitals_companion check` with the Duo on USB, with Developer Mode on and off: tier, connection and the
      "can read" list are right. Record which commands work with Developer Mode OFF (expected: lockdown info,
      battery registry, crash pull, syslog; not sysmon or sysdiagnose).
- [ ] `amfi developer-mode-status` output format (parser accepts "true"/"false" at the start).
- [ ] `around-action` with a real restart: the phone disappears from USB; the after-window runs over `--wifi`;
      condition mismatch (usb → wifi) is reported.
- [ ] `pull logs --via devicectl` (`--source .`) copies the whole folder including `Retired/`.
- [ ] Turn on Developer Mode; run a 10-minute capture while the phone heats (game + charging). Do processes appear?
- [ ] AirDrop the bundle to the Duo, open it in Vitals: temperature chart and leads look right?
- [ ] Wi-Fi with `--wifi` (PYMOBILEDEVICE3_NATIVE): works after a restart; note that it can take the device away
      from Xcode/devicectl for a while.
- [ ] `pull sysdiagnose`: time taken, then share the archive into Vitals.

## Release (needs the maintainer's accounts; not device items but not verifiable here)
- [ ] Companion packaging (5.13): pinned self-contained Python runtime (e.g. python-build-standalone) with
      pymobiledevice3 and its dependencies inside `Vitals Companion.app/Contents/Resources/python`. Record the bundle
      size. Hardened runtime, Developer ID signing of every embedded binary, notarisation and stapling need the maintainer's
      Developer ID; direct download, not the Mac App Store. Publish the companion source and third-party licence
      notices (GPL-3.0 for pymobiledevice3 and the companion).
- [ ] Layered Liquid Glass app icon (Icon Composer). The current icon is the flat design/logo PNGs.
- [ ] App Store privacy label: Photos are analysed on the phone and nothing leaves it, so "Data Not Collected"
      still holds; the Photos usage description is in Info.plist. Confirm when filling the form.

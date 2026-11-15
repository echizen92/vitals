# Vitals: build plan

The app is called Vitals (store listing "Vitals: Phone Check-up"; the name under the icon is "Vitals").

## 1. What this is

A free, open-source iPhone app that gives a full health check-up of the phone it runs on. It serves
light users (plain-language verdicts), repair technicians (hardware tests, deep capture) and engineers
(structured report with raw evidence). It started from a real problem: an iPhone Duo that runs hot with
no visible cause.

Everything in this plan ships: the core check-up, heat and crash analysis, widgets, hardware tests,
Live Activity, controls, and the Mac companion. Milestones in section 10 are a build order, not a cut line.

## 2. Principles (non-negotiable)

- **Private:** all processing on-device. No accounts, no analytics SDKs, no server, no network calls
  except the user-started network test.
- **Public APIs only** in the iOS app. No private frameworks, no private Settings URL schemes.
- **Honest readings:** every value carries a provenance: `measured`, `parsedFromLog` or `inferred`.
  Nothing the app cannot measure gets a number or a score. No fake progress or scanning theatre.
- **Cheap to run:** the app must not heat the phone. Animation cost is measured, and motion calms down
  when thermal state is `serious` or `critical`.
- **Accessible:** Dynamic Type, VoiceOver, Reduce Motion alternatives, sufficient contrast, colour never
  the only signal.
- **Its own identity:** not derived from the maintainer's other apps.

## 3. Hard platform limits (design around these, never fake them)

| Want | Reality |
|---|---|
| Temperature in degrees | Not available on-device. Only `ProcessInfo.thermalState` (nominal, fair, serious, critical). Degrees come from the Mac companion only. |
| Which app is using CPU, battery, memory, data | Not available on-device. Comes from imported logs or the Mac companion. |
| Battery max capacity and cycle count | Not in public APIs. Parsed from an imported analytics file. |
| Continuous background monitoring | Not allowed. Samples are taken while the app is open, on background refresh, and on widget timeline reloads. |
| Reading system logs automatically | Not possible. The user shares a file into the app. No deep link to the Settings screen. |
| Live widgets | Widgets refresh on a system budget (roughly every 15 to 60 minutes). Always show "last updated". |
| Genuine-part and repair history | Visible in Settings only. The report lets the user record it by hand. |

## 4. Data sources

1. **On-device probes (public APIs):** thermal state, battery level and state, Low Power Mode, storage
   (total, free, "important usage" capacity), physical memory and app memory footprint, memory-pressure
   warnings, network path (Wi-Fi, cellular, constrained, expensive, VPN/proxy), device model, OS version,
   uptime, display and fold/hinge posture if public API exposes it.
2. **Imported system files (user shares them in):**
   - Daily analytics file from Settings > Privacy & Security > Analytics & Improvements > Analytics Data
     (name like `Analytics-YYYY-MM-DD-*.ips.ca.synced`): expected to hold battery max capacity and cycle
     count among many other keys.
   - Individual `.ips` reports from the same list: app crashes, hangs, `cpu_resource` reports (a process
     exceeded its CPU budget), `JetsamEvent` reports (memory pressure, with per-process memory).
   - A sysdiagnose archive (`.tar.gz`, several hundred MB): superset of the above plus power and thermal
     logs.
3. **Mac companion over USB or Wi-Fi:** battery temperature, live per-process CPU and energy, syslog,
   crash-report pull, sysdiagnose pull. Built on `pymobiledevice3`.

**Unverified, confirm against real files from the Duo before relying on them** (section 11):
exact key names inside the analytics file; which thermal events appear in which file; what a widget
extension may read (battery level, thermal state); whether hinge angle is public API; pymobiledevice3
command names and whether per-process monitoring needs Developer Mode and a tunnel on iOS 27.

## 4a. What the first real diagnostic taught us (iPhone Duo, iOS 27.2.1, 15 Nov 2026)

Source: a diagnostic of one real iPhone Duo. Its report and raw files are personal data and are not part of
this repository; the tests use synthetic, redacted fixtures built from it (`Tests/.../Fixtures/duo-case`).
The case: a phone set up from iCloud the night before, hot and draining. Verdict: no fault, heavy
first-night restore work. Everything below is confirmed on that one phone unless marked otherwise.

**Confirmed, replaces guesses in section 4**
- The daily analytics file (`Analytics-YYYY-MM-DD-HHMMSS.ips.ca.synced`, written about 08:00) is the
  single richest file. Useful records seen: `OBCNoRotationBatteryHealthMetricsv2.last_value_CycleCount`,
  `OBC_Battery_Health_v3.sum_of_CycleCount`, `BatteryLevelReportView5` (level samples),
  `UnpluggedDurationEnergyViewNew`, `PowerModesDailyEngagement` (seconds at thermal pressure Light,
  Moderate and above), `PowerExceptionsDetectionEvents` (processes flagged for power),
  `massStorage_power_coalitionInfo` (disk writes per process), `deviceShutdownReasonDaily`,
  `ResetTelemetry2`, `DeviceBootReason`, `RebootAndRollover` (restarts and why), `InstallationResult`,
  `ExpressSetup` and `Datamigrator_*` (new-phone setup), `SpotlightIndexRebuild_Daily`,
  `HealthKit_CloudSync_Restore_DurationV3`.
- **Maximum capacity is not in that file as a readable number.** Cycle count is. Show capacity as
  "check Settings > Battery > Battery Health" with manual entry, never as parsed.
- Report types that matter: `cpu_resource`, **`diskwrites_resource`** (a process over its daily
  write budget; missing from the original plan and the main evidence here), `JetsamEvent`, crash
  `.ips`. Many sit in a `Retired/` subfolder. `ota_patch.txt` records an OS update.
- Thermal data in logs is pressure level and duration only. Degrees are not available from logs.
- **The analytics file is aggregated per day with no timestamps on its samples.** Timestamps come
  only from the individual reports. So matching a cause to a hot spell is per day from the
  analytics file and per minute only where a timestamped report exists. The UI must say which.
- Logs start when the phone was set up; there is no history before that, and none on day one until
  the first 08:00 file.
- From a Mac, Xcode's own `xcrun devicectl` pulls the phone's whole log folder with nothing to
  install: `devicectl device copy from --domain-type systemCrashLogs` (66 files, 27 MB here), plus
  `device info details` and `device info processes` (names only). It has no battery command.
  This phone had Developer Mode on; whether that is required is unverified.
- `pymobiledevice3 developer dvt sysmon process single` gives live per-process CPU and disk writes,
  with no sudo on the current version (it builds its own tunnel). Battery temperature in degrees
  was not captured yet: still unverified.

**Gaps this exposed, now in scope**
1. **"Expected and temporary" as a verdict.** Diagnosis needs context rules, not only fault rules:
   recent setup or restore, OS update, reindexing, bulk app installs. Finding says what is
   happening, that it is normal, how long it usually lasts (one to three days), and when to
   re-check. Add a status for it alongside good / attention / problem / unknown.
2. **Process glossary.** Evidence names system daemons. Ship a table mapping them to plain language
   and advice: `cloudd` and `bird` (iCloud sync), `fileproviderd`, `healthd` (Health), `searchd` and
   `spotlightknowledged` (search indexing), `mediaanalysisd` and `photoanalysisd` (Photos),
   `appstored`, `installd`, `StreamingUnzipService` (app installs), `nsurlsessiond` (downloads),
   `backupd`, `mobileassetd`, and widget extensions. Unknown names are shown raw.
3. **Per-app battery share is in no file.** It lives only in Settings > Battery. Add an import for a
   screenshot of that screen, read on-device with Vision text recognition, user confirms the values.
   Mark provenance as "read from screenshot". Verify recognition quality before relying on it.
4. **Unexpected restarts.** A finding type for watchdog resets and panics from
   `ResetTelemetry2` / `deviceShutdownReasonDaily`, distinguishing an update reboot from an
   unexplained one, with advice to note the time and look for `panic-full` / `watchdog` files.
5. **Sustained background work.** One snapshot cannot tell a long legitimate sync from a stuck one.
   The companion capture must compute rates between snapshots and support a repeat capture hours
   later with a comparison ("still writing 190 MB a minute after a day: likely stuck").
   Matching advice: check iCloud Drive size, leave on charger and Wi-Fi overnight, escalate if it
   persists.
6. **One-share flow asks for the newest daily analytics file first**, since it alone carries power
   exceptions, per-process disk writes, thermal pressure time and restart reasons. Individual
   reports are an optional second step for exact times. Multi-file and folder import must work for
   the Mac route.
7. **Companion baseline with no install:** a `devicectl` path (pull logs, device details, process
   names) before the pymobiledevice3 path (live figures). The Mac app should offer "pull all logs
   and analyse" as its first action and hand the bundle to the same parser as the phone.
8. **Follow-up check.** "Re-check tomorrow" is the main advice in this case, so the app needs a
   scheduled re-check: a local notification after the next 08:00 file, then a before/after
   comparison of thermal pressure time, flagged processes and restarts.
9. **Honest "could not determine" section** in every result and report, as the diagnostic had:
   what was not readable and what would settle it.
10. **Regression fixture, in two stages** (the diagnosis changed as evidence arrived, and the app
    must follow the same path):
    - Stage 1, first-night log files only (new phone, restore, one watchdog reset, one widget over
      its CPU budget once): the app concludes "expected, temporary, re-check tomorrow", not "fault".
    - Stage 2, add the later live captures and one user-supplied fact (iCloud Drive holds under
      50 GB): `bird` and `cloudd` had each written over 100 GB, still at about 230 MB a minute in
      lockstep, while the downloader `nsurlsessiond` wrote 8 MB a minute. The app concludes "likely
      stuck iCloud Drive sync", marked inferred and not proven, with the reasoning shown.
    This needs two things the plan lacked: findings that are **revised** when new evidence arrives
    (keeping the earlier verdict in the history), and the ability to **ask the user one fact** that
    no file holds (here, the size of iCloud Drive) and use the answer as evidence, labelled as
    user-supplied.

## 4b. Second round of gaps from the same diagnostic (live captures, restart, connection)

What happened after 4a: live captures pointed to a stuck iCloud Drive sync; the maintainer restarted the
phone; `bird` and `cloudd` fell from about 230 MB a minute each to under 3, and whole-phone CPU
fell about 70%. Measured over 5.5 minutes only, so "resolved" is provisional. The phone then
stopped appearing on USB and was reached over Wi-Fi.

**Diagnosis and data model**
1. **A case, not a single verdict.** This went: expected and temporary, then likely stuck sync,
   then relieved by restart and being watched. Model a case with a timeline of evidence,
   hypotheses, actions tried and outcomes, and states: open, action suggested, action taken,
   resolved-watching, resolved, came back. The report exports the whole case.
2. **Proof by intervention.** "It stopped when restarted, and no large download followed" was the
   strongest evidence. An action's measured outcome must feed back into the finding's confidence.
3. **Write-amplification rule.** Generic rule: a process has written several times the size of the
   data it manages (`bird`/`cloudd` over 100 GB for a drive under 50 GB; `healthd` 80 GB for a
   database of roughly 600 MB), especially when the downloader (`nsurlsessiond`) is near idle and
   two processes move in lockstep. Needs the dataset size, from a file where present, else asked
   of the user.
4. **Phone-only version of that rule.** The decisive live evidence needed a Mac. Without one, use
   the daily analytics file: per-process disk writes per day (`massStorage_power_coalitionInfo`)
   and `diskwrites_resource` reports, compared day over day and against the user-supplied size.
   Weaker, slower by a day, and must be labelled so.
5. **Units.** Some analytics values carry no unit. Never assume one; show "unit not stated".

**Companion (M10)**
6. **Rates come from deltas, and counters reset.** "Written since start" resets on restart or when
   a process relaunches. Compute rates only between timestamped snapshots, track process identity
   (pid and start time), and treat a reset as a new series, not a negative rate.
7. **Subtract the measurement.** The capture itself used about a quarter of the CPU it measured
   (`sysmond`, `DTServiceHub`, `remotepairingdeviced`). Exclude these from results and show the
   overhead.
8. **Record conditions.** Each capture stores charging state, adapter power, lock and screen state,
   and warns when they differ between two captures being compared.
9. **Before/after around an action.** A first-class flow: capture, user does the relief action,
   capture again, then a later re-check to see whether it held.
10. **Connection handling.** USB and Wi-Fi both, with automatic fallback. After a restart iOS keeps
    USB data off until the phone is unlocked and the accessory allowed, and the Mac then sees an
    empty bus. Detect "no data link" and walk the user through: unlock, replug, allow accessory,
    try another port or cable; meanwhile use Wi-Fi (`--native`).
11. **Developer Mode is required for live figures.** The live per-process route worked because
    Developer Mode was on. Most users do not have it. State this up front, explain how to turn it
    on and what it means, and keep the no-Developer-Mode route (log pull) useful on its own.
    Whether the `devicectl` log pull needs Developer Mode is still unverified.
12. **Battery registry is readable from the Mac** (`raw/battery_ioreg.json`): design capacity,
    full-charge capacity (so true maximum capacity is available by this route: 4995 against a
    design of 4830 here), cycle count, voltage, instantaneous current (real power draw), adapter
    wattage, slow-charging reason, time charging was thermally limited. A battery temperature in
    degrees was **not** found in this capture; keep it marked unverified.
13. **Redaction covers the device UDID and serial** in captures, commands shown to the user and
    exported reports.

**Advice**
14. Add catalogue entries proven by this case: stuck iCloud sync (check drive size, restart,
    re-check; escalate if it returns), unfinished Health restore, failed App Store downloads after
    setup, and "phone not seen over USB".

## 4c. Access tiers (the Developer Mode gap)

The fast, certain diagnosis of the Duo needed a Mac and Developer Mode. Normal users have neither.
The product must be designed for the lowest tier and treat the others as upgrades.

| Tier | Setup | Evidence | Speed |
|---|---|---|---|
| 0 | Phone only | Probes, widget samples, daily analytics file, Battery screenshot, Shortcuts readings (unverified) | Cause per day; confirmation of a fix next day |
| 1 | Mac, no Developer Mode | Full log pull, battery registry, live system log, sysdiagnose pull (all expected to work without Developer Mode; verify) | Exact times; same day |
| 2 | Mac + Developer Mode | Live per-process CPU and disk writes | Minutes; before/after within minutes |

Rules:
- **Tier 0 must reach a useful conclusion on its own.** Acceptance test: the Duo case from tier 0
  data only ends at "likely stuck iCloud sync, restart" by day two, and offers the harmless fix
  (restart) on day one with the caveat that the load may be normal.
- **Every finding states its tier** and what the next tier would add ("a Mac would confirm this
  in minutes"). No tier pretends to the certainty of a higher one.
- **Never push Developer Mode on ordinary users.** It is for developers, needs a restart, and
  loosens some protections. The companion offers it as explicit opt-in for technicians, explains
  what changes, and reminds them to turn it off afterwards.
- **To test for tier 0:** a sysdiagnose can be triggered on the phone by any user and holds a
  timestamped power log that may give per-process energy by the hour. Check what it contains on
  iOS 27 and whether reading it on the phone is practical (size, time, memory). If it is, it
  closes much of the gap.
- **To verify for tier 1:** which companion commands work with Developer Mode off.

## 5. Features

### 5.1 Check-up (home)
One tap runs every on-device probe and shows a scorecard: battery, heat, storage, memory and
performance, network, software. Each area gets a status (good, attention, problem, unknown), one
plain sentence, and a detail screen with the raw readings and their provenance. "Unknown" is a
legitimate status when data needs a log import.

### 5.2 Heat investigation
- **Timeline:** samples of thermal state, battery level, charging state, Low Power Mode, stored locally
  and shown as a scrubbable 24-hour and 7-day timeline. Hot spells (serious or critical) are detected
  and listed with start, duration, drain rate and whether charging.
- **Cause:** from a hot spell, "Find the cause" shows a short looping visual of the four taps in Settings,
  then accepts the shared file. The parser matches CPU-resource, Jetsam, crash and thermal entries to
  the spell's time window and names the processes, ranked by evidence.
- **Onboarding step:** ask the user to turn on "Share iPhone Analytics" so daily files exist.
- **Notification:** optional local notification when a sample sees serious or critical. State clearly
  that it can be late.

### 5.3 Battery
Level, state, drain rate and charge rate from samples. After an import: max capacity, cycle count,
and their date. Plain-language reading of battery wear.

### 5.4 Storage
Used, free, free-for-important-use, and a verdict on whether low space is likely to slow the phone.

### 5.5 Memory and performance
Physical memory, memory-pressure warnings seen, and a short benchmark (CPU single and multi-thread,
one Metal graphics pass, storage write/read). Under 10 seconds, skipped when thermal state is serious
or above. Results compared against a bundled table of expected ranges per model; if the model is not in
the table, show the raw result and say there is no baseline.

### 5.6 Network
Path status, a user-started speed and latency test (default: Cloudflare's public speed-test endpoints;
make the endpoint a single constant), DNS resolution timing, VPN/proxy detection. This is the only
feature that makes network calls, and only when tapped.

### 5.7 Software state
OS version, device model, uptime since restart, Low Power Mode, storage of the app's own data.
"Is the OS current" uses a bundled version table (no network), so it says "as of app version X".

### 5.8 Crashes and hangs
From imported files: which apps crash or hang most, counts, last occurrence, and unexpected system
restarts if present. Each entry links to the raw report text.

### 5.9 Hardware tests (guided, pass/fail/skipped, with notes)
Touch grid (paint the whole screen), display (solid colours for dead pixels, brightness sweep),
speakers (per speaker tone), microphones (record and play back, level meter per mic), cameras (each
lens preview and photo), haptics (pattern set), buttons (volume, Action, Camera Control where
detectable), motion sensors (accelerometer, gyro, magnetometer, barometer live values), proximity,
Face ID (LocalAuthentication prompt), Bluetooth (scan sees devices), Wi-Fi and cellular (path
status), GPS (fix and accuracy), NFC (session starts), flashlight. On iPhone Duo: both displays and,
if exposed, hinge posture. Nothing is stored from camera or microphone tests.

### 5.10 Report
- **PDF:** cover summary, scorecard, findings, heat timeline, hardware results, device details.
- **JSON:** versioned schema (section 7), the machine-readable twin of the PDF.
- **Redaction step before export:** toggles for device name, serial-like identifiers, app names from
  logs, network names. Default is redacted.
- **For Apple:** the report is a cover sheet. The export screen offers to include the original imported
  files alongside, and explains that Apple works from sysdiagnose via Feedback Assistant or a support case.

### 5.11 Widgets
| Widget | Content | Families |
|---|---|---|
| Health summary | Status mark per area, last check-up time | systemSmall, systemMedium |
| Heat | Current thermal state, 24-hour mini timeline | systemSmall, systemMedium, accessoryRectangular, accessoryCircular |
| Battery | Level, state, drain rate | systemSmall, accessoryCircular, accessoryInline |
| Storage | Used and free | systemSmall, accessoryCircular |

Each timeline reload also appends a sample to the shared store, which thickens the heat timeline.
All widgets show "last updated" and deep-link into the matching screen (`vitals://heat`, and so on).

### 5.12 Controls and Live Activity
- Control Center / Lock Screen control: "Run check-up" (opens the app and starts the scan).
- Live Activity: a user-started monitoring session ("watch my phone while I do X") showing thermal
  state, drain rate and elapsed time on the Lock Screen and Dynamic Island. Updated locally by the app
  while it has runtime; no push server. Ends itself with a session summary that is saved to the timeline.

### 5.13 Mac companion (`companion/`)
- **Capture engine:** Python CLI on `pymobiledevice3`. Commands: `probe` (battery registry incl.
  temperature and cycle count, device info), `capture` (timed session sampling battery temperature and
  per-process CPU/energy, plus syslog, into one bundle), `pull` (crash reports, sysdiagnose).
- **Output:** a capture bundle whose JSON uses the same report schema as the iOS app, so the iOS app can
  import a bundle and show it on the heat timeline, and the PDF generator can be shared in spirit.
- **Mac app:** a SwiftUI macOS app wrapping the engine. It follows section 6, as the iPhone app does:
  a check-up, not a dashboard; one task at a time, verdict first. A left column shows the phone (the
  icon's pulse, alive only while connected) and the connection in plain words, what this Mac can read,
  and a Wi-Fi switch; the stage shows one task: Collect logs, Watch it live, or Test a fix (before,
  your turn, after). Friendly process names first, raw names second; house springs with still variants
  under Reduce Motion; VoiceOver labels and announcements; an iPhone menu with keyboard shortcuts; a
  Settings window (save folder, Wi-Fi, and the simulated iPhone and Python path under Advanced).
  Results go to one folder (Documents › Vitals by default), never the Desktop. After one USB pairing,
  Wi-Fi works as a fallback.
- pymobiledevice3 is GPL-3.0, so `companion/` is GPL-3.0 (see section 9).
- **Packaging:** pymobiledevice3 never ships in the iPhone app. The Mac companion bundles a pinned,
  self-contained Python runtime and pymobiledevice3 inside the app, so users install nothing and
  never create a venv. Distribute as a signed, notarised direct download (project site or GitHub
  releases), not the Mac App Store, whose sandbox is expected to block the device access needed
  (verify). Publish the companion source and third-party licence notices with each release.
- `xcrun devicectl` exists only where Xcode is installed, so it is a developer convenience; for
  everyone else the bundled pymobiledevice3 must cover the log pull as well.
- **Unverified:** bundle size, and whether every bundled binary signs and notarises cleanly.
  During development a venv at `companion/engine/.venv` is fine (the maintainer approved a venv install for
  the diagnostic).

### 5.14 Advice and optimisation
The app must be useful, not just informative: every finding comes with what to do about it, and a
healthy phone still gets ways to run better.

- **Fixes attached to findings:** each finding (problem or attention) carries one to three
  recommended actions, ordered by likely effect and effort. Each action has a plain title, why it
  should help given this phone's evidence, numbered steps with the Settings path, expected effect,
  and any downside (for example "turning off Background App Refresh for X means it loads when opened").
- **Optimise tab:** a personalised list for phones with no faults, built from readings: battery
  longevity (optimised charging, charge limit, heat while charging), storage housekeeping, network
  (forget flaky networks, Wi-Fi Assist, DNS/VPN overhead), performance (pending OS update, long
  uptime, low free space), widgets and background activity. Only items relevant to this phone appear;
  no generic tip lists.
- **Close the loop:** after the user marks an action as done, the app watches the relevant readings
  and reports back ("drain overnight fell from 18% to 6%", or "no change, try the next step").
  Actions and outcomes are stored locally and included in the report.
- **Escalation ladder:** every problem ends with when to stop trying and what to do next: restart,
  update, reset settings, contact Apple Support or a repair shop, with the report ready to share.
  Safety cases (swelling, critical heat while charging, liquid) say stop using and seek service first.
- **Rules of honesty:**
  - The app cannot change system settings. It gives steps, and may open its own Settings page only;
    no private Settings deep links.
  - Advice is tied to evidence and says how strong that evidence is (confirmed by logs, or likely).
  - No myths: do not tell people to force-quit apps routinely, "clean RAM", or calibrate batteries
    by draining them. Prefer Apple's documented guidance, and cite it in the advice text.
  - Settings paths differ by iOS version, so steps are stored per OS version and marked "as of".
- **Implementation:** a bundled, versioned advice catalogue (JSON) in `VitalsKit/Advice/`, keyed by
  finding type and conditions, localisable, with unit tests that every finding type maps to at least
  one action and an escalation. No network; catalogue updates ship with app updates.

### 5.14a Quick relief
A "Relief" panel on the home screen and on each finding: short actions that leave the phone in a
better state now. Three honest tiers, each labelled so the user knows who does the work.

- **Vitals does it (one tap, with confirmation):**
  - Photo and video clean-up via PhotoKit (optional permission, asked only when the user opens it):
    exact duplicates, near-duplicate bursts, old screenshots, screen recordings, largest videos.
    Shows space to be recovered, user reviews the selection, deletion goes through the system
    confirmation and into Recently Deleted. All analysis on-device.
  - Clear Vitals' own imported logs and caches.
- **One tap through Shortcuts:** offer an installable "Vitals Relief" shortcut that the app runs with
  the public `shortcuts://run-shortcut` URL. Shortcuts can do what an app cannot: turn on Low Power
  Mode, lower brightness, switch off Bluetooth or cellular data. Ship "Cool down" and "Save battery"
  variants. Verify how shortcuts can be distributed and what actions exist on iOS 27 before building.
  - **How they are built (see 6a):** shortcut source lives in `shortcuts/` as Python using
    `unqforge`, compiled to a plist, converted and signed on a Mac
    (`plutil -convert binary1`, then `shortcuts sign -m anyone`). The signed files ship with the
    app; the source stays reviewable in the repo, which suits an open-source tool that changes
    settings.
  - **Actions confirmed present in unqforge's device-verified catalogue:** Low Power Mode, set
    brightness, Bluetooth, cellular data, Wi-Fi, Airplane Mode, Always-On Display, True Tone,
    appearance, Reduce Motion and Reduce Transparency toggles, battery charge limit
    (`SetBatteryChargeLimitAction`), and restart/shut down (`is.workflow.actions.reboot`).
  - **Relief shortcuts to ship:** "Cool down" (Low Power Mode on, brightness down, Always-On off),
    "Save battery" (Low Power Mode, brightness, Bluetooth off if unused), "Restart" (one tap to the
    system restart prompt, replacing the guided version where it works), "Protect battery" (set
    charge limit), and "Undo" for each, restoring what was changed.
  - **Possible data bridge, unverified:** Shortcuts can read things the app cannot (signal bars,
    carrier, radio technology, current brightness, and an app-usage intent,
    `CalculateAppUsageIntent`). A "Vitals Readings" shortcut could collect these and hand them back
    by opening a `vitals://` URL. Test on the Duo what it returns and whether it runs without
    prompts; label such readings "read via Shortcuts".
  - **Unverified:** whether an app can hand a bundled signed shortcut straight to Shortcuts or needs
    an iCloud link; what prompts appear on first run; behaviour on iOS 27.2.
- **Guided, under a minute:** restart (clears stuck processes and memory), cool-down checklist
  (unplug, remove case, stop the named app, out of the sun), offload unused apps, clear Safari
  website data, review Background App Refresh and Location for the app named in a finding, delete
  large message attachments. Each is a short step list with the Settings path.
- **Measured result:** every relief action records before and after (free space recovered, thermal
  state 10 minutes later, drain rate over the next hours) and reports it plainly, including "no change".
- **Never ship:** a "clear RAM", "boost" or "clean cache of other apps" button. iOS gives apps no way
  to do these and manages memory itself; a fake button breaks principle 2 and risks App Review
  rejection as misleading. Where users expect one, explain in a sentence and offer restart instead.

### 5.15 Experiment (not committed)
On-device access to the phone's own diagnostic services through a local VPN loopback and a pairing
file. Investigate feasibility and App Review risk in a written note only. Do not build it into the app
without the maintainer's say-so.

## 6. Design direction

**Concept:** a check-up, not a dashboard. One thing at a time, verdict first, detail on demand. The
phone is the hero, drawn as a model you can see into.

**Identity (starting point, refine in a design pass):** calm clinical instrument. Near-black and
paper-white grounds, one cool accent for "fine", a warm ramp for heat, status colours paired with
shapes. Rounded system typeface for numbers, system text elsewhere. Generous space, large numerals,
few borders. Follow current HIG and Liquid Glass conventions for bars and controls; use system
`TabView` so the tab bar adapts on iPhone Duo.

**Signature moments:**
1. **The scan:** a sweep across a rendered model of the user's phone; each region lights and settles
   into its status as its probe really completes. On Duo the model unfolds.
2. **Living heat:** thermal state as a slow gradient field, still when nominal, restless when hot.
   Timeline scrubbing with haptic ticks at hot spells.
3. **The reveal:** culprit processes rise from the timeline at the moment they spiked, sized by evidence.
4. **Tests as play:** touch test paints, speaker test shows sound travelling, each pass confirmed with
   a haptic.
5. **The report** assembles itself section by section.

**Motion rules:** springs, interruptible, gesture-driven, 120Hz where available. Prefer SwiftUI
animation, `TimelineView` + `Canvas`, and a single lightweight Metal shader for the heat field. Pause
or simplify animation off-screen and at serious/critical thermal state. Every animated screen has a
Reduce Motion variant. Measure energy cost of the scan and heat field with Instruments before calling
them done.

**iPhone Duo from day one:** no orientation lock, no fixed widths, layouts driven by size class;
inner display gets a two-column layout (scorecard beside detail). Use the `apple-hig` and `duo` skills.

## 6a. Reference repositories (shared by the maintainer)

**iPhone Duo by Examples** (`github.com/artemnovichkov/iPhone-Duo-by-Examples`, MIT, iOS 27.1+).
One-file SwiftUI examples of the Duo APIs. Read it before any Duo work. It settles an item that was
unverified in section 4: the hinge angle is public API (`onHingeChange`). Use it for:
- the hardware hinge test (live angle, history chart) in 5.9;
- the scan's phone model folding with the real hinge (its Hinge Angle example mirrors the angle in
  a 3D model);
- layout: reserved regions (`.division`, `.occlusion`) to keep content off the crease, and
  `ArrangementView` `.split` for scorecard beside detail on the inner display. Apple recommends
  reserved regions, not hinge angle, for layout.
These APIs need iOS 27.1, so gate them with availability checks; the app's minimum stays 18.0.

**Swift Pieces** (`github.com/Saivion/SwiftPieces`): single-file SwiftUI components with motion and
haptics. They are already used in the maintainer's other apps. Check the catalogue before hand-building a component.
Likely fits: `TouchGrid` (touch test), `ScrubChart` and `StatusTimeline` (heat timeline),
`LiveStat`, `Odometer`, `RingBreakdown`, `ActivityHeatmap` (readings), `StatusMorph` and
`OutcomeScreen` (check and test results), `StepTrail` and `SpotlightTour` (guided steps, the
"four taps" guide), `DragSelectGrid`, `PhotoViewer`, `HoldToConfirm`, `PermissionSheet` (photo
clean-up), `SkeletonLoader`, `Toast`, `TextReveal`.
- House convention (from the maintainer's other projects): copy piece files verbatim into a `Pieces/` folder with a short
  header (source URL, revision, licence), never edit them, and put Vitals styling in
  `PiecesStyle.swift`. Vitals keeps its own identity through that styling.
- **Licence constraint:** MIT + Commons Clause. Use inside an app is allowed; redistributing "the
  components themselves, whether alone, in a bundle, or as a ported version" is not. Vitals is meant
  to be a public open-source repo, and committing the piece files there may count as redistribution.
  So: keep `Pieces/` git-ignored and fetched by a script (`scripts/fetch-pieces.sh`, pinned
  revision) until the maintainer decides (ask the author, keep it this way, or replace with own components).
  Every piece must also meet the Reduce Motion and energy rules in section 6.

**unqforge** (`github.com/anupml/unqforge`, MIT, Python 3.8+, no dependencies). Builds Shortcuts
from Python and refuses any action or parameter not seen in a shortcut made on a real iPhone; it
also decompiles existing shortcuts. **Primary tool for the Relief shortcuts in 5.14a.** It runs on
the system Python already on this Mac. To add or re-check an action for iOS 27, decompile a shortcut
made on the Duo that uses it. Young project (38 stars), so pin a revision and keep the generated
plists under test with its round-trip tool.

**Cherri** (`github.com/electrikmilk/cherri`, GPL-2.0, Go, macOS). A mature Shortcuts language and
compiler (1,685 stars) that can also import a shortcut from an iCloud link and decompile it.
**Secondary: use it as a cross-check and decompiler, not as the source of anything shipped.**
Its licence is GPL-2.0 and parts of its standard library are written in the language itself, so
whether compiled output carries licence obligations is unresolved; unqforge avoids the question.
Installing it needs Homebrew; ask the maintainer first.

The two repos earlier in this section (Duo examples, Swift Pieces) were found from the maintainer's other
projects, not named by him for Vitals; they stay as useful references.

## 7. Architecture

```
vitals/
  project.yml                 XcodeGen
  App/                        iOS app target: app entry, navigation, screens
  Widgets/                    WidgetKit extension: widgets, control, Live Activity UI
  ShareExtension/             accepts shared files from Settings and hands them to the app
  Packages/VitalsKit/         Swift package, all logic, unit-tested
    Probes/                   one type per on-device reading
    Sampling/                 sample store, hot-spell detection, background refresh
    LogImport/                file sniffing, analytics/ips/sysdiagnose parsers, correlation
    Diagnosis/                rules that turn readings into findings and statuses
    Benchmarks/
    HardwareTests/            test definitions and result model
    Report/                   schema, redaction, JSON and PDF export
    DesignSystem/             colours, type, components, motion primitives
  companion/                  Python capture engine + macOS app
  Docs/                       spike notes, file-format notes, review notes
```

- **Stack:** Swift 6, SwiftUI, iOS 18.0 minimum (controls and current WidgetKit), built with Xcode 27.
  iPhone only (`TARGETED_DEVICE_FAMILY: 1`).
- **Signing:** team `ETR554P9HN`, automatic. Bundle ids `sg.com.vitals.app`, `.widgets`, `.share`.
  App group `group.sg.com.vitals.app` for the shared sample store and latest snapshot.
- **Storage:** samples and results in SQLite via SwiftData or GRDB inside the app group container;
  imported files copied into the app container, user can delete them.
- **File intake:** share extension plus document types / "Open in" for `.ips`, `.synced`, `.tar.gz`,
  and the companion bundle. Large archives are streamed, never loaded whole.
- **Background:** `BGAppRefreshTask` for samples; widget reloads also sample; thermal-state and battery
  notifications while foregrounded.
- **Report schema (v1):** `schemaVersion`, `generatedAt`, `device`, `readings[]` (`id`, `area`,
  `value`, `unit`, `provenance`, `source`, `takenAt`), `samples[]`, `hotSpells[]`, `findings[]`
  (`severity`, `summary`, `evidence[]`), `hardwareTests[]`, `imports[]`, `redactions[]`.
- **No third-party dependencies in the iOS app** unless one clearly earns its place; note any in Docs.

## 8. Testing

- Unit tests (Swift Testing) for VitalsKit: parsers against fixture files, hot-spell detection,
  diagnosis rules, redaction, schema round-trip.
- Fixtures: synthetic files first; replace with redacted real files from the Duo once available.
- Simulator runs on iPhone Duo and one standard iPhone; screenshots of each main screen in light,
  dark, large Dynamic Type and Reduce Motion.
- Accessibility audits with the VoiceOver, Dynamic Type and contrast skills.
- Simulator cannot validate: real thermal changes, battery readings, most hardware tests, widget
  refresh cadence, energy cost. These need the physical Duo (section 11).

## 9. Decisions taken by default (the maintainer can overrule)

| Decision | Default | Why |
|---|---|---|
| Name | Vitals (working) | Fits the check-up concept |
| Minimum iOS | 18.0 | Controls, current widgets |
| Devices | iPhone only | It diagnoses phones |
| Licence | iOS app MIT; `companion/` GPL-3.0 | pymobiledevice3 is GPL-3.0; keeping it separate keeps the app permissive |
| Speed test endpoint | Cloudflare public endpoints | No own server; one constant to change |
| Companion form | Python engine + SwiftUI Mac app | Fastest route to real data, native surface later |
| Distribution | TestFlight, then App Store | Review risk is real for diagnostics apps; public APIs only |

## 10. Build order

Each milestone ends with: builds clean, tests pass, runs in the Duo simulator, short note in `Docs/`.

- **M0 Foundation:** project.yml, targets, VitalsKit skeleton, app group, design-system tokens,
  navigation shell, git init.
- **M1 Probes and check-up:** all on-device probes, diagnosis rules, scorecard and detail screens.
- **M2 Sampling and heat timeline:** sample store, background refresh, hot-spell detection, timeline UI,
  notification.
- **M3 Log import:** share extension, document types, parsers, correlation to hot spells, crashes and
  hangs screen, battery health from import, guided "four taps" visual.
- **M4 Report:** schema, redaction, JSON and PDF export, share sheet.
- **Section 4a applies across milestones:** items 1, 2, 4, 9 and 10 belong to diagnosis and log
  import (M1, M3); item 3 to M3; item 6 to M3; item 8 to M4b; items 5 and 7 to M10. If a milestone
  is already built, go back and extend it.
- **Section 4b applies too:** items 1 to 5 to the findings model and diagnosis (M1, M3), items 6 to
  13 to the companion (M10), item 13 also to the report (M4), item 14 to advice (M4b).
- **M4c Quick relief (5.14a):** Relief panel, photo and video clean-up, Shortcuts-based relief,
  guided actions, before/after measurement. Build after M4b.
- **M4b Advice and optimisation (5.14):** advice catalogue, actions on every finding, Optimise tab,
  mark-as-done with before/after follow-up, escalation ladder, actions and outcomes in the report.
- **M5 Design and motion pass:** the scan, living heat, the reveal, report assembly, Reduce Motion
  variants, Duo inner-display layouts.
- **M6 Widgets:** four widgets, sampling on reload, deep links.
- **M7 Hardware tests:** full guided suite, results into the report.
- **M8 Benchmarks and network test.**
- **M9 Control and Live Activity session.**
- **M10 Mac companion:** capture engine, bundle import in the iOS app, Mac app.
- **M11 Release prep:** accessibility audits, privacy manifest and nutrition labels, App Store
  metadata draft, review notes, README and licences.

## 11. Needs the maintainer (cannot be done from the simulator)

1. Plug in the iPhone Duo and run the app on it; confirm what each probe returns.
2. Share one daily analytics file, a few `.ips` reports and one sysdiagnose into the app so parsers can
   be checked against real data (and redacted copies kept as fixtures).
3. Leave a widget installed for a day to measure refresh cadence and what it can read.
4. Run the scan and heat field under Instruments on the Duo for energy cost.
5. Install the companion tooling (`pymobiledevice3` needs a newer Python than the system 3.9) and run
   a capture while the phone heats up.
6. Register the app group and bundle ids on the developer account when device builds need them.
7. Decide how Swift Pieces files are handled in a public repo (section 6a).
8. Decide: licences, and whether the section 5.15 experiment goes further.

Until 1 to 5 are done, anything in section 4 marked unverified stays behind a clear "unverified" note
in code and docs, with the parser tolerant of missing keys.

# Plan 4a, 4b, 4c: what the real Duo diagnostic changed

Source: a diagnostic of one real iPhone Duo (personal data: not part of this repository; tests use redacted,
regenerated fixtures in
`Packages/VitalsKit/Tests/VitalsKitTests/Fixtures/duo-case/`, made by its `make.py`).

## 4a Built
- Analytics parser reads the real record names exactly (no fragment matching). Maximum capacity is not in the
  analytics file and is no longer derived from loose keys; cycle count is.
- `*.diskwrites_resource` reports (bug_type 145) with units read from the text ("17.18 GB"), never assumed;
  `Retired/` subfolders imported; day-precision vs minute-precision events kept apart in the timeline.
- "Expected and temporary" status (solid ring) for a new phone restoring and syncing; it outranks generic heat or
  drain findings instead of raising alarms.
- Process glossary (`process-glossary.json`): what bird, cloudd, healthd, mediaanalysisd… are, in plain words.
- Battery screenshot import with Vision (per-app share, maximum capacity), confirmed by the person, provenance
  "screenshot".
- Unexpected restart finding (from analytics shutdown reasons / watchdog), day precision.
- One-share flow: newest daily analytics first; folder import; companion pull path.
- Scheduled next-day re-check (09:00 local) and day-over-day comparison of analytics.
- "Could not determine" in every area result and in the report and PDF.
- Two-stage regression: day 1 → "expected and temporary, re-check tomorrow" with a harmless restart offered with
  its caveat; day 2 or live rates + the person's iCloud size (<50 GB) → "likely a stuck iCloud Drive sync"
  (inferred, not proven, and it says so). Findings are revised with history; the one question asked is labelled
  user-supplied.

## 4b Built
- Case model with timeline and states; proof by intervention (restart outcome supports or weakens the hypothesis).
- Write-amplification rule: written far more than the data could be (ratio ≥ 2 to the stated drive size) and more
  than is being downloaded. Phone-only weaker version from day-over-day analytics.
- Companion: rates from deltas, resets as new series, measurement overhead removed, conditions recorded and
  compared, before/after flow, USB then Wi-Fi with the "not seen over USB" walkthrough, Developer Mode stated up
  front, battery registry, UDID and serial redacted everywhere (Docs/M10-mac-companion.md).

## 4c Built
- Every finding states its access tier (phone only / Mac / Mac with Developer Mode), its confidence, and what the
  next tier would add. Developer Mode is never pushed on ordinary users.
- Tier 0 acceptance test: the Duo case reaches "likely stuck iCloud sync, restart" by day two from phone-only
  evidence, and day one offers the harmless restart with its caveat (`DuoCaseTests.tier0PhoneOnlyReachesStuckSyncByDayTwo`).

## Verified
- Swift: `DuoCaseTests` (6), `AdviceTests` (7), `ScreenshotParserTests`; `RealDeviceCheck` run locally with
  `VITALS_REAL_LOGS` against the real folder: 61 files, 14 diskwrites reports, cycle count 1, verdict "new phone,
  expected" (the run is skipped everywhere else).
- Companion rates against the real snapshots (M10 note).

## Still open (needs-device.md)
- Sysdiagnose power log on the phone (tier 0 per-process energy?), commands that work with Developer Mode off,
  Vision on real screenshots, the re-check notification.

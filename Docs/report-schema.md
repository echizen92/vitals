# Report schema v1

The JSON twin of the PDF, and the format of a Mac companion capture (`.vitalscapture`). Defined in
`Packages/VitalsKit/Sources/VitalsKit/Report/Schema.swift`. Dates are ISO 8601 with milliseconds.
Readers must ignore unknown keys; arrays may be missing (treated as empty).

| Field | Type | Notes |
|---|---|---|
| `schemaVersion` | int | 1. Renaming or removing a field bumps it; adding one does not. |
| `generatedAt` | date | |
| `generator` | string | `Vitals iOS 1.0`, `vitals-companion 0.1` |
| `device` | object | `model`, `modelIdentifier`, `osVersion`, `osBuild?`, `name?` (redacted by default), `identifiers?` (legacy; the companion no longer writes it, and the iOS redactor strips it by default) |
| `readings[]` | object | `id`, `area`, `label`, `value` (number, string or bool), `unit?`, `provenance` (`measured` / `parsedFromLog` / `inferred` / `userSupplied` / `screenshot` / `shortcuts`), `source`, `takenAt`, `unverified` |
| `samples[]` | object | `takenAt`, `thermal` (0–3), `batteryLevel?` (0–1), `charge`, `lowPowerMode`, `source`, `temperatureC?` (companion only) |
| `hotSpells[]` | object | `start`, `end`, `peak`, `drainPerHour?`, `wasCharging`, `sampleCount`, `ongoing` |
| `findings[]` | object | `id`, `area`, `severity` (`info` / `attention` / `problem`), `summary`, `detail?`, `evidence[]` (`text`, `provenance`, `readingID?`, `source?`) |
| `hardwareTests[]` | object | `kind`, `outcome` (`passed` / `failed` / `skipped` / `unavailable`), `notes`, `details[]`, `testedAt` |
| `imports[]` | object | `id`, `fileName`, `kind`, `importedAt`, `coversDate?`, `byteSize`, `storedPath?`, `eventCount`, `notes[]` |
| `redactions[]` | string | what was redacted: `deviceName`, `identifiers`, `appNames(N)`, `networkNames` |
| `events[]?` | object | log events: `id`, `kind`, `process`, `bundleID?`, `timestamp`, `magnitude?`, `magnitudeUnit?`, `detail?`, `importID` |
| `processSamples[]?` | object | companion only: `takenAt`, `process`, `pid?`, `cpuPercent?`, `energy?`, `energyUnit?` |
| `benchmark?` | object | see `BenchmarkResult` |
| `repairNotes?` | string | typed by the owner |
| `statuses[]?` | object | `area`, `status` (`good` / `expected` / `attention` / `problem` / `unknown`), `sentence` per scorecard area |
| `processRates[]?` | object | companion: `process`, `bytesWrittenPerMinute`, `cpuPercent?`, `from`, `to` (from two snapshots of the same process; overhead processes excluded) |
| `processTotals[]?` | object | companion: `process`, `bytesWritten` (since the process started), `since?`, `at` |
| `caseRecord?` | object | `current` (the case result: hypotheses with `id`, `title`, `status`, `confidence`, `tier`, `reasoning[]`, `adviceKey`, and the case state) and `history[]` (revisions: `at`, `title`, `status`, `confidence`, `state`) |
| `actions[]?` | object | `ActionRecord`: `id`, `actionID`, `title`, `findingID?`, `performedBy`, `doneAt`, `watch`, `before`, `after?` (metrics snapshots), `verdict`, `outcomeText?` |
| `userFacts[]?` | object | facts the person gave, labelled user-supplied: `key` (e.g. `icloudDriveGB`), `value`, `enteredAt` |
| `couldNotDetermine[]?` | string | what Vitals could not find out, per area |
| `adviceVersion?` | string | version of the advice catalogue used |

Companion captures also carry a `capture` object outside the schema (start, end, backend, notes, `accessTier`,
`conditions[]`, `resets[]`, `wholePhoneCPU`); the app ignores it.

Samples with `source: fixture` (synthetic or taken while values were injected) are never written to a report.

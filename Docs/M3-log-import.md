# M3 Log import

## Built
- **Share extension** (`VitalsShare`): accepts any file, copies it into the app-group `Inbox/` and says
  "Saved to Vitals". It parses nothing, so a several-hundred-MB sysdiagnose never meets the extension's
  memory limit. The app drains the inbox each time it becomes active.
- **Document types**: "Open in Vitals" for `.ips`, `.synced` (imported UTIs `sg.com.vitals.ips` /
  `sg.com.vitals.analytics`), `.tar.gz` (`org.gnu.gnu-zip-tar-archive`), and `.vitalscapture` (exported UTI).
  File URLs arriving through `onOpenURL` are imported. Logs also has a Files picker.
- **Parsers** (`VitalsKit/LogImport`):
  - `.ips`: header line + body split; classification by file name, then `bug_type`, then body.
    Crash (documented JSON), JetsamEvent (documented: `largestProcess`, `pageSize`, `processes[].rpages`, `reason`),
    cpu_resource / wakeups_resource / diskwrites_resource (text body, **unverified**), hang (**unverified**),
    panic (**unverified**).
  - Analytics `.ips.ca.synced`: walks every key of every JSON line and matches key *fragments*
    (`maximumcapacitypercent`, `cyclecount`, `designcapacity`, `nominalchargecapacity`…), range-checks
    values, records the exact key paths used, and reports "no battery keys found" rather than guessing.
    **Key names are unverified**; this is the part most likely to need changing once a real Duo file is in.
  - Sysdiagnose `.tar.gz`: streamed 1 MB at a time (gzip header parse + `compression_stream` raw deflate +
    incremental tar walker with GNU long-name and pax path support). Only `.ips`/analytics entries under
    16 MB are kept; everything else streams past. Progress is reported to the UI.
- **Correlation**: events within 30 min of a hot spell are scored by kind (CPU over budget weighs most,
  scaled by CPU seconds), by distance from the spell, and summed per process. Shown as leads, with the
  sentence "a report near a hot spell is a lead, not proof".
- **Screens**: Logs (intro, how-to, Files picker, progress, last result, battery health, crashes and hangs by
  app, unexpected restarts, processes flagged for heavy use, shared files with swipe-to-delete), crash detail,
  raw report text (selectable), hot-spell detail with "Find the cause" and the culprit timeline.
- **"Four taps" guide**: a looping sketch of Settings → Privacy & Security → Analytics & Improvements →
  Analytics Data → file, drawn in Vitals' own style (not a copy of Settings). Reduce Motion shows the same
  steps as a still numbered list (the list is always present for VoiceOver).
- **Onboarding** (first launch, 3 pages): what Vitals reads, privacy, and turning on Share iPhone Analytics
  (with the honest note that Apple receives that data while it is on).
- **Battery health from import** feeds the Battery area: maximum capacity (parsed, or inferred from mAh) and
  cycle count, each tagged "From a log · unverified".
- Originals are copied into Application Support/Imports and can be deleted; a sysdiagnose keeps only the
  reports found inside (noted on the import).
- Debug: "Add synthetic logs for a hot spell" / `-syntheticLogs` writes reports timed to the synthetic spell.

## Verified, and how
- `swift test`: 45 tests, including every fixture type, analytics with / without / mAh-only keys, the
  streamed sysdiagnose fixture (5 reports found, long tar path read, unique event ids, progress reaches 100%),
  non-gzip rejection, culprit ranking (CPU-heavy process first; a hang the day before and a panic excluded).
- Duo simulator with `-syntheticDay -syntheticLogs`: six synthetic files imported through the same pipeline as
  shared files; Battery verdict switched to "Healthy: holds about 86%"; Logs listed battery health and crashes;
  the 1:12 AM spell's "Find the cause" ranked mediaanalysisd, Instagram, locationd, Safari
  (`Docs/screens/m3-reveal.png`). Onboarding shown on a fresh install (`m3-onboarding.png`).

## Fixed after looking at it
- Samples taken while values were injected were stored as real `app` samples and showed up as hot spells.
  They are now stored as `fixture`. Launch-argument injection no longer persists (`@Observable` runs
  `didSet` during init); `-live` clears a saved injection.
- Culprit labels overlapped; dots are now laid out one level per rank with labels beside them.

## Not verified (needs the Duo)
- Every undocumented format above against real files; the share sheet flow from Settings > Analytics Data
  into the extension (simulator has no Analytics Data list); a real sysdiagnose's size and time to stream.

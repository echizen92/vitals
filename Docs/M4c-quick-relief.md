# M4c Quick relief (plan 5.14a)

Three labelled tiers that say who does the work. There is no "clear RAM", "boost" or cache-cleaner button; the
panel explains why (iOS gives apps no such control, and a fake one would be a lie).

## Built
- **Vitals does it**
  - Photos and videos clean-up (PhotoKit). Permission is asked only when this screen opens. On the phone it
    finds likely duplicates (same kind, pixel size and length, same second; one copy kept, preselected), extra burst
    shots (not the system's or the person's pick), screenshots older than 30 days, screen recordings, and the 20
    largest videos (nothing preselected). Sizes are labelled "about" (PhotoKit has no file-size API). Deletion goes
    through the system's own confirmation into Recently Deleted; the result says space returns when Recently
    Deleted is emptied, and the free-space change is measured as an action outcome.
  - Clear Vitals' own imported logs (confirmation; originals in Settings untouched).
- **One tap through Shortcuts**: rows for Cool down, Save battery, Restart, Protect battery, each with Undo, run by
  `shortcuts://x-callback-url/run-shortcut` with `x-success` back to Vitals for before/after. When the signed files
  are not bundled (this build), the panel says so and points to the guided steps. Source in `shortcuts/`.
- **Guided, under a minute**: restart, cool-down checklist, offload apps, Safari data, background refresh,
  Messages attachments, each with steps, effect, downside and "I did this, measure it".
- Info.plist: `NSPhotoLibraryUsageDescription`, `LSApplicationQueriesSchemes` = shortcuts.

## Verified, and how (simulator, iPhone Duo, iOS 27.1)
- Relief panel layout and tier labels (`Docs/screens/m4c-relief.png`).
- Photos: permission prompt, empty-library "Nothing obvious to clean up", then with two identical images added
  (`simctl addmedia`) one likely duplicate preselected (`m4c-photos.png`), the system "Allow Vitals to delete this
  photo?" confirmation (`m4c-photos-confirm.png`) and the result text (`m4c-photos-result.png`).
- **Bug found and fixed while doing this:** the app was killed the moment it asked PhotoKit to delete. The change
  block was main-actor isolated (it was written inside the `@MainActor` model) and PhotoKit runs it on its own
  queue, so Swift 6 trapped. The block is now built by a `nonisolated` helper. Also fixed "1 items".

## Not verified
- A real library (scan time and memory on thousands of items, detection quality), the measured free-space change.
- Shortcuts: Cool down, Save battery and Restart (with Undo for the first two) are now compiled, signed and bundled
  (`m4c-relief-shortcuts.png`); none has run, because the simulator has no Shortcuts app. Protect battery is not
  built (no evidence for the charge-limit value parameter) and is a guided step instead. See shortcuts/README.md.

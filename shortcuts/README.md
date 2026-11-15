# Vitals Relief shortcuts

Shortcuts can do things an iOS app cannot: turn on Low Power Mode, set brightness, switch off Always On,
set a charge limit, restart the phone. Vitals runs these with the public
`shortcuts://x-callback-url/run-shortcut` URL and gets control back through `x-success`, so it can
measure before and after (plan 5.14a).

| Shortcut | What it does | Undo (same shortcut, input text "undo") |
|---|---|---|
| Vitals Cool down | Low Power Mode on, brightness 30 %, Always On off | Low Power Mode off, Always On on |
| Vitals Save battery | Low Power Mode on, brightness 40 % | Low Power Mode off |
| Vitals Restart | Restart, after the system's own confirmation | none |

**One shortcut per row, named exactly as the app runs it.** Shortcuts names an imported shortcut after its file, so
the files are `App/Resources/Shortcuts/Vitals Cool down.shortcut` and so on (spaces, not dashes): the name in
`ReliefShortcut.rawValue`, which `run-shortcut?name=` asks for. Undo is not a second shortcut: Vitals runs the same
one with `input=text&text=undo`, and an If on Shortcut Input picks the branch (run from the Shortcuts app with no
input, it does the main job). Shortcuts imports only the first file of a multi-file share, so each Relief row has
its own Add button that shares its one file. Vitals cannot tell whether a shortcut is installed; when Shortcuts
calls back with x-error, the message names the row and points at its Add button.

**Not built: Protect battery (charge limit).** unqforge's device evidence for `SetBatteryChargeLimitAction` has only
`AppIntentDescriptor` and `setUntilTomorrow`; the limit value's parameter has never been seen in a real shortcut.
Guessing it could give a file that imports and silently does nothing, so Vitals offers the guided steps instead
(Settings > Battery > Charging). Revisit by exporting a charge-limit shortcut made by hand on the Duo and
decompiling it with `tools/decompile.py`.

Gaps, said plainly:
- **Undo does not restore an exact earlier brightness.** Shortcuts can read the current brightness but
  keeping it between two separate runs needs a file in the Shortcuts folder; not built yet.
  Auto-brightness or the person sets it back.
- "Save battery" does not switch off Bluetooth: Vitals cannot tell whether a watch or earbuds need it.
- A "Vitals Readings" shortcut (signal, brightness, app usage handed back to the app) is not built.

## Source and build

`src/*.py` is the source, written for **unqforge** (github.com/anupml/unqforge, MIT, Python 3.8+),
pinned to `489315242d8b8bf5f84352dca31f76479f87f8fe`. The build compiles each file to a plist, converts it
to binary (`plutil -convert binary1`) and signs it (`shortcuts sign -m anyone`) into
`App/Resources/Shortcuts/<Name with spaces>.shortcut`, where the app looks for them. The build first removes the old
`.shortcut` files there, so a renamed or dropped shortcut does not linger (it is tracked in git: stage the change).

```
git clone https://github.com/anupml/unqforge shortcuts/.unqforge
git -C shortcuts/.unqforge checkout 489315242d8b8bf5f84352dca31f76479f87f8fe
shortcuts/build.sh
```

`shortcuts/.unqforge/` is git-ignored. Cherri (GPL-2.0, needs Homebrew) is the fallback compiler and is
not installed.

## Built (2026-11-15)

Fetched with the maintainer's go-ahead, at the pinned revision (MIT). `shortcuts/build.sh` compiled, converted and signed the
five shortcuts (then with dashed names and separate Undo files; rebuilt as three on 2026-11-16) into `App/Resources/Shortcuts/` (signed AEA files, about 21 KB each); the app bundles them as a
folder. Compiled parameters, checked against unqforge's device evidence: Low Power Mode `OnValue` true/false,
brightness `WFBrightness` 0.3/0.4, Always On `OnValue` 0/1 (an integer, not a boolean), reboot
`WFShutdownMode` "Restart". The iOS simulator has no Shortcuts app; Vitals shows "Shortcuts did not open" there.

## Not verified yet (Docs/needs-device.md)

- Running any of them on iOS 27.2: unqforge's evidence comes from other people's real shortcuts, not this phone.
- First-run prompts ("Allow Vitals to run shortcuts", per-action privacy prompts), and whether `x-success` returns.
- That the If on Shortcut Input works: the text comparison (`WFCondition` 4 against `WFConditionalActionString`,
  input coerced to Text) is the shape unqforge records from real shortcuts, but this exact use is untested.
- Handing a file from the app's share sheet to Shortcuts works (seen on the Duo, 2026-11-16); the name with spaces
  is not seen yet.

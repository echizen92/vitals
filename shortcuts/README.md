# Vitals Relief shortcuts

Shortcuts can do things an iOS app cannot: turn on Low Power Mode, set brightness, switch off Always On,
set a charge limit, restart the phone. Vitals runs these with the public
`shortcuts://x-callback-url/run-shortcut` URL and gets control back through `x-success`, so it can
measure before and after (plan 5.14a).

| Shortcut | What it does | Undo |
|---|---|---|
| Vitals Cool down | Low Power Mode on, brightness 30 %, Always On off | Vitals Undo Cool down: Low Power Mode off, Always On on |
| Vitals Save battery | Low Power Mode on, brightness 40 % | Vitals Undo Save battery: Low Power Mode off |
| Vitals Restart | Restart, after the system's own confirmation | none |

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
`App/Resources/Shortcuts/<Name-With-Dashes>.shortcut`, where the app looks for them.

```
git clone https://github.com/anupml/unqforge shortcuts/.unqforge
git -C shortcuts/.unqforge checkout 489315242d8b8bf5f84352dca31f76479f87f8fe
shortcuts/build.sh
```

`shortcuts/.unqforge/` is git-ignored. Cherri (GPL-2.0, needs Homebrew) is the fallback compiler and is
not installed.

## Built (2026-11-15)

Fetched with the maintainer's go-ahead, at the pinned revision (MIT). `shortcuts/build.sh` compiled, converted and signed the
five shortcuts above into `App/Resources/Shortcuts/` (signed AEA files, about 21 KB each); the app bundles them as a
folder. Compiled parameters, checked against unqforge's device evidence: Low Power Mode `OnValue` true/false,
brightness `WFBrightness` 0.3/0.4, Always On `OnValue` 0/1 (an integer, not a boolean), reboot
`WFShutdownMode` "Restart". The iOS simulator has no Shortcuts app; Vitals shows "Shortcuts did not open" there.

## Not verified yet (Docs/needs-device.md)

- Running any of them on iOS 27.2: unqforge's evidence comes from other people's real shortcuts, not this phone.
- First-run prompts ("Allow Vitals to run shortcuts", per-action privacy prompts), whether a bundled
  `.shortcut` file can be handed to Shortcuts from inside the app, and whether `x-success` returns.

# Contributing to Vitals

Thank you for helping. A few things keep Vitals what it is.

## The rules the app lives by

- **Honest.** Every value says where it came from (measured, from a log, inferred). Never show a number
  Vitals cannot actually know, and never present a guess as a measurement.
- **Private.** Nothing leaves the phone. No analytics, no accounts, no network calls except the speed test
  the person starts. Pull requests that add tracking or a server will not be merged.
- **Public APIs only.** No private APIs, no private URL schemes.
- **No fake fixes.** No "clear RAM", "boost" or cache-cleaner buttons. iOS gives apps no such power.
- **Plain words.** Short sentences. If a term is unavoidable, explain it in one line.

## Getting started

Follow [For contributors](README.md#for-contributors) in the README: install XcodeGen, run
`xcodegen generate`, then build the `Vitals` scheme. The simulator launch arguments there let you see hot,
low-battery and log-filled states without a real phone.

## Before you open a pull request

- Logic goes in `Packages/VitalsKit`, with tests. Run `swift test` there.
- Mac engine changes: run `PYTHONPATH=. python3 -m unittest discover -s tests` in `companion/engine`.
- Build the `Vitals` scheme for an iPhone simulator with no warnings.
- Check your screen in light and dark, at a large text size, and with Reduce Motion on.
- Never commit real device logs, screenshots with personal details, or anything from `device-diagnostics/`.
  Make a small synthetic fixture instead (see `Packages/VitalsKit/Tests/VitalsKitTests/Fixtures`).
- If it can only be checked on a real phone, add a line to `Docs/needs-device.md`.

## Licences

By contributing you agree that your contribution is licensed under the same terms as the part of the project
it touches: MIT for everything except `companion/`, which is GPL-3.0-or-later.

## Reporting problems

Open an issue on GitHub. A redacted JSON report from *Check-up > Report* helps a lot.

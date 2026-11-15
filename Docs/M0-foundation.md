# M0 Foundation

## Built
- `project.yml` (XcodeGen 2.46) with three iOS targets: `Vitals` (`sg.com.vitals.app`), `VitalsWidgets`
  (`sg.com.vitals.app.widgets`), `VitalsShare` (`sg.com.vitals.app.share`). Team `ETR554P9HN`, automatic signing,
  iOS 18.0 minimum, iPhone only, Swift 6 language mode. All three share `group.sg.com.vitals.app`.
  Extension bundle ids are prefixed with the app id as iOS requires (plan said `.widgets` / `.share`).
- `Packages/VitalsKit`: two library targets.
  - `VitalsKit` (logic only, no SwiftUI): model (`Reading`, `Provenance`, `Area`, `Status`, `Finding`, `Sample`,
    `HotSpell`, `LogEvent`, `BatteryHealth`, `ImportRecord`), probes, sampling maths, diagnosis, SQLite store,
    shared container. Builds and tests on the Mac too (`swift test`).
  - `VitalsDesign`: design-system tokens (palette, type, spacing), components (`StatusMark`, `ProvenanceTag`,
    `ReadingRow`, `Panel`, `BigValue`) and motion primitives (`MotionLevel`, which combines Reduce Motion with thermal state).
  - The plan put `DesignSystem/` inside VitalsKit; it is a sibling target in the same package so logic tests never pull in SwiftUI.
- Storage: plain SQLite (system `SQLite3`, WAL mode) in the app-group container. No SwiftData or GRDB:
  the widget extension writes samples too, and raw SQLite keeps that simple with no third-party code.
- Navigation shell: system `TabView` with five tabs (Check-up, Heat, Logs, Tests, Report).
- App icon (light, dark, tinted) rendered by `scripts/make-icon.swift`: a phone outline crossed by one pulse line.
- `scripts/sim.sh`: build products install + launch + screenshot (captures both Duo displays).
- `git init` done. Nothing committed.

## Verified, and how
- `xcodebuild` for the iPhone Duo simulator (iOS 27.1): BUILD SUCCEEDED, no warnings in our code.
- `swift build` of the package on macOS: clean.
- Ran on the iPhone Duo simulator: app launches, paper ground, the system tab bar sits vertically in the outer
  display's side strip as the Duo HIG describes (`Docs/screens/m0-shell-d1.png`).

## Not verified
- Inner (unfolded) display: `simctl` has no hinge control, and the simulator app is not installed on this Mac
  (only CoreSimulator). Regular-width layouts are checked another way from M1 on (see M5 note).
- Device builds: the app group and bundle ids are not registered on the developer account yet (needs-device item 6).

## Finding recorded for later milestones
- Hinge state **is** public API on iOS 27.1: SwiftUI `View.onHingeChange` / `DeviceHinge` (status `.closed`,
  `.partiallyOpen`, `.fullyOpen`, plus `angle`), UIKit `UIHingeInteraction` / `UIHinge`. Checked in the
  iOS 27.2 SDK swiftinterface and Apple's documentation. Plan §4 listed this as unverified; it is now settled
  for the API's existence, but what it reports on the real Duo still needs the device.

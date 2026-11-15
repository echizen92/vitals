# M1 Probes and check-up

## Built
- `VitalsKit/Probes`: `SystemSource` protocol with one raw struct per area; `LiveSystemSource` (public APIs only:
  `ProcessInfo` thermal state / Low Power Mode / memory / uptime, `UIDevice` battery, `URLResourceValues` volume
  capacities, `task_info` footprint, `os_proc_available_memory`, `NWPathMonitor`, `getifaddrs` for tunnels,
  `CFNetworkCopySystemProxySettings`, `sysctl` `hw.machine` / `kern.osversion` / `kern.boottime`, window-scene screen);
  `FixedSystemSource` for injected values; `Probes` turns raw values into `Reading`s, each with provenance and source.
- `CheckupRunner` runs all six probes concurrently and emits an event as each area really finishes; the scan UI
  is driven by those events, not a timer.
- `Diagnosis`: rules per area with thresholds in one place (`Thresholds`). `unknown` is used when iOS gives
  nothing (e.g. no battery level and no analytics import).
- Bundled tables: `models.json` (built from Xcode 27.2 simulator device profiles; iPhone Duo = `iPhone19,4`)
  and `os-versions.json` ("is iOS current" without network, dated 2026-11-15, latest 27.2 from the SDK).
- Screens: Check-up home (phone model, verdict, one button, scorecard, provenance legend) in a
  `NavigationSplitView`; area detail (verdict sentence, findings with expandable evidence, every reading with
  provenance tag and API source); Settings (heat alerts, data deletion, simulator state injection, licences).
- Simulator state injection (Settings > Simulator state, or launch argument `-inject hot|critical|lowStorage|…`).
  Every screen shows "Injected values, not from this phone" while it is on. The section is hidden in release
  builds on a real phone.

## Verified, and how
- `swift test`: 29 tests (probes, rules for every area, versions, model table, hot spells, drain, store).
- Built for the iPhone Duo simulator; ran a check-up from `vitals://scan`. All six areas reported; the phone
  model drew open (two panels) because the model identifier is the Duo's. Screens: `Docs/screens/m1-checkup.png`.
- Detail screen for Storage showed findings, evidence and readings with "Measured" tags and API names.
- What the simulator reported is the Mac: no battery level (so Battery = Unknown, correctly), the Mac's disk,
  the Mac's memory, and a tunnel interface (VPN finding). These are honest readings of the simulator host.

## Fixed after looking at it
- Storage judged by percentage flagged a 494 GB disk with 15 GB free as a problem. Rules are now mostly absolute
  (problem < 3 GB, attention < 8 GB or < 5%), with tests for large drives.
- RAM was shown in decimal units (17.18 GB); memory readings now use binary units.

## Not verified (needs the Duo)
- Every live probe value on real hardware: battery level/state, thermal state changes, `os_proc_available_memory`,
  real storage, cellular paths, whether `UIDevice.name` returns the generic name. See `needs-device.md`.
- The tunnel heuristic (`utun` with a routable address) may flag iOS's own tunnels (e.g. iCloud Private Relay)
  as a VPN. It is labelled "Inferred" and rated info, not a problem.

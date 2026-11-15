# M7 Hardware tests

## Built
Tests tab with the guided suite (17 tests on iPhone Duo, 15 elsewhere). Every test shares one page
(`TestScaffold.swift`): instruction, the test, measured details tagged "Measured", Vitals' suggested outcome
(outlined), notes, and Passed / Failed / Skip (plus "Not available" when the hardware is absent). Results are
saved and go into the report (PDF "Hardware tests" section, JSON `hardwareTests[]`).

| Test | How | Decided by |
|---|---|---|
| Touch | full-screen 8×14 grid painted by drag, cells interpolated along fast drags, light haptic per new cell | complete grid → pass |
| Display | black, white, red, green, blue, grey, then a brightness sweep (still ramp under Reduce Motion) | person |
| Speakers | 1.2 s tone panned left/right on the loudspeakers, and through the earpiece (play-and-record route); rings show "sound travelling" | person, per output |
| Microphones | each built-in mic data source (`AVAudioSessionPortDescription.dataSources`), 3 s recording, level meter, playback, file deleted | person + peak level |
| Cameras | every built-in lens via `AVCaptureDevice.DiscoverySession`, live preview, one in-memory photo (never saved) | person, per lens |
| Haptics | four Core Haptics patterns | person |
| Buttons | volume up/down via `outputVolume` KVO; Camera Control via `AVCaptureEventInteraction` while a capture session runs; Action button only if assigned to Vitals' "Run check-up" shortcut | volume both seen → pass |
| Motion | accelerometer, gyroscope, magnetometer, barometer live values; `SignalActivity` decides "responding" | all present sensors responding → pass |
| Proximity | `isProximityMonitoringEnabled` + state changes | ≥2 changes → pass |
| Face ID | `LAContext` biometric prompt; only success/failure is known | automatic |
| Bluetooth | 8 s `CBCentralManager` scan; only a count is kept | ≥1 device → pass; none → skipped |
| Wi-Fi and cellular | per-interface `NWPathMonitor` | any usable → pass |
| GPS | one `CLLocationManager` fix; only accuracy and time to fix are kept | ≤100 m → pass |
| NFC | `NFCTagReaderSession` begins and becomes active | automatic |
| Flashlight | torch on/off | person |
| Both displays (Duo) | test pattern, checked closed and open; shows the hinge reading | person, per display |
| Hinge (Duo) | live `onHingeChange` status and angle; range seen | closed and fully open both seen → pass |

Logic in VitalsKit with tests: `TouchGrid` (incl. line interpolation), `SignalActivity`, `ToneGenerator`, suite
selection by device, result round-trip.

## Verified, and how
- Unit tests (62 total in the package at this point).
- Duo simulator: Tests list (17 tests), touch test painted by a simulated drag (48/112 cells; Vitals suggested
  Failed; result saved), flashlight reported "not found" with suggestion "Not available".
- Found by looking: the simulator delivers drag paths as sparse points, which showed fast drags could skip cells
  (fixed with interpolation); there was no way to record "Not available" (added).

## Not verified (needs the Duo)
All of the hardware itself: speakers, earpiece routing, every microphone data source, every lens, haptics,
volume and Camera Control detection, Action button via shortcut, motion sensors, proximity, Face ID, Bluetooth,
GPS, NFC, flashlight, both displays and the hinge. The simulator has none of them.

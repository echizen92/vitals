# App Review notes (draft)

Vitals is a device check-up that uses only public APIs: ProcessInfo (thermalState, Low Power Mode, physical memory),
UIDevice battery, URLResourceValues volume capacities, NWPathMonitor, task_info for its own footprint, Core Motion,
AVFoundation, Core Haptics, LocalAuthentication, Core Bluetooth, Core Location, Core NFC, WidgetKit and ActivityKit.

- **No private APIs, no private URL schemes.** Vitals cannot open Settings pages; it shows the steps instead.
- **System logs** are never read automatically. The person shares files from Settings > Privacy & Security >
  Analytics & Improvements > Analytics Data through the share sheet; Vitals parses them on the device.
- **Network**: only the user-started network test (Cloudflare's public speed-test endpoints), with a confirmation.
- **Hardware tests**: camera photos and microphone recordings are shown or played once and never saved; Bluetooth
  and GPS tests keep only a count and an accuracy.
- **Background**: BGAppRefreshTask takes one thermal/battery sample when iOS allows; a Live Activity is updated
  locally while the app runs (no push).
- **Benchmarks** are short, skipped when the phone is hot, and compare only against ranges measured on real phones
  (none ship in 1.0, so results are shown raw).
- **Photos** (Relief > Photos and videos clean-up, optional): access is asked only when that screen opens; the
  library is analysed on the device; deletion goes through the system's own confirmation into Recently Deleted.
  There is no "clear memory" or "boost" feature; the app explains why iOS has none.
- **Shortcuts**: Vitals runs its own shortcuts with the public `shortcuts://x-callback-url/run-shortcut` URL (Low
  Power Mode, brightness, Always On display, restart). Each one is shown to the person first and has an Undo.
- **Shortcuts in this build**: Cool down, Save battery and Restart (with Undo for the first two). They are added
  to the Shortcuts app by the person from Relief, then run from Vitals.
- **To see the app working without any logs** (about two minutes):
  1. Check-up tab: tap **Run check-up**. Each part of the phone drawing lights up; the verdict names anything worth
     a look; tap a part to see its readings and "What to do".
  2. Heat tab: the current heat level and a timeline. The timeline fills in as the app is opened over a day.
  3. Optimise tab > Quick relief: the Relief options; Photos clean-up asks for Photos access only there.
  4. Tests tab > Touch screen: paint the grid; then Speakers or Haptics.
  5. Check-up > Report (top right): the PDF preview, with personal details redacted by default.
  The log features (Logs tab, hot-spell causes) need a file iOS writes each morning when Settings > Privacy &
  Security > Analytics & Improvements > Share iPhone Analytics is on. Any "Analytics-…" file from Analytics Data
  can be shared to Vitals from that screen's Share button.
- The separate Mac companion is not part of this submission.

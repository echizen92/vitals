# M6 Widgets

## Built
- Widget extension `VitalsWidgets` with four widgets, one shared provider:
  | Widget | Families | Opens |
  |---|---|---|
  | Health summary | systemSmall, systemMedium | `vitals://checkup` |
  | Heat | systemSmall, systemMedium, accessoryRectangular, accessoryCircular | `vitals://heat` |
  | Battery | systemSmall, accessoryCircular, accessoryInline | `vitals://battery` |
  | Storage | systemSmall, accessoryCircular | `vitals://storage` |
- Every widget shows when it last updated ("Updated 11:32 AM"; the summary shows when the last check-up ran).
- **Sampling on reload**: each timeline reload reads thermal state, battery and storage in the extension and appends
  a `widget` sample to the shared SQLite store, de-duplicated (one sample per 5 minutes across all four widgets),
  so widgets thicken the heat timeline. Reload is requested every 15 minutes; iOS decides the real cadence.
- The app writes a small `WidgetSnapshot` (statuses, storage, drain) to the app group after each check-up and
  calls `WidgetCenter.reloadAllTimelines()`. Check-ups on injected values are never saved or handed to widgets.
- Status uses shape + colour; Lock Screen families use monochrome-friendly gauges and `widgetAccentable`.
- Debug widget gallery (Settings > Simulator state > Widget gallery, or `vitals://gallery`) renders the real widget
  views at widget sizes using the same loader, because the Home Screen cannot be driven from here.

## Verified, and how
- Builds clean (app + extension). Gallery screenshots on the Duo simulator: `Docs/screens/m6-widgets-1.png`, `-2.png`.
  With no battery level available (simulator), the battery widget shows "—" and "Level not available here" rather
  than a number. Fixture samples are excluded from the widget timeline.
- Fixed after looking: verbose relative time; "Norm" truncation in the circular heat gauge (short labels now).

## Not verified (needs the Duo)
- What a widget extension can actually read: `UIDevice.batteryLevel` (may be -1 in an extension) and whether
  `ProcessInfo.thermalState` in the extension reflects the phone. Marked unverified in `Shared/WidgetData.swift`.
- Real refresh cadence over a day, and whether reload-time samples appear on the Heat timeline.
- Widgets placed on the Home Screen / Lock Screen and their deep links (only the in-app gallery was viewed).

# M9 Control and Live Activity

## Built
- `RunCheckupIntent` (App Intent, `openAppWhenRun`), compiled into app and widget extension. It leaves a flag in
  the app group; the app starts the scan when it becomes active (also works from Shortcuts and the Action button).
  `AppShortcutsProvider` phrases: "Run a check-up in Vitals".
- Control Center / Lock Screen control `RunCheckupControl` (`ControlWidgetButton`).
- "Watch my phone" Live Activity (`MonitorAttributes`): started from the Heat screen with a purpose (Gaming,
  Charging, …). While Vitals runs it samples every minute (`liveActivity` samples), updates thermal state, battery,
  drain and elapsed time on the Lock Screen and in the Dynamic Island (compact, minimal, expanded). No push server.
  Stale after 30 min without an update; the activity always says when it last updated. Ends itself after 4 h.
- Stop saves a `MonitorSessionRecord` (duration, peak, hot minutes, drain) shown under "Watch sessions" and as a
  band on the heat timeline, and ends the activity with a summary line. Sessions orphaned by a quit app are ended
  and summarised on next launch.

## Verified, and how
- Duo simulator: started a session; iOS asked to allow Live Activities; the Lock Screen showed "Watching: Gaming",
  thermal state, elapsed time and "Updated …" (`Docs/screens/m9-lockscreen.png`). Stopped it; the session appeared
  under Watch sessions with its summary (`m9-session-saved.png`).
- Found by looking: the activity's text was dark on a dark tint (dynamic colours resolve differently on the Lock
  Screen); now fixed light-on-dark colours. A killed app left its activity running; now recovered on launch.

## Not verified
- The control in Control Center and on the Lock Screen, and the Shortcut / Action button path (needs adding the
  control by hand; not drivable from here).
- Dynamic Island presentations (the Duo's outer display has its Dynamic Island in the side strip; not captured).
- How long iOS keeps Vitals running to update the activity with the screen locked (likely not long).

# M2 Sampling and heat timeline

## Built
- Sample store: `samples` table in the app-group SQLite (`VitalsStore`), pruned to 30 days. Each sample records
  thermal state, battery level (nil when iOS gives none), charge state, Low Power Mode and who took it
  (`app`, `background`, `widget`, `liveActivity`, `companion`, `fixture`).
- When samples are taken: on every foreground, on `thermalStateDidChange`, battery state change and Low Power Mode
  change while the app runs, before each check-up, in `BGAppRefreshTask` (`sg.com.vitals.app.sample`, asked for
  every 20 min; iOS decides), and on widget reloads (M6).
- `HotSpellDetector`: runs of serious/critical samples; a non-hot sample or a gap over 45 min with no samples ends
  a spell (Vitals cannot see a gap). Each spell has start, end, peak, drain %/h (only when unplugged and ≥5 min),
  charging flag, sample count and "may still be going on".
- `BatteryMath`: drain and charge rates over runs of same-state samples ≥15 / ≥10 min; gaps over 90 min break runs.
  `Coverage`: share of hours with at least one sample, shown under the timeline so gaps are never hidden.
- Heat screen: "Right now" card over the living heat field (Metal shader, see M5), 24 h / 7 d timeline (Swift Charts:
  heat bands by state, battery line broken at gaps), scrubbing readout with a selection haptic when the scrubber
  enters a hot spell, coverage note, hot-spell list. Two columns at regular width.
- Optional heat notification (Settings): fires from any sample at serious/critical, at most hourly, with copy that
  says it can be late. Uses the sample time, not the delivery time.
- `SyntheticSamples.day()` plus `-syntheticDay` launch argument and a Settings button, marked `fixture`.

## Verified, and how
- Unit tests: hot-spell grouping, gap splitting, charging spells, unsorted input, drain/charge rates, coverage,
  store round-trip and pruning (included in the 29 → now 30+ tests).
- Duo simulator with a synthetic day and `-inject hot`: timeline drew bands and the battery line, three hot
  spells listed with duration, charging and drain; `Docs/screens` has the captures.
- Fixed after looking: duplicated "Hot. Hot." wording, truncated axis labels, a scrim that hid the heat field,
  long dates on spell rows.

## Not verified (needs the Duo)
- Real thermal transitions and whether `thermalStateDidChangeNotification` arrives while foregrounded.
- How often iOS actually grants `BGAppRefreshTask` time (likely rare and irregular).
- Notification timing relative to real heat.
- Scrubbing haptics (simulator has no Taptic Engine).

# M5 Design and motion pass

## Identity
Calm clinical instrument, its own look (not the maintainer's other apps):
- Grounds: paper `#F4F2EC` / near-black `#0B0D0E`; surfaces white / `#16191B`; no borders on panels.
- One cool accent that means "fine": `#0B7263` light / `#6CD6C3` dark. A warm ramp only for heat
  (`#3E8F86` → `#E3AA45` → `#E0672F` → `#C9302A`); text never sits in a heat colour, it uses status tones.
- Status = colour + shape everywhere (app, PDF, widgets): circle good, triangle attention, diamond problem,
  dashed ring unknown.
- Type: system text; rounded, monospaced-digit numerals for values; monospaced for raw evidence.
- Icon: a phone outline crossed by one pulse line (light, dark and tinted variants).

## Signature moments (as built)
| Moment | Full motion | Calm (serious heat) | Still (Reduce Motion or critical heat) |
|---|---|---|---|
| The scan (`PhoneModelView`) | sweep line, each region blooms as its probe really finishes, Duo model unfolds on appear and follows the hinge | 15 fps sweep, no bloom | no sweep, regions change state in place |
| Living heat (`HeatField.metal`) | noise field, speed and warmth from thermal state, still at nominal | 15 fps | one static frame |
| Timeline scrubbing | selection haptic on entering a hot spell | same | same (haptic is not motion) |
| The reveal (`CulpritTimeline`) | culprits rise from the heat band at their report time, staggered springs, sized by evidence | same | fade in place |
| The report assembles itself | section list ticks off as the report is built | same | fills at once |
| Four taps guide | looping sketch of the Settings path | same | hidden; numbered still list (always present) |

`MotionLevel` combines Reduce Motion with the live thermal state and is set once at the root, so every
animated view gets the right variant. `TimelineView` schedules pause whenever nothing moves (nominal heat, no
scan, view off screen). `-reduceMotion` launch argument forces the still variants for simulator checks.

## Duo
- System `TabView` (side strip on the outer display), `NavigationSplitView` for the check-up (scorecard beside
  detail at regular width), two-column Heat at regular width, readable max widths on detail screens.
- Hinge: SwiftUI `onHingeChange` (iOS 27.1, public) read once at the root into the environment and used only for
  the phone drawing (folded when closed, opening with the angle). Never for layout, per the Duo HIG.
  The Duo simulator reports the hinge as **closed** on the outer display, so the drawing shows one panel with all
  six regions; with no hinge reading it draws the open phone.

## Verified, and how
- Duo simulator, light and dark, with `-inject hot|critical` and `-reduceMotion`: scan result, folded Duo model,
  still heat field at critical, culprit reveal (`Docs/screens/m5-*.png`, `m3-reveal.png`).
- iPhone 18 Pro Max in landscape (regular width): check-up split view shows scorecard and detail side by side.
- Fixed after looking: battery/software regions hidden on the folded model; heat card scrim edge.

## Not verified
- The inner (unfolded) Duo display: the simulator here cannot open the hinge, and the Simulator app is not
  installed. Regular-width behaviour was checked on a large iPhone in landscape instead.
- Energy cost of the scan and heat field (needs Instruments on the Duo; see needs-device).
- 120 Hz pacing (simulator renders at 60 Hz).
- Launch takes ~4 s to first frame in the Debug simulator build; a sample shows all of it in `dyld_sim` loading
  libraries before app code runs. Check a Release build on the device.

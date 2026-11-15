# Design review fixes (iPhone app), 2026-11-15

Screens: `Docs/screens/review/` — `18pm-{light,dark}-*` (iPhone 18 Pro Max simulator, iOS 27.0) and
`duo-{light,dark}-*` (iPhone Duo simulator, iOS 27.1, outer display; the inner display stays off because the
simulator reports the hinge closed).

## 1. Blank launch
- **Measured.** iPhone 18 Pro Max simulator (iOS 27.0): first content 17 to 23 s after launch, blank ground from
  about 5 s. iPhone Duo simulator (iOS 27.1): first content **1.7 to 2.1 s**, same build.
- **Cause: the iOS 27.0 simulator runtime, not Vitals.** Main-thread samples during the blank period show the
  process still inside `dyld_sim` (Objective-C class registration) at 3 s and in Swift protocol-conformance lookup
  at 7 to 13 s, before any Vitals code runs. Apple's own Settings app takes 26.8 s to first content on the same
  simulator. `~/Library/Developer/CoreSimulator/Caches/dyld` is empty: the 27.0 runtime has no prebuilt loader
  cache. `xcrun simctl runtime dyld_shared_cache update` should fix it (not run: it writes several GB of caches;
  offered to the maintainer). Vitals' own start-up was already asynchronous after the first frame.
- **Changed anyway:** the launch screen now shows the Vitals mark on the paper or ink ground (`LaunchMark`,
  rendered by `scripts/make-launch-mark.swift` from the icon's geometry; `design/logo` untouched), so a slow start
  reads as starting, not broken.
- Not checked on a real phone.

## 2. Onboarding
Three pages that show rather than tell: the phone model scanning itself (on an iPhone Duo, the Duo, open), the
three provenance tags around a lock, and the Settings path drawn as Settings rows ending at the switch. Page dots
are custom and sit beside Skip/Next, never on the text; content is centred; landscape puts picture and words side
by side. Selection haptic on each page.

## 3. Check-up hero and verdict
- The phone model is larger (360 pt) and each region is a labelled, tappable tile (icon, name, status shape) that
  opens its area; names drop to icon-only only when a tile is too small, with the name kept for VoiceOver.
- The outline is always ink (the brown came from it taking the Software status colour).
- A closed iPhone Duo is drawn folded (second panel behind, hinge on the edge); open, it shows two panels.
- Verdict names the worst area with its own sentence ("Heat: 2 hot spells in the last 24 hours, none while
  charging"), says how many more areas to look at, and "See why" opens that area.

## 4. Heat
- Normal has presence: a cool mint field (cool colour only, so it never drifts to olive in dark), a 2.5 s settle on
  appearance, then still. Hotter levels stay restless as before.
- "ProcessInfo.thermalState · no degrees on iPhone" is now "iPhone reports heat levels, not degrees"; the API name
  stays in the reading's source (report and detail).
- Timeline: heat is its own colour strip; battery has its own 0 to 100% chart below on the same time axis.
- The scrim starts higher so the injected-values banner and labels read over the Very hot field in dark.

## 5. Hot spell reveal and process names
- `ProcessName` / `ProcessNames` (app) and `ProcessGlossary.friendlyName` (VitalsKit): friendly name first, raw
  name secondary, the glossary's explanation as the VoiceOver hint. Used in the reveal, culprit rows, Logs lists,
  event rows, crash titles, and the diagnosis sentences ("iOS flagged heavy CPU use by Photos analysis…").
- The reveal uses the heat palette (warmer and larger for stronger evidence), a soft halo, a staggered spring rise
  out of the heat band, and one light haptic. Reduce Motion: fade in place.

## 6. Logs
One action: "Share today's daily file" with a full-width "Show me how" and a quieter "Or choose files you already
saved". Shared files are titled by what they are ("Daily analytics, Nov 15") with the file name secondary; the
just-imported row leads with what was read.

## 7. Motion and haptics
Selection tick per area as a scan lands and success or warning at the end; scorecard rows arrive staggered and
spring on status change; numeric transitions on big values; a light tick for every sample the timeline scrubber
passes and a firmer one entering a hot spell; success or warning on each hardware test result (fired from the
model, because the test screen closes on the same tap) and a tick on each yes/no choice inside a test. All follow
`MotionLevel` (still under Reduce Motion).

## Fixed along the way
A Python slip while editing removed three Logs views (EventRow, CrashDetailView, RawReportView); they were
restored from the original text with the one later change reapplied, and the app builds and runs.

## Verified, and how
Simulators only: both simulators, light and dark, screens listed above; "See why" opens Heat; landscape onboarding.
84 Swift and 17 Python tests pass; the Mac companion still builds.

## Not verified
- Anything on a real phone (launch time there, haptics, 120 Hz motion, hinge-driven unfold).
- "During scan" on the Duo simulator: the scan finishes faster than a screenshot can be taken.
- The inner Duo display (off in the simulator), largest Dynamic Type sizes, VoiceOver, hardware test screens,
  Relief and the report were not re-reviewed.

## iPhone Duo shape (after the first real-device look, 2026-11-15)
Faiz's Release build on the Duo showed the open model as two separate iPhones side by side. Redrawn:
- **One body** whose proportions come from the screen the app is on (short edge ÷ long edge). On a Duo the outer
  and inner displays are the same rectangle turned (1398 × 2034 px outer, 2034 × 1398 px inner), so one
  measurement gives both shapes.
- **Closed:** the outer display's wider, shorter body, camera in the top corner, no Dynamic Island pill.
- **Open:** one wide body with a fine crease down the centre (a soft shadow and a hairline), no camera showing.
  Regions sit on either side of the crease and never straddle it.
- **Partly open:** the same single body narrows with the hinge angle; the far side is slightly shaded.
- **Ordinary iPhones:** unchanged, a tall body with the island, at their own screen proportions.
- Onboarding on wide space (the Duo's inner display, or landscape) puts the picture and words side by side,
  centred as one group.
- `-duoOpen` forces the open drawing for checking in the Simulator.

Verified: Duo simulator outer display, closed and forced-open, Check-up and onboarding, light and dark
(`Docs/screens/review/duo-shape-*`); iPhone 18 Pro Max unchanged (`iphone-shape-checkup-light.png`).
Not verified: the inner display (the Simulator keeps it off while it reports the hinge closed), the live unfold
and partly-open drawing on a real hinge, and onboarding's side-by-side layout on the real inner display.

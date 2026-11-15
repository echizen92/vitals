# M4b Advice and Optimise (plan 5.14)

## Built
- **Catalogue** `VitalsKit/Resources/advice.json`, version 1, "as of iOS 27.2": 32 actions (18 manual, 8 guided,
  4 Shortcuts, 2 done by Vitals), 36 finding types each mapped to 1 to 3 actions plus an escalation ladder, safety
  entries for swollen battery and overheating while charging (stop, seek service), and 3 myths kept as explanations,
  never as actions (clear RAM, force-quitting apps, battery calibration). Every action has steps with the Settings
  path, the effect, the downside, a source, effort, and what Vitals should watch to measure it.
  Includes the real-case entries: stuck iCloud Drive sync, unfinished Health restore, failed App Store downloads,
  phone not seen over USB.
- **Finding detail** shows "What to do" (numbered actions), "If that does not help" (the ladder, ending with "the
  report is ready to share with Apple or a repair shop"), the access tier and confidence, and "Could not determine".
- **Action detail**: why (tied to the evidence), numbered steps, what should change, downside, "Steps as of iOS
  27.2", then "I did this, measure it" (guided/manual), "Run …" (Shortcuts, when bundled) or "Open Relief".
- **Mark as done** stores an `ActionRecord` with a metrics snapshot before; Vitals evaluates it when the watch
  window passes and says Improved / No change / Worse / Too early, in plain words, including "no change".
- **Optimise tab**: only items relevant to this phone's findings and state, each with its effect and downside.
- **Case model** (plan 4b): open → action suggested → action taken → resolved, watching → resolved / came back,
  with a revision history; findings are revised, not replaced, when evidence or a user fact arrives.
- **"Something feels off?"** on Optimise: a person-started step, "Check what your apps accessed", that walks through
  iOS's App Privacy Report (sensor and data access, network domains) and VPN & Device Management. It is also an
  escalation step for unexplained heat, unexplained drain, and a VPN or proxy. Its footer says plainly that no app,
  Vitals included, can detect hardware side-channel attacks by other apps. Added after the maintainer asked about this.
- Report schema: `actions`, `caseRecord`, `userFacts`, `couldNotDetermine`, `adviceVersion` (Docs/report-schema.md).

Fixed on 2026-11-15: two titles ended in "for the app named" with no name (now "…for the busy app"); a photo
clean-up was judged "Worse" right after deleting because the photos sit in Recently Deleted. It now stays
"Measuring" with that explanation until the space returns or 30 days pass.

## Verified, and how
- Swift tests (`AdviceTests`, `DuoCaseTests`): every finding type has actions and an escalation ladder; every
  action is complete; safety cases say seek service; no myth is an action; Optimise lists only relevant items;
  outcomes say "no change" plainly; the case reaches the stuck-sync hypothesis, is revised by the iCloud size fact,
  and a restart outcome moves it to "resolved, watching".
- Tests for the privacy step's wiring and the photo clean-up verdict (84 Swift tests total).
- Simulator (Duo): "Something feels off?" section and its detail (`m4b-privacy-check.png`, `m4b-privacy-steps.png`), case card, case detail with the fact question and revision, advice section, action detail,
  Optimise (`Docs/screens/m4b-*.png`).

## Not verified
- Settings paths and wording on a real iOS 27.2 Duo (needs-device.md).
- Real before/after outcomes over a day.

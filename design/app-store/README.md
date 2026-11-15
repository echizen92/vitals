# App Store page: decisions (first submission, 2026-11-15)

Made with the ASO skill's rules: benefit first, differentiator second, one idea per screenshot, no word repeated
across name, subtitle and keywords.

```
App name (22/30):          Vitals: Phone Check-up
Subtitle (30/30):          Heat, battery & hardware tests
Keywords (97/100):         overheating,diagnostic,thermal,hot,drain,crash,storage,repair,benchmark,sensor,temperature,device
Promotional text (155/170): Why is your iPhone hot? Vitals keeps a heat timeline and, with the daily file iOS already writes, names the apps that were busy. Nothing leaves your phone.
```
No word in the keyword field appears in the name or subtitle. No competitor names, no "app", "free", "iPhone".

## Screenshots: default page (6.9", 1320 × 2868, `iphone-6.9/`)
1. [benefit]        "Find out why your iPhone runs hot" · Check-up with the named verdict
2. [differentiator] "See which apps were busy" · a hot spell with its causes rising out of the timeline
3. [feature]        "Steps that actually help" · Heat area: findings and "What to do"
4. [feature]        "Your phone's day, in heat" · Heat screen
5. [feature]        "Quick relief, no fake boosts" · Relief
6. [trust]          "Nothing leaves your phone" · onboarding, where every value says where it came from

Screens are real captures from the iPhone 18 Pro Max simulator running the submitted build, with the app's own
demo data (`-syntheticDay -syntheticLogs`), status bar set to 9:41 and full charge. No real user data.
Rendered by `render.swift` (Swift and AppKit, so nothing is installed); sources in `source/screens/`.

## Not done yet
- Custom product pages (ideas: "repair technicians" led by hardware tests and the report; "iPhone Duo").
- iPhone Duo screenshots (App Store Connect offers a badge for apps with them): the simulator can't show the
  inner display, so these need the real Duo.
- Header and search images.

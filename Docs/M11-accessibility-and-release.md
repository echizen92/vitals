# M11 Accessibility and release prep

## Built
- **Accessibility audit** (VoiceOver, Dynamic Type, contrast) across the main screens, 21 items applied, among them:
  hardware-test verdict buttons with `isSelected` and the test named in the label; an adaptive row that stacks
  at accessibility sizes; the touch grid with an accessibility action and an escape; combined labels for the Now
  card, culprit rows and Live Activity; spoken units ("degrees", "percent per hour"); `ScaledMetric` badge sizes;
  readout, picker, big value and legend reflow at large text; capped `dynamicTypeSize` only where a layout would
  break (widgets, Live Activity); longer line limits.
- **Contrast**: palette tokens aligned to the icon (ink #0B0F14, paper #F4F1EA, mint #3FD6B8, heat #FFB347 → #FF6B5E).
  Text colours meet 4.5:1 on their grounds; the attention banner tint was raised from 4.39 to 4.61. Status never
  relies on colour alone: each status has its own shape (circle, solid ring, triangle, diamond, dashed ring).
- **Reduce Motion**: every animation has a still or cross-fade variant (`MotionLevel`), also lowered when the
  phone is hot.
- **Privacy**: `PrivacyInfo.xcprivacy` in the app, widgets, share extension and VitalsKit (required-reason APIs:
  file timestamps, disk space, system boot time, user defaults). Usage descriptions for camera, microphone,
  Bluetooth, location, Face ID, motion, NFC, local network and Photos. Nothing leaves the phone, so the privacy
  label draft stays "Data Not Collected"; Photos are analysed on the phone only.
- **Icon**: `design/logo` PNGs copied into AppIcon (light, dark, tinted), launch background and accent tokens to
  match. `design/logo` itself is untouched.
- App Store metadata and App Review notes drafted (`AppStore-metadata-draft.md`, `AppReview-notes.md`).

## Verified, and how
- Simulator (Duo) with accessibility text sizes: check-up and scorecard reflow (`Docs/screens/m11-ax-*.png`),
  Home Screen icon (looked at; screenshot not kept). Contrast ratios computed from the token values.

## Not verified / release list
- VoiceOver walk-through on the device (rotor, hinge states, Live Activity).
- Layered Liquid Glass icon in Icon Composer (not done; the flat PNGs ship).
- Companion release: bundled Python runtime, Developer ID signing, notarisation (needs the maintainer's account). See
  needs-device.md "Release".
- Support, marketing and privacy policy URLs before submission.

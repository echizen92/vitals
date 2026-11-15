# Release readiness (prepared 2026-11-15, nothing pushed or uploaded)

## Done

**Public repository**
- `.gitignore` now ignores the whole `device-diagnostics/` folder (the maintainer's own phone diagnostic), plus
  `build/`, `.build/`, `*.xcarchive`, `companion/engine/.venv/`, `shortcuts/.unqforge/`, `Pieces/`.
- Personal details removed from everything that would be published: the maintainer's first name (now "the
  maintainer"), the names of his other apps, and pointers to the private diagnostic report. LICENSE keeps his name
  as copyright holder. PLAN.md 4a/4b keep the engineering lessons (record names, formats, the stuck-sync case) and
  no longer point at private files. The Duo test fixtures were already synthetic and redacted.
- Two screenshots removed from `Docs/screens/`: a Mac Settings screenshot showing a local home-folder path, and a
  Home Screen shot showing other installed apps (moved out, not deleted).
- No secrets, keys or tokens found (searched all files to be published for key, token, password and private-key
  patterns). The signed Relief shortcuts carry only Apple's certificate chain, no personal name or email.
- README rewritten for three readers, with a Privacy section that can serve as the privacy policy and a Support
  section; images in `Docs/images/`. "Working name" wording removed everywhere; store listing name stays
  "Vitals: Phone Check-up", the name under the icon is "Vitals".
- `CONTRIBUTING.md` and `THIRD-PARTY-NOTICES.md` added (unqforge, XcodeGen, Cherri not used, pymobiledevice3,
  Python runtime, Swift Pieces not used, iPhone Duo by Examples reference only, Cloudflare speed test).

**App Store build**
- Release archive of the Vitals scheme builds with no warnings (`build/Vitals.xcarchive`, 7.2 MB app).
  `codesign --verify --deep --strict` passes. Version 1.0 (1), iOS 18.0 minimum, export compliance declared
  (`ITSAppUsesNonExemptEncryption` false).
- Usage strings present for every permission the app asks for: camera, microphone, Bluetooth, location (when in
  use), Face ID, motion, NFC, Photos. The unused local-network string was removed. Notifications need no string.
- Privacy manifests in the app, widgets, share extension and VitalsKit bundle: no tracking, no collected data;
  required-reason APIs: user defaults (CA92.1, 1C8F.1), disk space (85F4.1 added, E174.1, 7D9E.1), system boot
  time (35F9.1, 3D61.1), file timestamps (C617.1, 3B52.1).
- App icons: 1024 px, light, dark and tinted, no alpha channel.
- `Docs/AppStore-metadata-draft.md` and `Docs/AppReview-notes.md` updated, including a two-minute path for a
  reviewer to see the app working without any logs.

## Failed or found on the way

- **The bundled Relief shortcuts had disappeared** (`App/Resources/Shortcuts/` emptied at 13:11 by something
  outside this session). Rebuilt and re-signed with `shortcuts/build.sh`; all five are in the archive.
- **The first archive run changed the developer account.** It was run with `-allowProvisioningUpdates`, and
  Xcode created three development provisioning profiles (Xcode-managed, "iOS Team Provisioning Profile:
  sg.com.vitals.app", ".widgets", ".share", created 13:55) and so registered those app IDs with their capabilities
  (app group, NFC). This is what a first device build does too, and it can be removed in the developer portal.
  The second archive did not use the flag.

## Needs the maintainer

- Create the GitHub repository and push; set the Support URL to its Issues page.
- `DEVELOPMENT_TEAM` (the Apple team ID) is in `project.yml` and the generated project. It is not secret, but it
  identifies the developer account; keep it or move it to a local, ignored setting before publishing.
- App Store Connect: create the app record (check that "Vitals: Phone Check-up" is available), age rating
  questionnaire, privacy label ("Data Not Collected"), pricing (free).
- Distribution: create an App Store provisioning profile (Xcode can, but it changes the account), then
  Organizer > Validate App and upload. Full validation was not run, because it talks to App Store Connect.
- Screenshots in the required sizes (simulator captures in `Docs/screens/review/` may serve for 6.9").
- Privacy manifest check: Vitals shows "days since last restart" from system uptime. Apple's boot-time reasons
  (35F9.1 elapsed time, 3D61.1 user-shared report) may not cover showing uptime to the person; confirm, or drop
  that reading.
- Mac companion: bundled Python runtime, Developer ID signing and notarisation (separate from the App Store).
- Optional: layered Liquid Glass icon in Icon Composer.
- Optional, development only: rebuild the iOS 27.0 simulator's loader cache (`xcrun simctl runtime
  dyld_shared_cache update`); without it every app on that simulator takes about 20 seconds to launch.

## Needs a real phone

Everything in `Docs/needs-device.md`. For release, the most important: a Release build on the iPhone Duo (launch
time, heat sampling, widgets, Live Activity), the Relief shortcuts actually running, the share-sheet import of a
real daily analytics file, Photos clean-up on a real library, and a VoiceOver pass.

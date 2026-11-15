# Third-party notices

Vitals is built almost entirely from Apple's frameworks. This file lists everything else the project uses,
whether it ships, and under which licence.

## Shipped inside the iPhone app

Nothing. The iPhone app, widgets and share extension have no third-party code or Swift packages.

The five Relief shortcut files (`App/Resources/Shortcuts/*.shortcut`) are generated from this project's own
source in `shortcuts/src/` by unqforge (below) and signed with Apple's `shortcuts sign` tool. They contain no
unqforge code.

## Used to build, not shipped

| Project | Licence | How it is used |
|---|---|---|
| [unqforge](https://github.com/anupml/unqforge), pinned at `489315242d8b8bf5f84352dca31f76479f87f8fe` | MIT | Compiles the Python shortcut source into Shortcuts files. Fetched by hand into `shortcuts/.unqforge/` (git-ignored); see `shortcuts/README.md`. |
| [XcodeGen](https://github.com/yonaskolb/XcodeGen) | MIT | Generates `Vitals.xcodeproj` from `project.yml`. |
| [Cherri](https://github.com/electrikmilk/cherri) | GPL-2.0 | **Not used.** Considered as a fallback shortcut compiler; never installed. |

## Shipped with the Mac companion (`companion/`, GPL-3.0-or-later)

| Project | Licence | How it is used |
|---|---|---|
| [pymobiledevice3](https://github.com/doronz88/pymobiledevice3) | GPL-3.0 | The companion's engine runs its command line to talk to the iPhone. Release builds will bundle it, with a pinned Python runtime, inside the app; its licence and source link will ship with it. This is why the companion is GPL-3.0-or-later. |
| Python (bundled runtime, release builds only, not yet built) | PSF License | Runs the engine. |

The engine itself uses only the Python standard library.

## Referenced, not copied

| Project | Licence | Status |
|---|---|---|
| [Swift Pieces](https://github.com/Saivion/SwiftPieces) | MIT with the Commons Clause | **No files are used.** Its licence restricts selling, so pieces are not committed. If any are adopted later they will be fetched by `scripts/fetch-pieces.sh` at a pinned revision into the git-ignored `Pieces/` folder, and this file will list them. |
| [iPhone Duo by Examples](https://github.com/artemnovichkov/iPhone-Duo-by-Examples) | MIT | Read as a reference for the hinge and display APIs. No code copied. |

## Services

The network speed test, started by the person, uses [Cloudflare's public speed test](https://speed.cloudflare.com)
endpoints. No account or key is involved.

"""Writes THIRD-PARTY-NOTICES.md for the downloadable Vitals Companion.

Run with the bundled Python (Contents/Resources/python/bin/python3), so it lists exactly what the app ships:
    python3 notices.py OUT.md
Each package's licence comes from its own installed metadata (License-Expression, else License, else the
licence classifiers), and its licence files are named so readers can find the full texts inside the app.
"""

import importlib.metadata as md
import sys

RUNTIME = """## Python runtime

CPython 3.13.18, built by python-build-standalone (astral-sh, release 20261026,
`cpython-3.13.18+20261026-aarch64-apple-darwin-install_only_stripped`). Licence: PSF-2.0 (Python Software Foundation
License); full text in `Contents/Resources/python/lib/python3.13/LICENSE.txt`, which also carries the licences of
the third-party code inside CPython itself.

Libraries python-build-standalone builds into that runtime, according to its documentation: OpenSSL (Apache-2.0),
libffi (MIT), SQLite (public domain), XZ Utils / liblzma (0BSD), zlib (Zlib), bzip2 (bzip2-1.0.6),
mpdecimal (BSD-2-Clause), ncurses (X11 / MIT), libedit (BSD-3-Clause), Tcl/Tk (TCL). Source:
https://github.com/astral-sh/python-build-standalone
"""


# Packages whose metadata names no licence; read from their licence files on 2026-11-19.
FROM_LICENCE_FILE = {"apple-compress": "MIT", "asgimiddlewarestaticfile": "MIT", "asgiwebdav": "MIT",
                     "pyimg4": "MIT", "pykdebugparser": "MIT"}


def licence(dist):
    m = dist.metadata
    known = FROM_LICENCE_FILE.get(m["Name"].lower())
    if known:
        return known + " (from its licence file)"
    expr = m.get("License-Expression")
    if expr:
        return expr.strip()
    text = (m.get("License") or "").strip()
    if text and "\n" not in text and len(text) <= 80:
        return text
    classifiers = [c.split(" :: ")[-1] for c in (m.get_all("Classifier") or []) if c.startswith("License ::")]
    if classifiers:
        return "; ".join(classifiers)
    return "see licence file" if text else "not stated in metadata"


def home(dist):
    m = dist.metadata
    for u in m.get_all("Project-URL") or []:
        label, _, url = u.partition(",")
        if label.strip().lower() in ("source", "source code", "repository", "homepage", "home", "github", "code"):
            return url.strip()
    return (m.get("Home-page") or "").strip()


def licence_files(dist):
    files = [str(f) for f in (dist.files or []) if "licen" in str(f).lower() or "copying" in str(f).lower()
             or "notice" in str(f).lower()]
    return ", ".join("`%s`" % f for f in files[:3])


def main(out):
    dists = sorted({d.metadata["Name"].lower(): d for d in md.distributions() if d.metadata["Name"].lower() != "pip"}.values(),
                   key=lambda d: d.metadata["Name"].lower())
    lines = [
        "# Third-party notices: Vitals Companion for Mac",
        "",
        "Vitals Companion is GPL-3.0-or-later (`LICENSE`). The downloadable app bundles a Python runtime and the",
        "packages below, unmodified, in `Contents/Resources/python`. Licence texts are inside the app at the paths",
        "listed (under `Contents/Resources/python/lib/python3.13/site-packages/`). The GPL source offer is in",
        "`companion/README.md`.",
        "",
        RUNTIME,
        "## Python packages (%d)" % len(dists),
        "",
        "| Package | Version | Licence | Source | Licence files |",
        "|---|---|---|---|---|",
    ]
    for d in dists:
        lines.append("| %s | %s | %s | %s | %s |" % (d.metadata["Name"], d.version, licence(d).replace("|", "/"),
                                                    home(d), licence_files(d)))
    lines.append("")
    open(out, "w").write("\n".join(lines))
    print("wrote %s (%d packages)" % (out, len(dists)))


if __name__ == "__main__":
    main(sys.argv[1])

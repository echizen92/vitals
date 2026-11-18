#!/bin/zsh
# Builds the downloadable Vitals Companion: Release app + bundled Python runtime + pymobiledevice3, signed with
# Developer ID (hardened runtime, timestamp), packaged as a signed DMG, notarised and stapled.
#
#   companion/packaging/make-release.sh [stage ...]
#
# Stages, in order (default: all): app runtime notices sign dmg notarize
# Needs: Xcode, the "Developer ID Application" identity in the keychain, and a notarytool keychain profile
# (default vitals-notary) that the maintainer created. Downloads only the pinned runtime (python.pin) and the
# hash-locked wheels (requirements.lock) from their official sources; both are verified before use.
set -euo pipefail
setopt null_glob
here=${0:A:h}
repo=${here:h:h}
cd "$repo"

IDENTITY=${IDENTITY:-"Developer ID Application: Faiz Rashid (ETR554P9HN)"}
PROFILE=${NOTARY_PROFILE:-vitals-notary}
VERSION=${VERSION:-1.0}
OUT=${OUT:-$repo/build/companion-release}
APP="$OUT/Vitals Companion.app"
DMG="$OUT/Vitals-Companion-$VERSION.dmg"
CACHE="$OUT/cache"
ENT="$here/python.entitlements"
stages=("$@"); (( $#stages )) || stages=(app runtime notices sign dmg notarize)
mkdir -p "$OUT" "$CACHE"
source "$here/python.pin"
has() { (( ${stages[(Ie)$1]} )); }

if has app; then
  echo "== app"
  xcodegen generate -q
  xcodebuild -project Vitals.xcodeproj -scheme VitalsCompanion -configuration Release \
    -derivedDataPath "$OUT/dd" build > "$OUT/app-build.log" 2>&1 || { tail -20 "$OUT/app-build.log"; exit 1; }
  rm -rf "$APP"
  ditto "$OUT/dd/Build/Products/Release/Vitals Companion.app" "$APP"
fi

PY="$APP/Contents/Resources/python"
if has runtime; then
  echo "== runtime ($ASSET)"
  tarball="$CACHE/$ASSET"
  [[ -f "$tarball" ]] || curl -fsSL -o "$tarball" "$URL"
  echo "$SHA256  $tarball" | shasum -a 256 -c - >/dev/null || { echo "checksum mismatch for $ASSET"; exit 1; }
  rm -rf "$PY" "$CACHE/unpack"; mkdir -p "$CACHE/unpack"
  tar -xzf "$tarball" -C "$CACHE/unpack"
  ditto "$CACHE/unpack/python" "$PY"
  # Wheels: downloaded with every hash required, then installed offline from them.
  mkdir -p "$CACHE/wheels"
  "$PY/bin/python3" -m pip download -q --disable-pip-version-check --require-hashes --only-binary :all: --no-deps -r "$here/requirements.lock" -d "$CACHE/wheels"
  "$PY/bin/python3" -m pip install -q --disable-pip-version-check --no-index --find-links "$CACHE/wheels" --require-hashes --no-deps -r "$here/requirements.lock"
  "$PY/bin/python3" -c "import pymobiledevice3, importlib.metadata as m; assert m.version('pymobiledevice3') == '11.55.0'"
  "$PY/bin/python3" "$here/relocate_scripts.py" "$PY/bin"
  # Not needed at run time: the test suite, IDLE, Tk, the installer and pip itself.
  lib="$PY/lib/python3.13"
  rm -rf "$lib/test" "$lib/idlelib" "$lib/tkinter" "$lib/turtledemo" "$lib/ensurepip" "$lib/lib2to3" \
         "$lib/site-packages/pip" "$lib/site-packages"/pip-*.dist-info "$PY/share" "$PY/include"
  rm -f "$PY/bin"/idle* "$PY/bin"/pip* "$PY/bin/pydoc"* "$PY/bin/2to3"*
  find "$PY/lib" -maxdepth 1 \( -name "libtcl*" -o -name "libtk*" -o -name "tcl*" -o -name "tk*" -o -name "itcl*" -o -name "thread*" \) -exec rm -rf {} +
  rm -f "$lib/lib-dynload"/_tkinter*.so
  # Bytecode now, so Python never writes into the signed bundle (the app also sets PYTHONDONTWRITEBYTECODE).
  find "$PY" -name "__pycache__" -type d -prune -exec rm -rf {} +
  "$PY/bin/python3" -m compileall -q -j 0 "$lib" "$APP/Contents/Resources/vitals_companion" >/dev/null || true
fi

if has notices; then
  echo "== notices"
  "$PY/bin/python3" "$here/notices.py" "$repo/companion/THIRD-PARTY-NOTICES.md"
  cp "$repo/companion/THIRD-PARTY-NOTICES.md" "$repo/companion/LICENSE" "$APP/Contents/Resources/"
fi

if has sign; then
  echo "== sign (inside-out)"
  # Every Mach-O under Resources/python: libraries and extension modules first, executables last.
  machos=("${(@f)$(find "$APP/Contents" -type f ! -path "*/_CodeSignature/*" -print0 | xargs -0 file | grep "Mach-O" | cut -d: -f1 | sed 's/ (for architecture .*)$//' | sort -u)}")
  for f in $machos; do
    case "$f" in
      "$APP/Contents/MacOS/"*) continue ;;                            # the app itself is signed last
      "$PY/bin/"*) codesign --force --timestamp --options runtime --entitlements "$ENT" --sign "$IDENTITY" "$f" ;;
      *) codesign --force --timestamp --options runtime --sign "$IDENTITY" "$f" ;;
    esac
  done
  codesign --force --timestamp --options runtime --sign "$IDENTITY" "$APP"
  codesign --verify --deep --strict --verbose=2 "$APP"
  spctl -a -vvv -t exec "$APP" || true    # "Unnotarized Developer ID" until the notarize stage
fi

if has dmg; then
  echo "== dmg"
  stage="$OUT/dmg-root"; rm -rf "$stage" "$DMG"; mkdir -p "$stage"
  ditto "$APP" "$stage/Vitals Companion.app"
  ln -s /Applications "$stage/Applications"
  hdiutil create -quiet -volname "Vitals Companion" -srcfolder "$stage" -fs HFS+ -format UDZO "$DMG"
  codesign --force --timestamp --sign "$IDENTITY" "$DMG"
  codesign --verify --verbose=2 "$DMG"
fi

if has notarize; then
  echo "== notarize ($PROFILE)"
  xcrun notarytool submit "$DMG" --keychain-profile "$PROFILE" --wait --output-format json | tee "$OUT/notary.json"
  xcrun stapler staple "$DMG"
  xcrun stapler validate "$DMG"
  spctl -a -vvv -t open --context context:primary-signature "$DMG"
fi
ls -la "$DMG" 2>/dev/null || true

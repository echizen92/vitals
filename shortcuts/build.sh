#!/bin/zsh
# Builds and signs the Vitals Relief shortcuts into App/Resources/Shortcuts/.
# Needs: macOS with the `shortcuts` command, Python 3.8+, and unqforge at the pinned revision in
# shortcuts/.unqforge (git-ignored). This script does NOT download anything; clone it yourself:
#   git clone https://github.com/anupml/unqforge shortcuts/.unqforge
#   git -C shortcuts/.unqforge checkout 489315242d8b8bf5f84352dca31f76479f87f8fe
set -euo pipefail
cd "$(dirname "$0")"
PIN=489315242d8b8bf5f84352dca31f76479f87f8fe
[ -d .unqforge ] || { echo "unqforge missing: see README.md"; exit 1; }
HEAD=$(git -C .unqforge rev-parse HEAD)
[ "$HEAD" = "$PIN" ] || { echo "unqforge is at $HEAD, expected $PIN"; exit 1; }
OUT=../App/Resources/Shortcuts
TMP=$(mktemp -d)
mkdir -p "$OUT"
# Shortcuts names an imported shortcut after its file, so the file is named exactly as the app runs it
# (ReliefShortcut.rawValue, spaces included). Undo is the same shortcut run with the text "undo" as input.
build() {  # source-file  shortcut-name
  PYTHONPATH=.unqforge:src python3 "src/$1" "$TMP/$2.plist"
  plutil -convert binary1 -o "$TMP/$2.shortcut" "$TMP/$2.plist"
  shortcuts sign -m anyone -i "$TMP/$2.shortcut" -o "$OUT/$2.shortcut"
  echo "built $OUT/$2.shortcut"
}
rm -f "$OUT"/*.shortcut
build cool_down.py     "Vitals Cool down"
build save_battery.py  "Vitals Save battery"
build restart.py       "Vitals Restart"
rm -rf "$TMP"

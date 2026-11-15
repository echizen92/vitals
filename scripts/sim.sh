#!/bin/zsh
# Build, install and launch Vitals in a simulator, then optionally take a screenshot.
# Usage: scripts/sim.sh <udid> [screenshot-name] [launch args...]
# Example: scripts/sim.sh B3019074-877C-4A51-B386-6C657B7FA38E checkup-hot -inject hot
set -e
UDID=$1; shift
NAME=${1:-}; [ $# -gt 0 ] && shift
cd "$(dirname "$0")/.."
xcrun simctl boot "$UDID" 2>/dev/null || true
APP=build/dd/Build/Products/Debug-iphonesimulator/Vitals.app
xcrun simctl install "$UDID" "$APP"
xcrun simctl terminate "$UDID" sg.com.vitals.app 2>/dev/null || true
xcrun simctl launch "$UDID" sg.com.vitals.app "$@" >/dev/null
if [ -n "$NAME" ]; then
  sleep ${SHOT_DELAY:-4}
  mkdir -p Docs/screens
  # iPhone Duo has two displays (outer and inner); a standard iPhone has one.
  if xcrun simctl io "$UDID" screenshot "Docs/screens/$NAME.png" >/dev/null 2>&1; then
    echo "Docs/screens/$NAME.png"
  else
    for d in ${=DISPLAYS:-1 3}; do
      xcrun simctl io "$UDID" screenshot --display=$d "Docs/screens/$NAME-d$d.png" >/dev/null 2>&1 && echo "Docs/screens/$NAME-d$d.png"
    done
  fi
fi

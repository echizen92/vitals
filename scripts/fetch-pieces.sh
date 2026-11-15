#!/bin/zsh
# Fetches Swift Pieces files (github.com/Saivion/SwiftPieces) into Pieces/ at a pinned revision.
# Licence: MIT + Commons Clause. Until the maintainer decides how that fits a public repo (PLAN 6a), Pieces/ is
# git-ignored and never committed; this script is the only way the files arrive.
# The current build uses NO pieces (Vitals' own components cover everything), so PIECES is empty and
# REV is unset. To adopt one: set REV to a reviewed commit, list the files, run this, and style them
# through PiecesStyle.swift.
set -euo pipefail
cd "$(dirname "$0")/.."
REPO=https://github.com/Saivion/SwiftPieces
REV=""            # pin a full commit hash before use
PIECES=()         # e.g. ("Sources/Pieces/ShimmerText.swift")
if [ ${#PIECES[@]} -eq 0 ]; then echo "No pieces listed; nothing to fetch."; exit 0; fi
[ -n "$REV" ] || { echo "Set REV to a pinned commit first."; exit 1; }
TMP=$(mktemp -d)
git clone --quiet --filter=blob:none --no-checkout "$REPO" "$TMP/src"
git -C "$TMP/src" checkout --quiet "$REV"
mkdir -p Pieces
for f in "${PIECES[@]}"; do cp "$TMP/src/$f" Pieces/; echo "Pieces/$(basename "$f")"; done
cp "$TMP/src/LICENSE"* Pieces/ 2>/dev/null || true
rm -rf "$TMP"

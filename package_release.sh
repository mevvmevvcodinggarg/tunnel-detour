#!/bin/bash
set -euo pipefail

ROOT="$(cd "$(dirname "$0")" && pwd)"
OUT_DIR="${1:-$ROOT/dist}"
APP="$($ROOT/build_app.sh "$OUT_DIR")"
ARCHIVE="$OUT_DIR/TunnelDetour.zip"

rm -f "$ARCHIVE" "$ARCHIVE.sha256"
/usr/bin/ditto -c -k --sequesterRsrc --keepParent "$APP" "$ARCHIVE"
(
    cd "$OUT_DIR"
    /usr/bin/shasum -a 256 TunnelDetour.zip > TunnelDetour.zip.sha256
)

printf '%s\n%s\n' "$ARCHIVE" "$ARCHIVE.sha256"

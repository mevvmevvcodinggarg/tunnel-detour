#!/bin/bash
set -euo pipefail

ROOT="$(cd "$(dirname "$0")/../.." && pwd)"
OUT="$(mktemp -d)"
trap 'rm -rf "$OUT"' EXIT

"$ROOT/package_release.sh" "$OUT"

test -x "$OUT/TunnelDetour.app/Contents/MacOS/TunnelDetour"
test -x "$OUT/TunnelDetour.app/Contents/Library/LaunchServices/TunnelDetourHelper"
test -f "$OUT/TunnelDetour.app/Contents/Resources/TunnelDetour.icns"
plutil -lint "$OUT/TunnelDetour.app/Contents/Info.plist"
codesign --verify --deep --strict "$OUT/TunnelDetour.app"
unzip -t "$OUT/TunnelDetour.zip"
(cd "$OUT" && shasum -a 256 -c TunnelDetour.zip.sha256)

echo "Application packaging passed."

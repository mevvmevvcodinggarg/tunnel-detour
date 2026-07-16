#!/bin/bash
set -euo pipefail

ROOT="$(cd "$(dirname "$0")/../.." && pwd)"
TEMP_DIR="$(mktemp -d)"
trap 'rm -rf "$TEMP_DIR"' EXIT

test -f "$ROOT/Assets/Brand/tunnel-detour-icon.png"
test -f "$ROOT/Assets/Brand/TunnelDetourMenuBar.png"
test -f "$ROOT/Assets/Brand/TunnelDetourMenuBar@2x.png"
test -f "$ROOT/Assets/TunnelDetour.icns"

/usr/bin/grep -Fq 'setActivationPolicy(.regular)' "$ROOT/Sources/TunnelDetourApp/TunnelDetourMain.swift"
/usr/bin/grep -Fq 'TunnelDetourMenuBar' "$ROOT/Sources/TunnelDetourApp/AppDelegate.swift"
if /usr/bin/grep -Eq 'point\.3\.connected|button\.title = " T"' "$ROOT/Sources/TunnelDetourApp/AppDelegate.swift"; then
    echo "Former status item artwork is still configured." >&2
    exit 1
fi

iconutil --convert iconset \
    --output "$TEMP_DIR/TunnelDetour.iconset" \
    "$ROOT/Assets/TunnelDetour.icns"

sips -g pixelWidth -g pixelHeight \
    "$TEMP_DIR/TunnelDetour.iconset/icon_512x512@2x.png" | grep -q '1024'

echo "Brand assets passed."

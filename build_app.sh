#!/bin/bash
set -euo pipefail

ROOT="$(cd "$(dirname "$0")" && pwd)"
OUT_DIR="${1:-$ROOT/dist}"
APP_NAME="TunnelDetour"
APP="$OUT_DIR/$APP_NAME.app"
BINARY="$ROOT/.build/release/TunnelDetourApp"
HELPER_BINARY="$ROOT/.build/release/TunnelDetourHelper"
ICON="$ROOT/Assets/TunnelDetour.icns"

cd "$ROOT"
swift build -c release --product TunnelDetourApp >&2
swift build -c release --product TunnelDetourHelper >&2

rm -rf "$APP"
mkdir -p "$APP/Contents/MacOS"
mkdir -p "$APP/Contents/Library/LaunchServices"
mkdir -p "$APP/Contents/Resources"
cp "$ROOT/Info.plist" "$APP/Contents/Info.plist"
cp "$BINARY" "$APP/Contents/MacOS/$APP_NAME"
cp "$HELPER_BINARY" "$APP/Contents/Library/LaunchServices/TunnelDetourHelper"
cp "$ICON" "$APP/Contents/Resources/TunnelDetour.icns"
cp "$ROOT/Assets/Brand/TunnelDetourMenuBar.png" "$APP/Contents/Resources/TunnelDetourMenuBar.png"
cp "$ROOT/Assets/Brand/TunnelDetourMenuBar@2x.png" "$APP/Contents/Resources/TunnelDetourMenuBar@2x.png"
chmod 755 "$APP/Contents/MacOS/$APP_NAME"
chmod 755 "$APP/Contents/Library/LaunchServices/TunnelDetourHelper"
strip -x "$APP/Contents/MacOS/$APP_NAME" || true
strip -x "$APP/Contents/Library/LaunchServices/TunnelDetourHelper" || true

codesign --force --deep --sign - "$APP" >/dev/null
codesign --verify --deep --strict "$APP"

echo "$APP"

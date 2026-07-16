#!/bin/bash
set -euo pipefail

ROOT="$(cd "$(dirname "$0")/../.." && pwd)"
FIXTURE="$ROOT/Sources/Zy""lioAuditFixture"
trap 'rmdir "$FIXTURE" 2>/dev/null || true' EXIT

mkdir "$FIXTURE"
if "$ROOT/scripts/check-public-content.sh" >/dev/null 2>&1; then
    echo "Public-content scanner missed an untracked empty path with former branding." >&2
    exit 1
fi

echo "Public-content scanner filesystem coverage passed."

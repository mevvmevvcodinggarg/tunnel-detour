#!/usr/bin/env bash
set -euo pipefail

workflow=".github/workflows/release.yml"

/usr/bin/grep -Fq 'gh release view "$GITHUB_REF_NAME"' "$workflow"
/usr/bin/grep -Fq 'gh release upload "$GITHUB_REF_NAME"' "$workflow"
/usr/bin/grep -Fq -- '--clobber' "$workflow"

echo "Release workflow idempotency passed."

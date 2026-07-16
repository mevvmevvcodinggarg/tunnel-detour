#!/bin/bash
set -euo pipefail

cd "$(dirname "$0")/.."
failed=0

if git ls-files | /usr/bin/grep -Ein '(vpnaidirect|zylio|corporate)'; then
    echo "Public-content violation: former name in tracked path" >&2
    failed=1
fi

if find . \
    -path './.git' -prune -o \
    -path './.build' -prune -o \
    -path './dist' -prune -o \
    -print | /usr/bin/grep -Ein '(vpnaidirect|zylio|corporate)'; then
    echo "Public-content violation: former name in workspace path" >&2
    failed=1
fi

if git grep -n -I -i -E '(VPNAIDirect|VPN AI Direct|Zylio|Corporate Check)' -- . \
    ':(exclude)scripts/check-public-content.sh' \
    ':(exclude)docs/plans/**' \
    ':(exclude)docs/superpowers/**'; then
    echo "Public-content violation: former name in tracked content" >&2
    failed=1
fi

scan() {
    local description="$1"
    local pattern="$2"
    shift 2
    if git grep -n -I -i -E "$pattern" -- "$@"; then
        echo "Public-content violation: $description" >&2
        failed=1
    fi
}

scan "machine-specific home directory" \
    '(/Users|/home)/[[:alnum:]_.-]+' \
    . ':(exclude)scripts/check-public-content.sh'

scan "credential-like assignment" \
    '(password|passwd|api[_-]?key|access[_-]?token|client[_-]?secret)[[:space:]]*[:=][[:space:]]*"[^"]+' \
    . ':(exclude)scripts/check-public-content.sh'

scan "credential-like URL query" \
    '[?&](token|api[_-]?key|access[_-]?token|client[_-]?secret)=[^&[:space:]]+' \
    . ':(exclude)scripts/check-public-content.sh'

scan "former user-visible branding" \
    'Zylio|VPN AI Direct|Corporate Check' \
    README.md Info.plist build_app.sh package_release.sh \
    Sources/TunnelDetourApp Assets .github

if [[ "$failed" -ne 0 ]]; then
    exit 1
fi

echo "Public-content scan passed."

#!/bin/bash

set -euo pipefail

here="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
probe="$here/system-probe"

if [ ! -f "$probe" ]; then
    echo "system-probe is not next to this script." >&2
    echo "Build it with: swiftc -O -o \"$probe\" \"$here/system-probe.swift\"" >&2
    exit 1
fi

xattr -d com.apple.quarantine "$probe" 2>/dev/null || true
chmod +x "$probe"

exec "$probe"

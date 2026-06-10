#!/usr/bin/env bash
# Build and launch the Viewer macOS app.
# Workaround for SwiftPM-built SwiftUI apps not activating from the terminal.
set -euo pipefail

cd "$(dirname "$0")/.."
swift build --product Viewer "$@"

BIN="$(swift build --show-bin-path "$@")/Viewer"
if [[ ! -x "$BIN" ]]; then
    echo "error: Viewer binary not found at $BIN" >&2
    exit 1
fi

# `open -a` runs it as a foreground GUI app and brings it to the front.
exec open -a "$BIN"

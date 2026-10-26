#!/bin/sh

set -eu

if command -v xcrun >/dev/null 2>&1 && xcrun --find swift-format >/dev/null 2>&1; then
  exec xcrun swift-format "$@"
fi

if command -v swift-format >/dev/null 2>&1; then
  exec swift-format "$@"
fi

# Without a toolchain (for example on Raspberry Pi), use the pinned fallback release.
binary=$("$(dirname "$0")/ensure-swift-format.sh")
exec "$binary" "$@"

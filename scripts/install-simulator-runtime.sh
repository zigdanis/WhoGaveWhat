#!/bin/sh
# Makes sure the named iOS Simulator runtime (for example "iOS 27.1") is installed for the
# selected Xcode. GitHub's xcode-27 image preinstalls only the iOS 27.0 runtime, so the
# runtime that matches Xcode's own SDK is downloaded with `xcodebuild -downloadPlatform iOS`.
# Prints the installed runtimes, the iPhones the runtime supports and, when a model is named,
# that model's Simulator profile (screen size and scale) for the run log.

set -eu

if [ "$#" -lt 1 ] || [ "$#" -gt 2 ]; then
  echo "usage: $0 'iOS 27.1' ['iPhone Duo']" >&2
  exit 2
fi
runtime=$1
device=${2:-}

has_runtime() {
  xcrun simctl list runtimes available --json | python3 -I -c '
import json, sys
names = [runtime.get("name") for runtime in json.load(sys.stdin).get("runtimes", []) if runtime.get("isAvailable")]
sys.exit(0 if sys.argv[1] in names else 1)
' "$runtime"
}

if has_runtime; then
  echo "$runtime Simulator runtime is already installed."
else
  echo "Downloading the iOS Simulator runtime for $(xcodebuild -version | head -n 1)"
  started=$(date +%s)
  xcodebuild -downloadPlatform iOS
  echo "Download took $(( $(date +%s) - started )) s."
  if ! has_runtime; then
    echo "::error::$runtime is still not available after downloading the iOS platform."
    xcrun simctl list runtimes
    exit 1
  fi
fi

xcrun simctl list runtimes
xcrun simctl list runtimes available --json | python3 -I -c '
import json, sys
for runtime in json.load(sys.stdin).get("runtimes", []):
    if runtime.get("name") == sys.argv[1]:
        names = [device.get("name", "") for device in runtime.get("supportedDeviceTypes", [])]
        print(runtime["name"], runtime.get("buildversion"), "supports:", ", ".join(name for name in names if name.startswith("iPhone")))
' "$runtime"

if [ -n "$device" ]; then
  bundle=$(xcrun simctl list devicetypes --json | python3 -I -c '
import json, sys
paths = [device_type.get("bundlePath", "") for device_type in json.load(sys.stdin).get("devicetypes", [])
         if device_type.get("name") == sys.argv[1]]
print(paths[0] if len(paths) == 1 else "")
' "$device")
  if [ -z "$bundle" ]; then
    echo "::error::No unique $device Simulator device type."
    exit 1
  fi
  echo "$device Simulator profile ($bundle):"
  plutil -p "$bundle/Contents/Resources/profile.plist" | grep -v -i -E 'data|png|pdf' || true
fi

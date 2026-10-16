#!/bin/sh
# Prints the path of a swift-format binary from the Swift release that CI's Xcode ships
# (Xcode 26.6, Swift 6.3.3), installing it once into a user cache directory when missing.
#   --print-install-dir  print the cache directory and exit (no network)
#   --print-url          print the toolchain download URL and exit (no network)
# SWIFT_FORMAT_OS and SWIFT_FORMAT_ARCH override uname for tests.

set -eu

SWIFT_VERSION=6.3.3
RELEASE=swift-$SWIFT_VERSION-RELEASE
BASE_URL=https://download.swift.org/swift-$SWIFT_VERSION-release

os=${SWIFT_FORMAT_OS:-$(uname -s)}
arch=${SWIFT_FORMAT_ARCH:-$(uname -m)}

case "$os" in
  Darwin) cache_root=${XDG_CACHE_HOME:-$HOME/Library/Caches} ;;
  Linux) cache_root=${XDG_CACHE_HOME:-$HOME/.cache} ;;
  *)
    echo "error: no pinned swift-format download for $os" >&2
    exit 1
    ;;
esac
install_dir=$cache_root/whogavewhat/swift-format/$SWIFT_VERSION

# The Debian 12 toolchains need only glibc 2.36, so they also run on Raspberry Pi OS
# (bookworm) and newer Debian and Ubuntu releases.
case "$os/$arch" in
  Linux/x86_64)
    archive=$RELEASE-debian12.tar.gz
    url=$BASE_URL/debian12/$RELEASE/$archive
    sha256=19e0c78cad5418ad48bfa87aa20c53ac9ac9996d1695d04dd94f7c7ea4eb133f
    ;;
  Linux/aarch64 | Linux/arm64)
    archive=$RELEASE-debian12-aarch64.tar.gz
    url=$BASE_URL/debian12-aarch64/$RELEASE/$archive
    sha256=ecba8ef87b54a5048d466af500f3169c939a6b8a2cb7c600f76b5184457f293a
    ;;
  Darwin/*)
    archive=$RELEASE-osx.pkg
    url=$BASE_URL/xcode/$RELEASE/$archive
    sha256=ee82e57774d6650f94aa06302435d6f44a055b9411698db8ecb85d9a3bcc91d0
    ;;
  *)
    echo "error: no pinned swift-format download for $os/$arch" >&2
    exit 1
    ;;
esac

case "${1:-}" in
  --print-install-dir)
    echo "$install_dir"
    exit 0
    ;;
  --print-url)
    echo "$url"
    exit 0
    ;;
  "") ;;
  *)
    echo "usage: $0 [--print-install-dir | --print-url]" >&2
    exit 2
    ;;
esac

binary=$install_dir/usr/bin/swift-format
if [ -x "$binary" ]; then
  echo "$binary"
  exit 0
fi

echo "Installing swift-format from Swift $SWIFT_VERSION into $install_dir (one-time download of about 1 GB)" >&2
work=$(mktemp -d "${TMPDIR:-/tmp}/swift-format.XXXXXX")
trap 'rm -rf "$work"' EXIT INT TERM
curl --fail --location --silent --show-error --retry 2 --output "$work/$archive" "$url"

if command -v sha256sum >/dev/null 2>&1; then
  actual=$(sha256sum "$work/$archive" | cut -d ' ' -f 1)
else
  actual=$(shasum -a 256 "$work/$archive" | cut -d ' ' -f 1)
fi
if [ "$actual" != "$sha256" ]; then
  echo "error: $archive checksum mismatch (expected $sha256, got $actual)" >&2
  exit 1
fi

mkdir -p "$work/root/usr/bin"
if [ "$os" = Linux ]; then
  # Keep only swift-format and the Swift runtime libraries it loads.
  tar -xzf "$work/$archive" -C "$work/root" --strip-components=1 --wildcards \
    "$RELEASE-*/usr/bin/swift-format" "$RELEASE-*/usr/lib/swift/linux/*.so"
else
  pkgutil --expand-full "$work/$archive" "$work/pkg"
  payload_binary=$(find "$work/pkg" -path '*/Payload/usr/bin/swift-format' | head -n 1)
  if [ -z "$payload_binary" ]; then
    echo "error: swift-format is missing from $archive" >&2
    exit 1
  fi
  cp "$payload_binary" "$work/root/usr/bin/swift-format"
fi

mkdir -p "$(dirname "$install_dir")"
rm -rf "$install_dir"
mv "$work/root" "$install_dir"
echo "$binary"

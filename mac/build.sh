#!/bin/bash
# Builds "World Clock.app" next to this script, using only the Xcode Command Line Tools.
#   bash mac/build.sh
# Needs: macOS 13 or newer, and `xcode-select --install` done once (it gives swiftc, codesign,
# sips, iconutil). No Xcode, no package manager, no network.
set -euo pipefail
cd "$(dirname "$0")"

APP="World Clock.app"
BIN="$APP/Contents/MacOS/World Clock"
ARCH="$(uname -m)"                      # arm64 on Apple silicon, x86_64 on Intel

[ -d "$APP" ] && rm -r "$APP"
mkdir -p "$APP/Contents/MacOS" "$APP/Contents/Resources"

echo "Compiling WorldClock.swift for $ARCH…"
swiftc -O -target "$ARCH-apple-macos13.0" \
  -framework Cocoa -framework WebKit -framework ServiceManagement \
  WorldClock.swift -o "$BIN"

cp Info.plist "$APP/Contents/Info.plist"

# App icon: QuickLook rasterises the SVG mark, sips makes every size, iconutil packs the .icns.
WORK="$(mktemp -d)"
ICONSET="$WORK/AppIcon.iconset"
mkdir -p "$ICONSET"
if qlmanage -t -s 1024 -o "$WORK" icon.svg >/dev/null 2>&1 && [ -f "$WORK/icon.svg.png" ]; then
  for s in 16 32 128 256 512; do
    sips -z "$s" "$s" "$WORK/icon.svg.png" --out "$ICONSET/icon_${s}x${s}.png" >/dev/null
    sips -z "$((s*2))" "$((s*2))" "$WORK/icon.svg.png" --out "$ICONSET/icon_${s}x${s}@2x.png" >/dev/null
  done
  iconutil -c icns "$ICONSET" -o "$APP/Contents/Resources/AppIcon.icns"
else
  echo "warning: could not rasterise icon.svg, the app will carry the generic icon" >&2
fi
rm -r "$WORK"

# Ad-hoc signature: no developer account involved, it only tells macOS the bundle is one app.
codesign --force --sign - "$APP" 2>/dev/null

echo "Built: $PWD/$APP"
echo "Run it:  open \"$PWD/$APP\"     Install it: drag it into /Applications"

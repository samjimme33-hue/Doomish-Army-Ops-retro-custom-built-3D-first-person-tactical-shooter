#!/bin/zsh
# Builds Doomish.app -- a double-clickable macOS app bundle -- from source.
# Uses swiftc directly (no Xcode project, no dependencies, no packages to fetch).
set -e
cd "$(dirname "$0")"

APP="Doomish.app"
BIN="$(swift build --package-path . -c release --show-bin-path 2>/dev/null | tail -1)"

# Locate an SDK. `xcrun --show-sdk-path` is unreliable on Command Line Tools-only
# installs, so fall back to globbing the SDK directory.
SDKROOT="$(xcrun --show-sdk-path 2>/dev/null || true)"
if [[ ! -d "$SDKROOT" ]]; then
  for d in /Library/Developer/CommandLineTools/SDKs/MacOSX*.sdk /Applications/Xcode.app/Contents/Developer/Platforms/MacOSX.platform/Developer/SDKs/MacOSX*.sdk; do
    [[ -d "$d" ]] && SDKROOT="$d"
  done
fi
if [[ ! -d "$SDKROOT" ]]; then
  echo "error: no macOS SDK found (install Xcode or the Command Line Tools)" >&2
  exit 1
fi
export SDKROOT
echo "using SDK: $SDKROOT"

echo "compiling..."
swiftc -O -whole-module-optimization \
  -sdk "$SDKROOT" \
  Sources/Doomish/*.swift \
  -o Doomish \
  -framework AppKit -framework AVFoundation

rm -rf "$APP"
mkdir -p "$APP/Contents/MacOS" "$APP/Contents/Resources"
cp Doomish "$APP/Contents/MacOS/Doomish"

cat > "$APP/Contents/Info.plist" <<'PLIST'
<?xml version="1.0" encoding="UTF-8"?>
<!DOCTYPE plist PUBLIC "-//Apple//DTD PLIST 1.0//EN" "http://www.apple.com/DTDs/PropertyList-1.0.dtd">
<plist version="1.0">
<dict>
  <key>CFBundleName</key><string>Doomish</string>
  <key>CFBundleDisplayName</key><string>Doomish</string>
  <key>CFBundleExecutable</key><string>Doomish</string>
  <key>CFBundleIdentifier</key><string>local.doomish.game</string>
  <key>CFBundlePackageType</key><string>APPL</string>
  <key>CFBundleShortVersionString</key><string>1.0</string>
  <key>CFBundleVersion</key><string>1</string>
  <key>LSMinimumSystemVersion</key><string>11.0</string>
  <key>NSHighResolutionCapable</key><true/>
  <key>NSHumanReadableCopyright</key><string>Doomish</string>
</dict>
</plist>
PLIST

codesign -s - --force "$APP" >/dev/null 2>&1 || true

echo ""
echo "built $PWD/$APP"
echo "run it with:  open $APP"

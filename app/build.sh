#!/bin/bash
# Build brb.app. Output: app/dist/brb.app (menu bar agent, no dock icon).
set -euo pipefail
HERE="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
DIST="$HERE/dist"
APP="$DIST/brb.app"
VERSION=$("/usr/bin/python3" -c "import json;print(json.load(open('$HERE/../.claude-plugin/plugin.json'))['version'])" 2>/dev/null || echo 0.0.0)

echo "building brbui ($VERSION)…"
swift build -c release --package-path "$HERE" >/dev/null

rm -rf "$APP"
mkdir -p "$APP/Contents/MacOS" "$APP/Contents/Resources"
cp "$HERE/.build/release/brbui" "$APP/Contents/MacOS/brb"

cat > "$APP/Contents/Info.plist" <<PLIST
<?xml version="1.0" encoding="UTF-8"?>
<!DOCTYPE plist PUBLIC "-//Apple//DTD PLIST 1.0//EN" "http://www.apple.com/DTDs/PropertyList-1.0.dtd">
<plist version="1.0">
<dict>
  <key>CFBundleName</key><string>brb</string>
  <key>CFBundleDisplayName</key><string>brb</string>
  <key>CFBundleIdentifier</key><string>com.usebrb.brb</string>
  <key>CFBundleExecutable</key><string>brb</string>
  <key>CFBundlePackageType</key><string>APPL</string>
  <key>CFBundleShortVersionString</key><string>$VERSION</string>
  <key>CFBundleVersion</key><string>$VERSION</string>
  <key>LSMinimumSystemVersion</key><string>14.0</string>
  <key>LSUIElement</key><true/>
  <key>NSHighResolutionCapable</key><true/>
  <key>NSSupportsAutomaticTermination</key><false/>
</dict>
</plist>
PLIST

# Ad-hoc signature: enough for a local build. A release needs a Developer ID.
codesign --force --sign - "$APP" >/dev/null 2>&1 || echo "warning: could not sign (the app still runs locally)"

echo "built $APP"
echo "run it:   open '$APP'"
echo "install:  cp -R '$APP' /Applications/"

#!/bin/bash
# Builds BlarneyKey.app into ~/Applications. Run it again after any source change.
set -euo pipefail

PROJECT="$(cd "$(dirname "$0")" && pwd)"
APP="$HOME/Applications/BlarneyKey.app"

echo "==> Compiling"
cd "$PROJECT"
swift build -c release --disable-sandbox

echo "==> Assembling $APP"
rm -rf "$APP"
mkdir -p "$APP/Contents/MacOS" "$APP/Contents/Resources"
cp ".build/release/BlarneyKey" "$APP/Contents/MacOS/BlarneyKey"

cat > "$APP/Contents/Info.plist" <<'PLIST'
<?xml version="1.0" encoding="UTF-8"?>
<!DOCTYPE plist PUBLIC "-//Apple//DTD PLIST 1.0//EN" "http://www.apple.com/DTDs/PropertyList-1.0.dtd">
<plist version="1.0">
<dict>
  <key>CFBundleExecutable</key><string>BlarneyKey</string>
  <key>CFBundleIdentifier</key><string>com.douglaswoollam.blarneykey</string>
  <key>CFBundleName</key><string>BlarneyKey</string>
  <key>CFBundleDisplayName</key><string>BlarneyKey</string>
  <key>CFBundlePackageType</key><string>APPL</string>
  <key>CFBundleShortVersionString</key><string>1.0</string>
  <key>CFBundleVersion</key><string>1</string>
  <key>LSMinimumSystemVersion</key><string>14.0</string>
  <key>LSUIElement</key><true/>
  <key>NSHighResolutionCapable</key><true/>
  <key>NSMicrophoneUsageDescription</key>
  <string>BlarneyKey transcribes your speech locally, on this Mac, for dictation.</string>
</dict>
</plist>
PLIST

echo "==> Signing"
# Ad-hoc signature. Enough for a locally built app, and it keeps the microphone and
# Accessibility grants attached to a stable bundle identifier.
codesign --force --sign - --identifier com.douglaswoollam.blarneykey "$APP"

echo
echo "Built: $APP"
echo "Launch it with:  open \"$APP\""

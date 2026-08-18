#!/bin/bash
# Builds BlarneyKey.app into /Applications. Run it again after any source change.
set -euo pipefail

PROJECT="$(cd "$(dirname "$0")" && pwd)"
APP="/Applications/BlarneyKey.app"

echo "==> Compiling"
cd "$PROJECT"
swift build -c release --disable-sandbox

echo "==> Assembling $APP"
rm -rf "$APP"
mkdir -p "$APP/Contents/MacOS" "$APP/Contents/Resources"
cp ".build/release/BlarneyKey" "$APP/Contents/MacOS/BlarneyKey"

# Marks the app draws at runtime, plus the icon. Regenerate the icon with
# `python3 assets/make-icon.py && iconutil -c icns assets/BlarneyKey.iconset -o assets/BlarneyKey.icns`
for asset in blarneykey-mark cork-ai-consulting-mark; do
  cp "assets/$asset.png" "$APP/Contents/Resources/" 2>/dev/null \
    || echo "    warning: assets/$asset.png missing, the app will fall back to a symbol"
done
if [ -f "assets/BlarneyKey.icns" ]; then
  cp "assets/BlarneyKey.icns" "$APP/Contents/Resources/BlarneyKey.icns"
else
  echo "    warning: assets/BlarneyKey.icns missing, the app will show the generic icon"
fi

cat > "$APP/Contents/Info.plist" <<'PLIST'
<?xml version="1.0" encoding="UTF-8"?>
<!DOCTYPE plist PUBLIC "-//Apple//DTD PLIST 1.0//EN" "http://www.apple.com/DTDs/PropertyList-1.0.dtd">
<plist version="1.0">
<dict>
  <key>CFBundleExecutable</key><string>BlarneyKey</string>
  <key>CFBundleIdentifier</key><string>com.douglaswoollam.blarneykey</string>
  <key>CFBundleName</key><string>BlarneyKey</string>
  <key>CFBundleIconFile</key><string>BlarneyKey</string>
  <key>CFBundleDisplayName</key><string>BlarneyKey</string>
  <key>CFBundlePackageType</key><string>APPL</string>
  <key>CFBundleShortVersionString</key><string>1.0</string>
  <key>CFBundleVersion</key><string>1</string>
  <key>LSMinimumSystemVersion</key><string>14.0</string>
  <key>NSHighResolutionCapable</key><true/>
  <key>NSMicrophoneUsageDescription</key>
  <string>BlarneyKey transcribes your speech locally, on this Mac, for dictation.</string>
</dict>
</plist>
PLIST

echo "==> Signing"
# macOS ties the Accessibility grant to the app's designated requirement. Signed with a
# real certificate, that requirement is the bundle identifier plus the certificate, both
# of which survive a rebuild. Signed ad-hoc there is no certificate, so the requirement
# falls back to the code hash — which changes every build, silently voiding the grant
# while System Settings still shows the app ticked.
#
# So: use a signing identity if there is one. See "Stable signing" in the README for the
# two-minute, one-time setup.
IDENTITY="${BLARNEYKEY_SIGNING_IDENTITY:-}"

# Any real certificate will do, so take the first one available rather than making
# people create something. An "Apple Development" certificate comes free with an Apple
# ID through Xcode, so most Macs that have ever opened Xcode already have one.
if [ -z "$IDENTITY" ]; then
  AVAILABLE="$(security find-identity -v -p codesigning 2>/dev/null || true)"
  for candidate in "BlarneyKey Self-Signed" "Developer ID Application" "Apple Development"; do
    match="$(printf '%s\n' "$AVAILABLE" | grep -F "$candidate" | head -1 || true)"
    if [ -n "$match" ]; then
      # Pull the quoted common name out of `security`'s listing.
      IDENTITY="$(printf '%s\n' "$match" | sed -n 's/.*"\(.*\)".*/\1/p')"
      break
    fi
  done
fi

if [ -n "$IDENTITY" ]; then
  codesign --force --sign "$IDENTITY" --identifier com.douglaswoollam.blarneykey "$APP"
  echo "    signed with \"$IDENTITY\""
  echo "    the Accessibility grant will survive future rebuilds."
else
  codesign --force --sign - --identifier com.douglaswoollam.blarneykey "$APP"
  echo "    signed ad-hoc: no code signing certificate was found."
  echo
  echo "    !! macOS will drop this app's Accessibility permission on every rebuild,"
  echo "       and you will have to remove and re-add it in Privacy & Security."
  echo "       Fix it once: see \"Stable signing\" in the README."
fi

echo
echo "Built: $APP"
echo "Launch it with:  open \"$APP\""

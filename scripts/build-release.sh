#!/usr/bin/env bash
# Build a Release Prosciutto.app. Requires Xcode + a Developer ID for signing/notarization.
# Set DEVELOPMENT_TEAM and CODE_SIGN_IDENTITY env vars for a signed build.
set -euo pipefail

cd "$(dirname "$0")/.."

echo "==> Regenerating Xcode project"
xcodegen generate

echo "==> Archiving"
xcodebuild \
  -project Prosciutto.xcodeproj \
  -scheme Prosciutto \
  -configuration Release \
  -archivePath build/Prosciutto.xcarchive \
  archive

echo "==> Exporting app"
cat > build/ExportOptions.plist <<'PLIST'
<?xml version="1.0" encoding="UTF-8"?>
<!DOCTYPE plist PUBLIC "-//Apple//DTD PLIST 1.0//EN" "http://www.apple.com/DTDs/PropertyList-1.0.dtd">
<plist version="1.0">
<dict>
  <key>method</key>
  <string>developer-id</string>
</dict>
</plist>
PLIST

xcodebuild \
  -exportArchive \
  -archivePath build/Prosciutto.xcarchive \
  -exportOptionsPlist build/ExportOptions.plist \
  -exportPath build/export

echo "==> Done: build/export/Prosciutto.app"

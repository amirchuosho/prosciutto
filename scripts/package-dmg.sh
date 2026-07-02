#!/usr/bin/env bash
# Build an unsigned (ad-hoc) Release DMG for open-source distribution.
# No Apple Developer account needed. Users bypass Gatekeeper once on first launch
# (see README "Install"). For a zero-warning DMG, use build-release.sh + notarize.sh
# with a Developer ID instead.
set -euo pipefail
cd "$(dirname "$0")/.."

VERSION=$(grep -m1 'MARKETING_VERSION' Project.yml | sed -E 's/.*"([^"]+)".*/\1/')
APP_NAME="Prosciutto"
OUT_DIR="dist"
DMG="$OUT_DIR/${APP_NAME}-${VERSION}.dmg"

echo "==> Regenerating project"
xcodegen generate >/dev/null

echo "==> Building Release (unsigned)"
xcodebuild -project Prosciutto.xcodeproj -scheme "$APP_NAME" \
  -configuration Release -derivedDataPath build build >/dev/null

APP="build/Build/Products/Release/${APP_NAME}.app"
[ -d "$APP" ] || { echo "build failed: $APP missing"; exit 1; }

echo "==> Ad-hoc signing (avoids the 'app is damaged' Gatekeeper error)"
codesign --force --deep --sign - "$APP"

echo "==> Staging DMG (app + /Applications symlink for drag-install)"
STAGE=$(mktemp -d)
cp -R "$APP" "$STAGE/"
ln -s /Applications "$STAGE/Applications"

mkdir -p "$OUT_DIR"
rm -f "$DMG"
hdiutil create -volname "$APP_NAME" -srcfolder "$STAGE" -ov -format UDZO "$DMG" >/dev/null
rm -rf "$STAGE"

echo "==> Done: $DMG"
echo -n "SHA256: "; shasum -a 256 "$DMG" | awk '{print $1}'
echo -n "Size:   "; du -h "$DMG" | awk '{print $1}'

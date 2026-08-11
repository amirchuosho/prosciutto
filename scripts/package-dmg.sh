#!/usr/bin/env bash
# Build a Release DMG for open-source distribution. No Apple Developer account needed;
# users bypass Gatekeeper once on first launch (see README "Install"). For a zero-warning
# DMG, use build-release.sh + notarize.sh with a Developer ID instead.
#
# Signing: prefers the STABLE self-signed identity from scripts/setup-codesign.sh
# ('Prosciutto Signing') so TCC permissions (Accessibility, etc.) survive updates. Falls
# back to ad-hoc if that identity isn't in the keychain — the DMG still installs, but each
# update will re-request permissions. Run scripts/setup-codesign.sh once to enable the
# stable identity.
set -euo pipefail
cd "$(dirname "$0")/.."

VERSION=$(grep -m1 'MARKETING_VERSION' Project.yml | sed -E 's/.*"([^"]+)".*/\1/')
APP_NAME="Prosciutto"
OUT_DIR="dist"
DMG="$OUT_DIR/${APP_NAME}-${VERSION}.dmg"

echo "==> Regenerating project"
xcodegen generate >/dev/null

echo "==> Building Release (xcodebuild produces it unsigned; we sign below)"
xcodebuild -project Prosciutto.xcodeproj -scheme "$APP_NAME" \
  -configuration Release -derivedDataPath build build >/dev/null

APP="build/Build/Products/Release/${APP_NAME}.app"
[ -d "$APP" ] || { echo "build failed: $APP missing"; exit 1; }

IDENTITY="${PROSCIUTTO_SIGN_IDENTITY:-Prosciutto Signing}"
# No `-v`: the self-signed identity is untrusted (never in the "valid" list) but signs fine
# and yields a stable cert-based designated requirement. `-F`: match the name as a literal
# string, not a regex. Match by name in the full list.
if security find-identity -p codesigning | grep -qF "$IDENTITY"; then
  echo "==> Signing with stable identity '$IDENTITY' (TCC permissions persist across updates)"
  codesign --force --deep --sign "$IDENTITY" "$APP"
else
  echo "==> '$IDENTITY' not found — ad-hoc signing (permissions will reset each update)."
  echo "    Run scripts/setup-codesign.sh once to make permissions persist."
  codesign --force --deep --sign - "$APP"
fi

echo "==> Staging DMG (app + /Applications symlink for drag-install)"
STAGE=$(mktemp -d)
trap 'rm -rf "$STAGE"' EXIT   # clean up even if hdiutil/cp fails under set -e
cp -R "$APP" "$STAGE/"
ln -s /Applications "$STAGE/Applications"

mkdir -p "$OUT_DIR"
rm -f "$DMG"
hdiutil create -volname "$APP_NAME" -srcfolder "$STAGE" -ov -format UDZO "$DMG" >/dev/null

echo "==> Done: $DMG"
echo -n "SHA256: "; shasum -a 256 "$DMG" | awk '{print $1}'
echo -n "Size:   "; du -h "$DMG" | awk '{print $1}'

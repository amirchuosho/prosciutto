#!/usr/bin/env bash
# Create a DMG, notarize it, and staple the ticket.
# Requires a stored notarytool keychain profile:
#   xcrun notarytool store-credentials prosciutto-notary \
#     --apple-id "you@example.com" --team-id "TEAMID" --password "app-specific-pw"
set -euo pipefail

cd "$(dirname "$0")/.."

APP="build/export/Prosciutto.app"
DMG="build/Prosciutto.dmg"
PROFILE="${NOTARY_PROFILE:-prosciutto-notary}"

[ -d "$APP" ] || { echo "Missing $APP — run scripts/build-release.sh first"; exit 1; }

echo "==> Creating DMG"
rm -f "$DMG"
hdiutil create -volname "Prosciutto" -srcfolder "$APP" -ov -format UDZO "$DMG"

echo "==> Submitting to notary service"
xcrun notarytool submit "$DMG" --keychain-profile "$PROFILE" --wait

echo "==> Stapling"
xcrun stapler staple "$DMG"

echo "==> Done: $DMG"
shasum -a 256 "$DMG"

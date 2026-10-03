#!/bin/bash
# Builds, codesigns with Developer ID, packages into a DMG installer,
# submits to Apple Notary Service, and staples the notarization ticket.
#
# Usage: Scripts/build_dmg.sh [sdk_mode: auto|macos27|default]
#
# No secrets live in this script. The signing private key is in the login Keychain, and the
# notarization credentials are in a Keychain profile created once with:
#   xcrun notarytool store-credentials "<profile>" --apple-id <id> --team-id <team>
# Your signing identity and profile name come from Scripts/release.env (untracked; copy
# Scripts/release.env.example) or from the environment, so you can switch accounts per release.
set -euo pipefail

cd "$(dirname "$0")/.."

SDK_MODE="${1:-auto}"
APP_NAME="VectorPDF"
VERSION="$(cat VERSION | tr -d '[:space:]')"
DMG_NAME="${APP_NAME}_Installer_${VERSION}.dmg"
STAGING_DIR="dmg_staging"
if [ -f Scripts/release.env ]; then
    # shellcheck disable=SC1091
    source Scripts/release.env
fi
SIGNING_IDENTITY="${SIGNING_IDENTITY:?Set SIGNING_IDENTITY in Scripts/release.env or the environment}"
NOTARY_PROFILE="${NOTARY_PROFILE:?Set NOTARY_PROFILE in Scripts/release.env or the environment}"

echo "=== 1. Building $APP_NAME release app bundle ==="
./Scripts/build_app_bundle.sh release "$SDK_MODE"

echo "=== 1b. Signing $APP_NAME with Developer ID and hardened runtime ==="
codesign --force --deep --options runtime --timestamp --entitlements Resources/VectorPDF.entitlements -s "$SIGNING_IDENTITY" "${APP_NAME}.app"

echo "=== 2. Preparing DMG staging ==="
rm -rf "$STAGING_DIR" "$DMG_NAME"
mkdir -p "$STAGING_DIR"
cp -R "${APP_NAME}.app" "$STAGING_DIR/"
ln -s /Applications "$STAGING_DIR/Applications"

echo "=== 3. Creating DMG ==="
hdiutil create -volname "${APP_NAME} ${VERSION}" -srcfolder "$STAGING_DIR" -ov -format UDZO "$DMG_NAME"
rm -rf "$STAGING_DIR"

echo "=== 4. Signing DMG with Developer ID ==="
codesign --force --timestamp -s "$SIGNING_IDENTITY" "$DMG_NAME"

echo "=== 5. Submitting to Apple Notary Service ==="
xcrun notarytool submit "$DMG_NAME" --keychain-profile "$NOTARY_PROFILE" --wait

echo "=== 6. Stapling Notarization Ticket ==="
xcrun stapler staple "$DMG_NAME"
xcrun stapler staple "${APP_NAME}.app"

echo "=== 7. Validating Gatekeeper Assessment ==="
spctl -a -t open --context context:primary-signature -v "$DMG_NAME"
spctl --assess --verbose --type execute "${APP_NAME}.app"

echo "--------------------------------------------------"
echo "SUCCESS: $DMG_NAME is signed, notarized, and ready for distribution."
echo "--------------------------------------------------"


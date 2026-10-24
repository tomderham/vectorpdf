#!/bin/bash
# Builds VectorPDF.app with Private Cloud Compute enabled, signed for your own Mac with your own
# Apple Developer account. Apple grants the PCC entitlement only for App Store, TestFlight, ad hoc,
# and development builds, so the released DMG (Developer ID) answers on-device.
#
# Usage: Scripts/build_pcc_dev.sh <profile.provisionprofile> [signing identity]
#
# You need the macOS 27 SDK (Xcode 27), the PCC entitlement on your account
# (https://developer.apple.com/private-cloud-compute/), and in Certificates, Identifiers & Profiles:
#   1. An explicit App ID (e.g. com.example.vectorpdf) with "Access to models on Private Cloud
#      Compute" enabled.
#   2. This Mac registered as a device.
#   3. A "macOS App Development" profile for that App ID, your Apple Development certificate, and
#      this Mac.
# The app is built under the profile's bundle identifier, and signed with the profile's
# certificate unless you name an identity.
set -euo pipefail

cd "$(dirname "$0")/.."

if [ $# -lt 1 ]; then
    echo "usage: $0 <profile.provisionprofile> [signing identity]" >&2
    exit 1
fi
PROFILE="$1"
SIGNING_IDENTITY="${2:-}"
APP_NAME="VectorPDF"
WORK_DIR="$(mktemp -d)"
trap 'rm -rf "$WORK_DIR"' EXIT

SDK_VER="$(xcrun --show-sdk-version --sdk macosx 2>/dev/null || echo 0)"
if [ "${SDK_VER%%.*}" -lt 27 ]; then
    echo "error: Private Cloud Compute needs the macOS 27 SDK (Xcode 27); found $SDK_VER" >&2
    exit 1
fi

# shellcheck source=Scripts/provisioning.sh
source Scripts/provisioning.sh
decode_provisioning_profile "$PROFILE" "$WORK_DIR"

if [ "$(profile_value Entitlements:com.apple.developer.private-cloud-compute)" != "true" ]; then
    echo "error: profile doesn't grant Private Cloud Compute. Enable it on the App ID, then edit and" >&2
    echo "       re-download the profile. Developer ID profiles never include it." >&2
    exit 1
fi
if ! profile_value ProvisionsAllDevices | grep -q true; then
    UDID="$(system_profiler SPHardwareDataType | awk -F': ' '/Provisioning UDID/ {print $2}')"
    if ! profile_value ProvisionedDevices | grep -q "$UDID"; then
        echo "error: profile doesn't include this Mac ($UDID). Register it and regenerate the profile." >&2
        exit 1
    fi
fi
TEAM_ID="$(profile_value Entitlements:com.apple.developer.team-identifier)"
APP_IDENTIFIER="$(profile_value Entitlements:com.apple.application-identifier)"
BUNDLE_ID="${APP_IDENTIFIER#"$TEAM_ID".}"
if [ "$BUNDLE_ID" = "$APP_IDENTIFIER" ] || [[ "$BUNDLE_ID" == *"*"* ]]; then
    echo "error: profile is for '$APP_IDENTIFIER'; PCC needs an explicit App ID" >&2
    exit 1
fi

# Pick the keychain identity whose certificate is in the profile.
if [ -z "$SIGNING_IDENTITY" ]; then
    IDENTITIES="$(security find-identity -v -p codesigning)"
    i=0
    while /usr/libexec/PlistBuddy -c "Print :DeveloperCertificates:$i" "$PROFILE_PLIST" > "$WORK_DIR/cert.der" 2>/dev/null; do
        SHA1="$(openssl x509 -inform der -in "$WORK_DIR/cert.der" -noout -fingerprint -sha1 | sed 's/.*=//; s/://g')"
        if grep -q "$SHA1" <<< "$IDENTITIES"; then
            SIGNING_IDENTITY="$SHA1"
            break
        fi
        i=$((i + 1))
    done
    if [ -z "$SIGNING_IDENTITY" ]; then
        echo "error: none of the profile's certificates has a private key in your keychain" >&2
        exit 1
    fi
fi

BUNDLE_ID="$BUNDLE_ID" ./Scripts/build_app_bundle.sh release macos27
apply_provisioning_profile "${APP_NAME}.app" "$PROFILE" "$WORK_DIR"

echo "Signing $APP_NAME as $BUNDLE_ID..."
codesign --force --deep --options runtime --entitlements "$ENTITLEMENTS" -s "$SIGNING_IDENTITY" "${APP_NAME}.app"
codesign -d --entitlements - "${APP_NAME}.app" 2>/dev/null | grep -q private-cloud-compute

echo "Done: $(pwd)/${APP_NAME}.app (runs only on the Macs in the profile)"
echo "In VectorPDF, choose Private Cloud Compute in Settings → AI Synthesis Engine."

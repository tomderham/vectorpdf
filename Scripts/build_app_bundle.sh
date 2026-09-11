#!/bin/bash
# Builds VectorPDF.app: compiles the executable with swift build and packages it into an
# application bundle with Info.plist, icon, and ad-hoc code signature.
#
# Usage: Scripts/build_app_bundle.sh [debug|release] [macos27|default|auto]
#   Defaults to "release" and "auto". When the active macOS SDK is 27+ (Xcode 27),
#   enables the Private Cloud Compute synthesis path (-DVECTORPDF_MACOS27_SDK).
set -euo pipefail

cd "$(dirname "$0")/.."

CONFIG="${1:-release}"
SDK_MODE="${2:-auto}"
APP_NAME="VectorPDF"
EXECUTABLE_NAME="VectorPDFApp"
APP_BUNDLE="$APP_NAME.app"
APP_VERSION="$(cat VERSION | tr -d '[:space:]')"

SDK_VER="$(xcrun --show-sdk-version --sdk macosx 2>/dev/null || echo "0")"
SDK_MAJOR="${SDK_VER%%.*}"

BUILD_ARGS=(-c "$CONFIG")
if [ "$SDK_MODE" = "macos27" ] || { [ "$SDK_MODE" = "auto" ] && [ "$SDK_MAJOR" -ge 27 ]; }; then
    BUILD_ARGS+=(-Xswiftc -DVECTORPDF_MACOS27_SDK)
    echo "Building $EXECUTABLE_NAME ($CONFIG, macOS $SDK_VER SDK with VECTORPDF_MACOS27_SDK)..."
else
    echo "Building $EXECUTABLE_NAME ($CONFIG, macOS $SDK_VER SDK)..."
fi
swift build "${BUILD_ARGS[@]}"

BUILT_BINARY=".build/$CONFIG/$EXECUTABLE_NAME"
if [ ! -f "$BUILT_BINARY" ]; then
    echo "error: expected build output at $BUILT_BINARY, not found" >&2
    exit 1
fi

echo "Assembling $APP_BUNDLE..."
rm -rf "$APP_BUNDLE"
mkdir -p "$APP_BUNDLE/Contents/MacOS" "$APP_BUNDLE/Contents/Resources"

cp "$BUILT_BINARY" "$APP_BUNDLE/Contents/MacOS/$EXECUTABLE_NAME"
cp Resources/AppIcon/AppIcon.icns "$APP_BUNDLE/Contents/Resources/AppIcon.icns"
cp Resources/AppIcon/DocumentIcon.icns "$APP_BUNDLE/Contents/Resources/DocumentIcon.icns"

cat > "$APP_BUNDLE/Contents/Info.plist" <<PLIST
<?xml version="1.0" encoding="UTF-8"?>
<!DOCTYPE plist PUBLIC "-//Apple//DTD PLIST 1.0//EN" "http://www.apple.com/DTDs/PropertyList-1.0.dtd">
<plist version="1.0">
<dict>
    <key>CFBundleDevelopmentRegion</key>
    <string>en</string>
    <key>CFBundleExecutable</key>
    <string>$EXECUTABLE_NAME</string>
    <key>CFBundleIdentifier</key>
    <string>com.vectorpdf.app</string>
    <key>CFBundleInfoDictionaryVersion</key>
    <string>6.0</string>
    <key>CFBundleName</key>
    <string>$APP_NAME</string>
    <key>CFBundleDisplayName</key>
    <string>$APP_NAME</string>
    <key>CFBundleIconFile</key>
    <string>AppIcon</string>
    <key>CFBundlePackageType</key>
    <string>APPL</string>
    <key>CFBundleShortVersionString</key>
    <string>$APP_VERSION</string>
    <key>CFBundleVersion</key>
    <string>$APP_VERSION</string>
    <key>NSHumanReadableCopyright</key>
    <string>© 2026 Thomas Derham</string>
    <key>LSMinimumSystemVersion</key>
    <string>14.0</string>
    <key>NSHighResolutionCapable</key>
    <true/>
    <key>CFBundleDocumentTypes</key>
    <array>
        <dict>
            <key>CFBundleTypeName</key>
            <string>PDF Document</string>
            <key>CFBundleTypeRole</key>
            <string>Viewer</string>
            <key>LSHandlerRank</key>
            <string>Alternate</string>
            <key>CFBundleTypeIconFile</key>
            <string>DocumentIcon</string>
            <key>LSItemContentTypes</key>
            <array>
                <string>com.adobe.pdf</string>
            </array>
        </dict>
    </array>
    <key>UTImportedTypeDeclarations</key>
    <array>
        <dict>
            <key>UTTypeIdentifier</key>
            <string>com.adobe.pdf</string>
            <key>UTTypeDescription</key>
            <string>PDF Document</string>
            <key>UTTypeConformsTo</key>
            <array>
                <string>public.data</string>
                <string>public.composite-content</string>
            </array>
            <key>UTTypeTagSpecification</key>
            <dict>
                <key>public.filename-extension</key>
                <array>
                    <string>pdf</string>
                </array>
                <key>public.mime-type</key>
                <array>
                    <string>application/pdf</string>
                </array>
            </dict>
        </dict>
    </array>
</dict>
</plist>
PLIST

echo "Signing (ad-hoc with entitlements)..."
codesign --force --deep --entitlements Resources/VectorPDF.entitlements -s - "$APP_BUNDLE"

echo "Done: $(pwd)/$APP_BUNDLE"

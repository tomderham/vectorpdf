#!/bin/bash
# Builds VectorPDF.app: compiles the executable with swift build and packages it into an
# application bundle with Info.plist, icon, and ad-hoc code signature.
#
# Usage: Scripts/build_app_bundle.sh [debug|release] [default|macos27]
#   Pass "macos27" as the second argument to compile against Xcode-beta.app with the
#   Private Cloud Compute synthesis path enabled (requires Xcode-beta.app installed).
set -euo pipefail

cd "$(dirname "$0")/.."

CONFIG="${1:-release}"
SDK_MODE="${2:-default}"
APP_NAME="VectorPDF"
EXECUTABLE_NAME="VectorPDFApp"
APP_BUNDLE="$APP_NAME.app"

BUILD_ARGS=(-c "$CONFIG")
if [ "$SDK_MODE" = "macos27" ]; then
    BETA_DEVELOPER_DIR="/Applications/Xcode-beta.app/Contents/Developer"
    if [ ! -d "$BETA_DEVELOPER_DIR" ]; then
        echo "error: macos27 mode requires Xcode beta at $BETA_DEVELOPER_DIR, not found" >&2
        exit 1
    fi
    export DEVELOPER_DIR="$BETA_DEVELOPER_DIR"
    BUILD_ARGS+=(-Xswiftc -DVECTORPDF_MACOS27_SDK)
    echo "Building $EXECUTABLE_NAME ($CONFIG, macOS 27 SDK via Xcode-beta)..."
else
    echo "Building $EXECUTABLE_NAME ($CONFIG)..."
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
    <string>0.1</string>
    <key>CFBundleVersion</key>
    <string>1</string>
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
            <key>LSItemContentTypes</key>
            <array>
                <string>com.adobe.pdf</string>
            </array>
        </dict>
    </array>
</dict>
</plist>
PLIST

echo "Signing (ad-hoc)..."
codesign --force --deep -s - "$APP_BUNDLE"

echo "Done: $(pwd)/$APP_BUNDLE"

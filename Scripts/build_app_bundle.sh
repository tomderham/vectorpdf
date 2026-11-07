#!/bin/bash
# Builds VectorPDF.app: compiles the executable with swift build and packages it into an
# application bundle with Info.plist, icon, and ad-hoc code signature.
#
# Usage: Scripts/build_app_bundle.sh [debug|release]
#   Defaults to "release". With the macOS 27 SDK (Xcode 27) the build includes Private Cloud
#   Compute and online models for the Agent; Package.swift decides, as for `swift run`.
#   Set BUNDLE_ID to build under another bundle identifier (Scripts/build_pcc_dev.sh does this).
set -euo pipefail

cd "$(dirname "$0")/.."

CONFIG="${1:-release}"
APP_NAME="VectorPDF"
EXECUTABLE_NAME="VectorPDF"
APP_BUNDLE="$APP_NAME.app"
APP_VERSION="$(cat VERSION | tr -d '[:space:]')"
BUNDLE_ID="${BUNDLE_ID:-com.thomasderham.vectorpdf}"

SDK_VER="$(xcrun --show-sdk-version --sdk macosx 2>/dev/null || echo "0")"

echo "Building $EXECUTABLE_NAME ($CONFIG, macOS $SDK_VER SDK)..."
swift build -c "$CONFIG"

BUILT_BINARY=".build/$CONFIG/$EXECUTABLE_NAME"
if [ ! -f "$BUILT_BINARY" ]; then
    echo "error: expected build output at $BUILT_BINARY, not found" >&2
    exit 1
fi

echo "Assembling $APP_BUNDLE..."
rm -rf "$APP_BUNDLE"
mkdir -p "$APP_BUNDLE/Contents/MacOS" "$APP_BUNDLE/Contents/Resources" "$APP_BUNDLE/Contents/Helpers"

cp "$BUILT_BINARY" "$APP_BUNDLE/Contents/MacOS/$EXECUTABLE_NAME"
# SyncTeX forward search for LaTeX editors (Skim's displayline arguments)
cp ".build/$CONFIG/displayline" "$APP_BUNDLE/Contents/Helpers/displayline"
cp Resources/AppIcon/AppIcon.icns "$APP_BUNDLE/Contents/Resources/AppIcon.icns"
cp Resources/AppIcon/DocumentIcon.icns "$APP_BUNDLE/Contents/Resources/DocumentIcon.icns"
cp "Resources/VectorPDF Tour.pdf" "$APP_BUNDLE/Contents/Resources/"

echo "Building the help book..."
HELP_BOOK_ID="$BUNDLE_ID.help"
python3 Scripts/build_help.py --guide docs/guide --resources "$APP_BUNDLE/Contents/Resources" \
    --version "$APP_VERSION" --bundle-id "$HELP_BOOK_ID" --icon Resources/AppIcon/AppIcon.iconset/icon_256x256.png

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
    <string>$BUNDLE_ID</string>
    <key>CFBundleInfoDictionaryVersion</key>
    <string>6.0</string>
    <key>CFBundleName</key>
    <string>$APP_NAME</string>
    <key>CFBundleDisplayName</key>
    <string>$APP_NAME</string>
    <key>CFBundleIconFile</key>
    <string>AppIcon.icns</string>
    <key>CFBundleIconName</key>
    <string>AppIcon</string>
    <key>CFBundleHelpBookFolder</key>
    <string>VectorPDF.help</string>
    <key>CFBundleHelpBookName</key>
    <string>$HELP_BOOK_ID</string>
    <key>CFBundlePackageType</key>
    <string>APPL</string>
    <key>CFBundleShortVersionString</key>
    <string>$APP_VERSION</string>
    <key>CFBundleVersion</key>
    <string>$APP_VERSION</string>
    <key>NSHumanReadableCopyright</key>
    <string>© 2026 Thomas Derham</string>
    <key>LSMinimumSystemVersion</key>
    <string>15.0</string>
    <key>NSHighResolutionCapable</key>
    <true/>
    <!-- SyncTeX forward search: Contents/Helpers/displayline sends vectorpdf://synctex?... -->
    <key>CFBundleURLTypes</key>
    <array>
        <dict>
            <key>CFBundleURLName</key>
            <string>$BUNDLE_ID.synctex</string>
            <key>CFBundleURLSchemes</key>
            <array>
                <string>vectorpdf</string>
            </array>
            <key>CFBundleTypeRole</key>
            <string>Viewer</string>
        </dict>
    </array>
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
            <string>DocumentIcon.icns</string>
            <key>LSItemContentTypes</key>
            <array>
                <string>com.adobe.pdf</string>
            </array>
        </dict>
        <!-- Formats MuPDF reads but can't save, opened for reading (OpenableDocumentTypes). The
             extensions are listed too, for when another app's declaration of a type wins. -->
        <dict>
            <key>CFBundleTypeName</key>
            <string>E-Book, Comic or XPS Document</string>
            <key>CFBundleTypeRole</key>
            <string>Viewer</string>
            <key>LSHandlerRank</key>
            <string>Alternate</string>
            <key>LSItemContentTypes</key>
            <array>
                <string>org.idpf.epub-container</string>
                <string>com.microsoft.xps</string>
                <string>com.microsoft.openxps</string>
                <string>com.thomasderham.vectorpdf.cbz</string>
                <string>com.thomasderham.vectorpdf.fb2</string>
            </array>
            <key>CFBundleTypeExtensions</key>
            <array>
                <string>epub</string>
                <string>xps</string>
                <string>oxps</string>
                <string>cbz</string>
                <string>fb2</string>
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
        <dict>
            <key>UTTypeIdentifier</key>
            <string>com.microsoft.xps</string>
            <key>UTTypeDescription</key>
            <string>XPS Document</string>
            <key>UTTypeConformsTo</key>
            <array>
                <string>public.data</string>
                <string>public.composite-content</string>
            </array>
            <key>UTTypeTagSpecification</key>
            <dict>
                <key>public.filename-extension</key>
                <array>
                    <string>xps</string>
                </array>
                <key>public.mime-type</key>
                <array>
                    <string>application/vnd.ms-xpsdocument</string>
                </array>
            </dict>
        </dict>
        <dict>
            <key>UTTypeIdentifier</key>
            <string>com.microsoft.openxps</string>
            <key>UTTypeDescription</key>
            <string>OpenXPS Document</string>
            <key>UTTypeConformsTo</key>
            <array>
                <string>public.data</string>
                <string>public.composite-content</string>
            </array>
            <key>UTTypeTagSpecification</key>
            <dict>
                <key>public.filename-extension</key>
                <array>
                    <string>oxps</string>
                </array>
                <key>public.mime-type</key>
                <array>
                    <string>application/oxps</string>
                </array>
            </dict>
        </dict>
        <dict>
            <key>UTTypeIdentifier</key>
            <string>com.thomasderham.vectorpdf.cbz</string>
            <key>UTTypeDescription</key>
            <string>Comic Book Archive</string>
            <key>UTTypeConformsTo</key>
            <array>
                <string>public.zip-archive</string>
            </array>
            <key>UTTypeTagSpecification</key>
            <dict>
                <key>public.filename-extension</key>
                <array>
                    <string>cbz</string>
                </array>
                <key>public.mime-type</key>
                <array>
                    <string>application/vnd.comicbook+zip</string>
                </array>
            </dict>
        </dict>
        <dict>
            <key>UTTypeIdentifier</key>
            <string>com.thomasderham.vectorpdf.fb2</string>
            <key>UTTypeDescription</key>
            <string>FictionBook Document</string>
            <key>UTTypeConformsTo</key>
            <array>
                <string>public.xml</string>
                <string>public.composite-content</string>
            </array>
            <key>UTTypeTagSpecification</key>
            <dict>
                <key>public.filename-extension</key>
                <array>
                    <string>fb2</string>
                </array>
                <key>public.mime-type</key>
                <array>
                    <string>application/x-fictionbook+xml</string>
                </array>
            </dict>
        </dict>
    </array>
    <key>NSUserActivityTypes</key>
    <array>
        <string>com.thomasderham.vectorpdf.document-reading</string>
    </array>
</dict>
</plist>
PLIST

echo "Signing (ad-hoc with entitlements)..."
codesign --force -s - "$APP_BUNDLE/Contents/Helpers/displayline"
codesign --force --deep --entitlements Resources/VectorPDF.entitlements -s - "$APP_BUNDLE"

echo "Done: $(pwd)/$APP_BUNDLE"

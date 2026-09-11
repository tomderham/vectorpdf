#!/bin/bash
# Generates AppIcon.icns and DocumentIcon.icns by rendering each required size
# and assembling the icon set directly with build_icns.swift.
set -euo pipefail

cd "$(dirname "$0")"

declare -a SPECS=(
    "16 icon_16x16.png"
    "32 icon_16x16@2x.png"
    "32 icon_32x32.png"
    "64 icon_32x32@2x.png"
    "128 icon_128x128.png"
    "256 icon_128x128@2x.png"
    "256 icon_256x256.png"
    "512 icon_256x256@2x.png"
    "512 icon_512x512.png"
    "1024 icon_512x512@2x.png"
)

SWIFT_CMD="swift -module-cache-path /tmp/swift-cache"

# 1. AppIcon.icns
APP_ICONSET="AppIcon.iconset"
rm -rf "$APP_ICONSET"
mkdir "$APP_ICONSET"
echo "Generating AppIcon PNGs..."
for spec in "${SPECS[@]}"; do
    px="${spec%% *}"
    name="${spec#* }"
    $SWIFT_CMD generate_icon.swift "$APP_ICONSET/$name" "$px"
done
$SWIFT_CMD build_icns.swift "$APP_ICONSET" AppIcon.icns

# 2. DocumentIcon.icns
DOC_ICONSET="DocumentIcon.iconset"
rm -rf "$DOC_ICONSET"
mkdir "$DOC_ICONSET"
echo "Generating DocumentIcon PNGs..."
for spec in "${SPECS[@]}"; do
    px="${spec%% *}"
    name="${spec#* }"
    $SWIFT_CMD generate_document_icon.swift "$DOC_ICONSET/$name" "$px"
done
$SWIFT_CMD build_icns.swift "$DOC_ICONSET" DocumentIcon.icns

#!/bin/bash
# Generates AppIcon.icns by rendering each required size via generate_icon.swift
# and assembling the icon set directly with build_icns.swift.
set -euo pipefail

cd "$(dirname "$0")"

ICONSET="AppIcon.iconset"
rm -rf "$ICONSET"
mkdir "$ICONSET"

# pixel size, output filename
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

for spec in "${SPECS[@]}"; do
    px="${spec%% *}"
    name="${spec#* }"
    swift generate_icon.swift "$ICONSET/$name" "$px"
done

swift build_icns.swift "$ICONSET" AppIcon.icns

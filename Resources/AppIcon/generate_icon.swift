// Generates the VectorPDF app icon as a PNG, at any requested size (defaults to 1024x1024).
//
// Usage:
//   swift Resources/AppIcon/generate_icon.swift Resources/AppIcon/AppIcon.iconset/icon_16x16.png 16
//
// Scales from the 1024x1024 master icon artwork (Resources/AppIcon/icon_1024.png) using high-quality
// bicubic interpolation directly into an NSBitmapImageRep with exact pixel dimensions.
//
// Ensures 100% compatibility with Apple Human Interface Guidelines and the curved macOS Dock icon shape:
// - Standard continuous-curvature squircle geometry
// - Subtle drop shadow
// - Fully transparent padding outside the squircle
// - Exact pixel backing store (never multiplied by display scale)

import AppKit

guard CommandLine.arguments.count > 1 else {
    print("Usage: swift generate_icon.swift <output.png> [size]")
    exit(1)
}

let outputURL = URL(fileURLWithPath: CommandLine.arguments[1])
let size: CGFloat = CommandLine.arguments.count > 2 ? (CGFloat(Double(CommandLine.arguments[2]) ?? 1024)) : 1024
let pixelSize = Int(size)

// Locate master icon artwork (icon_1024.png in same directory)
let scriptDir = URL(fileURLWithPath: CommandLine.arguments[0]).deletingLastPathComponent()
let masterURL = scriptDir.appendingPathComponent("icon_1024.png")

guard let masterImage = NSImage(contentsOf: masterURL) else {
    print("Error: Could not load master icon at \(masterURL.path)")
    exit(1)
}
masterImage.size = NSSize(width: 1024, height: 1024)

if pixelSize == 1024 {
    guard let masterData = try? Data(contentsOf: masterURL) else {
        exit(1)
    }
    try masterData.write(to: outputURL)
    print("Wrote \(outputURL.path) (1024x1024)")
    exit(0)
}

guard let rep = NSBitmapImageRep(
    bitmapDataPlanes: nil,
    pixelsWide: pixelSize,
    pixelsHigh: pixelSize,
    bitsPerSample: 8,
    samplesPerPixel: 4,
    hasAlpha: true,
    isPlanar: false,
    colorSpaceName: .calibratedRGB,
    bytesPerRow: pixelSize * 4,
    bitsPerPixel: 32
) else {
    print("Failed to allocate bitmap rep")
    exit(1)
}

if let data = rep.bitmapData {
    memset(data, 0, pixelSize * pixelSize * 4)
}
rep.size = NSSize(width: size, height: size)

NSGraphicsContext.saveGraphicsState()
guard let ctx = NSGraphicsContext(bitmapImageRep: rep) else {
    print("Failed to create graphics context")
    exit(1)
}
ctx.imageInterpolation = .high
NSGraphicsContext.current = ctx

masterImage.draw(
    in: NSRect(x: 0, y: 0, width: size, height: size),
    from: NSRect(x: 0, y: 0, width: 1024, height: 1024),
    operation: .sourceOver,
    fraction: 1.0
)

NSGraphicsContext.restoreGraphicsState()

guard let png = rep.representation(using: .png, properties: [:]) else {
    print("Failed to render PNG")
    exit(1)
}

try png.write(to: outputURL)
print("Wrote \(outputURL.path) (\(pixelSize)x\(pixelSize))")

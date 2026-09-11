// Generates the VectorPDF document icon as a PNG, at any requested size (defaults to 1024x1024).
//
// Concept: A clean document page with folded corner, subtle shadow, VectorPDF's signature
// blue-to-cyan gradient banner with motion streaks, and crisp document content lines.
// Tailored for high contrast and razor-sharp clarity in Finder (especially List view at 16x16 / 32x32).
// Explicitly contains NO "PDF" text.

import AppKit

guard CommandLine.arguments.count > 1 else {
    print("Usage: swift generate_document_icon.swift <output.png> [size]")
    exit(1)
}

let size: CGFloat = CommandLine.arguments.count > 2 ? (CGFloat(Double(CommandLine.arguments[2]) ?? 1024)) : 1024
let pixelSize = Int(size)
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
    print("Failed to create bitmap rep")
    exit(1)
}
if let data = rep.bitmapData {
    memset(data, 0, pixelSize * pixelSize * 4)
}
rep.size = NSSize(width: size, height: size)

NSGraphicsContext.saveGraphicsState()
guard let context = NSGraphicsContext(bitmapImageRep: rep) else {
    print("Failed to create graphics context")
    exit(1)
}
NSGraphicsContext.current = context

let isSmall = size <= 32
let isTiny = size <= 16

// Geometry calculation
let pageWidth: CGFloat
let pageHeight: CGFloat
let pageX: CGFloat
let pageY: CGFloat
let foldSize: CGFloat

if isTiny { // 16x16
    pageX = 2.0
    pageY = 1.0
    pageWidth = 12.0
    pageHeight = 14.0
    foldSize = 4.0
} else if isSmall { // 32x32
    pageX = 4.0
    pageY = 2.0
    pageWidth = 24.0
    pageHeight = 28.0
    foldSize = 7.0
} else {
    pageWidth = round(size * 0.72)
    pageHeight = round(size * 0.88)
    pageX = round((size - pageWidth) / 2)
    pageY = round(size * 0.05)
    foldSize = round(pageWidth * 0.28)
}

// 1. Page drop shadow (for sizes >= 32)
let pagePath = NSBezierPath()
pagePath.move(to: CGPoint(x: pageX, y: pageY))
pagePath.line(to: CGPoint(x: pageX + pageWidth, y: pageY))
pagePath.line(to: CGPoint(x: pageX + pageWidth, y: pageY + pageHeight - foldSize))
pagePath.line(to: CGPoint(x: pageX + pageWidth - foldSize, y: pageY + pageHeight))
pagePath.line(to: CGPoint(x: pageX, y: pageY + pageHeight))
pagePath.close()

if size >= 32 {
    NSGraphicsContext.saveGraphicsState()
    let shadow = NSShadow()
    shadow.shadowColor = NSColor.black.withAlphaComponent(0.26)
    shadow.shadowBlurRadius = max(1.5, size * 0.035)
    shadow.shadowOffset = NSSize(width: 0, height: -max(1.0, size * 0.02))
    shadow.set()
    NSColor.white.setFill()
    pagePath.fill()
    NSGraphicsContext.restoreGraphicsState()
}

// 2. White sheet fill
NSColor.white.setFill()
pagePath.fill()

// 3. Page border (ensures high contrast against white Finder list rows)
let borderWidth: CGFloat = isTiny ? 1.0 : (isSmall ? 1.0 : max(1.5, size * 0.012))
NSColor(calibratedRed: 0.16, green: 0.38, blue: 0.72, alpha: isTiny ? 0.90 : 0.65).setStroke()
pagePath.lineWidth = borderWidth
pagePath.stroke()

// 4. Folded corner triangle
let foldPath = NSBezierPath()
foldPath.move(to: CGPoint(x: pageX + pageWidth - foldSize, y: pageY + pageHeight))
foldPath.line(to: CGPoint(x: pageX + pageWidth - foldSize, y: pageY + pageHeight - foldSize))
foldPath.line(to: CGPoint(x: pageX + pageWidth, y: pageY + pageHeight - foldSize))
foldPath.close()

// Fold shadow
if size >= 32 {
    NSGraphicsContext.saveGraphicsState()
    let foldShadow = NSShadow()
    foldShadow.shadowColor = NSColor.black.withAlphaComponent(0.20)
    foldShadow.shadowBlurRadius = size * 0.02
    foldShadow.shadowOffset = NSSize(width: -size * 0.01, height: -size * 0.01)
    foldShadow.set()
    NSColor(calibratedWhite: 0.85, alpha: 1.0).setFill()
    foldPath.fill()
    NSGraphicsContext.restoreGraphicsState()
}

NSColor(calibratedWhite: 0.88, alpha: 1.0).setFill()
foldPath.fill()
NSColor(calibratedRed: 0.16, green: 0.38, blue: 0.72, alpha: isTiny ? 0.80 : 0.50).setStroke()
foldPath.lineWidth = borderWidth
foldPath.stroke()

// 5. Signature VectorPDF Header Banner (blue-to-cyan gradient with motion streak)
let bannerInset = isTiny ? 1.5 : (isSmall ? 2.5 : pageWidth * 0.12)
let bannerX = pageX + bannerInset
let bannerW = isTiny ? (pageWidth - bannerInset * 2) : (pageWidth - bannerInset * 2)
let bannerH = isTiny ? 3.0 : (isSmall ? 6.0 : pageHeight * 0.24)
let bannerY = isTiny ? (pageY + pageHeight - foldSize - 1.0) : (pageY + pageHeight - foldSize - (isSmall ? 2.0 : pageHeight * 0.06) - bannerH)

let bannerRect = CGRect(x: bannerX, y: bannerY, width: bannerW, height: bannerH)
let bannerCorner = isTiny ? 0.5 : (isSmall ? 1.5 : bannerH * 0.20)
let bannerPath = NSBezierPath(roundedRect: bannerRect, xRadius: bannerCorner, yRadius: bannerCorner)

let vpGradient = NSGradient(colors: [
    NSColor(calibratedRed: 0.12, green: 0.45, blue: 0.96, alpha: 1.0),
    NSColor(calibratedRed: 0.04, green: 0.65, blue: 0.88, alpha: 1.0)
])!
vpGradient.draw(in: bannerPath, angle: -45)

// Motion swoosh streak inside banner
if !isTiny {
    NSGraphicsContext.saveGraphicsState()
    bannerPath.addClip()
    NSColor.white.withAlphaComponent(0.35).setFill()
    let swooshPath = NSBezierPath()
    let swH = bannerH * 0.30
    swooshPath.move(to: CGPoint(x: bannerX, y: bannerY + bannerH * 0.2))
    swooshPath.line(to: CGPoint(x: bannerX + bannerW * 0.75, y: bannerY + bannerH * 0.6))
    swooshPath.line(to: CGPoint(x: bannerX + bannerW * 0.75, y: bannerY + bannerH * 0.6 + swH))
    swooshPath.line(to: CGPoint(x: bannerX, y: bannerY + bannerH * 0.2 + swH))
    swooshPath.close()
    swooshPath.fill()
    NSGraphicsContext.restoreGraphicsState()
}

// 6. Crisp document content lines (VectorPDF blue)
let lineStartX = bannerX
let lineAvailW = bannerW
let lineBlue = NSColor(calibratedRed: 0.14, green: 0.42, blue: 0.92, alpha: isTiny ? 0.95 : 0.80)
lineBlue.setFill()

if isTiny {
    // 3 lines at exact pixel positions: y = 2, 4, 6
    let lineYs: [CGFloat] = [2.0, 4.5, 7.0]
    let lineLens: [CGFloat] = [7.0, 8.0, 6.0]
    for (i, ly) in lineYs.enumerated() {
        let r = CGRect(x: bannerX, y: ly, width: lineLens[i], height: 1.0)
        NSBezierPath(rect: r).fill()
    }
} else if isSmall {
    // 4 lines
    let lineYs: [CGFloat] = [4.0, 8.0, 12.0, 16.0]
    let lineFractions: [CGFloat] = [0.85, 0.70, 0.90, 0.55]
    for (i, ly) in lineYs.enumerated() {
        let r = CGRect(x: bannerX, y: ly, width: lineAvailW * lineFractions[i], height: 1.5)
        NSBezierPath(roundedRect: r, xRadius: 0.75, yRadius: 0.75).fill()
    }
} else {
    let numLines = 5
    let lineHeight = max(2.0, size * 0.022)
    let topOfLines = bannerY - size * 0.04
    let bottomMargin = pageY + size * 0.05
    let spacing = (topOfLines - bottomMargin) / CGFloat(numLines)
    let lineWidthFractions: [CGFloat] = [0.90, 0.75, 0.85, 0.60, 0.45]
    for i in 0..<numLines {
        let ly = topOfLines - CGFloat(i) * spacing
        let lw = lineAvailW * lineWidthFractions[i]
        let r = CGRect(x: lineStartX, y: ly, width: lw, height: lineHeight)
        NSBezierPath(roundedRect: r, xRadius: lineHeight / 2, yRadius: lineHeight / 2).fill()
    }
}

NSGraphicsContext.restoreGraphicsState()

guard let png = rep.representation(using: .png, properties: [:]) else {
    print("Failed to render PNG")
    exit(1)
}

let outputURL = URL(fileURLWithPath: CommandLine.arguments[1])
try png.write(to: outputURL)
print("Wrote \(outputURL.path)")


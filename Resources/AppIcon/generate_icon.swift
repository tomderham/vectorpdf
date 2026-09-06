// Generates the VectorPDF app icon as a PNG, at any requested size (defaults to 1024x1024).
//
// Usage:
//   swift Resources/AppIcon/generate_icon.swift Resources/AppIcon/icon_1024.png
//   swift Resources/AppIcon/generate_icon.swift Resources/AppIcon/icon_16.png 16
//
// Renders natively at the target resolution for maximum clarity across all macOS display scales.
//
// Concept: a document page (folded corner, document lines) with motion lines on a blue-to-teal gradient.
//
// See build_iconset.sh in this directory to assemble these PNGs into AppIcon.icns.

import AppKit

guard CommandLine.arguments.count > 1 else {
    print("Usage: swift generate_icon.swift <output.png> [size]")
    exit(1)
}

let size: CGFloat = CommandLine.arguments.count > 2 ? (CGFloat(Double(CommandLine.arguments[2]) ?? 1024)) : 1024
let image = NSImage(size: NSSize(width: size, height: size))
image.lockFocus()

// MARK: - Background: full-bleed square, blue-to-teal gradient. Deliberately NOT pre-rounding
// the corners here — macOS applies its own standard icon mask on top of whatever's provided, and
// baking in a second, possibly-mismatched rounding invites visible edge artifacts. Full square,
// let the system mask it.
let bgRect = CGRect(x: 0, y: 0, width: size, height: size)
let bgGradient = NSGradient(colors: [
    NSColor(calibratedRed: 0.14, green: 0.42, blue: 0.92, alpha: 1.0),
    NSColor(calibratedRed: 0.08, green: 0.74, blue: 0.68, alpha: 1.0)
])!
bgGradient.draw(in: bgRect, angle: -60)

// MARK: - Motion swoosh lines, suggesting gliding movement, trailing behind the page.
NSColor.white.withAlphaComponent(0.20).setFill()
for i in 0..<3 {
    let bandHeight = size * 0.052
    let yCenter = size * (0.34 + CGFloat(i) * 0.16)
    let xStart = size * 0.07
    let xEnd = size * (0.34 - CGFloat(i) * 0.045)
    let path = NSBezierPath()
    path.move(to: CGPoint(x: xStart, y: yCenter + bandHeight / 2))
    path.line(to: CGPoint(x: xEnd, y: yCenter + bandHeight * 0.9))
    path.line(to: CGPoint(x: xEnd, y: yCenter + bandHeight * 0.9 - bandHeight))
    path.line(to: CGPoint(x: xStart, y: yCenter - bandHeight / 2))
    path.close()
    path.fill()
}

// MARK: - Page (white, folded top-right corner), holding a shadow so it lifts off the background.
let pageWidth = size * 0.44
let pageHeight = size * 0.58
let pageX = size * 0.40
let pageY = size * 0.21
let foldSize = pageWidth * 0.30

let pagePath = NSBezierPath()
pagePath.move(to: CGPoint(x: pageX, y: pageY))
pagePath.line(to: CGPoint(x: pageX + pageWidth, y: pageY))
pagePath.line(to: CGPoint(x: pageX + pageWidth, y: pageY + pageHeight - foldSize))
pagePath.line(to: CGPoint(x: pageX + pageWidth - foldSize, y: pageY + pageHeight))
pagePath.line(to: CGPoint(x: pageX, y: pageY + pageHeight))
pagePath.close()

NSGraphicsContext.saveGraphicsState()
let shadow = NSShadow()
shadow.shadowColor = NSColor.black.withAlphaComponent(0.28)
shadow.shadowBlurRadius = size * 0.025
shadow.shadowOffset = NSSize(width: 0, height: -size * 0.012)
shadow.set()
NSColor.white.setFill()
pagePath.fill()
NSGraphicsContext.restoreGraphicsState()

// Folded corner triangle, slightly darker than the page itself.
let foldPath = NSBezierPath()
foldPath.move(to: CGPoint(x: pageX + pageWidth - foldSize, y: pageY + pageHeight))
foldPath.line(to: CGPoint(x: pageX + pageWidth - foldSize, y: pageY + pageHeight - foldSize))
foldPath.line(to: CGPoint(x: pageX + pageWidth, y: pageY + pageHeight - foldSize))
foldPath.close()
NSColor(calibratedWhite: 0.82, alpha: 1.0).setFill()
foldPath.fill()

// MARK: - A few text lines on the page, in the same blue as the background gradient's start.
// Sized to fit within the space actually available below the folded corner and above the page's
// bottom edge (checked explicitly, rather than picking a spacing/count by eye and hoping).
NSColor(calibratedRed: 0.14, green: 0.42, blue: 0.92, alpha: 0.85).setFill()
let lineInset = pageWidth * 0.16
let lineHeight = size * 0.026
let lineWidthFractions: [CGFloat] = [0.68, 0.68, 0.46, 0.68, 0.68]
let topOfLines = pageY + pageHeight - foldSize - size * 0.10
let bottomMargin = size * 0.06
let availableHeight = topOfLines - (pageY + bottomMargin)
let lineSpacing = availableHeight / CGFloat(lineWidthFractions.count)
var lineY = topOfLines
for fraction in lineWidthFractions {
    let rect = CGRect(x: pageX + lineInset, y: lineY, width: pageWidth * fraction, height: lineHeight)
    NSBezierPath(roundedRect: rect, xRadius: lineHeight / 2, yRadius: lineHeight / 2).fill()
    lineY -= lineSpacing
}

image.unlockFocus()

guard let tiff = image.tiffRepresentation,
      let rep = NSBitmapImageRep(data: tiff),
      let png = rep.representation(using: .png, properties: [:]) else {
    print("Failed to render PNG")
    exit(1)
}

let outputURL = URL(fileURLWithPath: CommandLine.arguments[1])
try png.write(to: outputURL)
print("Wrote \(outputURL.path)")

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
    foldShadow.shadowColor = NSColor.black.withAlphaComponent(0.22)
    foldShadow.shadowBlurRadius = size * 0.025
    foldShadow.shadowOffset = NSSize(width: -size * 0.012, height: -size * 0.012)
    foldShadow.set()
    NSColor(calibratedWhite: 0.82, alpha: 1.0).setFill()
    foldPath.fill()
    NSGraphicsContext.restoreGraphicsState()
}

// Fold fill with subtle gradient
let foldGradient = NSGradient(colors: [
    NSColor(calibratedWhite: 0.94, alpha: 1.0),
    NSColor(calibratedWhite: 0.80, alpha: 1.0)
])!
foldGradient.draw(in: foldPath, angle: -45)

NSColor(calibratedRed: 0.08, green: 0.25, blue: 0.55, alpha: isTiny ? 0.85 : 0.45).setStroke()
foldPath.lineWidth = borderWidth
foldPath.stroke()

// Document content area
let contentInsetX = isTiny ? 1.5 : (isSmall ? 3.0 : pageWidth * 0.12)
let contentX = pageX + contentInsetX
let contentW = pageWidth - contentInsetX * 2
let contentTop = pageY + pageHeight - foldSize - (isTiny ? 1.0 : (isSmall ? 2.0 : pageHeight * 0.06))
let contentBottom = pageY + (isTiny ? 1.5 : (isSmall ? 3.0 : pageHeight * 0.08))
let contentH = contentTop - contentBottom

if isTiny {
    // 16x16: Bold, ultra-crisp "V" vector glyph for maximum clarity in Finder list view
    let vPath = NSBezierPath()
    vPath.move(to: CGPoint(x: pageX + 3.0, y: pageY + pageHeight - 3.5))
    vPath.line(to: CGPoint(x: pageX + pageWidth / 2, y: pageY + 2.5))
    vPath.line(to: CGPoint(x: pageX + pageWidth - 3.0, y: pageY + pageHeight - 5.0))
    
    NSColor(calibratedRed: 0.05, green: 0.22, blue: 0.58, alpha: 1.0).setStroke()
    vPath.lineWidth = 1.75
    vPath.lineCapStyle = .round
    vPath.lineJoinStyle = .round
    vPath.stroke()
    
    // Cyan control node at apex
    NSColor(calibratedRed: 0.0, green: 0.82, blue: 1.0, alpha: 1.0).setFill()
    NSRect(x: pageX + pageWidth / 2 - 1.0, y: pageY + 2.0, width: 2.0, height: 2.0).fill()
} else if isSmall {
    // 32x32: Clean vector "V" with bezier curve and cyan control nodes
    let vPath = NSBezierPath()
    let startPt = CGPoint(x: pageX + 6.0, y: pageY + pageHeight - 7.0)
    let apexPt = CGPoint(x: pageX + pageWidth / 2, y: pageY + 5.0)
    let endPt = CGPoint(x: pageX + pageWidth - 6.0, y: pageY + pageHeight - 10.0)
    
    vPath.move(to: startPt)
    vPath.curve(to: apexPt,
                controlPoint1: CGPoint(x: startPt.x + 1.0, y: (startPt.y + apexPt.y) / 2),
                controlPoint2: CGPoint(x: apexPt.x - 2.0, y: apexPt.y))
    vPath.curve(to: endPt,
                controlPoint1: CGPoint(x: apexPt.x + 3.0, y: apexPt.y + 1.0),
                controlPoint2: CGPoint(x: endPt.x - 2.0, y: (apexPt.y + endPt.y) / 2))
    
    // Deep royal navy stroke matching dock icon
    NSColor(calibratedRed: 0.06, green: 0.20, blue: 0.48, alpha: 1.0).setStroke()
    vPath.lineWidth = 2.5
    vPath.lineCapStyle = .round
    vPath.stroke()
    
    // Cyan tangent handle at bottom apex
    let handlePath = NSBezierPath()
    handlePath.move(to: CGPoint(x: apexPt.x - 4.0, y: apexPt.y))
    handlePath.line(to: CGPoint(x: apexPt.x + 4.0, y: apexPt.y))
    NSColor(calibratedRed: 0.0, green: 0.80, blue: 0.96, alpha: 0.9).setStroke()
    handlePath.lineWidth = 1.0
    handlePath.stroke()
    
    // Apex node
    NSColor(calibratedRed: 0.0, green: 0.85, blue: 1.0, alpha: 1.0).setFill()
    let nodeRect = NSRect(x: apexPt.x - 1.5, y: apexPt.y - 1.5, width: 3.0, height: 3.0)
    NSBezierPath(ovalIn: nodeRect).fill()
} else {
    // 64x64 to 1024x1024: Rich vector artwork directly echoing the dock icon
    let vAreaTop = contentTop - size * 0.04
    let vAreaBottom = contentBottom + size * 0.08
    let vAreaH = vAreaTop - vAreaBottom
    
    // Geometry closely matching icon_1024.png
    let startPt = CGPoint(x: contentX + contentW * 0.18, y: vAreaTop - vAreaH * 0.05)
    let midLeftPt = CGPoint(x: contentX + contentW * 0.28, y: vAreaBottom + vAreaH * 0.50)
    let apexPt = CGPoint(x: contentX + contentW * 0.43, y: vAreaBottom + vAreaH * 0.08)
    let midRightPt = CGPoint(x: contentX + contentW * 0.57, y: vAreaBottom + vAreaH * 0.50)
    let endPt = CGPoint(x: contentX + contentW * 0.82, y: vAreaTop - vAreaH * 0.03)
    
    // Vector Tangent Handles (cyan/electric blue matching dock icon)
    let handleCyan = NSColor(calibratedRed: 0.0, green: 0.88, blue: 0.98, alpha: 0.95)
    let handleLineWidth = max(1.2, size * 0.004)
    
    // 1. Tangent handle at top-left start
    let startHandleLeft = CGPoint(x: startPt.x - contentW * 0.08, y: startPt.y + vAreaH * 0.14)
    let startHandleRight = CGPoint(x: startPt.x + contentW * 0.06, y: startPt.y - vAreaH * 0.10)
    let startHPath = NSBezierPath()
    startHPath.move(to: startHandleLeft)
    startHPath.line(to: startHandleRight)
    handleCyan.setStroke()
    startHPath.lineWidth = handleLineWidth
    startHPath.stroke()
    
    // 2. Horizontal tangent handle at bottom apex
    let apexHandleLeft = CGPoint(x: apexPt.x - contentW * 0.18, y: apexPt.y)
    let apexHandleRight = CGPoint(x: apexPt.x + contentW * 0.18, y: apexPt.y)
    let apexHPath = NSBezierPath()
    apexHPath.move(to: apexHandleLeft)
    apexHPath.line(to: apexHandleRight)
    handleCyan.setStroke()
    apexHPath.lineWidth = handleLineWidth
    apexHPath.stroke()
    
    // 3. Tangent handle at top-right
    let endHandleLeft = CGPoint(x: endPt.x - contentW * 0.18, y: endPt.y)
    let endHandleRight = CGPoint(x: endPt.x + contentW * 0.05, y: endPt.y)
    let endHPath = NSBezierPath()
    endHPath.move(to: endHandleLeft)
    endHPath.line(to: endHandleRight)
    handleCyan.setStroke()
    endHPath.lineWidth = handleLineWidth
    endHPath.stroke()
    
    // Cyan control point dots at handle ends
    let handleDotRadius = max(2.5, size * 0.009)
    for pt in [startHandleLeft, apexHandleLeft, apexHandleRight, endHandleLeft] {
        let dotRect = NSRect(x: pt.x - handleDotRadius, y: pt.y - handleDotRadius, width: handleDotRadius * 2, height: handleDotRadius * 2)
        handleCyan.setFill()
        NSBezierPath(ovalIn: dotRect).fill()
        if size >= 128 {
            NSColor.white.withAlphaComponent(0.85).setFill()
            let innerDot = NSRect(x: pt.x - handleDotRadius * 0.45, y: pt.y - handleDotRadius * 0.45, width: handleDotRadius * 0.9, height: handleDotRadius * 0.9)
            NSBezierPath(ovalIn: innerDot).fill()
        }
    }
    
    // The main "V" bezier curves
    // Left stroke: slight graceful bow from startPt to apexPt
    let vLeftPath = NSBezierPath()
    vLeftPath.move(to: startPt)
    vLeftPath.curve(to: apexPt,
                    controlPoint1: CGPoint(x: startPt.x + (apexPt.x - startPt.x) * 0.4, y: vAreaBottom + vAreaH * 0.55),
                    controlPoint2: CGPoint(x: apexPt.x - (apexPt.x - startPt.x) * 0.1, y: apexPt.y + vAreaH * 0.15))
    
    // Right stroke: sweeping S-curve up to endPt
    let vRightPath = NSBezierPath()
    vRightPath.move(to: apexPt)
    vRightPath.curve(to: endPt,
                     controlPoint1: CGPoint(x: apexPt.x + contentW * 0.12, y: apexPt.y + vAreaH * 0.05),
                     controlPoint2: CGPoint(x: endPt.x - contentW * 0.16, y: endPt.y))
    
    let darkNavy = NSColor(calibratedRed: 0.10, green: 0.15, blue: 0.22, alpha: 1.0)
    
    // Curve shadow for depth
    if size >= 64 {
        NSGraphicsContext.saveGraphicsState()
        let curveShadow = NSShadow()
        curveShadow.shadowColor = NSColor.black.withAlphaComponent(0.20)
        curveShadow.shadowBlurRadius = max(1.5, size * 0.015)
        curveShadow.shadowOffset = NSSize(width: 0, height: -max(1.0, size * 0.008))
        curveShadow.set()
        
        darkNavy.setStroke()
        vLeftPath.lineWidth = max(3.0, size * 0.016)
        vLeftPath.lineCapStyle = .round
        vLeftPath.stroke()
        vRightPath.lineWidth = max(3.0, size * 0.016)
        vRightPath.lineCapStyle = .round
        vRightPath.stroke()
        NSGraphicsContext.restoreGraphicsState()
    }
    
    // Left and right stroke
    darkNavy.setStroke()
    vLeftPath.lineWidth = max(2.5, size * 0.015)
    vLeftPath.lineCapStyle = .round
    vLeftPath.stroke()
    vRightPath.lineWidth = max(2.5, size * 0.015)
    vRightPath.lineCapStyle = .round
    vRightPath.stroke()
    
    // Anchor Rings at curve nodes (matching the metallic/cyan rings in dock icon)
    let ringRadius = max(4.0, size * 0.020)
    for pt in [startPt, midLeftPt, apexPt, midRightPt] {
        let ringRect = NSRect(x: pt.x - ringRadius, y: pt.y - ringRadius, width: ringRadius * 2, height: ringRadius * 2)
        // Metallic / navy ring border
        NSGraphicsContext.saveGraphicsState()
        if size >= 128 {
            let halo = NSShadow()
            halo.shadowColor = handleCyan.withAlphaComponent(0.35)
            halo.shadowBlurRadius = ringRadius * 0.8
            halo.shadowOffset = .zero
            halo.set()
        }
        NSColor.white.setFill()
        NSBezierPath(ovalIn: ringRect).fill()
        
        NSColor(calibratedRed: 0.35, green: 0.45, blue: 0.55, alpha: 1.0).setStroke()
        let ringPath = NSBezierPath(ovalIn: ringRect)
        ringPath.lineWidth = max(1.5, size * 0.007)
        ringPath.stroke()
        
        // Inner cyan node center
        let centerRadius = ringRadius * 0.45
        let centerRect = NSRect(x: pt.x - centerRadius, y: pt.y - centerRadius, width: centerRadius * 2, height: centerRadius * 2)
        handleCyan.setFill()
        NSBezierPath(ovalIn: centerRect).fill()
        NSGraphicsContext.restoreGraphicsState()
    }
    
    // Stylized fountain pen drawing the right stroke (at sizes >= 64)
    if size >= 64 {
        NSGraphicsContext.saveGraphicsState()
        let penAngle: CGFloat = -42.0 * .pi / 180.0
        let penNibPt = CGPoint(x: apexPt.x + contentW * 0.15, y: apexPt.y + vAreaH * 0.08)
        
        let penL = max(28.0, size * 0.36)
        let penW = max(5.0, size * 0.052)
        
        let ctx = NSGraphicsContext.current!.cgContext
        ctx.translateBy(x: penNibPt.x, y: penNibPt.y)
        ctx.rotate(by: penAngle)
        
        // Pen shadow
        let pShadow = NSShadow()
        pShadow.shadowColor = NSColor.black.withAlphaComponent(0.32)
        pShadow.shadowBlurRadius = max(2.0, size * 0.02)
        pShadow.shadowOffset = NSSize(width: -max(1.0, size * 0.01), height: -max(1.5, size * 0.012))
        pShadow.set()
        
        // Metallic fountain pen nib
        let nibPath = NSBezierPath()
        nibPath.move(to: .zero)
        nibPath.line(to: CGPoint(x: -penW * 0.5, y: penL * 0.22))
        nibPath.line(to: CGPoint(x: penW * 0.5, y: penL * 0.22))
        nibPath.close()
        
        let nibGrad = NSGradient(colors: [
            NSColor(calibratedWhite: 0.88, alpha: 1.0),
            NSColor(calibratedWhite: 0.55, alpha: 1.0),
            NSColor(calibratedWhite: 0.75, alpha: 1.0)
        ])!
        nibGrad.draw(in: nibPath, angle: 0)
        
        // Nib center slit
        let slit = NSBezierPath()
        slit.move(to: .zero)
        slit.line(to: CGPoint(x: 0, y: penL * 0.14))
        NSColor(calibratedWhite: 0.2, alpha: 1.0).setStroke()
        slit.lineWidth = max(0.5, size * 0.002)
        slit.stroke()
        
        // Pen barrel grip (dark graphite)
        let gripPath = NSBezierPath(roundedRect: NSRect(x: -penW * 0.55, y: penL * 0.22, width: penW * 1.1, height: penL * 0.25), xRadius: penW * 0.15, yRadius: penW * 0.15)
        NSColor(calibratedWhite: 0.22, alpha: 1.0).setFill()
        gripPath.fill()
        
        // Pen metallic body
        let bodyPath = NSBezierPath(roundedRect: NSRect(x: -penW * 0.5, y: penL * 0.47, width: penW, height: penL * 0.53), xRadius: penW * 0.2, yRadius: penW * 0.2)
        let bodyGrad = NSGradient(colors: [
            NSColor(calibratedWhite: 0.80, alpha: 1.0),
            NSColor(calibratedWhite: 0.45, alpha: 1.0),
            NSColor(calibratedWhite: 0.70, alpha: 1.0)
        ])!
        bodyGrad.draw(in: bodyPath, angle: 0)
        
        NSGraphicsContext.restoreGraphicsState()
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


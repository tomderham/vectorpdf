import AppKit
import SwiftUI

public extension NSImage {
    /// Vector template image depicting an anchor (nautical anchor ⚓)
    static let anchorIcon: NSImage = {
        let size: CGFloat = 16
        let img = NSImage(size: NSSize(width: size, height: size), flipped: false) { rect in
            let s = size / 16.0
            guard let ctx = NSGraphicsContext.current?.cgContext else { return false }
            ctx.saveGState()

            NSColor.black.setStroke()
            NSColor.black.setFill()

            // Ring at top: center (8*s, 13.2*s), radius 1.7*s
            let ringCenter = CGPoint(x: 8.0 * s, y: 13.2 * s)
            let ringRadius = 1.7 * s
            let ringPath = NSBezierPath()
            ringPath.lineWidth = 1.3 * s
            ringPath.appendArc(withCenter: ringCenter, radius: ringRadius, startAngle: 0, endAngle: 360)
            ringPath.stroke()

            let path = NSBezierPath()
            path.lineWidth = 1.3 * s
            path.lineCapStyle = .round
            path.lineJoinStyle = .round

            // Shank (vertical shaft)
            path.move(to: CGPoint(x: 8.0 * s, y: 11.5 * s))
            path.line(to: CGPoint(x: 8.0 * s, y: 2.5 * s))

            // Stock (crossbar)
            path.move(to: CGPoint(x: 4.5 * s, y: 10.2 * s))
            path.line(to: CGPoint(x: 11.5 * s, y: 10.2 * s))

            // Flukes (curved lower arms)
            path.move(to: CGPoint(x: 2.8 * s, y: 6.2 * s))
            path.curve(to: CGPoint(x: 13.2 * s, y: 6.2 * s),
                       controlPoint1: CGPoint(x: 2.8 * s, y: 1.6 * s),
                       controlPoint2: CGPoint(x: 13.2 * s, y: 1.6 * s))
            path.stroke()

            // Arrow tips / flukes
            let flukeLeft = NSBezierPath()
            flukeLeft.move(to: CGPoint(x: 1.8 * s, y: 6.2 * s))
            flukeLeft.line(to: CGPoint(x: 2.8 * s, y: 7.6 * s))
            flukeLeft.line(to: CGPoint(x: 3.8 * s, y: 6.2 * s))
            flukeLeft.close()
            flukeLeft.fill()

            let flukeRight = NSBezierPath()
            flukeRight.move(to: CGPoint(x: 12.2 * s, y: 6.2 * s))
            flukeRight.line(to: CGPoint(x: 13.2 * s, y: 7.6 * s))
            flukeRight.line(to: CGPoint(x: 14.2 * s, y: 6.2 * s))
            flukeRight.close()
            flukeRight.fill()

            ctx.restoreGState()
            return true
        }
        img.isTemplate = true
        img.setName(NSImage.Name("anchor"))
        return img
    }()
}

public extension Image {
    /// SwiftUI Image for the anchor icon
    static var anchorIcon: Image {
        Image(nsImage: NSImage.anchorIcon)
    }
}


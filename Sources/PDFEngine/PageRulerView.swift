//
// VectorPDF
// Copyright (c) 2026 Thomas Derham
//
// This program is free software: you can redistribute it and/or modify it
// under the terms of the GNU Affero General Public License as published by
// the Free Software Foundation, either version 3 of the License, or (at your
// option) any later version.
//
// This application links to and incorporates the MuPDF framework, which is
// Copyright (c) 2006-2026 Artifex Software, Inc.
//
// VECTORPDF IS PROVIDED "AS IS" WITHOUT ANY WARRANTY, AND ALL
// WARRANTIES, WHETHER EXPRESSED OR IMPLIED, INCLUDING WARRANTY OF
// MERCHANTABILITY OR FITNESS FOR A PARTICULAR PURPOSE, ARE DISCLAIMED.
//

import AppKit
import Combine

/// A ruler along the top or left of the page view (View > Show Rulers), measuring the page
/// under the pointer, or the current page, from its top-left corner in the status bar's units,
/// with a mark where the pointer is. Drag from it onto a page to add a guide.
final class PageRulerView: NSRulerView {
    private weak var canvas: PDFCanvasView?
    private var cancellables = Set<AnyCancellable>()

    init(scrollView: NSScrollView, orientation: NSRulerView.Orientation, canvas: PDFCanvasView) {
        self.canvas = canvas
        super.init(scrollView: scrollView, orientation: orientation)
        clientView = canvas
        ruleThickness = 20
        reservedThicknessForMarkers = 0
        reservedThicknessForAccessoryView = 0
        let redraw: () -> Void = { [weak self] in self?.needsDisplay = true }
        canvas.viewModel.canvasReadout.$pointer.removeDuplicates().receive(on: RunLoop.main).sink { _ in redraw() }.store(in: &cancellables)
        canvas.viewModel.objectWillChange.receive(on: RunLoop.main).sink { _ in redraw() }.store(in: &cancellables)
        PDFViewerAppCoordinator.shared.$readoutUnit.receive(on: RunLoop.main).sink { _ in redraw() }.store(in: &cancellables)
    }

    required init(coder: NSCoder) { fatalError("init(coder:) has not been implemented") }

    private var isHorizontal: Bool { orientation == .horizontalRuler }

    /// The page the ruler measures: the one under the pointer, or else the current one.
    private var referencePage: Int? {
        guard let viewModel = canvas?.viewModel, let doc = viewModel.document, doc.pageCount > 0 else { return nil }
        return min(viewModel.canvasReadout.pointer?.pageIndex ?? viewModel.currentPageIndex, doc.pageCount - 1)
    }

    /// How the ruler maps page lengths along it: where 0 (the page's top or left edge) is, in the
    /// ruler's coordinates, and how far one point of the page goes (negative when the view's
    /// rotation runs the page the other way).
    private func mapping(for page: Int) -> (geometry: PageGeometry, pageAxisIsX: Bool, zero: CGFloat, perPoint: CGFloat)? {
        guard let canvas, let geometry = canvas.pageGeometry(for: page) else { return nil }
        let pageAxisIsX = (geometry.rotation % 180 == 0) == isHorizontal
        let bounds = geometry.pageBounds
        func coordinate(_ offset: CGFloat) -> CGFloat {
            let pagePoint = pageAxisIsX
                ? CGPoint(x: bounds.minX + offset, y: bounds.midY)
                : CGPoint(x: bounds.midX, y: bounds.minY + offset)
            let point = convert(geometry.canvasPoint(forPagePoint: pagePoint), from: canvas)
            return isHorizontal ? point.x : point.y
        }
        let zero = coordinate(0)
        return (geometry, pageAxisIsX, zero, coordinate(1) - zero)
    }

    override func drawHashMarksAndLabels(in rect: NSRect) {
        guard let page = referencePage, let map = mapping(for: page), abs(map.perPoint) > 0.0001 else { return }
        let unit = PDFViewerAppCoordinator.shared.readoutUnit
        let perUnit = map.perPoint * CGFloat(unit.pointsPerUnit)
        let thickness = ruleThickness
        let base = isHorizontal ? bounds.maxY : bounds.maxX

        // The page's own length, lighter.
        let pageLength = map.pageAxisIsX ? map.geometry.pageBounds.width : map.geometry.pageBounds.height
        let start = map.zero, end = map.zero + pageLength * map.perPoint
        let band = isHorizontal
            ? NSRect(x: min(start, end), y: bounds.minY, width: abs(end - start), height: bounds.height)
            : NSRect(x: bounds.minX, y: min(start, end), width: bounds.width, height: abs(end - start))
        NSColor.controlBackgroundColor.setFill()
        band.intersection(rect).fill()

        let steps = RulerSteps.choose(unit: unit, pixelsPerUnit: Double(abs(perUnit)))
        let minor = steps.major / Double(steps.minorCount)
        let lo = Double(((isHorizontal ? rect.minX : rect.minY) - map.zero) / perUnit)
        let hi = Double(((isHorizontal ? rect.maxX : rect.maxY) - map.zero) / perUnit)
        let first = Int(floor(min(lo, hi) / minor)) - 1, last = Int(ceil(max(lo, hi) / minor)) + 1
        guard last - first < 5000 else { return }

        let ticks = NSBezierPath()
        ticks.lineWidth = 1
        let attributes: [NSAttributedString.Key: Any] = [
            .font: NSFont.monospacedDigitSystemFont(ofSize: 9, weight: .regular),
            .foregroundColor: NSColor.secondaryLabelColor,
        ]
        for k in first...last {
            let value = Double(k) * minor
            let at = (map.zero + CGFloat(value) * perUnit).rounded() + 0.5
            let isMajor = k % steps.minorCount == 0
            let isHalf = steps.minorCount % 2 == 0 && k % (steps.minorCount / 2) == 0
            let length = thickness * (isMajor ? 0.6 : (isHalf ? 0.4 : 0.22))
            if isHorizontal {
                ticks.move(to: NSPoint(x: at, y: base))
                ticks.line(to: NSPoint(x: at, y: base - length))
            } else {
                ticks.move(to: NSPoint(x: base, y: at))
                ticks.line(to: NSPoint(x: base - length, y: at))
            }
            guard isMajor else { continue }
            let label = NSAttributedString(string: Self.label(value), attributes: attributes)
            if isHorizontal {
                label.draw(at: NSPoint(x: at + 2, y: bounds.minY + 1))
            } else {
                NSGraphicsContext.saveGraphicsState()
                let transform = NSAffineTransform()
                transform.translateX(by: bounds.minX + 1, yBy: at - 2)
                transform.rotate(byDegrees: -90)
                transform.concat()
                label.draw(at: NSPoint(x: 0, y: 0))
                NSGraphicsContext.restoreGraphicsState()
            }
        }
        NSColor.tertiaryLabelColor.setStroke()
        ticks.stroke()

        // Where the pointer is.
        if let pointer = canvas?.viewModel.canvasReadout.pointer, pointer.pageIndex == page {
            let offset = map.pageAxisIsX ? pointer.point.x : pointer.point.y
            let at = (map.zero + offset * map.perPoint).rounded() + 0.5
            let mark = NSBezierPath()
            mark.lineWidth = 1
            if isHorizontal {
                mark.move(to: NSPoint(x: at, y: bounds.minY))
                mark.line(to: NSPoint(x: at, y: bounds.maxY))
            } else {
                mark.move(to: NSPoint(x: bounds.minX, y: at))
                mark.line(to: NSPoint(x: bounds.maxX, y: at))
            }
            NSColor.controlAccentColor.setStroke()
            mark.stroke()
        }
    }

    /// A major mark's number: whole, or with as few decimals as it needs.
    nonisolated static func label(_ value: Double) -> String {
        let rounded = (value * 1000).rounded() / 1000
        return rounded.formatted(.number.precision(.fractionLength(0...3)).grouping(.never).locale(Locale(identifier: "en_US_POSIX")))
    }

    // MARK: Dragging out a guide

    override func mouseDown(with event: NSEvent) {
        guard let canvas, let window, canvas.viewModel.document != nil else { return }
        var placed: (page: Int, guide: PageGuide)?
        var current: NSEvent? = event
        while let ev = current {
            let canvasPoint = canvas.convert(ev.locationInWindow, from: nil)
            if let (page, _, pagePoint) = canvas.pageInfo(at: canvasPoint), let geometry = canvas.pageGeometry(for: page) {
                // A line along the ruler on screen: across the page, in the page's orientation.
                let isVertical = (geometry.rotation % 180 == 0) != isHorizontal
                placed = (page, PageGuide(id: placed?.guide.id ?? UUID(), isVertical: isVertical, position: isVertical ? pagePoint.x : pagePoint.y))
            } else {
                placed = nil
            }
            canvas.guidePreview = placed.map { (pageIndex: $0.page, guide: $0.guide) }
            canvas.needsDisplay = true
            if ev.type == .leftMouseUp { break }
            current = window.nextEvent(matching: [.leftMouseDragged, .leftMouseUp])
        }
        canvas.guidePreview = nil
        if let placed {
            canvas.viewModel.addGuide(onPage: placed.page, isVertical: placed.guide.isVertical, position: placed.guide.position)
        }
        canvas.needsDisplay = true
    }

    override func resetCursorRects() {
        addCursorRect(bounds, cursor: isHorizontal ? .resizeUpDown : .resizeLeftRight)
    }
}

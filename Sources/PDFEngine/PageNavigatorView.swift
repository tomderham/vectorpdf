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

import SwiftUI

/// The navigator (View > Show Navigator): a miniature of the page in view, in the corner of the
/// window, with the part on screen outlined. Drag the outline, or click the miniature, to move
/// around a large sheet at high zoom.
struct PageNavigatorView: View {
    @ObservedObject var viewModel: PDFViewerViewModel
    @ObservedObject var viewport: ViewportReadout
    private let maxSide: CGFloat = 170

    init(viewModel: PDFViewerViewModel) {
        self.viewModel = viewModel
        self.viewport = viewModel.viewportReadout
    }

    var body: some View {
        if let visible = viewport.visible, let doc = viewModel.document, visible.pageIndex < doc.pageBounds.count {
            let bounds = doc.pageBounds[visible.pageIndex]
            let rotated = viewModel.viewRotationDegrees % 180 != 0
            let shown = rotated ? CGSize(width: bounds.height, height: bounds.width) : bounds.size
            let scale = maxSide / max(shown.width, shown.height, 1)
            let size = CGSize(width: shown.width * scale, height: shown.height * scale)
            ZStack(alignment: .topLeading) {
                Group {
                    if let image = viewModel.thumbnailImages[visible.pageIndex] {
                        Image(nsImage: image)
                            .resizable()
                            .rotationEffect(.degrees(Double(viewModel.viewRotationDegrees)))
                            .frame(width: rotated ? size.height : size.width, height: rotated ? size.width : size.height)
                            .frame(width: size.width, height: size.height)
                    } else {
                        Color.white
                    }
                }
                .frame(width: size.width, height: size.height)
                Rectangle()
                    .strokeBorder(Color.accentColor, lineWidth: 2)
                    .background(Color.accentColor.opacity(0.12))
                    .frame(width: max(6, frame(of: visible.rect, in: bounds, scale: scale).width),
                           height: max(6, frame(of: visible.rect, in: bounds, scale: scale).height))
                    .offset(x: frame(of: visible.rect, in: bounds, scale: scale).minX,
                            y: frame(of: visible.rect, in: bounds, scale: scale).minY)
                    .allowsHitTesting(false)
            }
            .frame(width: size.width, height: size.height)
            .clipped()
            .contentShape(Rectangle())
            .gesture(DragGesture(minimumDistance: 0).onChanged { value in
                center(at: value.location, page: visible.pageIndex, bounds: bounds, scale: scale)
            })
            .overlay(RoundedRectangle(cornerRadius: 4).strokeBorder(.separator))
            .padding(6)
            .background(.regularMaterial, in: RoundedRectangle(cornerRadius: 8))
            .shadow(color: .black.opacity(0.15), radius: 6, y: 2)
            .help("The part of the page in view. Drag to move around the page.")
            .onAppear { viewModel.requestThumbnail(for: visible.pageIndex) }
            .onChange(of: visible.pageIndex) { _, page in viewModel.requestThumbnail(for: page) }
        }
    }

    /// The miniature's rect for a page rect, as the view's rotation shows it.
    private func frame(of pageRect: CGRect, in bounds: CGRect, scale: CGFloat) -> CGRect {
        let corners = [CGPoint(x: pageRect.minX, y: pageRect.minY), CGPoint(x: pageRect.maxX, y: pageRect.maxY)]
            .map { miniaturePoint(forPagePoint: $0, bounds: bounds, scale: scale) }
        return CGRect(x: min(corners[0].x, corners[1].x), y: min(corners[0].y, corners[1].y),
                      width: abs(corners[1].x - corners[0].x), height: abs(corners[1].y - corners[0].y))
    }

    private func miniaturePoint(forPagePoint p: CGPoint, bounds: CGRect, scale: CGFloat) -> CGPoint {
        let x = p.x - bounds.minX, y = p.y - bounds.minY
        let w = bounds.width, h = bounds.height
        let turned: CGPoint
        switch viewModel.viewRotationDegrees {
        case 90: turned = CGPoint(x: h - y, y: x)
        case 180: turned = CGPoint(x: w - x, y: h - y)
        case 270: turned = CGPoint(x: y, y: w - x)
        default: turned = CGPoint(x: x, y: y)
        }
        return CGPoint(x: turned.x * scale, y: turned.y * scale)
    }

    private func center(at location: CGPoint, page: Int, bounds: CGRect, scale: CGFloat) {
        let x = location.x / scale, y = location.y / scale
        let w = bounds.width, h = bounds.height
        let p: CGPoint
        switch viewModel.viewRotationDegrees {
        case 90: p = CGPoint(x: y, y: h - x)
        case 180: p = CGPoint(x: w - x, y: h - y)
        case 270: p = CGPoint(x: w - y, y: x)
        default: p = CGPoint(x: x, y: y)
        }
        viewport.center(onPage: page, at: CGPoint(x: bounds.minX + p.x, y: bounds.minY + p.y))
    }
}

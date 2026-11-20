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

import CoreGraphics
import Foundation
import ImageIO
import MuPDFBridge
import UniformTypeIdentifiers

/// The image formats pages can be exported as.
public enum PageImageFormat: String, CaseIterable, Codable, Sendable {
    case png, jpeg, tiff

    public var title: String {
        switch self {
        case .png: return "PNG"
        case .jpeg: return "JPEG"
        case .tiff: return "TIFF"
        }
    }

    public var fileExtension: String {
        switch self {
        case .png: return "png"
        case .jpeg: return "jpg"
        case .tiff: return "tiff"
        }
    }

    public var contentType: UTType {
        switch self {
        case .png: return .png
        case .jpeg: return .jpeg
        case .tiff: return .tiff
        }
    }
}

extension PDFDocumentCore {
    /// The longest side, in pixels, a page is exported at: 600 dpi on a large drawing would
    /// need gigabytes.
    public static let maxExportPixelEdge = 16_384

    /// The page as shown (with its comments and form fields, and only the layers shown), at
    /// `dpi`, made smaller if its longest side would pass `maxExportPixelEdge`.
    public func renderPageImage(pageIndex: Int, dpi: Double) throws -> CGImage {
        guard pageIndex >= 0, pageIndex < pageCount else { throw PDFError.outOfBounds(pageIndex) }
        return try withLockedDocument { context, doc in
            var pagePointer: FZPage?
            var error: UnsafePointer<CChar>?
            guard mupdf_page_load(context, doc, Int32(pageIndex), &pagePointer, &error) == 0, let page = pagePointer else {
                throw PDFError.pageLoadFailed(pageIndex, error.map { String(cString: $0) } ?? "The page can't be read")
            }
            defer { mupdf_page_drop(context, page) }
            var bounds = fz_rect()
            _ = mupdf_page_bounds(context, page, &bounds, nil)
            let longest = Double(max(bounds.x1 - bounds.x0, bounds.y1 - bounds.y0))
            var scale = dpi / 72
            if longest * scale > Double(Self.maxExportPixelEdge) { scale = Double(Self.maxExportPixelEdge) / longest }
            var pixmap: FZPixmap?
            guard mupdf_render_page(context, page, Float(scale), Float(scale), &pixmap, &error) == 0, let pix = pixmap else {
                throw PDFError.renderFailed(error.map { String(cString: $0) } ?? "The page can't be drawn")
            }
            defer { mupdf_pixmap_drop(context, pix) }
            let width = Int(mupdf_pixmap_width(pix)), height = Int(mupdf_pixmap_height(pix))
            let stride = Int(mupdf_pixmap_stride(pix)), n = Int(mupdf_pixmap_n(pix))
            guard let samples = mupdf_pixmap_samples(pix), width > 0, height > 0,
                  let provider = CGDataProvider(data: Data(bytes: samples, count: stride * height) as CFData),
                  let image = CGImage(
                      width: width, height: height, bitsPerComponent: 8, bitsPerPixel: n * 8, bytesPerRow: stride,
                      space: CGColorSpace(name: CGColorSpace.sRGB) ?? CGColorSpaceCreateDeviceRGB(),
                      bitmapInfo: CGBitmapInfo(rawValue: (n == 4 ? CGImageAlphaInfo.premultipliedLast : .none).rawValue),
                      provider: provider, decode: nil, shouldInterpolate: true, intent: .defaultIntent
                  ) else { throw PDFError.renderFailed("The page can't be drawn") }
            return image
        }
    }

    /// Writes `pageIndices` as images to `destination`: that file for one page; for more, a
    /// folder of that name (without its extension), a file per page named for its page number.
    /// Returns the files written. `progress` is called after each page with how many are done.
    @discardableResult
    public func exportPageImages(
        pageIndices: [Int], format: PageImageFormat, dpi: Double, to destination: URL,
        progress: (Int) -> Bool = { _ in true }
    ) throws -> [URL] {
        guard !pageIndices.isEmpty else { return [] }
        let targets: [URL]
        if pageIndices.count == 1 {
            targets = [destination]
        } else {
            let folder = destination.deletingPathExtension()
            var isDirectory: ObjCBool = false
            if FileManager.default.fileExists(atPath: folder.path, isDirectory: &isDirectory), !isDirectory.boolValue {
                throw PDFError.operationFailed("A file named “\(folder.lastPathComponent)” is already there. Choose another name for the folder of images.")
            }
            try FileManager.default.createDirectory(at: folder, withIntermediateDirectories: true)
            let base = folder.lastPathComponent
            let digits = String(pageCount).count
            targets = pageIndices.map { index in
                let number = String(index + 1)
                let padded = String(repeating: "0", count: max(0, digits - number.count)) + number
                return folder.appendingPathComponent("\(base) \(padded).\(format.fileExtension)")
            }
        }
        var written: [URL] = []
        for (page, url) in zip(pageIndices, targets) {
            // Each page's image let go before the next is made.
            try autoreleasepool {
                let image = try renderPageImage(pageIndex: page, dpi: dpi)
                // Made smaller than asked (a large page), its resolution is what it was made at.
                var shown = dpi
                if page < pageBounds.count {
                    let longest = Double(max(pageBounds[page].width, pageBounds[page].height))
                    if longest > 0 { shown = min(dpi, Double(max(image.width, image.height)) / longest * 72) }
                }
                try Self.write(image, to: url, format: format, dpi: shown)
            }
            written.append(url)
            guard progress(written.count) else { break }
        }
        return written
    }

    static func write(_ image: CGImage, to url: URL, format: PageImageFormat, dpi: Double) throws {
        guard let destination = CGImageDestinationCreateWithURL(url as CFURL, format.contentType.identifier as CFString, 1, nil) else {
            throw PDFError.operationFailed("“\(url.lastPathComponent)” can't be written")
        }
        var properties: [CFString: Any] = [
            kCGImagePropertyDPIWidth: dpi,
            kCGImagePropertyDPIHeight: dpi,
        ]
        switch format {
        case .jpeg: properties[kCGImageDestinationLossyCompressionQuality] = 0.9
        case .tiff: properties[kCGImagePropertyTIFFDictionary] = [kCGImagePropertyTIFFCompression: 5]  // LZW
        case .png: break
        }
        CGImageDestinationAddImage(destination, image, properties as CFDictionary)
        guard CGImageDestinationFinalize(destination) else {
            throw PDFError.operationFailed("“\(url.lastPathComponent)” can't be written")
        }
    }
}

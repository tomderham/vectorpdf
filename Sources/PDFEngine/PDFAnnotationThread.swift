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


import Foundation
import CoreGraphics

/// The review statuses of ISO 32000's Review state model, which Acrobat also uses.
public enum PDFReviewStatus: String, CaseIterable, Identifiable, Sendable {
    case none = "None"
    case accepted = "Accepted"
    case rejected = "Rejected"
    case cancelled = "Cancelled"
    case completed = "Completed"

    public var id: String { rawValue }
    public var displayName: String { self == .none ? "No Status" : rawValue }
}

/// One annotation in the document as other PDF apps see it: read from the file, so it includes
/// annotations that came with the document, and identified by its PDF object.
public struct PDFAnnotationComment: Identifiable, Sendable, Equatable {
    public let objectNumber: Int
    public let parentObjectNumber: Int?
    public let pageIndex: Int
    public let rect: CGRect
    public let color: AnnotationColor
    public let subtype: String
    public let isCallout: Bool
    public let isCloud: Bool
    public let author: String
    public let text: String
    public let created: Date?
    public let modified: Date?
    public let state: String
    public let stateModel: String
    /// The object number of the layer it's on, or nil.
    public var layerObjectNumber: Int? = nil
    /// Whether it's on a layer that's hidden, so it isn't shown on the page.
    public var isOnHiddenLayer = false

    public var id: Int { objectNumber }
    public var date: Date? { modified ?? created }

    public var typeName: String {
        if isCloud { return "Revision Cloud" }
        if isCallout { return "Callout" }
        switch subtype {
        case "Text": return "Note"
        case "FreeText": return "Text Box"
        case "Highlight": return "Highlight"
        case "Underline": return "Underline"
        case "Squiggly": return "Squiggly Underline"
        case "StrikeOut": return "Strikethrough"
        case "Ink": return "Drawing"
        case "Stamp": return "Stamp"
        case "Square": return "Rectangle"
        case "Circle": return "Ellipse"
        case "PolyLine": return "Polyline"
        case "FileAttachment": return "Attachment"
        default: return subtype
        }
    }
}

/// An annotation with its replies, in the order they were made, and its current review status.
public struct PDFAnnotationThread: Identifiable, Sendable, Equatable {
    public let root: PDFAnnotationComment
    public let replies: [PDFAnnotationComment]
    public let status: PDFReviewStatus

    public var id: Int { root.objectNumber }

    /// Gathers a page's annotations into threads. A reply to a reply belongs to the same thread,
    /// and a reply whose parent is missing stays visible as its own thread rather than vanishing.
    static func threads(from entries: [PDFAnnotationComment]) -> [PDFAnnotationThread] {
        let byNumber = Dictionary(entries.map { ($0.objectNumber, $0) }, uniquingKeysWith: { first, _ in first })
        func rootNumber(of entry: PDFAnnotationComment) -> Int {
            var current = entry
            var seen: Set<Int> = [entry.objectNumber]
            while let parent = current.parentObjectNumber, let next = byNumber[parent] {
                // In a loop of replies nothing is the root, so each stands alone.
                guard seen.insert(parent).inserted else { return entry.objectNumber }
                current = next
            }
            return current.objectNumber
        }
        var members: [Int: [PDFAnnotationComment]] = [:]
        for entry in entries {
            let root = rootNumber(of: entry)
            if root != entry.objectNumber { members[root, default: []].append(entry) }
        }
        return entries.compactMap { entry in
            guard rootNumber(of: entry) == entry.objectNumber else { return nil }
            let sorted = (members[entry.objectNumber] ?? []).sorted { ($0.date ?? .distantPast) < ($1.date ?? .distantPast) }
            let statuses = sorted.filter { !$0.state.isEmpty && ($0.stateModel.isEmpty || $0.stateModel == "Review") }
            return PDFAnnotationThread(
                root: entry,
                replies: sorted.filter { $0.state.isEmpty },
                status: statuses.last.flatMap { PDFReviewStatus(rawValue: $0.state) } ?? .none
            )
        }
    }
}

/// How long ago an annotation was changed, for filtering.
public enum PDFAnnotationDateFilter: String, CaseIterable, Identifiable, Sendable {
    case any = "Any Date"
    case today = "Today"
    case lastWeek = "Last 7 Days"
    case lastMonth = "Last 30 Days"

    public var id: String { rawValue }

    func matches(_ date: Date?, now: Date = Date(), calendar: Calendar = .current) -> Bool {
        switch self {
        case .any: return true
        case .today: return date.map { calendar.isDate($0, inSameDayAs: now) } ?? false
        case .lastWeek: return date.map { now.timeIntervalSince($0) <= 7 * 86_400 } ?? false
        case .lastMonth: return date.map { now.timeIntervalSince($0) <= 30 * 86_400 } ?? false
        }
    }
}

/// The filters at the top of the Annotations table. A nil filter matches everything.
public struct PDFAnnotationFilter: Equatable, Sendable {
    public var type: String?
    public var author: String?
    public var status: PDFReviewStatus?
    public var date: PDFAnnotationDateFilter = .any

    public init(type: String? = nil, author: String? = nil, status: PDFReviewStatus? = nil, date: PDFAnnotationDateFilter = .any) {
        self.type = type
        self.author = author
        self.status = status
        self.date = date
    }

    public func matches(_ thread: PDFAnnotationThread, now: Date = Date()) -> Bool {
        if let type, thread.root.typeName != type { return false }
        if let author, thread.root.author != author { return false }
        if let status, thread.status != status { return false }
        return date.matches(thread.root.date, now: now)
    }
}

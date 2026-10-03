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
import AppKit

/// Types of AcroForm interactive form widgets supported by MuPDF
public enum PDFWidgetType: Int, Sendable, Codable {
    case unknown = 0
    case button = 1
    case checkbox = 2
    case combobox = 3
    case listbox = 4
    case radiobutton = 5
    case signature = 6
    case text = 7
}

/// Represents an interactive AcroForm widget within a PDF page
public struct PDFFormWidget: Identifiable, Sendable, Equatable {
    public let id: String
    public let pageIndex: Int
    public let widgetIndex: Int
    public let type: PDFWidgetType
    public let rect: CGRect
    public let name: String
    public var value: String
    public let isReadOnly: Bool
    public let isMultiline: Bool
    public let isPassword: Bool
    public let fontSize: CGFloat
    public let maxLen: Int
    public let isComb: Bool
    public let isPushButton: Bool
    public let isEditableChoice: Bool
    /// A push button whose action is ResetForm.
    public let isResetButton: Bool
    public let textAlignment: NSTextAlignment
    public let options: [String]
    
    public init(
        pageIndex: Int,
        widgetIndex: Int,
        type: PDFWidgetType,
        rect: CGRect,
        name: String,
        value: String,
        isReadOnly: Bool = false,
        isMultiline: Bool = false,
        isPassword: Bool = false,
        fontSize: CGFloat = 0,
        maxLen: Int = 0,
        isComb: Bool = false,
        isPushButton: Bool = false,
        isEditableChoice: Bool = false,
        isResetButton: Bool = false,
        textAlignment: NSTextAlignment = .left,
        options: [String] = []
    ) {
        self.id = "p\(pageIndex)_w\(widgetIndex)"
        self.pageIndex = pageIndex
        self.widgetIndex = widgetIndex
        self.type = type
        self.rect = rect
        self.name = name
        self.value = value
        self.isReadOnly = isReadOnly
        self.isMultiline = isMultiline
        self.isPassword = isPassword
        self.fontSize = fontSize
        self.maxLen = maxLen
        self.isComb = isComb
        self.isPushButton = isPushButton
        self.isEditableChoice = isEditableChoice
        self.isResetButton = isResetButton
        self.textAlignment = textAlignment
        self.options = options
    }
}

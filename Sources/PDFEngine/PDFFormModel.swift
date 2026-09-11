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
        self.textAlignment = textAlignment
        self.options = options
    }
}

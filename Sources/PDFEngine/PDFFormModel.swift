import Foundation
import CoreGraphics

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
        self.options = options
    }
}

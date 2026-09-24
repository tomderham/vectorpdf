import Foundation
import CoreGraphics

/// Comprehensive metadata extracted from the PDF Trailer / Info dictionary and Fitz metadata.
public struct DocumentMetadata: Sendable, Equatable {
    public let format: String
    public let pdfVersion: String
    public let title: String
    public let author: String
    public let subject: String
    public let keywords: String
    public let creator: String
    public let producer: String
    public let creationDate: String
    public let modificationDate: String
    public let fileSizeDescription: String
    public let pageCount: Int
    public let isEncrypted: Bool
    public let encryptionMethod: String

    public init(
        format: String,
        pdfVersion: String,
        title: String,
        author: String,
        subject: String,
        keywords: String,
        creator: String,
        producer: String,
        creationDate: String,
        modificationDate: String,
        fileSizeDescription: String,
        pageCount: Int,
        isEncrypted: Bool,
        encryptionMethod: String
    ) {
        self.format = format
        self.pdfVersion = pdfVersion
        self.title = title
        self.author = author
        self.subject = subject
        self.keywords = keywords
        self.creator = creator
        self.producer = producer
        self.creationDate = creationDate
        self.modificationDate = modificationDate
        self.fileSizeDescription = fileSizeDescription
        self.pageCount = pageCount
        self.isEncrypted = isEncrypted
        self.encryptionMethod = encryptionMethod
    }
}

/// Cryptographic permissions and usage flags defined by the PDF specification.
public struct DocumentSecurityPermissions: Sendable, Equatable {
    public let canPrint: Bool
    public let canModify: Bool
    public let canCopy: Bool
    public let canAnnotate: Bool
    public let canFillForms: Bool
    public let canAccessibility: Bool
    public let canAssemble: Bool
    public let canPrintHighQuality: Bool

    public init(
        canPrint: Bool,
        canModify: Bool,
        canCopy: Bool,
        canAnnotate: Bool,
        canFillForms: Bool,
        canAccessibility: Bool,
        canAssemble: Bool,
        canPrintHighQuality: Bool
    ) {
        self.canPrint = canPrint
        self.canModify = canModify
        self.canCopy = canCopy
        self.canAnnotate = canAnnotate
        self.canFillForms = canFillForms
        self.canAccessibility = canAccessibility
        self.canAssemble = canAssemble
        self.canPrintHighQuality = canPrintHighQuality
    }
}

/// Standard page boundary boxes defined by ISO 32000-1 (PDF).
public struct PageBoxGeometry: Sendable, Equatable, Identifiable {
    public var id: Int { pageIndex }
    public let pageIndex: Int
    public let mediaBox: CGRect
    public let cropBox: CGRect
    public let bleedBox: CGRect
    public let trimBox: CGRect
    public let artBox: CGRect
    public let hasCropBox: Bool
    public let hasBleedBox: Bool
    public let hasTrimBox: Bool
    public let hasArtBox: Bool

    public init(
        pageIndex: Int,
        mediaBox: CGRect,
        cropBox: CGRect,
        bleedBox: CGRect,
        trimBox: CGRect,
        artBox: CGRect,
        hasCropBox: Bool,
        hasBleedBox: Bool,
        hasTrimBox: Bool,
        hasArtBox: Bool
    ) {
        self.pageIndex = pageIndex
        self.mediaBox = mediaBox
        self.cropBox = cropBox
        self.bleedBox = bleedBox
        self.trimBox = trimBox
        self.artBox = artBox
        self.hasCropBox = hasCropBox
        self.hasBleedBox = hasBleedBox
        self.hasTrimBox = hasTrimBox
        self.hasArtBox = hasArtBox
    }
}

/// Information about an embedded or referenced font in the PDF document.
public struct PDFEmbeddedFont: Sendable, Identifiable, Equatable {
    public let id = UUID()
    public let rawName: String
    public let cleanName: String
    public let subtype: String
    public let encoding: String
    public let isEmbedded: Bool
    public let isSubset: Bool

    public init(
        rawName: String,
        subtype: String,
        encoding: String,
        isEmbedded: Bool,
        isSubset: Bool
    ) {
        self.rawName = rawName
        self.subtype = subtype
        self.encoding = encoding
        self.isEmbedded = isEmbedded
        self.isSubset = isSubset

        // Parse subset tag prefix if present (e.g. "ABCDEF+Helvetica" -> "Helvetica")
        if isSubset, let plusIdx = rawName.firstIndex(of: "+") {
            let next = rawName.index(after: plusIdx)
            self.cleanName = String(rawName[next...])
        } else {
            self.cleanName = rawName
        }
    }
}

/// Full inspection report containing metadata, permissions, page boxes, and fonts.
public struct PDFDocumentInspectionReport: Sendable, Equatable {
    public let metadata: DocumentMetadata
    public let permissions: DocumentSecurityPermissions
    public let pageBoxes: [PageBoxGeometry]
    public let fonts: [PDFEmbeddedFont]

    public init(
        metadata: DocumentMetadata,
        permissions: DocumentSecurityPermissions,
        pageBoxes: [PageBoxGeometry],
        fonts: [PDFEmbeddedFont]
    ) {
        self.metadata = metadata
        self.permissions = permissions
        self.pageBoxes = pageBoxes
        self.fonts = fonts
    }
}

// Generates a small password-protected PDF for testing VectorPDF's password-prompt flow.
// Uses the same CoreGraphics PDF-encryption approach as the automated test
// (testPasswordProtectedDocumentRequiresAndAcceptsPassword in PDFEngineTests.swift).
//
// Usage: swift generate_password_protected_pdf.swift <output.pdf> <password>

import AppKit
import CoreGraphics

guard CommandLine.arguments.count > 2 else {
    print("Usage: swift generate_password_protected_pdf.swift <output.pdf> <password>")
    exit(1)
}

let outputPath = CommandLine.arguments[1]
let password = CommandLine.arguments[2]

var mediaBox = CGRect(x: 0, y: 0, width: 612, height: 792)
let auxInfo: [CFString: Any] = [
    kCGPDFContextUserPassword: password,
    kCGPDFContextOwnerPassword: "owner-\(password)"
]
guard let context = CGContext(URL(fileURLWithPath: outputPath) as CFURL, mediaBox: &mediaBox, auxInfo as CFDictionary) else {
    print("Failed to create encrypted PDF context")
    exit(1)
}

NSGraphicsContext.current = NSGraphicsContext(cgContext: context, flipped: false)

context.beginPDFPage(nil)
let titleFont = NSFont.boldSystemFont(ofSize: 20)
let bodyFont = NSFont.systemFont(ofSize: 13)
("This PDF is password-protected." as NSString).draw(at: NSPoint(x: 72, y: 700), withAttributes: [.font: titleFont])
("Password: \(password)" as NSString).draw(at: NSPoint(x: 72, y: 660), withAttributes: [.font: bodyFont])
("Generated for testing VectorPDF's password prompt." as NSString).draw(at: NSPoint(x: 72, y: 630), withAttributes: [.font: bodyFont])
context.endPDFPage()

context.closePDF()
print("Wrote \(outputPath) (password: \(password))")

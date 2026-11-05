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
import UniformTypeIdentifiers

extension PDFViewerViewModel {
    /// Reads the list of attachments again, after the document changed.
    func refreshAttachments() {
        let current = document?.attachments() ?? []
        if current != attachments { attachments = current }
    }

    /// Writes `attachment` to a folder of its own in the temporary directory, for Quick Look,
    /// opening or dragging out. Removed with VectorPDF's other temporary files at a later launch.
    public func extractAttachment(_ attachment: PDFAttachment) throws -> URL {
        guard let doc = document else { throw PDFError.openFailed("No document is open") }
        // "VectorPDF" first, so StoredData clears it up.
        let folder = FileManager.default.temporaryDirectory.appendingPathComponent("VectorPDF-attachment-\(UUID().uuidString)")
        try FileManager.default.createDirectory(at: folder, withIntermediateDirectories: true)
        let url = folder.appendingPathComponent(attachment.fileName)
        try doc.saveAttachment(attachment, to: url.path)
        Self.quarantine(url)
        return url
    }

    /// Marks a file taken out of a PDF as downloaded, so Gatekeeper checks it before an app or
    /// script in it runs, as it would for one from a browser or Mail.
    nonisolated static func quarantine(_ url: URL) {
        var values = URLResourceValues()
        values.quarantineProperties = [
            kLSQuarantineAgentNameKey as String: "VectorPDF",
            kLSQuarantineTypeKey as String: kLSQuarantineTypeOtherDownload as String
        ]
        var url = url
        try? url.setResourceValues(values)
    }

    /// Opens the attachment in its default app.
    public func openAttachment(_ attachment: PDFAttachment) {
        do {
            NSWorkspace.shared.open(try extractAttachment(attachment))
        } catch {
            showErrorAlert(title: "Couldn't Open Attachment", message: error.localizedDescription)
        }
    }

    /// Asks where to save the attachment, then saves it there.
    public func saveAttachmentAs(_ attachment: PDFAttachment) {
        guard let doc = document else { return }
        let panel = NSSavePanel()
        panel.nameFieldStringValue = attachment.fileName
        panel.canCreateDirectories = true
        panel.title = "Save Attachment"
        let completion: (NSApplication.ModalResponse) -> Void = { [weak self] response in
            guard response == .OK, let url = panel.url else { return }
            do {
                try doc.saveAttachment(attachment, to: url.path)
                Self.quarantine(url)
            } catch {
                self?.showErrorAlert(title: "Couldn't Save Attachment", message: error.localizedDescription)
            }
        }
        if let window = currentWindow ?? NSApplication.shared.keyWindow, window.attachedSheet == nil {
            panel.beginSheetModal(for: window, completionHandler: completion)
        } else {
            panel.begin(completionHandler: completion)
        }
    }

    /// Asks for a folder, then saves every attachment in it, numbering names that would clash.
    public func saveAllAttachments() {
        guard let doc = document, !attachments.isEmpty else { return }
        let attachments = self.attachments
        let panel = NSOpenPanel()
        panel.canChooseFiles = false
        panel.canChooseDirectories = true
        panel.canCreateDirectories = true
        panel.prompt = "Save"
        panel.title = "Save All Attachments"
        let completion: (NSApplication.ModalResponse) -> Void = { [weak self] response in
            guard response == .OK, let folder = panel.url else { return }
            do {
                for (attachment, name) in zip(attachments, Self.uniqueNames(for: attachments, in: folder)) {
                    let url = folder.appendingPathComponent(name)
                    try doc.saveAttachment(attachment, to: url.path)
                    Self.quarantine(url)
                }
            } catch {
                self?.showErrorAlert(title: "Couldn't Save Attachments", message: error.localizedDescription)
            }
        }
        if let window = currentWindow ?? NSApplication.shared.keyWindow, window.attachedSheet == nil {
            panel.beginSheetModal(for: window, completionHandler: completion)
        } else {
            panel.begin(completionHandler: completion)
        }
    }

    /// A name for each attachment that's free in `folder` and not used by another of them:
    /// "plan.dwg", then "plan 2.dwg", and so on.
    static func uniqueNames(for attachments: [PDFAttachment], in folder: URL) -> [String] {
        var taken = Set<String>()
        return attachments.map { attachment in
            let name = attachment.fileName
            let base = (name as NSString).deletingPathExtension
            let ext = (name as NSString).pathExtension
            var candidate = name
            var number = 2
            while taken.contains(candidate.lowercased())
                    || FileManager.default.fileExists(atPath: folder.appendingPathComponent(candidate).path) {
                candidate = ext.isEmpty ? "\(base) \(number)" : "\(base) \(number).\(ext)"
                number += 1
            }
            taken.insert(candidate.lowercased())
            return candidate
        }
    }
}

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
import Foundation

/// Copies of documents with unsaved changes, kept so a crash doesn't lose them. Each is a PDF and
/// a note of the file it's a copy of, in Application Support/VectorPDF/Recovery. Saving, Revert,
/// Don't Save and a normal quit delete a document's copy; what's left at launch is from a crash.
public enum AutosaveRecovery {
    public struct Record: Codable, Equatable, Sendable {
        public let id: UUID
        public let originalPath: String
        public let title: String
        public let savedAt: Date
    }

    /// How long after a change its document is copied.
    nonisolated static let delay: Duration = .seconds(30)

    /// Under the test runner, a folder of its own in the temporary directory, which tests may
    /// also set.
    nonisolated(unsafe) static var directoryOverride: URL?

    @MainActor
    static var directory: URL {
        if let directoryOverride { return directoryOverride }
        if PDFViewerViewModel.isRunningTests {
            return FileManager.default.temporaryDirectory.appendingPathComponent("VectorPDF-test-recovery", isDirectory: true)
        }
        return StoredData.supportDirectory.appendingPathComponent("Recovery", isDirectory: true)
    }

    @MainActor static func pdfURL(_ id: UUID) -> URL { directory.appendingPathComponent("\(id.uuidString).pdf") }
    @MainActor static func recordURL(_ id: UUID) -> URL { directory.appendingPathComponent("\(id.uuidString).json") }

    /// The copies there are, newest first; ones whose PDF is missing are dropped.
    @MainActor
    public static func records() -> [Record] {
        let urls = (try? FileManager.default.contentsOfDirectory(at: directory, includingPropertiesForKeys: nil)) ?? []
        return urls.filter { $0.pathExtension == "json" }.compactMap { url -> Record? in
            guard let data = try? Data(contentsOf: url), let record = try? JSONDecoder().decode(Record.self, from: data) else {
                try? FileManager.default.removeItem(at: url)
                return nil
            }
            guard FileManager.default.fileExists(atPath: pdfURL(record.id).path) else {
                try? FileManager.default.removeItem(at: url)
                return nil
            }
            return record
        }.sorted { $0.savedAt > $1.savedAt }
    }

    @MainActor
    public static func discard(_ id: UUID) {
        try? FileManager.default.removeItem(at: pdfURL(id))
        try? FileManager.default.removeItem(at: recordURL(id))
    }

    /// Copies `record`'s document beside its original as "Name (Recovered).pdf" (numbered if
    /// that's taken), or to Downloads when its folder can't be written to; discards the copy kept
    /// here; and returns where it went.
    @MainActor
    public static func restore(_ record: Record, fallbackFolder: URL? = nil) throws -> URL {
        let original = URL(fileURLWithPath: record.originalPath)
        let base = original.deletingPathExtension().lastPathComponent
        let folder = original.deletingLastPathComponent()
        let downloads = fallbackFolder ?? FileManager.default.urls(for: .downloadsDirectory, in: .userDomainMask).first ?? FileManager.default.temporaryDirectory
        let candidates = FileManager.default.isWritableFile(atPath: folder.path) ? [folder, downloads] : [downloads]
        var lastError: Error?
        for target in candidates {
            var destination = target.appendingPathComponent("\(base) (Recovered).pdf")
            var n = 2
            while FileManager.default.fileExists(atPath: destination.path) {
                destination = target.appendingPathComponent("\(base) (Recovered \(n)).pdf")
                n += 1
            }
            do {
                try FileManager.default.copyItem(at: pdfURL(record.id), to: destination)
                discard(record.id)
                return destination
            } catch {
                lastError = error
            }
        }
        throw lastError ?? CocoaError(.fileWriteUnknown)
    }

    /// Run once windows are up: offers what a crash left behind.
    @MainActor
    public static func offerRecoveryAtLaunch() {
        guard !PDFViewerViewModel.isRunningTests else { return }
        let found = records()
        guard !found.isEmpty else { return }
        let alert = NSAlert()
        alert.messageText = found.count == 1
            ? "VectorPDF didn’t quit normally, and “\(found[0].title)” had changes that weren’t saved."
            : "VectorPDF didn’t quit normally, and \(found.count) documents had changes that weren’t saved."
        let names = found.count == 1 ? "" : found.map { "• \($0.title)" }.joined(separator: "\n") + "\n\n"
        alert.informativeText = names + "Open the recovered copies to keep the changes. Each is saved beside its original, named “(Recovered)”; the original isn’t changed."
        alert.addButton(withTitle: found.count == 1 ? "Open Recovered Copy" : "Open Recovered Copies")
        alert.addButton(withTitle: "Decide Later")
        alert.addButton(withTitle: "Discard Changes")
        alert.buttons[2].hasDestructiveAction = true
        switch alert.runModal() {
        case .alertFirstButtonReturn:
            var failed: [String] = []
            for record in found {
                if let url = try? restore(record) {
                    DocumentWindowing.openDocumentHandlingEmptyStart(url: url)
                } else {
                    failed.append(record.title)
                }
            }
            if !failed.isEmpty {
                let problem = NSAlert()
                problem.messageText = "Couldn’t save the recovered copy of \(failed.map { "“\($0)”" }.joined(separator: ", "))."
                problem.informativeText = "It’s kept, and offered again next time VectorPDF opens."
                problem.runModal()
            }
        case .alertThirdButtonReturn:
            for record in found { discard(record.id) }
        default:
            break
        }
    }

    /// A normal quit: the copies of open documents aren't needed, as their changes were saved or
    /// thrown away when asked.
    @MainActor
    public static func discardAllAtQuit() {
        for viewModel in PDFViewerAppCoordinator.shared.openViewModels {
            viewModel.discardRecoveryCopy()
        }
    }
}

extension PDFViewerViewModel {
    /// Whether this document's unsaved changes are copied for recovery: not for one that's
    /// password-protected (the copy would be unencrypted), read-only, or a transient view.
    var keepsRecoveryCopy: Bool {
        document?.isPDF == true && !isReadOnlyDocument && currentDocumentPassword == nil && !isTransientWindow && !isComparePane
    }

    /// Called whenever the document is marked edited or saved.
    func documentEditedChanged() {
        if isDocumentEdited {
            scheduleAutosave()
        } else {
            discardRecoveryCopy()
        }
    }

    /// Copies the document once `AutosaveRecovery.delay` has passed, unless one is due already.
    func scheduleAutosave() {
        guard keepsRecoveryCopy, autosaveTask == nil else { return }
        autosaveTask = Task { @MainActor [weak self] in
            try? await Task.sleep(for: AutosaveRecovery.delay)
            guard let self, !Task.isCancelled else { return }
            self.autosaveTask = nil
            await self.autosaveNow()
        }
    }

    /// Writes the recovery copy now.
    func autosaveNow() async {
        guard isDocumentEdited, keepsRecoveryCopy, let doc = document else { return }
        let id = recoveryID ?? UUID()
        recoveryID = id
        let record = AutosaveRecovery.Record(id: id, originalPath: doc.filePath, title: documentTitle, savedAt: Date())
        let folder = AutosaveRecovery.directory
        let pdf = AutosaveRecovery.pdfURL(id)
        let note = AutosaveRecovery.recordURL(id)
        let ok = await Task.detached(priority: .utility) { () -> Bool in
            do {
                try FileManager.default.createDirectory(at: folder, withIntermediateDirectories: true)
                try doc.save(to: pdf.path)
                try JSONEncoder().encode(record).write(to: note, options: .atomic)
                return true
            } catch {
                return false
            }
        }.value
        // Saved or thrown away meanwhile: the copy isn't wanted.
        if ok, !isDocumentEdited || document !== doc { AutosaveRecovery.discard(id) }
    }

    func discardRecoveryCopy() {
        autosaveTask?.cancel()
        autosaveTask = nil
        if let id = recoveryID {
            AutosaveRecovery.discard(id)
            recoveryID = nil
        }
    }
}

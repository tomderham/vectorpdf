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

import Testing
import Foundation
@testable import PDFEngine

/// Unsaved changes are copied aside, so a crash doesn't lose them.
@MainActor
@Suite(.serialized) struct AutosaveRecoveryTests {
    /// A document with a change in it, its copies kept in a folder of the test's own.
    private func editedDocument(in dir: URL) async throws -> (PDFViewerViewModel, URL) {
        AutosaveRecovery.directoryOverride = dir.appendingPathComponent("Recovery", isDirectory: true)
        let url = dir.appendingPathComponent("Report.pdf")
        makeLabelledPDF(at: url, labels: ["Alpha", "Bravo"])
        let vm = PDFViewerViewModel()
        await vm.loadDocument(from: url.path)
        try #require(vm.addShapeAnnotation(pageIndex: 0, shape: .rectangle, from: CGPoint(x: 100, y: 100), to: CGPoint(x: 200, y: 200)) != nil)
        #expect(vm.isDocumentEdited)
        return (vm, url)
    }

    @Test func aCopyIsKeptUntilTheDocumentIsSaved() async throws {
        let dir = try makeScratchDirectory()
        defer { try? FileManager.default.removeItem(at: dir); AutosaveRecovery.directoryOverride = nil }
        let (vm, url) = try await editedDocument(in: dir)
        // A copy is due, not written straight away.
        #expect(vm.autosaveTask != nil)
        #expect(AutosaveRecovery.records().isEmpty)

        await vm.autosaveNow()
        let record = try #require(AutosaveRecovery.records().first)
        #expect(record.originalPath == url.path && record.title == "Report.pdf")
        // The copy has the change in it.
        let copy = try PDFDocumentCore(filePath: AutosaveRecovery.pdfURL(record.id).path)
        #expect(copy.pageCount == 2)

        vm.saveDocument()
        #expect(!vm.isDocumentEdited)
        #expect(AutosaveRecovery.records().isEmpty)
        #expect(vm.autosaveTask == nil)
    }

    @Test func dontSaveThrowsTheCopyAway() async throws {
        let dir = try makeScratchDirectory()
        defer { try? FileManager.default.removeItem(at: dir); AutosaveRecovery.directoryOverride = nil }
        let (vm, _) = try await editedDocument(in: dir)
        await vm.autosaveNow()
        #expect(AutosaveRecovery.records().count == 1)
        // What Don't Save does.
        vm.isDocumentEdited = false
        #expect(AutosaveRecovery.records().isEmpty)
    }

    @Test func aRecoveredCopyGoesBesideTheOriginal() async throws {
        let dir = try makeScratchDirectory()
        defer { try? FileManager.default.removeItem(at: dir); AutosaveRecovery.directoryOverride = nil }
        let (vm, url) = try await editedDocument(in: dir)
        await vm.autosaveNow()
        // As a crash leaves it: the copy, and nothing to delete it.
        vm.recoveryID = nil
        let record = try #require(AutosaveRecovery.records().first)
        let first = try AutosaveRecovery.restore(record)
        #expect(first == url.deletingLastPathComponent().appendingPathComponent("Report (Recovered).pdf"))
        #expect(AutosaveRecovery.records().isEmpty)
        #expect(try PDFDocumentCore(filePath: first.path).pageCount == 2)

        // A second is numbered rather than replacing the first.
        await vm.autosaveNow()
        let again = try #require(AutosaveRecovery.records().first)
        #expect(try AutosaveRecovery.restore(again).lastPathComponent == "Report (Recovered 2).pdf")
    }

    @Test func aPasswordProtectedDocumentIsntCopied() async throws {
        let dir = try makeScratchDirectory()
        defer { try? FileManager.default.removeItem(at: dir); AutosaveRecovery.directoryOverride = nil }
        AutosaveRecovery.directoryOverride = dir.appendingPathComponent("Recovery", isDirectory: true)
        let plain = dir.appendingPathComponent("Plain.pdf")
        makeLabelledPDF(at: plain, labels: ["Alpha"])
        let locked = dir.appendingPathComponent("Locked.pdf")
        try PDFDocumentCore(filePath: plain.path).saveEncrypted(to: locked.path, password: "secret")
        let vm = PDFViewerViewModel()
        await vm.loadDocument(from: locked.path, password: "secret")
        try #require(vm.document != nil)
        _ = vm.addShapeAnnotation(pageIndex: 0, shape: .rectangle, from: CGPoint(x: 100, y: 100), to: CGPoint(x: 200, y: 200))
        #expect(vm.isDocumentEdited)
        #expect(!vm.keepsRecoveryCopy)
        await vm.autosaveNow()
        #expect(AutosaveRecovery.records().isEmpty)
    }
}

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
import Testing
@testable import PDFEngine

@Suite(.serialized)
struct StoredDataTests {

    private func makeIndex(for source: URL, chunks: Int = 3, dimensions: Int = 512) throws -> DocumentSemanticIndex {
        let modified = try FileManager.default.attributesOfItem(atPath: source.path)[.modificationDate] as! Date
        let embedded = (0..<chunks).map { i in
            EmbeddedChunk(
                chunk: SemanticChunk(pageIndex: i, text: "Chunk \(i) text"),
                vector: (0..<dimensions).map { _ in Float.random(in: -0.1...0.1) }
            )
        }
        return DocumentSemanticIndex(sourcePath: source.path, sourceModifiedAt: modified, chunks: embedded)
    }

    private func touch(_ url: URL, daysAgo: Double) throws {
        try FileManager.default.setAttributes(
            [.modificationDate: Date().addingTimeInterval(-daysAgo * 86_400)], ofItemAtPath: url.path)
    }

    @Test func vectorsRoundTripAtHalfPrecision() throws {
        let vector: [Float] = [0, -1.5, 0.25, -0.0063641276, 0.05538212, 0.7071068]
        let chunk = EmbeddedChunk(chunk: SemanticChunk(pageIndex: 4, text: "abc"), vector: vector)
        let encoder = PropertyListEncoder()
        encoder.outputFormat = .binary
        let decoded = try PropertyListDecoder().decode(EmbeddedChunk.self, from: encoder.encode(chunk))
        #expect(decoded.chunk == chunk.chunk)
        #expect(decoded.vector.count == vector.count)
        for (a, b) in zip(decoded.vector, vector) {
            #expect(abs(a - b) <= abs(b) / 1000 + 1e-6)
        }
        // Exactly representable values come back unchanged, so a saved index is stable.
        #expect(Array(decoded.vector[0...2]) == [0, -1.5, 0.25])
    }

    @Test func halfPrecisionKeepsTheRankingOfPassages() {
        var generator = SystemRandomNumberGenerator()
        func randomVector() -> [Float] { (0..<512).map { _ in Float.random(in: -0.1...0.1, using: &generator) } }
        let query = randomVector()
        let passages = (0..<50).map { _ in randomVector() }
        let halved = passages.map { $0.map { Float(Float16($0)) } }
        let rank = { (vectors: [[Float]]) in
            vectors.indices.sorted { cosineSimilarity(query, vectors[$0]) > cosineSimilarity(query, vectors[$1]) }
        }
        #expect(Array(rank(passages).prefix(5)) == Array(rank(halved).prefix(5)))
    }

    @Test func aBinaryIndexIsFarSmallerThanTheOldJSON() throws {
        let dir = try makeScratchDirectory()
        defer { try? FileManager.default.removeItem(at: dir) }
        let source = dir.appendingPathComponent("doc.pdf")
        createSamplePDF(at: source)
        let index = try makeIndex(for: source, chunks: 20)

        // What format 6 wrote: the vector as a JSON array of numbers.
        struct OldChunk: Encodable { let chunk: SemanticChunk; let vector: [Float] }
        let oldBytes = try JSONEncoder().encode(index.chunks.map { OldChunk(chunk: $0.chunk, vector: $0.vector) }).count
        let encoder = PropertyListEncoder()
        encoder.outputFormat = .binary
        let newBytes = try encoder.encode(index).count
        #expect(newBytes * 3 < oldBytes, "\(newBytes) bytes against \(oldBytes)")
    }

    @Test func storeSavesAndLoadsAndForgetsChangedDocuments() async throws {
        let dir = try makeScratchDirectory()
        defer { try? FileManager.default.removeItem(at: dir) }
        let source = dir.appendingPathComponent("doc.pdf")
        createSamplePDF(at: source)
        let store = SemanticIndexStore(directory: dir.appendingPathComponent("Index"))

        let index = try makeIndex(for: source)
        await store.save(index)
        let loaded = await store.load(for: source.path)
        #expect(loaded?.chunks.map(\.chunk) == index.chunks.map(\.chunk))
        #expect(loaded?.sourcePath == index.sourcePath)
        #expect(SemanticIndexStore.sourcePath(of: await store.fileURL(for: source.path)) == source.path)

        try touch(source, daysAgo: 1)
        #expect(await store.load(for: source.path) == nil)
    }

    @Test func pruningDropsOldFormatsMissingDocumentsAndTheLeastRecentlyUsed() async throws {
        let dir = try makeScratchDirectory()
        defer { try? FileManager.default.removeItem(at: dir) }
        let indexDir = dir.appendingPathComponent("Index")
        let sources = (0..<3).map { dir.appendingPathComponent("doc\($0).pdf") }
        sources.forEach(createSamplePDF(at:))

        // Big enough for two indexes, not three.
        let probe = SemanticIndexStore(directory: indexDir)
        await probe.save(try makeIndex(for: sources[0]))
        let oneIndex = await probe.totalBytes()
        await probe.removeAll()

        let store = SemanticIndexStore(directory: indexDir, maxBytes: oneIndex * 2 + oneIndex / 2)
        let legacy = indexDir.appendingPathComponent("0123abcd.json")
        try Data("{}".utf8).write(to: legacy)

        for source in sources[0...1] {
            await store.save(try makeIndex(for: source))
        }
        try touch(await store.fileURL(for: sources[0].path), daysAgo: 2)
        try touch(await store.fileURL(for: sources[1].path), daysAgo: 1)
        // Loading counts as use, so doc0 becomes the most recent.
        #expect(await store.load(for: sources[0].path) != nil)

        await store.save(try makeIndex(for: sources[2]))
        #expect(!FileManager.default.fileExists(atPath: legacy.path))
        #expect(await store.load(for: sources[0].path) != nil)
        #expect(await store.load(for: sources[1].path) == nil)
        #expect(await store.load(for: sources[2].path) != nil)

        try FileManager.default.removeItem(at: sources[2])
        await store.prune()
        #expect(!FileManager.default.fileExists(atPath: await store.fileURL(for: sources[2].path).path))
        #expect(FileManager.default.fileExists(atPath: await store.fileURL(for: sources[0].path).path))

        await store.removeAll()
        #expect(await store.totalBytes() == 0)
    }

    @Test func launchCleanupDeletesOnlyStaleUnusedTemporaryFiles() throws {
        let dir = try makeScratchDirectory()
        defer { try? FileManager.default.removeItem(at: dir) }
        func file(_ name: String, daysAgo: Double) throws -> URL {
            let url = dir.appendingPathComponent(name)
            try Data("x".utf8).write(to: url)
            try touch(url, daysAgo: daysAgo)
            return url
        }
        let crashed = try file("VectorPDF-working-old.pdf", daysAgo: 3)
        let update = try file("VectorPDF_Update.dmg", daysAgo: 2)
        let recent = try file("VectorPDF-print-new.pdf", daysAgo: 0.1)
        let inUse = try file("VectorPDF-working-open.pdf", daysAgo: 3)
        let other = try file("SomeOtherApp.tmp", daysAgo: 30)
        let docx = dir.appendingPathComponent("VectorPDF-docx-old")
        try FileManager.default.createDirectory(at: docx, withIntermediateDirectories: true)
        try touch(docx, daysAgo: 5)

        StoredData.removeTemporaryItems(in: dir, olderThan: StoredData.staleAge, keeping: [inUse.standardizedFileURL.path])

        let fm = FileManager.default
        #expect(!fm.fileExists(atPath: crashed.path))
        #expect(!fm.fileExists(atPath: update.path))
        #expect(!fm.fileExists(atPath: docx.path))
        #expect(fm.fileExists(atPath: recent.path))
        #expect(fm.fileExists(atPath: inUse.path))
        #expect(fm.fileExists(atPath: other.path))
    }

    @Test func unusedAnchorThumbnailsAreDeleted() throws {
        let dir = try makeScratchDirectory()
        defer { try? FileManager.default.removeItem(at: dir) }
        let used = UUID(), orphan = UUID(), fresh = UUID()
        for (id, days) in [(used, 5.0), (orphan, 5.0), (fresh, 0.0)] {
            let url = dir.appendingPathComponent("\(id.uuidString).png")
            try Data("png".utf8).write(to: url)
            try touch(url, daysAgo: days)
        }

        StoredData.removeUnusedThumbnails(in: dir, keeping: [used])

        let remaining = Set(try FileManager.default.contentsOfDirectory(atPath: dir.path))
        #expect(remaining == ["\(used.uuidString).png", "\(fresh.uuidString).png"])
    }
}

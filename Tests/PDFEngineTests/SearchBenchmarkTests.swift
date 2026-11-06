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
import PDFKit
import Testing
@testable import PDFEngine

/// Time to first hit and for the whole document when searching a large document, and the peak
/// memory it takes. Prints its numbers rather than asserting them; only runs with
/// `VECTORPDF_BENCHMARKS=1 swift test --filter SearchBenchmark`.
@Suite(.enabled(if: ProcessInfo.processInfo.environment["VECTORPDF_BENCHMARKS"] == "1",
                "Benchmark; run with VECTORPDF_BENCHMARKS=1"))
struct SearchBenchmarkTests {
    @Test func searchLargeDocument() async throws {
        let dir = try makeScratchDirectory()
        defer { try? FileManager.default.removeItem(at: dir) }
        let url = dir.appendingPathComponent("large.pdf")

        // About 1,000 pages of real typesetting: the larger fixtures, repeated.
        let output = PDFDocument()
        let sources = ["hr1968-ih.pdf", "lcms2-tutorial.pdf", "nist-tn-2255.pdf", "rfc9457.pdf"]
            .compactMap { PDFDocument(url: Fixture.url($0)) }
        while output.pageCount < 1000 {
            for source in sources {
                for i in 0..<source.pageCount {
                    if let page = source.page(at: i)?.copy() as? PDFPage {
                        output.insert(page, at: output.pageCount)
                    }
                }
            }
        }
        #expect(output.write(to: url))
        let pageCount = output.pageCount

        // VECTORPDF_SEARCH_WORKERS compares worker counts (1 is the old serial search).
        let workers = Int(ProcessInfo.processInfo.environment["VECTORPDF_SEARCH_WORKERS"] ?? "") ?? PDFSearchActor.defaultWorkerCount
        let actor = PDFSearchActor(workerCount: workers)
        try await actor.openDocument(filePath: url.path)
        let baseline = Self.residentMemory()
        var peak = baseline

        for query in ["the", "notwithstanding"] + Array(repeating: "Bluetooth", count: Int(ProcessInfo.processInfo.environment["VECTORPDF_BENCH_REPEAT"] ?? "") ?? 2) {
            let start = Date()
            var firstHit: TimeInterval?
            var hits = 0
            for await _ in await actor.searchStream(query: query, nearPage: pageCount / 2) {
                if firstHit == nil { firstHit = Date().timeIntervalSince(start) }
                hits += 1
                if hits % 500 == 0 { peak = max(peak, Self.residentMemory()) }
            }
            peak = max(peak, Self.residentMemory())
            let total = Date().timeIntervalSince(start)
            print(String(format: "SearchBenchmark (%d workers): \"%@\" over %d pages: %d hits, first after %.0f ms, all after %.0f ms",
                         workers, query, pageCount, hits, (firstHit ?? total) * 1000, total * 1000))
        }
        print(String(format: "SearchBenchmark: resident memory %.0f MB after opening, peak %.0f MB",
                     Double(baseline) / 1_048_576, Double(peak) / 1_048_576))
    }

    /// Compare Documents on the same document and a revision with pages taken out and others put
    /// in: reading both documents' words, then diffing them. The document repeats its sources,
    /// so most of its text occurs several times: a hard case for anchoring.
    @Test func compareLargeDocuments() throws {
        let dir = try makeScratchDirectory()
        defer { try? FileManager.default.removeItem(at: dir) }
        let originalURL = dir.appendingPathComponent("original.pdf")
        let revisedURL = dir.appendingPathComponent("revised.pdf")
        let output = PDFDocument()
        let sources = ["hr1968-ih.pdf", "lcms2-tutorial.pdf", "nist-tn-2255.pdf", "rfc9457.pdf"]
            .compactMap { PDFDocument(url: Fixture.url($0)) }
        while output.pageCount < 1000 {
            for source in sources {
                for i in 0..<source.pageCount {
                    if let page = source.page(at: i)?.copy() as? PDFPage { output.insert(page, at: output.pageCount) }
                }
            }
        }
        #expect(output.write(to: originalURL))
        // Twenty pages out near the start, and five pages of the RFC in near the middle.
        for _ in 0..<20 { output.removePage(at: 50) }
        for i in 0..<5 {
            if let page = sources[3].page(at: i)?.copy() as? PDFPage { output.insert(page, at: 500 + i) }
        }
        #expect(output.write(to: revisedURL))

        let start = Date()
        let original = try #require(try ComparedText.load(filePath: originalURL.path))
        let revised = try #require(try ComparedText.load(filePath: revisedURL.path))
        let loaded = Date()
        let comparison = DocumentComparison(original: original, revised: revised)
        let done = Date()
        print(String(format: "CompareBenchmark: %d and %d pages, %d and %d words: read in %.0f ms, diffed in %.0f ms; %d changes, %d anchors, similarity %.3f",
                     original.pageCount, revised.pageCount, original.words.count, revised.words.count,
                     loaded.timeIntervalSince(start) * 1000, done.timeIntervalSince(loaded) * 1000,
                     comparison.changes.count, comparison.anchors.count, comparison.similarity))
        #expect(comparison.similarity > 0.95)
    }

    /// Compare Documents on two revisions of your own, given by `VECTORPDF_COMPARE_ORIGINAL` and
    /// `VECTORPDF_COMPARE_REVISED`, with each option and without: the time each diff takes and
    /// the changes it finds.
    @Test(.enabled(if: ProcessInfo.processInfo.environment["VECTORPDF_COMPARE_ORIGINAL"] != nil))
    func compareGivenDocuments() throws {
        let environment = ProcessInfo.processInfo.environment
        let originalPath = try #require(environment["VECTORPDF_COMPARE_ORIGINAL"])
        let revisedPath = try #require(environment["VECTORPDF_COMPARE_REVISED"])
        let start = Date()
        let original = try #require(try ComparedText.load(filePath: originalPath))
        let revised = try #require(try ComparedText.load(filePath: revisedPath))
        print(String(format: "CompareBenchmark: %d and %d pages, %d and %d words, %d and %d links: read in %.0f ms",
                     original.pageCount, revised.pageCount, original.words.count, revised.words.count,
                     original.links.count, revised.links.count, Date().timeIntervalSince(start) * 1000))
        var previous: DocumentComparison?
        for (label, options, reuse) in [("plain", CompareOptions(), false),
                                        ("ignoring renumbering", CompareOptions(ignoresRenumbering: true), false),
                                        ("ignoring renumbering, from the plain one", CompareOptions(ignoresRenumbering: true), true)] {
            let diffStart = Date()
            let comparison = DocumentComparison(original: original, revised: revised, options: options, previous: reuse ? previous : nil)
            print(String(format: "CompareBenchmark: %@: diffed in %.0f ms; %d changes, %d moves, similarity %.4f",
                         label, Date().timeIntervalSince(diffStart) * 1000, comparison.changes.count, comparison.moves.count, comparison.similarity))
            if previous == nil { previous = comparison }
        }
    }

    private static func residentMemory() -> UInt64 {
        var info = mach_task_basic_info()
        var count = mach_msg_type_number_t(MemoryLayout<mach_task_basic_info>.size / MemoryLayout<natural_t>.size)
        let result = withUnsafeMutablePointer(to: &info) {
            $0.withMemoryRebound(to: integer_t.self, capacity: Int(count)) {
                task_info(mach_task_self_, task_flavor_t(MACH_TASK_BASIC_INFO), $0, &count)
            }
        }
        return result == KERN_SUCCESS ? info.resident_size : 0
    }
}

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

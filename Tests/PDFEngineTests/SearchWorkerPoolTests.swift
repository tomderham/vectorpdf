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

/// Search workers each hold a copy of the document. Once searching stops for a while, all but
/// one are closed; the next search opens them again.
struct SearchWorkerPoolTests {

    private func makePool(delay: TimeInterval) throws -> (SearchWorkerPool, URL) {
        let url = FileManager.default.temporaryDirectory.appendingPathComponent("vpdf_pool_\(UUID().uuidString).pdf")
        makeLabelledPDF(at: url, labels: ["Alpha", "Bravo"])
        let first = try SearchResource(filePath: url.path, password: nil)
        return (SearchWorkerPool(first: first, filePath: url.path, password: nil, capacity: 4, idleTrimDelay: delay), url)
    }

    @Test func idleWorkersAreClosedDownToOneAfterSearchingStops() async throws {
        let (pool, url) = try makePool(delay: 0.2)
        defer { try? FileManager.default.removeItem(at: url) }
        let workers = (0..<4).compactMap { _ in pool.checkOut() }
        #expect(workers.count == 4)
        workers.forEach(pool.checkIn)
        #expect(pool.idleCount == 4)
        try await Task.sleep(for: .milliseconds(600))
        #expect(pool.idleCount == 1)

        // The next search opens them again.
        let again = (0..<3).compactMap { _ in pool.checkOut() }
        #expect(again.count == 3)
        again.forEach(pool.checkIn)
        #expect(pool.idleCount == 3)
    }

    @Test func workersAreKeptWhileASearchRunsOrOneStartedSince() async throws {
        let (pool, url) = try makePool(delay: 0.3)
        defer { try? FileManager.default.removeItem(at: url) }
        let workers = (0..<3).compactMap { _ in pool.checkOut() }
        workers.forEach(pool.checkIn)

        // A search starting before the trim, and still running when it's due: nothing closed.
        try await Task.sleep(for: .milliseconds(100))
        let running = try #require(pool.checkOut())
        try await Task.sleep(for: .milliseconds(400))
        #expect(pool.idleCount == 2)

        // Once it ends, the wait starts again.
        pool.checkIn(running)
        #expect(pool.idleCount == 3)
        try await Task.sleep(for: .milliseconds(100))
        #expect(pool.idleCount == 3)
        try await Task.sleep(for: .milliseconds(600))
        #expect(pool.idleCount == 1)
    }

    @Test func aClosedPoolHandsOutNothing() throws {
        let (pool, url) = try makePool(delay: 0.1)
        defer { try? FileManager.default.removeItem(at: url) }
        pool.close()
        #expect(pool.checkOut() == nil)
        #expect(pool.idleCount == 0)
    }
}

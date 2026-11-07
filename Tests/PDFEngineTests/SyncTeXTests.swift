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
import Testing
import SyncTeXLink
@testable import PDFEngine

/// A SyncTeX file as pdfTeX writes one, for a two-page `main.pdf` built from `main.tex`, which
/// `\input`s `sub/chapter.tex`. Positions are in scaled points (65781.76 to a PDF point),
/// measured from the page's top-left, as pdfTeX records them.
enum SyncTeXFixture {
    static func sp(_ points: CGFloat) -> Int { Int((points * 65781.76).rounded()) }

    /// An hbox for `line` of input `tag`: left edge `x`, baseline `y`, `width` wide, rising 8 and
    /// dropping 2 points.
    static func hbox(tag: Int, line: Int, x: CGFloat, y: CGFloat, width: CGFloat) -> String {
        "(\(tag),\(line):\(sp(x)),\(sp(y)):\(sp(width)),\(sp(8)),\(sp(2))\nh\(tag),\(line):\(sp(x)),\(sp(y)):\(sp(width)),\(sp(8)),\(sp(2))\n)\n"
    }

    static func contents(mainPath: String) -> String {
        """
        SyncTeX Version:1
        Input:1:\(mainPath)
        Input:2:./sub/chapter.tex
        Output:pdf
        Magnification:1000
        Unit:1
        X Offset:0
        Y Offset:0
        Content:
        !200
        {1
        [1,3:0,0:\(sp(612)),\(sp(792)),0
        \(hbox(tag: 1, line: 10, x: 72, y: 100, width: 300))\(hbox(tag: 1, line: 11, x: 72, y: 120, width: 250))]
        }1
        !100
        {2
        [1,3:0,0:\(sp(612)),\(sp(792)),0
        \(hbox(tag: 2, line: 5, x: 72, y: 200, width: 400))\(hbox(tag: 1, line: 30, x: 72, y: 400, width: 200))]
        }2
        Postamble:
        Count:12
        !50
        Post scriptum:

        """
    }

    /// `main.pdf`, `main.tex`, `sub/chapter.tex` and `main.synctex` in a new folder.
    static func make(in dir: URL, gzip: Bool = false) throws -> URL {
        let pdf = dir.appendingPathComponent("main.pdf")
        makeLabelledPDF(at: pdf, labels: ["First page", "Second page"])
        let main = dir.appendingPathComponent("main.tex")
        try "\\documentclass{article}\n".write(to: main, atomically: true, encoding: .utf8)
        try FileManager.default.createDirectory(at: dir.appendingPathComponent("sub"), withIntermediateDirectories: true)
        try "Chapter\n".write(to: dir.appendingPathComponent("sub/chapter.tex"), atomically: true, encoding: .utf8)
        let synctex = dir.appendingPathComponent("main.synctex")
        try contents(mainPath: main.path).write(to: synctex, atomically: true, encoding: .utf8)
        if gzip {
            let process = Process()
            process.executableURL = URL(fileURLWithPath: "/usr/bin/gzip")
            process.arguments = ["-f", synctex.path]
            try process.run()
            process.waitUntilExit()
        }
        return pdf
    }
}

@Suite struct SyncTeXIndexTests {
    @Test(arguments: [false, true]) func forwardAndBackward(gzip: Bool) throws {
        let dir = try makeScratchDirectory()
        defer { try? FileManager.default.removeItem(at: dir) }
        let pdf = try SyncTeXFixture.make(in: dir, gzip: gzip)
        let file = try #require(SyncTeXFile.find(forPDF: pdf.path))
        #expect(file.url.lastPathComponent == (gzip ? "main.synctex.gz" : "main.synctex"))
        let index = try #require(SyncTeXIndex(file: file, pdfPath: pdf.path))
        #expect(index.pageCount == 2)
        #expect(index.matches(pageCount: 2))
        #expect(!index.matches(pageCount: 1))

        let main = dir.appendingPathComponent("main.tex").path
        let boxes = index.boxes(source: main, line: 11, column: nil, pageHint: 0)
        let box = try #require(boxes.first)
        #expect(box.pageIndex == 0)
        #expect(abs(box.rect.minX - 72) < 0.1 && abs(box.rect.minY - 112) < 0.1)
        #expect(abs(box.rect.width - 250) < 0.1 && abs(box.rect.height - 10) < 0.1)

        // An \input file, named as TeX recorded it (./sub/chapter.tex) or as the editor has it.
        let chapter = dir.appendingPathComponent("sub/chapter.tex").path
        #expect(index.boxes(source: chapter, line: 5, column: nil, pageHint: 0).first?.pageIndex == 1)

        // Backward: the second line on page 1, and the chapter's line on page 2.
        let back = try #require(index.sourceLocation(pageIndex: 0, point: CGPoint(x: 100, y: 118)))
        #expect(back.file == main && back.line == 11)
        let backChapter = try #require(index.sourceLocation(pageIndex: 1, point: CGPoint(x: 100, y: 198)))
        #expect(URL(fileURLWithPath: backChapter.file).standardizedFileURL.path
                == URL(fileURLWithPath: chapter).standardizedFileURL.path)
        #expect(backChapter.line == 5)
    }

    /// TeX and the editor can name the same file differently (/var and /private/var, as the
    /// temporary folder is): the file on disk decides.
    @Test func aDifferentNameForTheSameFileMatches() throws {
        let dir = try makeScratchDirectory()
        defer { try? FileManager.default.removeItem(at: dir) }
        let pdf = try SyncTeXFixture.make(in: dir)
        let real = try #require(realpath(dir.appendingPathComponent("main.tex").path, nil).map { pointer in
            defer { free(pointer) }
            return String(cString: pointer)
        })
        let synctex = dir.appendingPathComponent("main.synctex")
        try SyncTeXFixture.contents(mainPath: real).write(to: synctex, atomically: true, encoding: .utf8)
        let index = try #require(SyncTeXFile.find(forPDF: pdf.path).flatMap { SyncTeXIndex(file: $0, pdfPath: pdf.path) })
        let editorName = dir.appendingPathComponent("main.tex").path
        #expect(editorName != real)
        #expect(index.boxes(source: editorName, line: 11, column: nil, pageHint: 0).first?.pageIndex == 0)
        #expect(index.boxes(source: real, line: 30, column: nil, pageHint: 0).first?.pageIndex == 1)
    }

    /// Only the PDF a SyncTeX file is named after uses it.
    @Test func otherPDFsInTheFolderDontUseIt() throws {
        let dir = try makeScratchDirectory()
        defer { try? FileManager.default.removeItem(at: dir) }
        _ = try SyncTeXFixture.make(in: dir)
        let other = dir.appendingPathComponent("handout.pdf")
        makeLabelledPDF(at: other, labels: ["Handout"])
        #expect(SyncTeXFile.find(forPDF: other.path) == nil)
    }

    @Test func aBuildFolderAndABusyFileAreFound() throws {
        let dir = try makeScratchDirectory()
        defer { try? FileManager.default.removeItem(at: dir) }
        let pdf = try SyncTeXFixture.make(in: dir)
        let build = dir.appendingPathComponent("build")
        try FileManager.default.createDirectory(at: build, withIntermediateDirectories: true)
        try FileManager.default.moveItem(at: dir.appendingPathComponent("main.synctex"), to: build.appendingPathComponent("main.synctex"))
        let file = try #require(SyncTeXFile.find(forPDF: pdf.path))
        #expect(file.url.deletingLastPathComponent().lastPathComponent == "build")
        #expect(!file.isBusy)
        #expect(SyncTeXIndex(file: file, pdfPath: pdf.path)?.pageCount == 2)

        try Data().write(to: build.appendingPathComponent("main.synctex(busy)"))
        #expect(SyncTeXFile.find(forPDF: pdf.path)?.isBusy == true)
    }

    @Test func aRewrittenFileIsNoLongerCurrent() throws {
        let dir = try makeScratchDirectory()
        defer { try? FileManager.default.removeItem(at: dir) }
        let pdf = try SyncTeXFixture.make(in: dir)
        let index = try #require(SyncTeXFile.find(forPDF: pdf.path).flatMap { SyncTeXIndex(file: $0, pdfPath: pdf.path) })
        #expect(index.isCurrent)
        let synctex = dir.appendingPathComponent("main.synctex")
        try (String(contentsOf: synctex, encoding: .utf8) + "\n").write(to: synctex, atomically: true, encoding: .utf8)
        #expect(!index.isCurrent)
    }

    @Test func garbageIsRefused() throws {
        let dir = try makeScratchDirectory()
        defer { try? FileManager.default.removeItem(at: dir) }
        let pdf = dir.appendingPathComponent("junk.pdf")
        makeLabelledPDF(at: pdf, labels: ["Junk"])
        for junk in ["", "SyncTeX Version:1\n", "not synctex at all\n{1\n(((\n", String(repeating: "{", count: 10_000)] {
            try junk.write(to: dir.appendingPathComponent("junk.synctex"), atomically: true, encoding: .utf8)
            let file = try #require(SyncTeXFile.find(forPDF: pdf.path))
            #expect(SyncTeXIndex(file: file, pdfPath: pdf.path) == nil)
        }
    }
}

@Suite struct SyncTeXPageMappingTests {
    /// A PDF page with the given boxes and rotation, written by hand (MuPDF rebuilds the xref).
    private func makePDF(at url: URL, mediaBox: String, cropBox: String?, rotate: Int) throws {
        let crop = cropBox.map { "/CropBox [\($0)]" } ?? ""
        let pdf = """
        %PDF-1.7
        1 0 obj << /Type /Catalog /Pages 2 0 R >> endobj
        2 0 obj << /Type /Pages /Kids [3 0 R] /Count 1 >> endobj
        3 0 obj << /Type /Page /Parent 2 0 R /MediaBox [\(mediaBox)] \(crop) /Rotate \(rotate) >> endobj
        trailer << /Root 1 0 R >>
        %%EOF
        """
        try pdf.write(to: url, atomically: true, encoding: .ascii)
    }

    @Test func aPlainPageIsTheSameSpace() throws {
        let dir = try makeScratchDirectory()
        defer { try? FileManager.default.removeItem(at: dir) }
        let url = dir.appendingPathComponent("plain.pdf")
        try makePDF(at: url, mediaBox: "0 0 612 792", cropBox: nil, rotate: 0)
        let mapping = try #require(PDFDocumentCore(filePath: url.path).syncTeXMapping(for: 0))
        #expect(mapping.pagePoint(fromSyncTeX: CGPoint(x: 72, y: 100)) == CGPoint(x: 72, y: 100))
    }

    /// SyncTeX measures from the MediaBox's corner; page space starts at the CropBox's.
    @Test func aCropBoxMovesTheOrigin() throws {
        let dir = try makeScratchDirectory()
        defer { try? FileManager.default.removeItem(at: dir) }
        let url = dir.appendingPathComponent("cropped.pdf")
        try makePDF(at: url, mediaBox: "0 0 612 792", cropBox: "50 60 562 732", rotate: 0)
        let doc = try PDFDocumentCore(filePath: url.path)
        let mapping = try #require(doc.syncTeXMapping(for: 0))
        let page = mapping.pagePoint(fromSyncTeX: CGPoint(x: 60, y: 70))
        #expect(abs(page.x - 10) < 0.01 && abs(page.y - 10) < 0.01)
        let back = mapping.syncTeXPoint(fromPage: page)
        #expect(abs(back.x - 60) < 0.01 && abs(back.y - 70) < 0.01)
    }

    /// On a page turned 90° clockwise, the top-left of the unturned page is the top-right.
    @Test func aRotatedPageTurnsWithIt() throws {
        let dir = try makeScratchDirectory()
        defer { try? FileManager.default.removeItem(at: dir) }
        let url = dir.appendingPathComponent("rotated.pdf")
        try makePDF(at: url, mediaBox: "0 0 612 792", cropBox: "50 60 562 732", rotate: 90)
        let doc = try PDFDocumentCore(filePath: url.path)
        let mapping = try #require(doc.syncTeXMapping(for: 0))
        let bounds = doc.pageBounds[0]
        let corner = mapping.pagePoint(fromSyncTeX: CGPoint(x: 50, y: 60))
        #expect(abs(corner.x - bounds.maxX) < 0.01 && abs(corner.y - bounds.minY) < 0.01)
        let rect = mapping.pageRect(fromSyncTeX: CGRect(x: 100, y: 100, width: 200, height: 10))
        #expect(abs(rect.width - 10) < 0.01 && abs(rect.height - 200) < 0.01)
        let p = CGPoint(x: 123, y: 456)
        let round = mapping.syncTeXPoint(fromPage: mapping.pagePoint(fromSyncTeX: p))
        #expect(abs(round.x - p.x) < 0.01 && abs(round.y - p.y) < 0.01)
    }
}

@Suite struct SyncTeXForwardRequestTests {
    private let pdf = "/Users/example/Papers/My Paper.pdf"
    private let source = "/Users/example/Papers/sections/intro & more+.tex"

    @Test func roundTripsThroughItsURL() throws {
        let request = try #require(SyncTeXForwardRequest(pdfPath: pdf, line: 42, column: 3, sourcePath: source, inBackground: true, reloads: true))
        let url = request.url
        #expect(url.scheme == "vectorpdf" && url.host == "synctex")
        #expect(SyncTeXForwardRequest(url: url) == request)
        let plain = try #require(SyncTeXForwardRequest(pdfPath: pdf, line: 1))
        #expect(SyncTeXForwardRequest(url: plain.url) == plain)
    }

    @Test(arguments: [
        "vectorpdf://synctex?pdf=%2Ftmp%2Fa.pdf&line=1&extra=1",          // unknown key
        "vectorpdf://synctex?pdf=%2Ftmp%2Fa.pdf&line=1&line=2",           // repeated key
        "vectorpdf://synctex?pdf=%2Ftmp%2Fa.pdf",                          // no line
        "vectorpdf://synctex?line=3",                                      // no pdf
        "vectorpdf://synctex?pdf=a.pdf&line=3",                            // relative path
        "vectorpdf://synctex?pdf=%2Ftmp%2Fa.txt&line=3",                   // not a PDF
        "vectorpdf://synctex?pdf=%2Ftmp%2Fa%00.pdf&line=3",                // NUL
        "vectorpdf://synctex?pdf=%2Ftmp%2Fa%0A.pdf&line=3",                // newline
        "vectorpdf://synctex?pdf=%2Ftmp%2Fa.pdf&line=0",                   // line 0
        "vectorpdf://synctex?pdf=%2Ftmp%2Fa.pdf&line=-4",                  // negative
        "vectorpdf://synctex?pdf=%2Ftmp%2Fa.pdf&line=+4",                  // sign
        "vectorpdf://synctex?pdf=%2Ftmp%2Fa.pdf&line=4%20",                // trailing space
        "vectorpdf://synctex?pdf=%2Ftmp%2Fa.pdf&line=99999999999999999999",// overflow
        "vectorpdf://synctex?pdf=%2Ftmp%2Fa.pdf&line=0x10",                // hex
        "vectorpdf://synctex?pdf=%2Ftmp%2Fa.pdf&line=3&column=x",          // bad column
        "vectorpdf://synctex?pdf=%2Ftmp%2Fa.pdf&line=3&background=yes",    // flag not "1"
        "vectorpdf://synctex?pdf=%2Ftmp%2Fa.pdf&line=3&source=rel.tex",    // relative source
        "vectorpdf://synctex?pdf=&line=3",                                 // empty value
        "vectorpdf://synctex?pdf&line=3",                                  // no value
        "vectorpdf://synctex?pdf=%ZZ&line=3",                              // bad escape
        "vectorpdf://synctex/other?pdf=%2Ftmp%2Fa.pdf&line=3",             // path
        "vectorpdf://synctex?pdf=%2Ftmp%2Fa.pdf&line=3#frag",              // fragment
        "vectorpdf://user@synctex?pdf=%2Ftmp%2Fa.pdf&line=3",              // user
        "vectorpdf://synctex:99?pdf=%2Ftmp%2Fa.pdf&line=3",                // port
        "vectorpdf://open?pdf=%2Ftmp%2Fa.pdf&line=3",                      // host
        "http://synctex?pdf=%2Ftmp%2Fa.pdf&line=3",                        // scheme
        "vectorpdf://synctex",                                             // nothing
        "vectorpdf://synctex?pdf=%2F..%2F..%2F&line=3",                    // resolves to /
    ])
    func refusesMalformedURLs(_ text: String) throws {
        let url = try #require(URL(string: text))
        #expect(SyncTeXForwardRequest(url: url) == nil)
    }

    @Test func refusesOverlongInput() throws {
        let longPath = "/" + String(repeating: "a", count: SyncTeXForwardRequest.maximumPathLength) + ".pdf"
        #expect(SyncTeXForwardRequest(pdfPath: longPath, line: 1) == nil)
        let huge = "vectorpdf://synctex?pdf=%2Ftmp%2Fa.pdf&line=3&source=%2F" + String(repeating: "b", count: 10_000)
        #expect(SyncTeXForwardRequest(url: try #require(URL(string: huge))) == nil)
    }

    @Test func standardizesPaths() throws {
        let url = try #require(URL(string: "vectorpdf://synctex?pdf=%2Ftmp%2Fx%2F..%2F.%2Fa.pdf&line=3"))
        #expect(SyncTeXForwardRequest(url: url)?.pdfPath == "/tmp/a.pdf")
        // Only "." and "..": /private stays, as TeX may have recorded it.
        #expect(SyncTeXForwardRequest(pdfPath: "/private/tmp/a.pdf", line: 1)?.pdfPath == "/private/tmp/a.pdf")
    }

    @Test func readsSkimsDisplaylineArguments() {
        let cwd = "/Users/example/Papers"
        #expect(SyncTeXForwardRequest.parseCommandLine(["12", "paper.pdf", "intro.tex"], currentDirectory: cwd)
                == .request(SyncTeXForwardRequest(pdfPath: "/Users/example/Papers/paper.pdf", line: 12, sourcePath: "/Users/example/Papers/intro.tex")!))
        #expect(SyncTeXForwardRequest.parseCommandLine(["-r", "-b", "-g", "7:4", "/tmp/out/paper"], currentDirectory: cwd)
                == .request(SyncTeXForwardRequest(pdfPath: "/tmp/out/paper.pdf", line: 7, column: 4, inBackground: true, reloads: true)!))
        #expect(SyncTeXForwardRequest.parseCommandLine(["-h"], currentDirectory: cwd) == .help)
        for bad in [[], ["12"], ["x", "a.pdf"], ["-z", "1", "a.pdf"], ["0", "a.pdf"], ["1:y", "a.pdf"], ["1", "a.pdf", "b.tex", "c"]] {
            guard case .invalid = SyncTeXForwardRequest.parseCommandLine(bad, currentDirectory: cwd) else {
                Issue.record("\(bad) should be refused")
                continue
            }
        }
    }
}

@Suite(.serialized) struct SyncTeXViewModelTests {
    /// A view model showing `pdf`, set up directly rather than through `loadDocument`, which would
    /// make it the app's active one and upset tests of the shared coordinator running alongside.
    @MainActor private func viewModel(showing pdf: URL) throws -> PDFViewerViewModel {
        let vm = PDFViewerViewModel()
        vm.isTransientWindow = true
        let doc = try PDFDocumentCore(filePath: pdf.path)
        vm.document = doc
        vm.recomputeEffectiveLayout()
        vm.loadedFileModificationDate = PDFViewerViewModel.modificationDate(ofFileAt: pdf.path)
        vm.refreshSyncTeXAvailability()
        return vm
    }

    /// Forward search goes to the line's page and asks for its box to be shown; a line TeX
    /// recorded nothing for goes to the nearest one below it.
    @Test @MainActor func forwardSearchRevealsTheLine() async throws {
        let dir = try makeScratchDirectory()
        defer { try? FileManager.default.removeItem(at: dir) }
        let pdf = try SyncTeXFixture.make(in: dir)
        let vm = try viewModel(showing: pdf)
        #expect(vm.hasSyncTeX)

        let main = dir.appendingPathComponent("main.tex").path
        #expect(await vm.showSyncTeXLocation(source: main, line: 30, column: nil))
        let reveal = try #require(vm.syncTeXReveal)
        #expect(reveal.pageIndex == 1 && vm.currentPageIndex == 1)
        let rect = try #require(reveal.rects.first)
        #expect(abs(rect.minX - 72) < 0.5 && abs(rect.minY - 392) < 0.5 && abs(rect.width - 200) < 0.5)

        // Line 9 has nothing; line 10 is the nearest below.
        #expect(await vm.showSyncTeXLocation(source: main, line: 9, column: nil))
        #expect(vm.syncTeXReveal?.pageIndex == 0 && vm.syncTeXReveal?.token == reveal.token + 1)
        // Without a source, the main file (the PDF's name with .tex).
        #expect(await vm.showSyncTeXLocation(source: nil, line: 11, column: nil))
        // A file TeX never read finds nothing.
        #expect(await vm.showSyncTeXLocation(source: dir.appendingPathComponent("other.tex").path, line: 10, column: nil) == false)
    }

    @Test @MainActor func backwardSearchFindsTheSourceLine() async throws {
        let dir = try makeScratchDirectory()
        defer { try? FileManager.default.removeItem(at: dir) }
        let pdf = try SyncTeXFixture.make(in: dir)
        let vm = try viewModel(showing: pdf)
        let location = try #require(await vm.syncTeXSourceLocation(pageIndex: 0, pagePoint: CGPoint(x: 150, y: 97)))
        #expect(location.file == dir.appendingPathComponent("main.tex").path && location.line == 10)
    }

    /// A SyncTeX file describing more pages than the PDF has belongs to another document.
    @Test @MainActor func aSyncTeXFileForAnotherDocumentIsIgnored() async throws {
        let dir = try makeScratchDirectory()
        defer { try? FileManager.default.removeItem(at: dir) }
        let pdf = try SyncTeXFixture.make(in: dir)
        makeLabelledPDF(at: pdf, labels: ["Only page"])
        let vm = try viewModel(showing: pdf)
        #expect(await vm.showSyncTeXLocation(source: nil, line: 10, column: nil) == false)
        #expect(await vm.syncTeXSourceLocation(pageIndex: 0, pagePoint: CGPoint(x: 150, y: 97)) == nil)
    }

    @Test func boxesOnOneLineMerge() {
        let merged = PDFViewerViewModel.mergedLines([
            CGRect(x: 200, y: 100, width: 50, height: 10), CGRect(x: 72, y: 101, width: 100, height: 10),
            CGRect(x: 72, y: 130, width: 100, height: 10),
        ])
        #expect(merged == [CGRect(x: 72, y: 100, width: 178, height: 11), CGRect(x: 72, y: 130, width: 100, height: 10)])
    }

    @Test func aHalfWrittenPDFIsNotComplete() throws {
        let dir = try makeScratchDirectory()
        defer { try? FileManager.default.removeItem(at: dir) }
        let pdf = dir.appendingPathComponent("a.pdf")
        makeLabelledPDF(at: pdf, labels: ["A"])
        #expect(PDFViewerViewModel.pdfLooksComplete(atPath: pdf.path))
        let data = try Data(contentsOf: pdf)
        try data.prefix(data.count / 2).write(to: pdf)
        #expect(!PDFViewerViewModel.pdfLooksComplete(atPath: pdf.path))
    }
}

@Suite struct EditorLauncherTests {
    private let location = SyncTeXSourceLocation(file: "/Users/example/My Papers/it's \"here\"; rm -rf ~.tex", line: 12, column: nil)

    /// File names are filled in within an argument, never passed through a shell.
    @Test func aFileNameStaysOneArgument() throws {
        #expect(try EditorLauncher.arguments(for: "code --goto %file:%line", location: location)
                == ["code", "--goto", "/Users/example/My Papers/it's \"here\"; rm -rf ~.tex:12"])
        #expect(try EditorLauncher.arguments(for: "bbedit +%line %file", location: location)
                == ["bbedit", "+12", location.file])
        #expect(try EditorLauncher.arguments(for: "ed %column", location: location) == ["ed", "0"])
    }

    @Test func splitsLikeAShellWithoutBeingOne() throws {
        #expect(try EditorLauncher.split(#""/Applications/My Editor.app/bin/ed" -l '%line' a\ b $HOME;x"#)
                == ["/Applications/My Editor.app/bin/ed", "-l", "%line", "a b", "$HOME;x"])
        #expect(try EditorLauncher.split("   ") == [])
        #expect(throws: EditorLauncher.LaunchError.unbalancedQuotes) { try EditorLauncher.split("ed \"%file") }
        #expect(throws: EditorLauncher.LaunchError.emptyCommand) { try EditorLauncher.arguments(for: "", location: location) }
    }

    @Test func findsPrograms() {
        #expect(EditorLauncher.resolve(program: "ls", knownLocations: [], searchPath: []) == "/bin/ls")
        #expect(EditorLauncher.resolve(program: "/bin/ls", knownLocations: [], searchPath: []) == "/bin/ls")
        #expect(EditorLauncher.resolve(program: "zed", knownLocations: ["/bin/ls"], searchPath: []) != nil)
        #expect(EditorLauncher.resolve(program: "no-such-editor-xyz", knownLocations: ["/nonexistent/cli"], searchPath: []) == nil)
    }

    @Test func aMissingSourceFileIsReported() {
        #expect(throws: EditorLauncher.LaunchError.sourceNotFound(location.file)) {
            try EditorLauncher.open(location, command: "true %file", knownLocations: [])
        }
    }

    /// The editor gets the file and line as arguments, and runs.
    @Test func runsTheEditor() async throws {
        let dir = try makeScratchDirectory()
        defer { try? FileManager.default.removeItem(at: dir) }
        let source = dir.appendingPathComponent("a b.tex")
        try "x\n".write(to: source, atomically: true, encoding: .utf8)
        let script = dir.appendingPathComponent("editor.sh")
        let out = dir.appendingPathComponent("out.txt")
        try "#!/bin/sh\nprintf '%s|' \"$@\" > \"\(out.path)\"\n".write(to: script, atomically: true, encoding: .utf8)
        try FileManager.default.setAttributes([.posixPermissions: 0o755], ofItemAtPath: script.path)
        try EditorLauncher.open(SyncTeXSourceLocation(file: source.path, line: 7, column: nil),
                                command: "'\(script.path)' +%line %file", knownLocations: [])
        for _ in 0..<50 where !FileManager.default.fileExists(atPath: out.path) {
            try await Task.sleep(nanoseconds: 50_000_000)
        }
        try await Task.sleep(nanoseconds: 50_000_000)
        #expect(try String(contentsOf: out, encoding: .utf8) == "+7|\(source.path)|")
    }
}

/// Real pdfTeX output, checked against the `synctex` tool TeX comes with and against where MuPDF
/// finds the text. Needs TeX; run with `VECTORPDF_TEX_TESTS=1 swift test --filter RealSyncTeX`.
@Suite(.needsTeX) struct RealSyncTeXTests {
    static let texbin = "/Library/TeX/texbin"

    /// Runs `tool` from TeX's folder in `dir`, returning what it printed.
    @discardableResult
    static func run(_ tool: String, _ arguments: [String], in dir: URL) throws -> String {
        let process = Process()
        process.executableURL = URL(fileURLWithPath: "\(texbin)/\(tool)")
        process.arguments = arguments
        process.currentDirectoryURL = dir
        let pipe = Pipe()
        process.standardOutput = pipe
        process.standardError = FileHandle.nullDevice
        try process.run()
        let output = pipe.fileHandleForReading.readDataToEndOfFile()
        process.waitUntilExit()
        return String(decoding: output, as: UTF8.self)
    }

    /// A three-page paper in a folder with a space in its name, `\input`ting a chapter.
    static func compile(in dir: URL) throws -> URL {
        let folder = dir.appendingPathComponent("my paper", isDirectory: true)
        try FileManager.default.createDirectory(at: folder.appendingPathComponent("chapters"), withIntermediateDirectories: true)
        try """
        \\documentclass[11pt]{article}
        \\usepackage[margin=1in]{geometry}
        \\begin{document}
        \\section{Introduction}
        This is the first paragraph of the introduction. It runs long enough
        to wrap across several lines, so that a line of source and a line of
        output are not the same thing, which is what SyncTeX is for.

        % a comment line
        Second paragraph, short.

        \\input{chapters/methods}

        \\section{Conclusion}
        The end.
        \\end{document}

        """.write(to: folder.appendingPathComponent("paper.tex"), atomically: true, encoding: .utf8)
        var methods = "\\section{Methods}\nWe describe the methods here.\n\n"
        for i in 1...60 { methods += "Filler sentence number \(i) to push the text onto another page, again and again.\n\n" }
        methods += "The last line of the methods chapter.\n"
        try methods.write(to: folder.appendingPathComponent("chapters/methods.tex"), atomically: true, encoding: .utf8)
        try run("pdflatex", ["-synctex=1", "-interaction=nonstopmode", "paper.tex"], in: folder)
        return folder.appendingPathComponent("paper.pdf")
    }

    /// `synctex view`'s first box for a line: page (0-based), left, width.
    static func officialBox(line: Int, source: String, pdf: URL) throws -> (page: Int, h: CGFloat, width: CGFloat)? {
        let output = try run("synctex", ["view", "-i", "\(line):0:\(source)", "-o", pdf.path], in: pdf.deletingLastPathComponent())
        var values: [String: String] = [:]
        for row in output.split(separator: "\n") {
            let parts = row.split(separator: ":", maxSplits: 1).map(String.init)
            if parts.count == 2, values[parts[0]] == nil { values[parts[0]] = parts[1] }
        }
        guard let page = values["Page"].flatMap(Int.init), let h = values["h"].flatMap(Double.init),
              let width = values["W"].flatMap(Double.init) else { return nil }
        return (page - 1, CGFloat(h), CGFloat(width))
    }

    @Test @MainActor func matchesTheOfficialToolAndTheText() async throws {
        let dir = try makeScratchDirectory()
        defer { try? FileManager.default.removeItem(at: dir) }
        let pdf = try Self.compile(in: dir)
        let folder = pdf.deletingLastPathComponent()
        let doc = try PDFDocumentCore(filePath: pdf.path)
        #expect(doc.pageCount >= 2)
        let index = try #require(SyncTeXFile.find(forPDF: pdf.path).flatMap { SyncTeXIndex(file: $0, pdfPath: pdf.path) })
        #expect(index.matches(pageCount: doc.pageCount))

        let main = folder.appendingPathComponent("paper.tex").path
        let chapter = folder.appendingPathComponent("chapters/methods.tex").path
        let lastLine = 2 + 60 * 2 + 2  // "The last line of the methods chapter."
        for (source, line, text) in [(main, 5, "first paragraph"), (main, 10, "Second paragraph"),
                                     (chapter, 2, "We describe the methods"), (chapter, lastLine, "The last line"),
                                     (main, 15, "The end.")] {
            let boxes = index.boxes(source: source, line: line, column: nil, pageHint: 0)
            let box = try #require(boxes.first, "nothing for \(source):\(line)")
            // The same as TeX's own tool says.
            let official = try #require(try Self.officialBox(line: line, source: source, pdf: pdf))
            #expect(box.pageIndex == official.page, "page for line \(line)")
            #expect(abs(box.rect.minX - official.h) < 0.5 && abs(box.rect.width - official.width) < 0.5, "box for line \(line)")

            // Over the text that line made, as MuPDF finds it on the page.
            let mapping = try #require(doc.syncTeXMapping(for: box.pageIndex))
            let onPage = boxes.map { mapping.pageRect(fromSyncTeX: $0.rect) }.reduce(CGRect.null) { $0.union($1) }
            let page = try #require(doc.loadStructuredPage(for: box.pageIndex))
            let textLine = try #require(page.blocks.flatMap(\.lines).first { $0.text.contains(text) }, "no “\(text)” on page \(box.pageIndex)")
            #expect(onPage.insetBy(dx: -2, dy: -2).intersects(textLine.bbox), "“\(text)”: box \(onPage) vs text \(textLine.bbox)")

            // And back: the middle of that text gives the line.
            let back = try #require(index.sourceLocation(pageIndex: box.pageIndex, point: mapping.syncTeXPoint(fromPage: CGPoint(x: textLine.bbox.midX, y: textLine.bbox.midY))))
            #expect(Self.sameFile(back.file, source), "\(back.file) vs \(source)")
            #expect(back.line == line || (source == main && (5...7).contains(back.line) && (5...7).contains(line)),
                    "line \(line) came back as \(back.line)")
        }
    }

    static func sameFile(_ a: String, _ b: String) -> Bool {
        var x = stat(), y = stat()
        return stat(a, &x) == 0 && stat(b, &y) == 0 && x.st_dev == y.st_dev && x.st_ino == y.st_ino
    }
}

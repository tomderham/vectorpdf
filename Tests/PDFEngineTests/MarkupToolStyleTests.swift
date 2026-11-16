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

/// Each markup tool keeps its own color and width.
@MainActor
@Suite struct MarkupToolStyleTests {
    @Test func eachToolStartsWithItsOwnColor() {
        let vm = PDFViewerViewModel()
        let expected: [(CanvasMode, AnnotationColor)] = [
            (.select, .yellow), (.draw, .red), (.shape, .red), (.text, .black), (.callout, .black), (.note, .yellow),
        ]
        for (mode, color) in expected {
            vm.canvasMode = mode
            #expect(vm.selectedAnnotationColor == color, "\(mode)")
        }
        #expect(vm.toolColor(.underline) == .red && vm.toolColor(.strikethrough) == .red)
        #expect(vm.measurementColor == .gray && vm.measurementStrokeWidth == 1.5)
    }

    @Test func choosingAColorForOneToolLeavesTheOthers() {
        let vm = PDFViewerViewModel()
        vm.canvasMode = .draw
        vm.selectedAnnotationColor = .blue
        vm.drawStrokeWidth = 0.5
        vm.canvasMode = .shape
        #expect(vm.selectedAnnotationColor == .red && vm.drawStrokeWidth == 2.5)
        vm.canvasMode = .select
        #expect(vm.selectedAnnotationColor == .yellow)
        vm.canvasMode = .draw
        #expect(vm.selectedAnnotationColor == .blue && vm.drawStrokeWidth == 0.5)
    }

    @Test func recoloringASelectedAnnotationIsForThatAnnotationOnly() {
        let vm = PDFViewerViewModel()
        let shape = PDFAnnotation(pageIndex: 0, type: .square, rect: CGRect(x: 0, y: 0, width: 50, height: 50), color: .red)
        vm.pageAnnotations[0] = [shape]
        // Selected in Text Selection mode: the toolbar shows and changes it, not the highlighter.
        vm.inspectedAnnotation = InspectedAnnotation(id: shape.id, pageIndex: 0)
        vm.selectedAnnotationColor = .green
        #expect(vm.toolColor(.highlight) == .yellow)
        vm.inspectedAnnotation = nil
        #expect(vm.selectedAnnotationColor == .yellow)
    }

    @Test func recoloringWhatAToolJustMadeIsForTheToolToo() {
        let vm = PDFViewerViewModel()
        vm.canvasMode = .shape
        let shape = PDFAnnotation(pageIndex: 0, type: .square, rect: CGRect(x: 0, y: 0, width: 50, height: 50), color: .red)
        vm.pageAnnotations[0] = [shape]
        vm.inspectedAnnotation = InspectedAnnotation(id: shape.id, pageIndex: 0)
        vm.selectedAnnotationColor = .purple
        #expect(vm.toolColor(.shape) == .purple)
    }

    @Test func aColorChosenFromAMenuIsKeptForThatMarkup() {
        let vm = PDFViewerViewModel()
        vm.rememberToolColor(.blue, for: .underline)
        #expect(vm.toolColor(.underline) == .blue)
        #expect(vm.toolColor(.strikethrough) == .red)
        // The highlighter's shows straight away in Text Selection mode.
        vm.rememberToolColor(.green, for: .highlight)
        #expect(vm.selectedAnnotationColor == .green)
    }

    @Test func stylesAreKeptBetweenLaunches() throws {
        let suite = "vpdf.toolstyles.\(UUID().uuidString)"
        let defaults = try #require(UserDefaults(suiteName: suite))
        defer { defaults.removePersistentDomain(forName: suite) }
        do {
            let styles = MarkupToolStyles(defaults: defaults)
            styles[.pen] = MarkupToolStyle(color: .blue, width: 0.75)
            styles[.measurement] = MarkupToolStyle(color: .black, width: 0.25)
        }
        let reopened = MarkupToolStyles(defaults: defaults)
        #expect(reopened[.pen] == MarkupToolStyle(color: .blue, width: 0.75))
        #expect(reopened[.measurement] == MarkupToolStyle(color: .black, width: 0.25))
        #expect(reopened[.highlight] == MarkupToolStyles.defaultStyles[.highlight])
    }
}

@MainActor
@Suite struct ChoosingAToolTests {
    @Test func choosingAToolPutsDownTheSelectionAndShowsTheToolsColor() async throws {
        let fixture = try await CanvasFixture(view: .single)
        defer { fixture.close() }
        let shape = try #require(fixture.vm.addShapeAnnotation(pageIndex: 0, shape: .rectangle, from: CGPoint(x: 100, y: 100), to: CGPoint(x: 200, y: 200), strokeWidth: 2, lineEnding: .none, color: .green))
        fixture.canvas.selectedAnnotation = (shape.id, 0)
        fixture.vm.selectedAnnotationColor = .green
        fixture.vm.canvasMode = .draw
        try await Task.sleep(nanoseconds: 100_000_000)
        #expect(fixture.canvas.selectedAnnotation == nil)
        #expect(fixture.vm.selectedAnnotationColor == .red)
        // The shape kept its own color.
        #expect(fixture.vm.pageAnnotations[0]?.first { $0.id == shape.id }?.color == .green)
    }
}

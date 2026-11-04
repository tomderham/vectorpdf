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
import Combine
import CoreGraphics
import MuPDFBridge

extension PDFCanvasView {
    // MARK: - Keyboard Shortcuts
    
    public override func keyDown(with event: NSEvent) {
        // Return key: complete polyline perimeter or polygon area takeoff
        if event.keyCode == 36 {
            if viewModel.canvasMode == .measurePerimeter && currentMeasurePoints.count >= 2 {
                commitCurrentPerimeter()
                return
            }
            if viewModel.canvasMode == .measureArea && currentMeasurePoints.count >= 3 {
                commitCurrentArea()
                return
            }
        }

        // Escape key: cancel in-progress measurement
        if event.keyCode == 53 {
            if currentMeasurePage != nil {
                currentMeasurePage = nil
                currentMeasurePoints = []
                currentMeasureCandidatePoint = nil
                needsDisplay = true
                return
            }
        }

        // Filter for user-held modifier keys only. deviceIndependentFlagsMask includes
        // .numericPad and .function which are automatically set by macOS for arrow keys,
        // page navigation keys, and function keys, which would break exact equality checks.
        let flags = event.modifierFlags.intersection([.command, .option, .shift, .control])
        
        // Cmd + S: Save
        if flags == .command && event.charactersIgnoringModifiers == "s" {
            viewModel.saveDocument()
            return
        }
        
        // Shift + Cmd + S: Save As
        if flags == [.command, .shift] && event.charactersIgnoringModifiers == "s" {
            viewModel.saveDocumentAs()
            return
        }
        
        // Cmd + P: Print
        if flags == .command && event.charactersIgnoringModifiers == "p" {
            viewModel.printDocument()
            return
        }
        
        // Cmd + C
        if flags == .command && event.charactersIgnoringModifiers == "c" {
            copy(nil)
            return
        }
        
        // Cmd + G: Find Next
        if flags == .command && event.charactersIgnoringModifiers == "g" {
            viewModel.nextSearchMatch()
            return
        }
        
        // Shift + Cmd + G: Find Previous
        if flags == [.command, .shift] && event.charactersIgnoringModifiers == "g" {
            viewModel.previousSearchMatch()
            return
        }

        // Shift + Cmd + H: Highlight selection in the current colour (same as the menu item)
        if flags == [.command, .shift] && event.charactersIgnoringModifiers?.lowercased() == "h" {
            viewModel.highlightSelection(color: viewModel.selectedAnnotationColor)
            needsDisplay = true
            return
        }

        // Cmd + [ : Back in navigation history
        if flags == .command && event.charactersIgnoringModifiers == "[" {
            viewModel.goBack()
            return
        }

        // Cmd + ] : Forward in navigation history
        if flags == .command && event.charactersIgnoringModifiers == "]" {
            viewModel.goForward()
            return
        }
        
        // Cmd + = / Cmd + +: Zoom In
        if flags.contains(.command) && (event.charactersIgnoringModifiers == "=" || event.charactersIgnoringModifiers == "+") {
            viewModel.zoomIn()
            return
        }
        
        // Cmd + -: Zoom Out
        if flags.contains(.command) && event.charactersIgnoringModifiers == "-" {
            viewModel.zoomOut()
            return
        }

        // Cmd + 9: Zoom to Fit Width
        if flags == .command && event.charactersIgnoringModifiers == "9" {
            viewModel.zoomToFitWidth(viewportWidth: enclosingScrollView?.contentView.bounds.width)
            return
        }

        // Opt + Cmd + 0: Zoom to Fit Page / Window
        if (flags == [.command, .option] || (flags.contains(.command) && flags.contains(.option))) && event.charactersIgnoringModifiers == "0" {
            viewModel.zoomToFitPage(viewportSize: enclosingScrollView?.contentView.bounds.size)
            return
        }
        
        // Cmd + 1: Actual Size (100%), matching View > Actual Size
        if flags == .command && event.charactersIgnoringModifiers == "1" {
            viewModel.resetZoom()
            return
        }

        // Cmd + Up Arrow or Cmd + Home: Go to First Page
        if flags == .command && (event.keyCode == 126 || event.keyCode == 115 || event.specialKey == .upArrow || event.specialKey == .home) {
            viewModel.goToFirstPage()
            return
        }

        // Cmd + Down Arrow or Cmd + End: Go to Last Page
        if flags == .command && (event.keyCode == 125 || event.keyCode == 119 || event.specialKey == .downArrow || event.specialKey == .end) {
            viewModel.goToLastPage()
            return
        }

        // Option + Up Arrow / Option + Left Arrow / Option + Page Up: Previous Page / Spread
        if flags == .option && (event.keyCode == 126 || event.keyCode == 123 || event.specialKey == .upArrow || event.specialKey == .leftArrow || event.specialKey == .pageUp) {
            viewModel.previousPage()
            return
        }

        // Option + Down Arrow / Option + Right Arrow / Option + Page Down: Next Page / Spread
        if flags == .option && (event.keyCode == 125 || event.keyCode == 124 || event.specialKey == .downArrow || event.specialKey == .rightArrow || event.specialKey == .pageDown) {
            viewModel.nextPage()
            return
        }
        
        // Shift + Cmd + A: Toggle Markup Toolbar
        if flags == [.command, .shift] && event.charactersIgnoringModifiers?.lowercased() == "a" {
            viewModel.toggleMarkupToolbar()
            return
        }

        // Delete / Backspace: Delete selected annotation
        if (event.keyCode == 51 || event.keyCode == 117) && activeInlineTextField == nil {
            if selectedAnnotation != nil {
                deleteSelectedAnnotation()
                return
            }
        }

        // Return / Enter: Edit selected annotation
        if (event.keyCode == 36 || event.keyCode == 76) && activeInlineTextField == nil {
            if let sel = selectedAnnotation,
               let list = viewModel.pageAnnotations[sel.pageIndex],
               let annot = list.first(where: { $0.id == sel.id }),
               annot.type == .freeText || annot.type == .callout, !annot.isFromFile {
                startInlineEditing(annotation: annot, pageIndex: sel.pageIndex)
                return
            }
        }

        // Arrow keys: Nudge selected annotation
        if activeInlineTextField == nil, selectedAnnotation != nil, !flags.contains(.command) {
            let step: CGFloat = flags.contains(.shift) ? 10.0 : 1.0
            var dx: CGFloat = 0
            var dy: CGFloat = 0
            switch event.keyCode {
            case 123: dx = -step
            case 124: dx = step
            case 125: dy = -step
            case 126: dy = step
            default: break
            }
            if dx != 0 || dy != 0 {
                nudgeSelectedAnnotation(dx: dx, dy: dy)
                return
            }
        }

        // Navigation: Page / Spread flipping via Arrow keys & Space when not editing or nudging
        if activeInlineTextField == nil && selectedAnnotation == nil {
            if flags.isEmpty {
                // Left Arrow: Always turns to Previous Page / Spread
                if event.keyCode == 123 || event.specialKey == .leftArrow {
                    viewModel.previousPage()
                    return
                }
                // Right Arrow: Always turns to Next Page / Spread
                if event.keyCode == 124 || event.specialKey == .rightArrow {
                    viewModel.nextPage()
                    return
                }
                // Two-Page Mode (fitted spreads): Up / Down / PageUp / PageDown / Space flip facing spreads
                if viewModel.isTwoPageMode {
                    if event.keyCode == 126 || event.specialKey == .upArrow || event.keyCode == 116 || event.specialKey == .pageUp {
                        viewModel.previousPage()
                        return
                    }
                    if event.keyCode == 125 || event.specialKey == .downArrow || event.keyCode == 121 || event.specialKey == .pageDown || event.keyCode == 49 /* Space */ {
                        viewModel.nextPage()
                        return
                    }
                } else {
                    // Single-Page Mode (Smart Adaptive Navigation):
                    let isUp = (event.keyCode == 126 || event.specialKey == .upArrow)
                    let isDown = (event.keyCode == 125 || event.specialKey == .downArrow)
                    let isPageUp = (event.keyCode == 116 || event.specialKey == .pageUp)
                    let isPageDown = (event.keyCode == 121 || event.specialKey == .pageDown || event.keyCode == 49 /* Space */)

                    if isUp || isDown || isPageUp || isPageDown {
                        let clipView = enclosingScrollView?.contentView ?? superview as? NSClipView
                        let viewportBounds = clipView?.bounds ?? bounds
                        let viewportHeight = viewportBounds.height

                        if let pFrame = pageFrame(for: viewModel.currentPageIndex) {
                            let pageFitsInWindow = pFrame.height <= (viewportHeight + 20)
                            
                            if pageFitsInWindow {
                                // Entire page fits vertically: Down/PageDown goes to Next Page, Up/PageUp goes to Previous Page
                                if isDown || isPageDown {
                                    viewModel.nextPage()
                                } else {
                                    viewModel.previousPage()
                                }
                                return
                            } else {
                                // Zoomed in (page is taller than window):
                                let currentScrollY = viewportBounds.origin.y
                                let pageTop = pFrame.origin.y
                                let pageBottom = pFrame.origin.y + pFrame.height
                                let viewportBottom = currentScrollY + viewportHeight

                                if isDown || isPageDown {
                                    // If already at or near the bottom of the current page, advance to the next page
                                    if viewportBottom >= pageBottom - 15 {
                                        viewModel.nextPage()
                                    } else if let clip = clipView, let sv = enclosingScrollView {
                                        let chunkSize = isPageDown ? (viewportHeight * 0.8) : max(100, viewportHeight * 0.35)
                                        let targetY = min(currentScrollY + chunkSize, max(0, frame.height - viewportHeight))
                                        clip.scroll(to: NSPoint(x: viewportBounds.origin.x, y: targetY))
                                        sv.reflectScrolledClipView(clip)
                                    } else {
                                        viewModel.nextPage()
                                    }
                                    return
                                } else if isUp || isPageUp {
                                    // If already at or near the top of the current page, retreat to the previous page
                                    if currentScrollY <= pageTop + 15 {
                                        viewModel.previousPage()
                                    } else if let clip = clipView, let sv = enclosingScrollView {
                                        let chunkSize = isPageUp ? (viewportHeight * 0.8) : max(100, viewportHeight * 0.35)
                                        let targetY = max(0, currentScrollY - chunkSize)
                                        clip.scroll(to: NSPoint(x: viewportBounds.origin.x, y: targetY))
                                        sv.reflectScrolledClipView(clip)
                                    } else {
                                        viewModel.previousPage()
                                    }
                                    return
                                }
                            }
                        } else {
                            // Fallback if page frame is unavailable
                            if isDown || isPageDown {
                                viewModel.nextPage()
                            } else {
                                viewModel.previousPage()
                            }
                            return
                        }
                    }
                }
            } else if flags == .shift {
                // Shift + Space: Previous Page / Spread
                if event.keyCode == 49 /* Space */ {
                    viewModel.previousPage()
                    return
                }
            }
        }

        // Escape: Cancellation / Mode Exit hierarchy
        if event.keyCode == 53 {
            if activeInlineTextField != nil {
                commitActiveInlineTextField()
                needsDisplay = true
                return
            }
            if selectedAnnotation != nil {
                selectedAnnotation = nil
                needsDisplay = true
                return
            }
            if viewModel.canvasMode != .select {
                viewModel.canvasMode = .select
                viewModel.pendingSignatureData = nil
                currentHoverCanvasPoint = nil
                needsDisplay = true
                return
            }
            if viewModel.activeSelection != nil {
                viewModel.clearSelection()
                needsDisplay = true
                return
            }
            return
        }
        
        super.keyDown(with: event)
    }
    
    // MARK: - AppKit Menu Responder Chain Support
    
    @objc public func saveDocument(_ sender: Any?) {
        viewModel.saveDocument()
    }
    
    @objc public func save(_ sender: Any?) {
        viewModel.saveDocument()
    }
    
    @objc public func saveDocumentAs(_ sender: Any?) {
        viewModel.saveDocumentAs()
    }
    
    @objc public func saveDocumentFlattenedAs(_ sender: Any?) {
        viewModel.saveDocumentFlattenedAs()
    }

    @objc public func printDocument(_ sender: Any?) {
        viewModel.printDocument()
    }
    
    public override func printView(_ sender: Any?) {
        viewModel.printDocument()
    }
    
    public func validateUserInterfaceItem(_ item: NSValidatedUserInterfaceItem) -> Bool {
        let action = item.action
        if action == #selector(saveDocument(_:)) || action == #selector(save(_:)) ||
           action == #selector(saveDocumentAs(_:)) || action == #selector(saveDocumentFlattenedAs(_:)) ||
           action == #selector(printDocument(_:)) || action == #selector(printView(_:)) {
            return viewModel.document != nil
        }
        return true
    }
}

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
    // MARK: - Native Context Menu

    public override func menu(for event: NSEvent) -> NSMenu? {
        // Context menu is only active in standard interactive viewing mode.
        guard viewModel.isInteractiveViewingMode else { return nil }
        let point = convert(event.locationInWindow, from: nil)
        self.lastContextMenuLocation = point

        // An active selection takes priority over a coincidental cross-reference link at the same
        // point.
        if let sel = viewModel.activeSelection, !sel.result.highlightQuads.isEmpty || !viewModel.additionalSelectionPages.isEmpty {
            let menu = buildSelectionMenu(for: sel)
            if sel.result.mode != .rectangularArea, var reference = ReferenceExtractor.references(in: sel.result.text).first {
                reference.sourceRect = sel.result.boundingRect
                insertCrossDocReferenceItems(into: menu, reference: reference, pageIndex: sel.pageIndex)
            }
            return menu
        }

        // Right-clicking a cross-reference link (with no active selection) offers anchor & open actions.
        if let link = internalLinkInfo(at: point) {
            let menu = NSMenu(title: "Anchor")

            if !viewModel.isTransientWindow {
                let snapItem = NSMenuItem(title: "Create Anchor", action: #selector(snapshotTargetAction(_:)), keyEquivalent: "")
                snapItem.image = NSImage.anchorIcon
                snapItem.target = self
                snapItem.representedObject = link
                menu.addItem(snapItem)

                let snapAndOpenItem = NSMenuItem(title: "Create Anchor and Open in New Window", action: #selector(snapshotAndOpenTargetAction(_:)), keyEquivalent: "")
                snapAndOpenItem.image = NSImage.anchorIcon
                snapAndOpenItem.target = self
                snapAndOpenItem.representedObject = link
                menu.addItem(snapAndOpenItem)

                menu.addItem(NSMenuItem.separator())
            }

            menu.addItem(makeOpenInNewWindowItem(target: link))
            return menu
        }

        // Right-clicking an existing annotation offers removal
        if let (pIdx, _, pPoint) = pageInfo(at: point),
           let hitAnnot = annotationForCommands(at: pPoint, pageIndex: pIdx) {
            let menu = NSMenu(title: "Annotation")
            if hitAnnot.documentObjectNumber != nil {
                menu.addItem(makeCommentsItem(representing: (pIdx, hitAnnot.documentObjectNumber ?? 0)))
                menu.addItem(NSMenuItem.separator())
            }
            if (hitAnnot.type == .freeText || hitAnnot.type == .callout) && !hitAnnot.isFromFile {
                let editTitle = hitAnnot.type == .callout ? "Edit Callout Note" : "Edit Text Box"
                let editItem = NSMenuItem(title: editTitle, action: #selector(editHitAnnotationAction(_:)), keyEquivalent: "")
                editItem.image = NSImage(systemSymbolName: "pencil", accessibilityDescription: nil)
                editItem.target = self
                editItem.representedObject = hitAnnot
                menu.addItem(editItem)
                if hitAnnot.type == .callout {
                    menu.addItem(makeLineEndingItem(for: hitAnnot))
                }
                menu.addItem(NSMenuItem.separator())
            }
            if hitAnnot.type == .line {
                menu.addItem(makeLineEndingItem(for: hitAnnot))
                menu.addItem(NSMenuItem.separator())
            }
            let removeTitle: String
            switch hitAnnot.type {
            case .highlight: removeTitle = "Remove Highlight"
            case .underline: removeTitle = "Remove Underline"
            case .strikeout: removeTitle = "Remove Strikethrough"
            case .ink: removeTitle = "Delete Drawing"
            case .freeText: removeTitle = "Delete Text Box"
            case .callout: removeTitle = "Delete Callout"
            case .stamp: removeTitle = "Delete Signature"
            case .note: removeTitle = "Delete Note"
            case .cloud: removeTitle = "Delete Revision Cloud"
            case .other: removeTitle = "Delete Annotation"
            case .square: removeTitle = "Delete Rectangle"
            case .circle: removeTitle = "Delete Oval"
            case .line: removeTitle = hitAnnot.lineEnding == PDFLineEnding.none ? "Delete Line" : "Delete Arrow"
            case .measureLength: removeTitle = "Delete Dimension"
            case .measurePerimeter: removeTitle = "Delete Perimeter"
            case .measureArea: removeTitle = "Delete Area Takeoff"
            case .measureAngle: removeTitle = "Delete Angle Measurement"
            }
            let removeItem = NSMenuItem(title: removeTitle, action: #selector(removeHitAnnotationAction(_:)), keyEquivalent: "")
            removeItem.image = NSImage(systemSymbolName: "trash", accessibilityDescription: nil)
            removeItem.target = self
            removeItem.representedObject = hitAnnot
            menu.addItem(removeItem)
            return menu
        }

        // An annotation that came with the file can't be edited on the canvas, but it can be read,
        // answered and given a status. It can be large, so the page's commands stay available.
        var fileCommentsItem: NSMenuItem?
        if let (pIdx, _, pPoint) = pageInfo(at: point),
           let thread = viewModel.annotationThread(pageIndex: pIdx, at: pPoint) {
            fileCommentsItem = makeCommentsItem(representing: (pIdx, thread.root.objectNumber))
        }

        // No link, no selection — offer to create an anchor from surrounding text or open here in a new window.
        if let target = pointTarget(at: point) {
            let menu = NSMenu(title: "Page")
            if let fileCommentsItem {
                menu.addItem(fileCommentsItem)
                menu.addItem(NSMenuItem.separator())
            }
            if let (reference, pageIndex) = crossDocReference(at: point) {
                insertCrossDocReferenceItems(into: menu, reference: reference, pageIndex: pageIndex)
            }

            if !viewModel.isTransientWindow {
                let snapItem = NSMenuItem(title: "Create Anchor", action: #selector(snapshotTargetAction(_:)), keyEquivalent: "")
                snapItem.image = NSImage.anchorIcon
                snapItem.target = self
                snapItem.representedObject = target
                menu.addItem(snapItem)

                let snapAndOpenItem = NSMenuItem(title: "Create Anchor and Open in New Window", action: #selector(snapshotAndOpenTargetAction(_:)), keyEquivalent: "")
                snapAndOpenItem.image = NSImage.anchorIcon
                snapAndOpenItem.target = self
                snapAndOpenItem.representedObject = target
                menu.addItem(snapAndOpenItem)

                menu.addItem(NSMenuItem.separator())
            }

            menu.addItem(makeOpenInNewWindowItem(target: target))
            return menu
        }
        return nil
    }

    private func makeCommentsItem(representing target: (pageIndex: Int, objectNumber: Int)) -> NSMenuItem {
        let item = NSMenuItem(title: "Comments…", action: #selector(showCommentsAction(_:)), keyEquivalent: "")
        item.image = NSImage(systemSymbolName: "text.bubble", accessibilityDescription: nil)
        item.target = self
        item.representedObject = [target.pageIndex, target.objectNumber]
        return item
    }

    @objc private func showCommentsAction(_ sender: NSMenuItem) {
        guard let target = sender.representedObject as? [Int], target.count == 2 else { return }
        showComments(pageIndex: target[0], objectNumber: target[1])
    }

    /// The topmost annotation at a point, for its right-click commands. One that came with the
    /// file is found as precisely as the document allows, and picked up so it has the same ones.
    private func annotationForCommands(at pagePoint: CGPoint, pageIndex: Int) -> PDFAnnotation? {
        let fileHit = viewModel.document?.annotationObjectNumber(pageIndex: pageIndex, at: pagePoint)
        let shown = viewModel.pageAnnotations[pageIndex]?.last { annot in
            annot.isFromFile ? annot.documentObjectNumber == fileHit : annot.contains(pagePoint: pagePoint)
        }
        return shown ?? fileHit.flatMap { viewModel.pickUpFileAnnotation(pageIndex: pageIndex, objectNumber: $0) }
    }

    private func makeLineEndingItem(for annot: PDFAnnotation) -> NSMenuItem {
        let item = NSMenuItem(title: "Line Ending", action: nil, keyEquivalent: "")
        let submenu = NSMenu(title: "Line Ending")
        for ending in PDFLineEnding.allCases {
            let choice = NSMenuItem(title: ending.displayName, action: #selector(setLineEndingAction(_:)), keyEquivalent: "")
            choice.target = self
            choice.tag = Int(ending.rawValue)
            choice.representedObject = annot
            choice.state = ending == (annot.lineEnding ?? (annot.type == .line ? PDFLineEnding.none : .closedArrow)) ? .on : .off
            submenu.addItem(choice)
        }
        item.submenu = submenu
        return item
    }

    @objc private func setLineEndingAction(_ sender: NSMenuItem) {
        guard let annot = sender.representedObject as? PDFAnnotation,
              let ending = PDFLineEnding(rawValue: Int32(sender.tag)),
              ending != annot.lineEnding else { return }
        if annot.isFromFile {
            viewModel.editFileAnnotation(annot) { try $0.restyleAnnotation(pageIndex: annot.pageIndex, objectNumber: $1, lineEnding: ending) }
            needsDisplay = true
            return
        }
        if annot.type == .line {
            viewModel.beginReplacingAnnotation(annot)
            defer { viewModel.finishReplacingAnnotation() }
            if let updated = viewModel.addRestyledShape(annot, lineEnding: ending) {
                selectedAnnotation = (id: updated.id, pageIndex: annot.pageIndex)
            }
            needsDisplay = true
            return
        }
        guard let rect = annot.rect, let target = annot.targetPoint, let knee = annot.kneePoint else { return }
        viewModel.beginReplacingAnnotation(annot)
        defer { viewModel.finishReplacingAnnotation() }
        if let updated = viewModel.addCalloutAnnotation(
            pageIndex: annot.pageIndex,
            targetPoint: target,
            kneePoint: knee,
            textBoxRect: rect,
            text: annot.text,
            fontSize: annot.fontSize ?? viewModel.selectedFontSize,
            color: annot.color,
            lineEnding: ending
        ) {
            selectedAnnotation = (id: updated.id, pageIndex: annot.pageIndex)
        }
        needsDisplay = true
    }

    private func buildSelectionMenu(for sel: (pageIndex: Int, result: SelectionResult)) -> NSMenu {
        let menu = NSMenu(title: "Selection")

        if sel.result.mode == .rectangularArea {
            if !sel.result.text.isEmpty {
                let copyTextItem = NSMenuItem(title: "Copy Extracted Text", action: #selector(copyTextAction(_:)), keyEquivalent: "")
                copyTextItem.image = NSImage(systemSymbolName: "doc.on.doc", accessibilityDescription: nil)
                copyTextItem.target = self
                menu.addItem(copyTextItem)
            }

            let copyScreenshotItem = NSMenuItem(title: "Copy Screenshot", action: #selector(copyScreenshotAction(_:)), keyEquivalent: "c")
            copyScreenshotItem.image = NSImage(systemSymbolName: "camera", accessibilityDescription: nil)
            copyScreenshotItem.target = self
            menu.addItem(copyScreenshotItem)

            let saveScreenshotItem = NSMenuItem(title: "Save Screenshot As...", action: #selector(saveScreenshotAction(_:)), keyEquivalent: "s")
            saveScreenshotItem.image = NSImage(systemSymbolName: "arrow.down.doc", accessibilityDescription: nil)
            saveScreenshotItem.target = self
            menu.addItem(saveScreenshotItem)

            if !viewModel.isTransientWindow {
                menu.addItem(NSMenuItem.separator())

                let snapItem = NSMenuItem(title: "Create Anchor", action: #selector(snapshotAction(_:)), keyEquivalent: "")
                snapItem.image = NSImage.anchorIcon
                snapItem.target = self
                menu.addItem(snapItem)

                let snapAndOpenItem = NSMenuItem(title: "Create Anchor and Open in New Window", action: #selector(snapshotAndOpenSelectionAction(_:)), keyEquivalent: "")
                snapAndOpenItem.image = NSImage.anchorIcon
                snapAndOpenItem.target = self
                menu.addItem(snapAndOpenItem)
            }
        } else {
            // Only include Copy Text if extracted text is non-empty across all spanned pages.
            if !viewModel.activeSelectionCombinedText.isEmpty {
                let copyItem = NSMenuItem(title: "Copy Text", action: #selector(copyTextAction(_:)), keyEquivalent: "c")
                copyItem.image = NSImage(systemSymbolName: "doc.on.doc", accessibilityDescription: nil)
                copyItem.target = self
                menu.addItem(copyItem)

                let rawSelectedText = viewModel.activeSelectionCombinedText.trimmingCharacters(in: .whitespacesAndNewlines)
                let truncated = rawSelectedText.truncatedAtWordBoundary(maxLength: 24)

                let lookUpItem = NSMenuItem(title: "Look Up \"\(truncated)\"", action: #selector(lookUpSelectionAction(_:)), keyEquivalent: "")
                lookUpItem.image = NSImage(systemSymbolName: "magnifyingglass", accessibilityDescription: nil)
                lookUpItem.target = self
                menu.addItem(lookUpItem)

                let translateItem = NSMenuItem(title: "Translate Selection", action: #selector(translateSelectionAction(_:)), keyEquivalent: "t")
                translateItem.keyEquivalentModifierMask = [.control, .option]
                translateItem.image = NSImage(systemSymbolName: "character.bubble", accessibilityDescription: nil)
                translateItem.target = self
                menu.addItem(translateItem)

                if PDFSpeechCoordinator.shared.isSpeaking {
                    let stopItem = NSMenuItem(title: "Stop Speaking", action: #selector(stopSpeakingAction(_:)), keyEquivalent: "")
                    stopItem.image = NSImage(systemSymbolName: "speaker.slash.fill", accessibilityDescription: nil)
                    stopItem.target = self
                    menu.addItem(stopItem)
                } else {
                    let startItem = NSMenuItem(title: "Start Speaking", action: #selector(startSpeakingAction(_:)), keyEquivalent: "")
                    startItem.image = NSImage(systemSymbolName: "speaker.wave.2.fill", accessibilityDescription: nil)
                    startItem.target = self
                    menu.addItem(startItem)
                }

                // Markup writes to the file, which EPUB, XPS, CBZ and FB2 can't be.
                if !viewModel.isReadOnlyDocument {
                    menu.addItem(NSMenuItem.separator())

                    // Highlight submenu with colors
                    let highlightMenu = NSMenu(title: "Highlight")
                    for color in AnnotationColor.allCases {
                        let colorItem = NSMenuItem(title: color.displayName, action: #selector(highlightWithColorAction(_:)), keyEquivalent: "")
                        colorItem.image = color.menuIcon
                        colorItem.target = self
                        colorItem.representedObject = color
                        highlightMenu.addItem(colorItem)
                    }
                    let highlightParentItem = NSMenuItem(title: "Highlight", action: #selector(highlightDefaultAction(_:)), keyEquivalent: "h")
                    highlightParentItem.keyEquivalentModifierMask = [.command, .shift]
                    highlightParentItem.image = NSImage(systemSymbolName: "highlighter", accessibilityDescription: nil)
                    highlightParentItem.target = self
                    highlightParentItem.submenu = highlightMenu
                    menu.addItem(highlightParentItem)

                    // Underline submenu with colors
                    let underlineMenu = NSMenu(title: "Underline")
                    for color in AnnotationColor.allCases {
                        let colorItem = NSMenuItem(title: color.displayName, action: #selector(underlineWithColorAction(_:)), keyEquivalent: "")
                        colorItem.image = color.menuIcon
                        colorItem.target = self
                        colorItem.representedObject = color
                        underlineMenu.addItem(colorItem)
                    }
                    let underlineParentItem = NSMenuItem(title: "Underline", action: #selector(underlineDefaultAction(_:)), keyEquivalent: "u")
                    underlineParentItem.keyEquivalentModifierMask = [.command, .shift]
                    underlineParentItem.image = NSImage(systemSymbolName: "underline", accessibilityDescription: nil)
                    underlineParentItem.target = self
                    underlineParentItem.submenu = underlineMenu
                    menu.addItem(underlineParentItem)

                    // Strikethrough submenu with colors
                    let strikeMenu = NSMenu(title: "Strikethrough")
                    for color in AnnotationColor.allCases {
                        let colorItem = NSMenuItem(title: color.displayName, action: #selector(strikethroughWithColorAction(_:)), keyEquivalent: "")
                        colorItem.image = color.menuIcon
                        colorItem.target = self
                        colorItem.representedObject = color
                        strikeMenu.addItem(colorItem)
                    }
                    let strikeParentItem = NSMenuItem(title: "Strikethrough", action: #selector(strikethroughDefaultAction(_:)), keyEquivalent: "x")
                    strikeParentItem.keyEquivalentModifierMask = [.command, .shift]
                    strikeParentItem.image = NSImage(systemSymbolName: "strikethrough", accessibilityDescription: nil)
                    strikeParentItem.target = self
                    strikeParentItem.submenu = strikeMenu
                    menu.addItem(strikeParentItem)
                }
            }

            if !viewModel.isTransientWindow {
                if !viewModel.activeSelectionCombinedText.isEmpty {
                    menu.addItem(NSMenuItem.separator())
                }

                let snapItem = NSMenuItem(title: "Create Anchor", action: #selector(snapshotAction(_:)), keyEquivalent: "")
                snapItem.image = NSImage.anchorIcon
                snapItem.target = self
                menu.addItem(snapItem)

                let snapAndOpenItem = NSMenuItem(title: "Create Anchor and Open in New Window", action: #selector(snapshotAndOpenSelectionAction(_:)), keyEquivalent: "")
                snapAndOpenItem.image = NSImage.anchorIcon
                snapAndOpenItem.target = self
                menu.addItem(snapAndOpenItem)
            }
        }

        if menu.numberOfItems > 0 {
            menu.addItem(NSMenuItem.separator())
        }

        // Available for any selection (text or area), not just cross-reference links
        let openWindowItem = NSMenuItem(title: "Open in New Window", action: #selector(openSelectionInNewWindowAction(_:)), keyEquivalent: "")
        openWindowItem.image = NSImage(systemSymbolName: "macwindow.badge.plus", accessibilityDescription: nil)
        openWindowItem.target = self
        menu.addItem(openWindowItem)

        return menu
    }

    @objc private func lookUpSelectionAction(_ sender: NSMenuItem) {
        let text = viewModel.activeSelectionCombinedText.trimmingCharacters(in: .whitespacesAndNewlines)
        guard !text.isEmpty else { return }
        let targetPoint = (lastContextMenuLocation != .zero) ? lastContextMenuLocation : currentSelectionAnchorPoint()
        self.showDefinition(for: NSAttributedString(string: text), at: targetPoint)
    }

    @objc private func translateSelectionAction(_ sender: NSMenuItem) {
        viewModel.translateSelection()
    }

    @objc private func startSpeakingAction(_ sender: NSMenuItem) {
        viewModel.startSpeakingSelection()
    }

    @objc private func stopSpeakingAction(_ sender: NSMenuItem) {
        viewModel.stopSpeaking()
    }

    @objc public func startSpeaking(_ sender: Any?) {
        viewModel.startSpeakingSelection()
    }

    @objc public func stopSpeaking(_ sender: Any?) {
        viewModel.stopSpeaking()
    }

    @objc public func highlightSelection(_ sender: Any?) {
        viewModel.highlightSelection(color: viewModel.selectedAnnotationColor)
        needsDisplay = true
    }

    @objc public func underlineSelection(_ sender: Any?) {
        viewModel.underlineSelection(color: viewModel.selectedAnnotationColor)
        needsDisplay = true
    }

    @objc public func strikethroughSelection(_ sender: Any?) {
        viewModel.strikethroughSelection(color: viewModel.selectedAnnotationColor)
        needsDisplay = true
    }

    private func currentSelectionAnchorPoint() -> CGPoint {
        if let sel = viewModel.activeSelection, let firstQuad = sel.result.highlightQuads.first {
            let pIdx = sel.pageIndex
            let pageY = (viewModel.document?.pageYOffsets.indices.contains(pIdx) == true) ? viewModel.document!.pageYOffsets[pIdx] : 0
            return CGPoint(x: firstQuad.ul.x, y: pageY + firstQuad.ul.y)
        }
        return CGPoint(x: bounds.midX, y: bounds.midY)
    }

    @objc private func snapshotTargetAction(_ sender: NSMenuItem) {
        guard let target = sender.representedObject as? SnapshotTarget else { return }
        viewModel.addSnapshotTarget(target)
    }

    @objc private func snapshotAndOpenTargetAction(_ sender: NSMenuItem) {
        guard let target = sender.representedObject as? SnapshotTarget else { return }
        viewModel.addSnapshotAndOpen(target)
    }

    @objc private func snapshotAndOpenSelectionAction(_ sender: Any) {
        viewModel.addSnapshotAndOpenFromSelection()
    }

    @objc func openTargetInNewWindowAction(_ sender: NSMenuItem) {
        guard let target = sender.representedObject as? SnapshotTarget else { return }
        viewModel.openSnapshotInNewWindow(target)
    }

    @objc public override func selectAll(_ sender: Any?) {
        viewModel.selectAllOnCurrentPage()
    }

    @objc public func copy(_ sender: Any?) {
        if let sel = viewModel.activeSelection, sel.result.mode == .rectangularArea {
            viewModel.copyActiveScreenshot()
        } else {
            viewModel.copyActiveSelection()
        }
    }
    
    @objc private func copyScreenshotAction(_ sender: Any) {
        viewModel.copyActiveScreenshot()
    }
    
    @objc private func saveScreenshotAction(_ sender: Any) {
        viewModel.saveActiveScreenshot()
    }
    
    @objc private func copyTextAction(_ sender: Any) {
        viewModel.copyActiveSelection()
    }
    
    @objc private func snapshotAction(_ sender: Any) {
        viewModel.addSnapshotFromSelection()
    }

    @objc private func openSelectionInNewWindowAction(_ sender: Any) {
        viewModel.openSelectionInNewWindow()
    }

    @objc private func highlightDefaultAction(_ sender: Any) {
        viewModel.highlightSelection(color: .yellow)
        needsDisplay = true
    }

    @objc private func highlightWithColorAction(_ sender: NSMenuItem) {
        guard let color = sender.representedObject as? AnnotationColor else { return }
        viewModel.highlightSelection(color: color)
        needsDisplay = true
    }

    @objc private func underlineDefaultAction(_ sender: Any) {
        viewModel.underlineSelection(color: viewModel.selectedAnnotationColor)
        needsDisplay = true
    }

    @objc private func underlineWithColorAction(_ sender: NSMenuItem) {
        guard let color = sender.representedObject as? AnnotationColor else { return }
        viewModel.underlineSelection(color: color)
        needsDisplay = true
    }

    @objc private func strikethroughDefaultAction(_ sender: Any) {
        viewModel.strikethroughSelection(color: viewModel.selectedAnnotationColor)
        needsDisplay = true
    }

    @objc private func strikethroughWithColorAction(_ sender: NSMenuItem) {
        guard let color = sender.representedObject as? AnnotationColor else { return }
        viewModel.strikethroughSelection(color: color)
        needsDisplay = true
    }

    @objc private func removeHitAnnotationAction(_ sender: NSMenuItem) {
        guard let annot = sender.representedObject as? PDFAnnotation else { return }
        viewModel.removeAnnotation(annot)
        needsDisplay = true
    }

    @objc private func editHitAnnotationAction(_ sender: NSMenuItem) {
        guard let annot = sender.representedObject as? PDFAnnotation else { return }
        startInlineEditing(annotation: annot, pageIndex: annot.pageIndex)
    }
}

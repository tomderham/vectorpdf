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
    // MARK: - AcroForm Control Synchronization
    
    public func syncFormControls() {
        // A Compare Documents pane is read-only: its fields show as drawn on the page.
        guard let doc = viewModel.document, !viewModel.isComparePane else {
            for (_, view) in activeFormControls {
                view.removeFromSuperview()
                forgetPlacement(of: view)
            }
            activeFormControls.removeAll()
            return
        }

        let visible = visibleRect
        guard visible.width > 0 && visible.height > 0 else { return }
        
        let unscaledMinY = max(0, (visible.minY - 16) / viewModel.effectiveZoom)
        let unscaledMaxY = max(0, (visible.maxY - 16) / viewModel.effectiveZoom)
        let firstPage = viewModel.effectivePageIndex(atYOffset: unscaledMinY)
        let lastPage = viewModel.effectivePageIndex(atYOffset: unscaledMaxY)
        
        let start = max(0, firstPage - 1)
        let end = min(doc.pageCount - 1, lastPage + 1)
        guard start <= end else { return }
        
        var visibleKeys = Set<String>()
        
        for pageIdx in start...end {
            guard let geometry = pageGeometry(for: pageIdx) else { continue }
            let pFrame = geometry.frame
            guard pFrame.intersects(visible) || abs(pFrame.midY - visible.midY) < visible.height else { continue }
            
            if viewModel.pageFormWidgets[pageIdx] == nil {
                // Defer loading metadata to avoid mutating published state during layout().
                // The view model weakly: the canvas holds it unowned, and it can be gone by then.
                Task { @MainActor [weak viewModel] in
                    viewModel?.loadPageMetadata(pageIdx)
                }
                // Retain live controls while metadata is loading.
                let pagePrefix = "p\(pageIdx)_"
                for key in activeFormControls.keys where key.hasPrefix(pagePrefix) {
                    visibleKeys.insert(key)
                }
                continue
            }

            guard let widgets = viewModel.pageFormWidgets[pageIdx], !widgets.isEmpty else { continue }
            let pBounds = doc.pageBounds[pageIdx]
            
            for widget in widgets {
                let key = widget.id
                visibleKeys.insert(key)

                // Placed on the page unturned, then turned with it in a rotated view.
                let widgetFrame = widgetScreenFrame(for: widget, pageFrame: geometry.layoutFrame, pageBounds: pBounds)

                // Match control appearance to page appearance mode for visual consistency.
                let controlAppearance = NSAppearance(named: isDarkMode ? .darkAqua : .aqua)

                if let existing = activeFormControls[key] {
                    place(existing, layoutRect: widgetFrame, geometry: geometry)
                    existing.appearance = controlAppearance
                    updateExistingControl(existing, for: widget, layoutFrame: widgetFrame)
                } else {
                    if let newControl = PDFFormControlFactory.makeControl(for: widget, viewModel: viewModel, frame: widgetFrame) {
                        newControl.appearance = controlAppearance
                        place(newControl, layoutRect: widgetFrame, geometry: geometry)
                        addSubview(newControl)
                        activeFormControls[key] = newControl
                    }
                }
            }
        }
        
        let keysToRemove = activeFormControls.keys.filter { !visibleKeys.contains($0) }
        for key in keysToRemove {
            if let view = activeFormControls[key] {
                let isEditing = (view.window?.firstResponder as? NSView)?.isDescendant(of: view) == true || view.window?.firstResponder == view
                if !isEditing {
                    view.removeFromSuperview()
                    forgetPlacement(of: view)
                    activeFormControls.removeValue(forKey: key)
                }
            }
        }
        
        // Chain key-view loop in reading order (top-to-bottom, left-to-right) for Tab and Shift+Tab navigation
        // This view is flipped, so reading order is ascending y.
        let sortedControls = readingOrder(
            activeFormControls.values.filter { $0.canBecomeKeyView },
            rowTolerance: 4,
            frame: { self.layoutRect(of: $0) }
        )
        if sortedControls.count > 1 {
            for i in 0..<(sortedControls.count - 1) {
                sortedControls[i].nextKeyView = sortedControls[i + 1]
            }
        }
    }
    
    var isActivelyEditingFormControl: Bool {
        guard let firstResponder = window?.firstResponder as? NSView else { return false }
        for control in activeFormControls.values {
            if firstResponder.isDescendant(of: control) || firstResponder == control {
                return true
            }
        }
        return false
    }
    
    /// `layoutFrame` is the control's unturned frame, which sets its font size.
    private func updateExistingControl(_ view: NSView, for widget: PDFFormWidget, layoutFrame: NSRect) {
        if let tf = view as? PDFFormTextField {
            tf.updateZoom(frame: layoutFrame)
            let isEditing = (tf.window?.firstResponder as? NSView)?.isDescendant(of: tf) == true
            if !isEditing && tf.stringValue != widget.value {
                tf.stringValue = widget.value
            }
        } else if let ctf = view as? PDFFormCombTextField {
            ctf.updateZoom(frame: layoutFrame)
            let isEditing = ctf.window?.firstResponder == ctf
            if !isEditing && ctf.stringValue != widget.value {
                ctf.stringValue = widget.value
            }
        } else if let stf = view as? PDFFormSecureTextField {
            stf.updateZoom(frame: layoutFrame)
            let isEditing = (stf.window?.firstResponder as? NSView)?.isDescendant(of: stf) == true
            if !isEditing && stf.stringValue != widget.value {
                stf.stringValue = widget.value
            }
        } else if let btn = view as? PDFFormButton {
            btn.updateZoom(frame: layoutFrame)
            let isChecked = PDFFormButton.isValueChecked(widget.value)
            let targetState: NSControl.StateValue = isChecked ? .on : .off
            if btn.state != targetState {
                btn.state = targetState
            }
        } else if let popup = view as? PDFFormChoiceButton {
            popup.updateZoom(frame: layoutFrame)
            if popup.titleOfSelectedItem != widget.value && !widget.value.isEmpty {
                popup.selectItem(withTitle: widget.value)
            }
        } else if let ecf = view as? PDFFormEditableChoiceField {
            ecf.updateZoom(frame: layoutFrame)
            let isEditing = (ecf.window?.firstResponder as? NSView)?.isDescendant(of: ecf) == true
            if !isEditing && ecf.stringValue != widget.value {
                ecf.stringValue = widget.value
            }
        } else if let pb = view as? PDFFormPushButton {
            pb.updateZoom(frame: layoutFrame)
        } else if let sig = view as? PDFSignatureStampButton {
            sig.updateZoom(frame: layoutFrame)
        }
    }
}

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

import SwiftUI
import AppKit
import Combine
import UniformTypeIdentifiers
import ObjectiveC

extension PDFViewerViewModel {
    public func printDocument() {
        guard let doc = document else { return }
        flushPendingFormEdits()

        let printURL: URL
        var temporaryFileURL: URL? = nil
        
        if isDocumentEdited {
            let tempDir = FileManager.default.temporaryDirectory
            let tempFile = tempDir.appendingPathComponent("VectorPDF-print-\(UUID().uuidString).pdf")
            do {
                try doc.save(to: tempFile.path)
                printURL = tempFile
                temporaryFileURL = tempFile
            } catch {
                print("Failed to save temporary copy for printing: \(error)")
                printURL = URL(fileURLWithPath: doc.filePath)
            }
        } else {
            printURL = URL(fileURLWithPath: doc.filePath)
        }
        
        // Print through MuPDF (MuPDFPrintView) rather than PDFKit so the output matches the on-screen
        // rendering (font rasterization, blend modes, form appearances).

        // Isolate print settings on an optimized PDFPrintInfo rather than mutating the shared singleton
        let baseShared = NSPrintInfo.shared
        let dict = (baseShared.dictionary() as? [NSPrintInfo.AttributeKey: Any]) ?? [:]
        let printInfo = PDFPrintInfo(dictionary: dict)
        printInfo.isHorizontallyCentered = true
        printInfo.isVerticallyCentered = true
        printInfo.dictionary()[NSPrintInfo.AttributeKey.firstPage] = 1
        printInfo.dictionary()[NSPrintInfo.AttributeKey.lastPage] = doc.pageCount
        printInfo.dictionary()[NSPrintInfo.AttributeKey.allPages] = true

        if let firstPageBounds = doc.pageBounds.first {
            printInfo.orientation = (firstPageBounds.width > firstPageBounds.height) ? .landscape : .portrait
        }

        let printView: MuPDFPrintView
        do {
            printView = try MuPDFPrintView(filePath: printURL.path, password: currentDocumentPassword, pageCount: doc.pageCount, printInfo: printInfo)
        } catch {
            if let temp = temporaryFileURL {
                try? FileManager.default.removeItem(at: temp)
            }
            showPrintFailureAlert(reason: "Failed to open document for printing: \(error.localizedDescription)")
            return
        }

        let printOp = NSPrintOperation(view: printView, printInfo: printInfo)

        // Set job title so "Save as PDF" and print spools use the document's actual filename
        printOp.jobTitle = (doc.filePath as NSString).lastPathComponent

        printOp.showsPrintPanel = true
        printOp.showsProgressPanel = true
        // Must be false: NSView and MuPDFPrintView are @MainActor-isolated. Spawning a separate
        // background thread causes AppKit to invoke knowsPageRange(_:) and draw(_:) on a non-main
        // thread, which trips Swift Concurrency's executor assertion (_dispatch_assert_queue_fail).
        printOp.canSpawnSeparateThread = false
        
        // Expose native orientation and paper size options in the print dialog.
        printOp.printPanel.options.insert([
            .showsPaperSize,
            .showsOrientation
        ])
        printOp.printPanel.options.remove([
            .showsScaling,
            .showsPageSetupAccessory
        ])
        
        let hasMeasurements = self.hasMeasurementAnnotations
        if hasMeasurements {
            printView.scaleMode = 0
            printView.customScale = 1.0
        }
        let accessoryVC = PDFPrintAccessoryViewController(printOperation: printOp, printView: printView, hasMeasurements: hasMeasurements)
        printOp.printPanel.addAccessoryController(accessoryVC)
        
        let cleanup = {
            if let temp = temporaryFileURL {
                try? FileManager.default.removeItem(at: temp)
            }
        }
        
        let completionDelegate = PrintCompletionDelegate(onComplete: cleanup)
        objc_setAssociatedObject(printOp, &printCompletionDelegateKey, completionDelegate, .OBJC_ASSOCIATION_RETAIN_NONATOMIC)
        
        if let window = currentWindow ?? NSApplication.shared.keyWindow {
            printOp.runModal(for: window, delegate: completionDelegate, didRun: #selector(PrintCompletionDelegate.printOperationDidRun(_:success:contextInfo:)), contextInfo: nil)
        } else {
            printOp.run()
            cleanup()
        }
    }

    private func showPrintFailureAlert(reason: String) {
        showErrorAlert(title: "Unable to Print Document", message: reason)
    }
}

private nonisolated(unsafe) var printCompletionDelegateKey: UInt8 = 0

@MainActor
private final class PrintCompletionDelegate: NSObject {
    private var onComplete: (() -> Void)?
    
    init(onComplete: @escaping () -> Void) {
        self.onComplete = onComplete
        super.init()
    }
    
    @objc func printOperationDidRun(_ printOperation: NSPrintOperation, success: Bool, contextInfo: UnsafeMutableRawPointer?) {
        if success {
            NSPrintInfo.shared = printOperation.printInfo
        }
        onComplete?()
        onComplete = nil
    }
}

/// Print panel accessory view controller providing controls for Auto Rotate and Scaling.
@MainActor
final class PDFPrintAccessoryViewController: NSViewController, NSPrintPanelAccessorizing {
    private weak var printOperation: NSPrintOperation?
    private weak var printView: MuPDFPrintView?
    private let hasMeasurements: Bool
    
    @objc dynamic var previewAutoRotate: Bool = true
    @objc dynamic var previewScale: Double = 1.0
    
    private var autoRotateCheckbox: NSButton!
    private var scaleToFitRadio: NSButton!
    private var scaleCustomRadio: NSButton!
    private var scaleField: NSTextField!
    private var scaleStepper: NSStepper!
    
    private var activePrintInfo: NSPrintInfo? {
        return printOperation?.printInfo
    }
    
    init(printOperation: NSPrintOperation, printView: MuPDFPrintView, hasMeasurements: Bool = false) {
        self.printOperation = printOperation
        self.printView = printView
        self.hasMeasurements = hasMeasurements
        super.init(nibName: nil, bundle: nil)
        self.title = "PDF Options"
        self.previewAutoRotate = printView.autoRotate
        self.previewScale = 1.0
    }
    
    required init?(coder: NSCoder) {
        fatalError("init(coder:) has not been implemented")
    }
    
    override func loadView() {
        let container = NSView()
        container.translatesAutoresizingMaskIntoConstraints = false
        
        // Auto Rotate (left side)
        autoRotateCheckbox = NSButton(checkboxWithTitle: "Auto Rotate", target: self, action: #selector(autoRotateChanged(_:)))
        autoRotateCheckbox.state = printView?.autoRotate == false ? .off : .on
        
        // Scale controls (right side)
        scaleToFitRadio = NSButton(radioButtonWithTitle: "Scale to Fit", target: self, action: #selector(scaleModeChanged(_:)))
        scaleToFitRadio.state = hasMeasurements ? .off : .on
        
        scaleCustomRadio = NSButton(radioButtonWithTitle: "Scale:", target: self, action: #selector(scaleModeChanged(_:)))
        scaleCustomRadio.state = hasMeasurements ? .on : .off
        
        scaleField = NSTextField(string: "100")
        scaleField.alignment = .right
        scaleField.target = self
        scaleField.action = #selector(customScaleChanged(_:))
        scaleField.isEnabled = hasMeasurements
        scaleField.widthAnchor.constraint(equalToConstant: 50).isActive = true
        
        let pctLabel = NSTextField(labelWithString: "%")
        
        scaleStepper = NSStepper()
        scaleStepper.minValue = 10
        scaleStepper.maxValue = 400
        scaleStepper.increment = 5
        scaleStepper.integerValue = 100
        scaleStepper.target = self
        scaleStepper.action = #selector(stepperChanged(_:))
        scaleStepper.isEnabled = hasMeasurements
        
        let customScaleRow = NSStackView(views: [scaleCustomRadio, scaleField, pctLabel, scaleStepper])
        customScaleRow.orientation = .horizontal
        customScaleRow.spacing = 4
        customScaleRow.alignment = .centerY
        
        let scaleStack = NSStackView(views: [scaleToFitRadio, customScaleRow])
        scaleStack.orientation = .vertical
        scaleStack.alignment = .leading
        scaleStack.spacing = 6
        
        // Horizontal main stack: Auto Rotate on the left, Scale options to the right
        let mainStack = NSStackView(views: [autoRotateCheckbox, scaleStack])
        mainStack.orientation = .horizontal
        mainStack.alignment = .top
        mainStack.spacing = 32
        
        let outerStack = NSStackView()
        outerStack.orientation = .vertical
        outerStack.alignment = .leading
        outerStack.spacing = 10
        outerStack.translatesAutoresizingMaskIntoConstraints = false
        outerStack.addArrangedSubview(mainStack)
        
        if hasMeasurements {
            let noteContainer = NSView()
            noteContainer.wantsLayer = true
            noteContainer.layer?.cornerRadius = 6
            noteContainer.layer?.borderWidth = 1
            noteContainer.layer?.borderColor = NSColor.systemOrange.withAlphaComponent(0.4).cgColor
            noteContainer.layer?.backgroundColor = NSColor.systemOrange.withAlphaComponent(0.08).cgColor
            
            let noteIcon = NSImageView()
            if let rulerImg = NSImage(systemSymbolName: "ruler", accessibilityDescription: "Measurements") {
                noteIcon.image = rulerImg
            } else {
                noteIcon.image = NSImage(systemSymbolName: "info.circle", accessibilityDescription: "Information")
            }
            noteIcon.contentTintColor = .systemOrange
            noteIcon.setContentHuggingPriority(.required, for: .horizontal)
            
            let noteLabel = NSTextField(wrappingLabelWithString: "Document contains calibrated measurements. Scale defaults to 100% (Actual Size). Please confirm paper type, size, and zoom to preserve calibrated scale.")
            noteLabel.font = NSFont.systemFont(ofSize: NSFont.smallSystemFontSize)
            noteLabel.textColor = .labelColor
            
            let noteStack = NSStackView(views: [noteIcon, noteLabel])
            noteStack.orientation = .horizontal
            noteStack.alignment = .centerY
            noteStack.spacing = 8
            noteStack.translatesAutoresizingMaskIntoConstraints = false
            
            noteContainer.addSubview(noteStack)
            NSLayoutConstraint.activate([
                noteStack.leadingAnchor.constraint(equalTo: noteContainer.leadingAnchor, constant: 10),
                noteStack.trailingAnchor.constraint(equalTo: noteContainer.trailingAnchor, constant: -10),
                noteStack.topAnchor.constraint(equalTo: noteContainer.topAnchor, constant: 6),
                noteStack.bottomAnchor.constraint(equalTo: noteContainer.bottomAnchor, constant: -6),
                noteContainer.widthAnchor.constraint(lessThanOrEqualToConstant: 440)
            ])
            outerStack.addArrangedSubview(noteContainer)
        }
        
        container.addSubview(outerStack)
        
        NSLayoutConstraint.activate([
            outerStack.leadingAnchor.constraint(equalTo: container.leadingAnchor, constant: 16),
            outerStack.topAnchor.constraint(equalTo: container.topAnchor, constant: 10),
            outerStack.bottomAnchor.constraint(equalTo: container.bottomAnchor, constant: -10),
            outerStack.trailingAnchor.constraint(lessThanOrEqualTo: container.trailingAnchor, constant: -16)
        ])
        
        self.view = container
    }
    
    @objc func keyPathsForValuesAffectingPreview() -> Set<String> {
        return ["previewScale", "previewAutoRotate"]
    }
    
    @objc private func autoRotateChanged(_ sender: NSButton) {
        let enabled = (sender.state == .on)
        previewAutoRotate = enabled
        printView?.autoRotate = enabled
        printView?.needsDisplay = true
    }
    
    @objc private func scaleModeChanged(_ sender: NSButton) {
        if sender === scaleToFitRadio {
            scaleToFitRadio.state = .on
            scaleCustomRadio.state = .off
            scaleField.isEnabled = false
            scaleStepper.isEnabled = false
            printView?.scaleMode = 1
            previewScale = 1.0
        } else {
            scaleToFitRadio.state = .off
            scaleCustomRadio.state = .on
            scaleField.isEnabled = true
            scaleStepper.isEnabled = true
            applyCustomScale()
        }
        printView?.needsDisplay = true
    }
    
    @objc private func stepperChanged(_ sender: NSStepper) {
        if scaleCustomRadio.state != .on {
            scaleToFitRadio.state = .off
            scaleCustomRadio.state = .on
            scaleField.isEnabled = true
            scaleStepper.isEnabled = true
        }
        scaleField.integerValue = sender.integerValue
        applyCustomScale()
    }
    
    @objc private func customScaleChanged(_ sender: NSTextField) {
        if scaleCustomRadio.state != .on {
            scaleToFitRadio.state = .off
            scaleCustomRadio.state = .on
            scaleField.isEnabled = true
            scaleStepper.isEnabled = true
        }
        let val = max(10, min(400, sender.integerValue))
        scaleField.integerValue = val
        scaleStepper.integerValue = val
        applyCustomScale()
    }
    
    private func applyCustomScale() {
        let pct = max(10, min(400, scaleField.integerValue))
        let factor = CGFloat(pct) / 100.0
        printView?.scaleMode = 0
        printView?.customScale = factor
        previewScale = Double(factor)
        printView?.needsDisplay = true
    }
    
    nonisolated func localizedSummaryItems() -> [[NSPrintPanel.AccessorySummaryKey: String]] {
        return MainActor.assumeIsolated {
            var items: [[NSPrintPanel.AccessorySummaryKey: String]] = []
            let autoRot = (autoRotateCheckbox?.state == .on) ? "Yes" : "No"
            items.append([.itemName: "Auto Rotate", .itemDescription: autoRot])
            let scaleDesc = (scaleToFitRadio?.state == .on) ? "Scale to Fit" : "\(scaleField?.stringValue ?? "100")%"
            items.append([.itemName: "Scale", .itemDescription: scaleDesc])
            if hasMeasurements {
                items.append([.itemName: "Measurements", .itemDescription: "100% Actual Size (Calibrated)"])
            }
            return items
        }
    }
}

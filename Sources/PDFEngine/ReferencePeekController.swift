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

/// Pinned, clickable preview of where an unlinked reference ("Section 4.2 of the Master
/// Agreement") most likely points in another tab. Shows the best candidate; ←/→ or the chevrons
/// cycle through the rest; a click or Return opens it; Esc, a click elsewhere or scrolling closes.
@MainActor
final class ReferencePeekController: NSObject {
    static let headerHeight: CGFloat = 30
    static let minWidth: CGFloat = 340
    static let loadingHeight: CGFloat = 96

    private var panel: NSPanel?
    private var eventMonitor: Any?
    private var resignObserver: NSObjectProtocol?
    private var loadTask: Task<Void, Never>?
    private var dismissTask: Task<Void, Never>?

    private var candidates: [ReferenceCandidate] = []
    private var images: [UUID: NSImage] = [:]
    private var index = 0
    private var anchorRect: NSRect = .zero
    private weak var parent: NSWindow?
    private var render: (@MainActor (ReferenceCandidate) async -> NSImage?)?
    private var onOpen: (@MainActor (ReferenceCandidate) -> Void)?
    private(set) var isShowing = false

    /// A one-line status ("Searching…", "No match…") under `anchor` (screen coordinates).
    func showMessage(_ text: String, spinning: Bool, anchor: NSRect, parent: NSWindow, autoDismissAfter delay: Duration? = nil) {
        reset()
        self.anchorRect = anchor
        self.parent = parent
        let label = NSTextField(labelWithString: text)
        label.font = .systemFont(ofSize: NSFont.smallSystemFontSize)
        label.textColor = .secondaryLabelColor
        label.lineBreakMode = .byTruncatingTail
        label.sizeToFit()
        let width = min(max(label.frame.width + (spinning ? 44 : 24), 200), 520)
        let container = makeContainer(size: NSSize(width: width, height: Self.headerHeight), parent: parent)
        var x: CGFloat = 12
        if spinning {
            let spinner = NSProgressIndicator(frame: NSRect(x: x, y: (Self.headerHeight - 16) / 2, width: 16, height: 16))
            spinner.style = .spinning
            spinner.controlSize = .small
            spinner.startAnimation(nil)
            container.addSubview(spinner)
            x += 22
        }
        label.frame = NSRect(x: x, y: (Self.headerHeight - label.frame.height) / 2, width: width - x - 12, height: label.frame.height)
        container.addSubview(label)
        present(container, parent: parent)
        if let delay {
            dismissTask = Task { @MainActor [weak self] in
                try? await Task.sleep(for: delay)
                guard !Task.isCancelled else { return }
                self?.dismiss()
            }
        }
    }

    /// Previews `candidates[0]`, best first, under `anchor` (screen coordinates).
    func show(
        _ candidates: [ReferenceCandidate],
        anchor: NSRect,
        parent: NSWindow,
        render: @escaping @MainActor (ReferenceCandidate) async -> NSImage?,
        onOpen: @escaping @MainActor (ReferenceCandidate) -> Void
    ) {
        guard !candidates.isEmpty else { return dismiss() }
        reset()
        self.candidates = candidates
        self.anchorRect = anchor
        self.parent = parent
        self.render = render
        self.onOpen = onOpen
        showCurrent()
    }

    func dismiss() {
        reset()
        if let panel {
            panel.parent?.removeChildWindow(panel)
            panel.orderOut(nil)
        }
        if let eventMonitor {
            NSEvent.removeMonitor(eventMonitor)
            self.eventMonitor = nil
        }
        if let resignObserver {
            NotificationCenter.default.removeObserver(resignObserver)
            self.resignObserver = nil
        }
        isShowing = false
    }

    // MARK: - Private

    private func reset() {
        loadTask?.cancel()
        loadTask = nil
        dismissTask?.cancel()
        dismissTask = nil
        candidates = []
        images = [:]
        index = 0
        render = nil
        onOpen = nil
    }

    private func showCurrent() {
        guard let parent, candidates.indices.contains(index) else { return }
        let candidate = candidates[index]
        present(makeCandidateView(candidate, image: images[candidate.id], parent: parent), parent: parent)
        guard images[candidate.id] == nil, let render else { return }
        loadTask?.cancel()
        loadTask = Task { @MainActor [weak self] in
            let image = await render(candidate)
            guard !Task.isCancelled, let self, let image else { return }
            self.images[candidate.id] = image
            if self.candidates.indices.contains(self.index), self.candidates[self.index].id == candidate.id {
                self.showCurrent()
            }
        }
    }

    private func step(_ delta: Int) {
        guard candidates.count > 1 else { return }
        index = (index + delta + candidates.count) % candidates.count
        showCurrent()
    }

    private func openCurrent() {
        guard candidates.indices.contains(index), let onOpen else { return }
        let candidate = candidates[index]
        dismiss()
        onOpen(candidate)
    }

    @objc private func previousAction(_ sender: Any?) { step(-1) }
    @objc private func nextAction(_ sender: Any?) { step(1) }

    private func maxImageSize(in parent: NSWindow) -> NSSize {
        NSSize(width: max(Self.minWidth, min(parent.frame.width - 32, 900)), height: parent.frame.height * 0.4)
    }

    private func makeCandidateView(_ candidate: ReferenceCandidate, image: NSImage?, parent: NSWindow) -> NSView {
        let maxSize = maxImageSize(in: parent)
        let imageSize: NSSize
        if let image {
            imageSize = NSSize(width: max(Self.minWidth, min(image.size.width, maxSize.width)), height: min(image.size.height, maxSize.height))
        } else {
            imageSize = NSSize(width: Self.minWidth, height: Self.loadingHeight)
        }
        let size = NSSize(width: imageSize.width, height: imageSize.height + Self.headerHeight)
        let container = makeContainer(size: size, parent: parent)

        // Body: the rendered target, clickable to open.
        let body = ClickableView(frame: NSRect(origin: .zero, size: imageSize))
        body.onClick = { [weak self] in self?.openCurrent() }
        if let image {
            let truncated = image.size.width > imageSize.width + 0.5 || image.size.height > imageSize.height + 0.5
            let content = LinkPeekController.makeContentView(image: image, size: imageSize, isTruncated: truncated, truncationHint: "Click to open")
            content.layer?.cornerRadius = 0
            content.layer?.borderWidth = 0
            body.addSubview(content)
        } else {
            let spinner = NSProgressIndicator(frame: NSRect(x: (imageSize.width - 16) / 2, y: (imageSize.height - 16) / 2, width: 16, height: 16))
            spinner.style = .spinning
            spinner.controlSize = .small
            spinner.startAnimation(nil)
            body.addSubview(spinner)
        }
        container.addSubview(body)

        // Header: heading and document, then the candidate switcher (or an open hint).
        let header = ClickableView(frame: NSRect(x: 0, y: imageSize.height, width: size.width, height: Self.headerHeight))
        header.onClick = { [weak self] in self?.openCurrent() }
        var trailingX = size.width - 8
        if candidates.count > 1 {
            let next = makeChevron("chevron.right", action: #selector(nextAction(_:)), help: "Next Match (→)")
            trailingX -= next.frame.width
            next.setFrameOrigin(NSPoint(x: trailingX, y: (Self.headerHeight - next.frame.height) / 2))
            header.addSubview(next)

            let count = NSTextField(labelWithString: "\(index + 1) of \(candidates.count)")
            count.font = .monospacedDigitSystemFont(ofSize: NSFont.smallSystemFontSize, weight: .regular)
            count.textColor = .secondaryLabelColor
            count.sizeToFit()
            trailingX -= count.frame.width + 2
            count.setFrameOrigin(NSPoint(x: trailingX, y: (Self.headerHeight - count.frame.height) / 2))
            header.addSubview(count)

            let previous = makeChevron("chevron.left", action: #selector(previousAction(_:)), help: "Previous Match (←)")
            trailingX -= previous.frame.width + 2
            previous.setFrameOrigin(NSPoint(x: trailingX, y: (Self.headerHeight - previous.frame.height) / 2))
            header.addSubview(previous)
        } else {
            let hint = NSTextField(labelWithString: "↩ to open")
            hint.font = .systemFont(ofSize: NSFont.smallSystemFontSize)
            hint.textColor = .tertiaryLabelColor
            hint.sizeToFit()
            trailingX -= hint.frame.width
            hint.setFrameOrigin(NSPoint(x: trailingX, y: (Self.headerHeight - hint.frame.height) / 2))
            header.addSubview(hint)
        }

        let title = NSMutableAttributedString(
            string: candidate.heading,
            attributes: [.font: NSFont.boldSystemFont(ofSize: NSFont.smallSystemFontSize), .foregroundColor: NSColor.labelColor]
        )
        title.append(NSAttributedString(
            string: "  \(candidate.documentTitle) · p. \(candidate.target.targetPage + 1)",
            attributes: [.font: NSFont.systemFont(ofSize: NSFont.smallSystemFontSize), .foregroundColor: NSColor.secondaryLabelColor]
        ))
        let titleLabel = NSTextField(labelWithAttributedString: title)
        titleLabel.lineBreakMode = .byTruncatingTail
        titleLabel.cell?.truncatesLastVisibleLine = true
        titleLabel.sizeToFit()
        let titleWidth = max(40, trailingX - 12 - 8)
        titleLabel.frame = NSRect(x: 12, y: (Self.headerHeight - titleLabel.frame.height) / 2, width: titleWidth, height: titleLabel.frame.height)
        titleLabel.toolTip = "\(candidate.heading) — \(candidate.documentTitle)"
        header.addSubview(titleLabel)

        let divider = NSBox(frame: NSRect(x: 0, y: imageSize.height, width: size.width, height: 1))
        divider.boxType = .separator
        container.addSubview(header)
        container.addSubview(divider)
        return container
    }

    private func makeChevron(_ symbol: String, action: Selector, help: String) -> NSButton {
        let image = NSImage(systemSymbolName: symbol, accessibilityDescription: help) ?? NSImage()
        let button = NSButton(image: image, target: self, action: action)
        button.isBordered = false
        button.toolTip = help
        button.frame.size = NSSize(width: 20, height: 20)
        return button
    }

    private func makeContainer(size: NSSize, parent: NSWindow) -> NSView {
        let container = NSView(frame: NSRect(origin: .zero, size: size))
        container.wantsLayer = true
        parent.effectiveAppearance.performAsCurrentDrawingAppearance {
            container.layer?.backgroundColor = NSColor.windowBackgroundColor.cgColor
            container.layer?.borderColor = NSColor.separatorColor.cgColor
        }
        container.layer?.cornerRadius = 8
        container.layer?.masksToBounds = true
        container.layer?.borderWidth = 1
        return container
    }

    private func present(_ content: NSView, parent: NSWindow) {
        let screenFrame = (parent.screen ?? NSScreen.main)?.visibleFrame ?? parent.frame
        let frame = LinkPeekController.panelFrame(size: content.frame.size, linkRect: anchorRect, screenFrame: screenFrame)
        let panel = self.panel ?? makePanel()
        self.panel = panel
        panel.appearance = parent.effectiveAppearance
        panel.contentView = content
        panel.setFrame(frame, display: false)
        if panel.parent !== parent {
            panel.parent?.removeChildWindow(panel)
            parent.addChildWindow(panel, ordered: .above)
        }
        panel.orderFront(nil)
        isShowing = true
        installMonitors(parent: parent)
    }

    private func makePanel() -> NSPanel {
        let panel = NSPanel(contentRect: .zero, styleMask: [.borderless, .nonactivatingPanel], backing: .buffered, defer: true)
        panel.isOpaque = false
        panel.backgroundColor = .clear
        panel.hasShadow = true
        panel.isReleasedWhenClosed = false
        panel.hidesOnDeactivate = true
        panel.animationBehavior = .none
        return panel
    }

    private func installMonitors(parent: NSWindow) {
        if eventMonitor == nil {
            let mask: NSEvent.EventTypeMask = [.keyDown, .leftMouseDown, .rightMouseDown, .otherMouseDown, .scrollWheel, .magnify]
            eventMonitor = NSEvent.addLocalMonitorForEvents(matching: mask) { [weak self] event in
                guard let self, self.isShowing else { return event }
                return self.handle(event)
            }
        }
        if resignObserver == nil {
            resignObserver = NotificationCenter.default.addObserver(forName: NSWindow.didResignKeyNotification, object: parent, queue: .main) { [weak self] _ in
                MainActor.assumeIsolated { self?.dismiss() }
            }
        }
    }

    private func handle(_ event: NSEvent) -> NSEvent? {
        switch event.type {
        case .keyDown:
            let isReturn = event.keyCode == 36 || event.keyCode == 76
            let isArrow = event.keyCode == 123 || event.keyCode == 124
            if event.keyCode == 53 {                        // Esc
                dismiss()
                return nil
            } else if isReturn, !candidates.isEmpty {
                openCurrent()
                return nil
            } else if isArrow, candidates.count > 1 {
                step(event.keyCode == 123 ? -1 : 1)
                return nil
            }
            dismiss()
            return event
        case .scrollWheel, .magnify:
            if event.window !== panel { dismiss() }
            return event
        default:
            if event.window !== panel { dismiss() }
            return event
        }
    }
}

/// Plain view that reports clicks, accepting the first one even though the panel never becomes key.
private final class ClickableView: NSView {
    var onClick: (() -> Void)?
    override func acceptsFirstMouse(for event: NSEvent?) -> Bool { true }
    override func mouseDown(with event: NSEvent) { onClick?() }
    override func resetCursorRects() { addCursorRect(bounds, cursor: .pointingHand) }
}

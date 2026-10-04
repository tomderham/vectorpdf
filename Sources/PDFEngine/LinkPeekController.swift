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

/// The rendered target region, and the link's position on screen.
struct LinkPeekContent {
    let image: NSImage
    let linkScreenRect: NSRect
}

/// Chrome-less preview of a link's target, shown while Command is held over the link or during a
/// Force Click. Never takes focus or mouse events, so clicks reach the link underneath.
@MainActor
final class LinkPeekController {
    /// Delay before showing, so pressing Command for a shortcut doesn't flash a peek.
    static let showDelay: Duration = .milliseconds(200)

    private var panel: NSPanel?
    private var pendingTask: Task<Void, Never>?
    /// Link currently shown, or about to be shown.
    private(set) var targetId: UUID?
    private(set) var isShowing = false

    /// Shows `link` after `showDelay`, or at once for a Force Click or when already peeking.
    func request(
        _ link: SnapshotTarget,
        immediate: Bool = false,
        parent: NSWindow,
        content: @escaping @MainActor (SnapshotTarget) async -> LinkPeekContent?
    ) {
        guard link.id != targetId else { return }
        pendingTask?.cancel()
        targetId = link.id
        let skipDelay = immediate || isShowing
        pendingTask = Task { @MainActor [weak self, weak parent] in
            if !skipDelay {
                try? await Task.sleep(for: Self.showDelay)
            }
            guard !Task.isCancelled, let content = await content(link), !Task.isCancelled,
                  let self, let parent, self.targetId == link.id else { return }
            self.present(content, parent: parent)
        }
    }

    func dismiss() {
        pendingTask?.cancel()
        pendingTask = nil
        targetId = nil
        isShowing = false
        if let panel {
            panel.parent?.removeChildWindow(panel)
            panel.orderOut(nil)
        }
    }

    private func present(_ content: LinkPeekContent, parent: NSWindow) {
        let screenFrame = (parent.screen ?? NSScreen.main)?.visibleFrame ?? parent.frame
        let maxSize = NSSize(
            width: min(parent.frame.width - 32, 900),
            height: parent.frame.height * 0.4
        )
        let size = NSSize(
            width: min(content.image.size.width, maxSize.width),
            height: min(content.image.size.height, maxSize.height)
        )
        let isTruncated = content.image.size.width > size.width + 0.5 || content.image.size.height > size.height + 0.5
        let frame = Self.panelFrame(size: size, linkRect: content.linkScreenRect, screenFrame: screenFrame)

        let panel = self.panel ?? makePanel()
        self.panel = panel
        panel.contentView = Self.makeContentView(image: content.image, size: size, isTruncated: isTruncated)
        panel.setFrame(frame, display: false)
        if panel.parent !== parent {
            panel.parent?.removeChildWindow(panel)
            parent.addChildWindow(panel, ordered: .above)
        }
        panel.orderFront(nil)
        isShowing = true
    }

    private func makePanel() -> NSPanel {
        let panel = NSPanel(contentRect: .zero, styleMask: [.borderless, .nonactivatingPanel], backing: .buffered, defer: true)
        panel.isOpaque = false
        panel.backgroundColor = .clear
        panel.hasShadow = true
        panel.ignoresMouseEvents = true
        panel.isReleasedWhenClosed = false
        panel.hidesOnDeactivate = true
        panel.animationBehavior = .none
        return panel
    }

    private static func makeContentView(image: NSImage, size: NSSize, isTruncated: Bool) -> NSView {
        let container = NSView(frame: NSRect(origin: .zero, size: size))
        container.wantsLayer = true
        container.layer?.cornerRadius = 6
        container.layer?.masksToBounds = true
        container.layer?.borderWidth = 1
        container.layer?.borderColor = NSColor.separatorColor.cgColor

        // Top-left pinned, so truncation cuts the bottom/right.
        let imageLayer = CALayer()
        imageLayer.contents = image
        imageLayer.contentsGravity = .topLeft
        imageLayer.contentsScale = image.recommendedLayerContentsScale(0)
        imageLayer.frame = container.bounds
        container.layer?.addSublayer(imageLayer)

        if isTruncated {
            let fadeHeight = min(48, size.height / 2)
            let fade = CAGradientLayer()
            let base = NSColor.windowBackgroundColor
            fade.colors = [base.withAlphaComponent(0).cgColor, base.withAlphaComponent(0.95).cgColor]
            fade.startPoint = CGPoint(x: 0.5, y: 1)
            fade.endPoint = CGPoint(x: 0.5, y: 0)
            fade.frame = CGRect(x: 0, y: 0, width: size.width, height: fadeHeight)
            container.layer?.addSublayer(fade)

            let hint = NSTextField(labelWithString: "⌘-click to open")
            hint.font = .systemFont(ofSize: NSFont.smallSystemFontSize)
            hint.textColor = .secondaryLabelColor
            hint.sizeToFit()
            hint.setFrameOrigin(NSPoint(x: size.width - hint.frame.width - 8, y: 4))
            container.addSubview(hint)
        }
        return container
    }

    /// Below the link, or above when there's no room, kept on screen. Screen coordinates.
    static func panelFrame(size: NSSize, linkRect: NSRect, screenFrame: NSRect, gap: CGFloat = 6, margin: CGFloat = 8) -> NSRect {
        let roomBelow = linkRect.minY - gap - screenFrame.minY
        let roomAbove = screenFrame.maxY - (linkRect.maxY + gap)
        let y: CGFloat
        if roomBelow >= size.height || roomBelow >= roomAbove {
            y = max(screenFrame.minY, linkRect.minY - gap - size.height)
        } else {
            y = min(screenFrame.maxY - size.height, linkRect.maxY + gap)
        }
        let x = max(screenFrame.minX + margin, min(linkRect.minX, screenFrame.maxX - margin - size.width))
        return NSRect(x: x, y: y, width: size.width, height: size.height)
    }
}

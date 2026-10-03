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
import SwiftUI

/// An internal background view representing the rounded tab card.
/// Automatically listens for tab button frame/bounds changes and executes dynamic layout synchronization.
@MainActor
final class TabCardBackgroundView: NSView {
    weak var helper: TabBarAppearanceHelper?
    private var frameObserver: (any NSObjectProtocol)?
    private var boundsObserver: (any NSObjectProtocol)?

    private func cleanupObservers() {
        if let observer = frameObserver {
            NotificationCenter.default.removeObserver(observer)
            frameObserver = nil
        }
        if let observer = boundsObserver {
            NotificationCenter.default.removeObserver(observer)
            boundsObserver = nil
        }
    }

    override func viewWillMove(toSuperview newSuperview: NSView?) {
        super.viewWillMove(toSuperview: newSuperview)
        if newSuperview == nil {
            cleanupObservers()
        }
    }

    override func viewDidMoveToSuperview() {
        super.viewDidMoveToSuperview()
        cleanupObservers()
        guard let button = superview else { return }
        button.postsFrameChangedNotifications = true
        button.postsBoundsChangedNotifications = true
        frameObserver = NotificationCenter.default.addObserver(
            forName: NSView.frameDidChangeNotification,
            object: button,
            queue: .main
        ) { [weak self, weak button] _ in
            MainActor.assumeIsolated {
                guard let self, let button else { return }
                self.helper?.synchronizeTabLayout(for: button, bg: self)
            }
        }
        boundsObserver = NotificationCenter.default.addObserver(
            forName: NSView.boundsDidChangeNotification,
            object: button,
            queue: .main
        ) { [weak self, weak button] _ in
            MainActor.assumeIsolated {
                guard let self, let button else { return }
                self.helper?.synchronizeTabLayout(for: button, bg: self)
            }
        }
    }

    override func layout() {
        super.layout()
        if let button = superview {
            helper?.synchronizeTabLayout(for: button, bg: self)
        }
    }
}

/// Helper that provides visual styling for active vs. inactive window tabs.
@MainActor
public final class TabBarAppearanceHelper {
    public static let shared = TabBarAppearanceHelper()

    private let activeCardBgId = NSUserInterfaceItemIdentifier("VectorPDFTabBarActiveCardBg")
    private let activeIndicatorId = NSUserInterfaceItemIdentifier("VectorPDFTabBarActiveIndicator")

    /// Horizontal gap between a tab's card and its button edge; two adjacent tabs are separated by twice this.
    private let tabSideInset: CGFloat = 1
    private let tabBarBackingLayerName = "VectorPDFTabBarBacking"

    private var topBarEventMonitor: Any?
    private var appearanceObservation: NSKeyValueObservation?
    /// Windows whose sidebar/split view resized since the last coalesced refresh.
    private let splitResizeWindows = NSHashTable<NSWindow>.weakObjects()
    private var isSplitResizeRefreshScheduled = false

    /// How far (in points) `view`'s left edge extends into the window's sidebar column, or 0 when
    /// there is no sidebar to overlap. The system tab bar is laid out from the sidebar's nominal
    /// edge, so its first tab's rounded corner can poke past the sidebar's drawn edge.
    private func sidebarOverlap(of view: NSView) -> CGFloat {
        guard let window = view.window, let content = window.contentView else { return 0 }
        func findSplit(_ v: NSView, _ depth: Int) -> NSSplitView? {
            if let s = v as? NSSplitView, s.arrangedSubviews.count >= 2 { return s }
            guard depth < 10 else { return nil }
            for sub in v.subviews { if let f = findSplit(sub, depth + 1) { return f } }
            return nil
        }
        guard let split = findSplit(content, 0), let sidebar = split.arrangedSubviews.first, !sidebar.isHidden, sidebar.frame.width > 1 else { return 0 }
        // The divider sits between the two panes (e.g. sidebar ends at 260, detail starts at 261),
        // so measure to whichever of the two edges is further right.
        var sidebarMaxX = sidebar.convert(sidebar.bounds, to: nil).maxX
        if let detail = split.arrangedSubviews.dropFirst().first {
            sidebarMaxX = max(sidebarMaxX, detail.convert(detail.bounds, to: nil).minX)
        }
        let viewMinX = view.convert(view.bounds, to: nil).minX
        return max(0, sidebarMaxX - viewMinX)
    }

    private init() {
        DocumentWindowing.installTabBarPlusButtonHandler()

        // Global monitor for right-clicks anywhere in the top bar / toolbar / titlebar of any window
        topBarEventMonitor = NSEvent.addLocalMonitorForEvents(matching: .rightMouseDown) { event in
            guard let window = event.window else { return event }
            let loc = event.locationInWindow
            let titlebarHeight = window.frame.height - window.contentLayoutRect.height
            let effectiveHeight = max(titlebarHeight, 52.0)
            guard loc.y >= window.frame.height - effectiveHeight else { return event }

            let hit = (window.contentView?.superview ?? window.contentView)?.hitTest(loc)
            let hitName = hit.map { String(describing: type(of: $0)) } ?? ""
            if hitName.contains("TextField") || hitName.contains("Search") {
                return event
            }

            if let menu = DocumentContextMenuHelper.buildMenu(for: PDFViewerViewModel.active) {
                NSMenu.popUpContextMenu(menu, with: event, for: hit ?? window.contentView ?? NSView())
                return nil // Suppress default toolbar customization menu
            }
            return event
        }

        NotificationCenter.default.addObserver(
            forName: NSWindow.didBecomeKeyNotification,
            object: nil,
            queue: .main
        ) { [weak self] notif in
            guard let self else { return }
            if let window = notif.object as? NSWindow {
                MainActor.assumeIsolated {
                    self.refreshTabs(for: window)
                }
            }
        }

        NotificationCenter.default.addObserver(
            forName: NSWindow.didBecomeMainNotification,
            object: nil,
            queue: .main
        ) { [weak self] notif in
            guard let self else { return }
            if let window = notif.object as? NSWindow {
                MainActor.assumeIsolated {
                    self.refreshTabs(for: window)
                }
            }
        }

        NotificationCenter.default.addObserver(
            forName: NSWindow.didResignKeyNotification,
            object: nil,
            queue: .main
        ) { [weak self] notif in
            guard let self else { return }
            if let window = notif.object as? NSWindow {
                MainActor.assumeIsolated {
                    self.refreshTabs(for: window)
                }
            }
        }

        for name in [NSWindow.didResignMainNotification, NSApplication.didBecomeActiveNotification, NSApplication.didResignActiveNotification] {
            NotificationCenter.default.addObserver(forName: name, object: nil, queue: .main) { [weak self] notif in
                guard let self else { return }
                if let window = notif.object as? NSWindow {
                    MainActor.assumeIsolated { self.refreshTabs(for: window) }
                } else {
                    MainActor.assumeIsolated {
                        for window in NSApp.windows where window.tabGroup != nil { self.refreshTabs(for: window) }
                    }
                }
            }
        }

        NotificationCenter.default.addObserver(
            forName: NSWindow.didResizeNotification,
            object: nil,
            queue: .main
        ) { [weak self] notif in
            guard let self else { return }
            if let window = notif.object as? NSWindow {
                MainActor.assumeIsolated {
                    self.refreshTabs(for: window)
                }
            }
        }

        NotificationCenter.default.addObserver(
            forName: NSWindow.willCloseNotification,
            object: nil,
            queue: .main
        ) { [weak self] notif in
            guard let self else { return }
            if let closingWindow = notif.object as? NSWindow {
                MainActor.assumeIsolated {
                    var siblingWindows = (closingWindow.tabGroup?.windows ?? closingWindow.tabbedWindows ?? []).filter { $0 !== closingWindow }
                    if siblingWindows.isEmpty {
                        for otherWin in NSApp.windows where otherWin !== closingWindow {
                            if otherWin.tabGroup?.windows.contains(where: { $0 === closingWindow }) == true ||
                               otherWin.tabbedWindows?.contains(where: { $0 === closingWindow }) == true {
                                siblingWindows.append(otherWin)
                            }
                        }
                    }
                    guard !siblingWindows.isEmpty else { return }

                    for win in siblingWindows {
                        self.refreshTabs(for: win)
                    }
                    DispatchQueue.main.async { [weak self] in
                        guard let self else { return }
                        for win in siblingWindows {
                            self.refreshTabs(for: win)
                        }
                    }
                    DispatchQueue.main.asyncAfter(deadline: .now() + 0.15) { [weak self] in
                        guard let self else { return }
                        for win in siblingWindows {
                            self.refreshTabs(for: win)
                        }
                    }
                    DispatchQueue.main.asyncAfter(deadline: .now() + 0.3) { [weak self] in
                        guard let self else { return }
                        for win in siblingWindows {
                            self.refreshTabs(for: win)
                        }
                    }
                }
            }
        }

        // Coalesce sidebar resize tab layout updates to once per frame.
        NotificationCenter.default.addObserver(
            forName: NSSplitView.didResizeSubviewsNotification,
            object: nil,
            queue: .main
        ) { [weak self] notif in
            guard let self, let window = (notif.object as? NSSplitView)?.window else { return }
            MainActor.assumeIsolated {
                guard window.tabGroup != nil else { return }
                self.scheduleSplitResizeRefresh(for: window)
            }
        }

        // Restyle tab backing layers when app appearance changes.
        appearanceObservation = NSApp.observe(\.effectiveAppearance, options: [.new]) { [weak self] _, _ in
            Task { @MainActor [weak self] in
                guard let self else { return }
                for window in NSApp.windows where window.tabGroup != nil {
                    self.refreshTabs(for: window)
                }
            }
        }
    }

    private func scheduleSplitResizeRefresh(for window: NSWindow) {
        splitResizeWindows.add(window)
        guard !isSplitResizeRefreshScheduled else { return }
        isSplitResizeRefreshScheduled = true
        DispatchQueue.main.asyncAfter(deadline: .now() + 1.0 / 30.0) { [weak self] in
            guard let self else { return }
            self.isSplitResizeRefreshScheduled = false
            let windows = self.splitResizeWindows.allObjects
            self.splitResizeWindows.removeAllObjects()
            for window in windows {
                self.refreshTabs(for: window)
            }
        }
    }

    /// Refreshes the visual styling of all tabs belonging to the given window's tab group.
    public func refreshTabs(for window: NSWindow?) {
        guard let window else { return }

        let windowsToUpdate: [NSWindow]
        if let tabGroup = window.tabGroup, tabGroup.windows.count > 1 {
            windowsToUpdate = tabGroup.windows
            let activeWindow = tabGroup.selectedWindow ?? (window.isKeyWindow ? window : tabGroup.windows.first)
            for win in tabGroup.windows {
                let isSelected = (win === activeWindow)
                updateTabTitle(for: win, isSelected: isSelected)
                (win.contentViewController as? NSHostingController<PDFViewerMainView>)?.rootView.viewModel.updateTitlebarHeight()
            }
        } else {
            windowsToUpdate = [window]
            updateTabTitle(for: window, isSelected: true)
            (window.contentViewController as? NSHostingController<PDFViewerMainView>)?.rootView.viewModel.updateTitlebarHeight()
        }

        func applyStyling() {
            for win in windowsToUpdate {
                if let frameView = win.contentView?.superview {
                    styleTopBar(in: frameView)
                    styleTabButtons(in: frameView)
                }
            }
        }

        applyStyling()
        DispatchQueue.main.async { [weak window] in
            guard let window, window.windowNumber > 0 else { return }
            applyStyling()
        }
    }

    /// Static convenience method for `shared.refreshTabs(for:)`.
    public static func refreshTabs(for window: NSWindow?) {
        shared.refreshTabs(for: window)
    }

    private func updateTabTitle(for window: NSWindow, isSelected: Bool) {
        var title = window.title.trimmingCharacters(in: .whitespacesAndNewlines)
        if title.isEmpty, let url = window.representedURL {
            title = url.lastPathComponent
        }
        if title.isEmpty, let vmTitle = (window.contentViewController as? NSHostingController<PDFViewerMainView>)?.rootView.viewModel.documentTitle, !vmTitle.isEmpty {
            title = vmTitle
        }
        if title.isEmpty {
            title = "VectorPDF"
        }
        if window.title.isEmpty {
            window.title = title
            window.titleVisibility = .hidden
        }
        let font = NSFont.systemFont(ofSize: 11, weight: isSelected ? .medium : .regular)
        // Unselected tabs stay legible; everything dims when the window group is inactive.
        let groupActive = NSApp.isActive && (window.tabGroup?.windows ?? [window]).contains { $0.isKeyWindow }
        let color: NSColor
        if isSelected {
            color = groupActive ? NSColor.labelColor : NSColor.secondaryLabelColor
        } else {
            color = NSColor.labelColor.withAlphaComponent(groupActive ? 0.72 : 0.5)
        }

        let attrTitle = NSAttributedString(string: title, attributes: [
            .font: font,
            .foregroundColor: color
        ])

        window.tab.attributedTitle = attrTitle
        window.tab.title = title
        window.tab.toolTip = title
    }

    private func styleTopBar(in frameView: NSView) {
        func clearBackgrounds(_ v: NSView) {
            if let win = v.window, v === win.contentView {
                return
            }
            let className = String(describing: type(of: v))
            if className == "NSTitlebarContainerView" || className == "NSTitlebarBackgroundView" || className == "NSToolbarView" {
                v.layer?.backgroundColor = nil
            }
            if className == "NSTitlebarSeparatorView" {
                v.isHidden = true
                v.alphaValue = 0.0
            }
            // Match tab bar background to toolbar color.
            if className == "NSTitlebarAccessoryContainerView" {
                v.wantsLayer = true
                var barColor = NSColor.topWindowBarColor.cgColor
                v.effectiveAppearance.performAsCurrentDrawingAppearance {
                    barColor = NSColor.topWindowBarColor.cgColor
                }
                // Inset from the sidebar's trailing edge so the backing never paints over it.
                let overlap = sidebarOverlap(of: v)
                v.layer?.backgroundColor = nil
                let backing: CALayer
                if let existing = v.layer?.sublayers?.first(where: { $0.name == tabBarBackingLayerName }) {
                    backing = existing
                } else {
                    backing = CALayer()
                    backing.name = tabBarBackingLayerName
                    v.layer?.insertSublayer(backing, at: 0)
                }
                // Disable implicit CALayer animations during live window or sidebar resize.
                CATransaction.begin()
                CATransaction.setDisableActions(true)
                backing.backgroundColor = barColor
                backing.frame = CGRect(x: overlap, y: 0, width: max(0, v.bounds.width - overlap), height: v.bounds.height)
                CATransaction.commit()
            }
            // Hide default tab bar background view.
            if className == "NSView",
               v.layer?.backgroundColor != nil,
               let parent = v.superview, String(describing: type(of: parent)) == "NSView",
               let grand = parent.superview, String(describing: type(of: grand)) == "NSTabBar" {
                v.isHidden = true
                v.layer?.backgroundColor = nil
            }
            if className.contains("SubduedGlass") {
                v.isHidden = true
                v.alphaValue = 0.0
            }
            // Hide background inversion layers behind curved tabs.
            if let l = v.layer {
                if let name = l.name, name.contains("VibrantColorMatrix") || name.contains("Inversion") || name.contains("FilterHost") {
                    l.backgroundColor = nil
                    l.filters = nil
                    l.opacity = 0.0
                    l.isHidden = true
                }
                for sl in l.sublayers ?? [] {
                    if let sname = sl.name, sname.contains("VibrantColorMatrix") || sname.contains("Inversion") {
                        sl.backgroundColor = nil
                        sl.filters = nil
                        sl.opacity = 0.0
                        sl.isHidden = true
                    }
                }
            }
            for sub in v.subviews {
                clearBackgrounds(sub)
            }
        }
        clearBackgrounds(frameView)
    }

    private func styleTabButtons(in root: NSView) {
        // Do not recurse into the window's main contentView (document viewer / split view / canvas)
        if let win = root.window, root === win.contentView {
            return
        }

        let className = String(describing: type(of: root))
        if className.contains("Separator") || className.contains("Divider") {
            root.isHidden = true
            root.alphaValue = 0.0
            return
        }

        // 1. New Tab (+) Button
        if className == "NSTabBarNewTabButton" || className.contains("NewTab") {
            updateNewTabButton(root)
            return
        }

        // 2. Tab Bar Buttons
        if className == "NSTabButton" || (className.contains("TabButton") && !className.contains("NewTab")) {
            let tabCount = root.window?.tabGroup?.windows.count ?? (root.window?.tabbedWindows?.count ?? 1)
            let isSingle = tabCount <= 1
            let active: Bool
            if isSingle {
                active = true
            } else if root.responds(to: NSSelectorFromString("isActive")) {
                active = (root.value(forKey: "isActive") as? Bool) ?? false
            } else if root.responds(to: NSSelectorFromString("active")) {
                active = (root.value(forKey: "active") as? Bool) ?? false
            } else {
                active = false
            }
            updateSingleTabButton(root, isActive: active)
            return
        }

        for sub in root.subviews {
            styleTabButtons(in: sub)
        }
    }

    private func updateNewTabButton(_ button: NSView) {
        let isDark = button.effectiveAppearance.bestMatch(from: [.darkAqua, .aqua]) == .darkAqua
        button.wantsLayer = true
        let diameter = min(max(button.frame.width, 24.0), max(button.frame.height, 24.0))
        let radius = diameter / 2.0
        button.layer?.cornerRadius = radius
        button.layer?.cornerCurve = .continuous
        button.layer?.masksToBounds = true
        button.layer?.backgroundColor = isDark
            ? NSColor(white: 1.0, alpha: 0.10).cgColor
            : NSColor(white: 0.0, alpha: 0.06).cgColor
        button.layer?.borderColor = isDark
            ? NSColor(white: 1.0, alpha: 0.12).cgColor
            : NSColor(white: 0.0, alpha: 0.08).cgColor
        button.layer?.borderWidth = 0.5

        func roundChildViews(_ v: NSView) {
            v.wantsLayer = true
            v.layer?.cornerRadius = radius
            v.layer?.cornerCurve = .continuous
            v.layer?.masksToBounds = true
            for sub in v.subviews {
                roundChildViews(sub)
            }
        }
        for sub in button.subviews {
            roundChildViews(sub)
        }
    }

    private func updateSingleTabButton(_ button: NSView, isActive: Bool) {
        let isDark = button.effectiveAppearance.bestMatch(from: [.darkAqua, .aqua]) == .darkAqua

        button.isHidden = false
        button.alphaValue = 1.0
        button.wantsLayer = true
        button.layer?.cornerRadius = 12.0
        button.layer?.cornerCurve = .continuous
        button.layer?.masksToBounds = true

        // Ensure internal glass and inversion layers match the continuous oval corner radius and don't paint dark inversion backgrounds
        func roundInternalGlassViews(_ v: NSView) {
            let subClass = String(describing: type(of: v))
            if subClass.contains("RootView") {
                v.isHidden = true
                v.alphaValue = 0.0
                return
            }
            if subClass.contains("Glass") || subClass.contains("Inversion") {
                v.wantsLayer = true
                v.layer?.cornerRadius = 12.0
                v.layer?.cornerCurve = .continuous
                if let l = v.layer {
                    if let name = l.name, name.contains("VibrantColorMatrix") || name.contains("Inversion") {
                        l.backgroundColor = nil
                        l.filters = nil
                        l.opacity = 0.0
                        l.isHidden = true
                    }
                    for sl in l.sublayers ?? [] {
                        if let sname = sl.name, sname.contains("VibrantColorMatrix") || sname.contains("Inversion") {
                            sl.backgroundColor = nil
                            sl.filters = nil
                            sl.opacity = 0.0
                            sl.isHidden = true
                        }
                    }
                }
            }
            for sub in v.subviews {
                roundInternalGlassViews(sub)
            }
        }
        roundInternalGlassViews(button)

        // Remove document/PDF file icons from the tab while preserving the close button
        func removeTabIcons(_ v: NSView) {
            if v.identifier?.rawValue == "_closeButton" {
                return
            }
            if let iv = v as? NSImageView {
                iv.isHidden = true
                iv.image = nil
            }
            if v.identifier?.rawValue == "_placeholderAccessoryViewForCentering" {
                v.isHidden = true
            }
            for sub in v.subviews {
                removeTabIcons(sub)
            }
        }
        removeTabIcons(button)

        let bg = ensureTabCardBackground(for: button)
        synchronizeTabLayout(for: button, bg: bg)

        if isActive {
            // 1. Active Tab: elevated prominent card with shadow
            bg.layer?.backgroundColor = isDark
                ? NSColor(white: 0.32, alpha: 0.95).cgColor
                : NSColor(white: 1.0, alpha: 0.96).cgColor
            bg.layer?.borderColor = isDark
                ? NSColor(white: 1.0, alpha: 0.18).cgColor
                : NSColor(white: 0.0, alpha: 0.12).cgColor
            bg.layer?.borderWidth = 1.0
            bg.layer?.shadowColor = NSColor.black.cgColor
            bg.layer?.shadowOpacity = isDark ? 0.35 : 0.08
            bg.layer?.shadowRadius = 2.0
            bg.layer?.shadowOffset = CGSize(width: 0, height: -1)
        } else {
            // 2. Inactive Tab: subtle oval pill blending into the track without rectangular dark grey box
            bg.layer?.backgroundColor = isDark
                ? NSColor(white: 1.0, alpha: 0.08).cgColor
                : NSColor(white: 0.0, alpha: 0.06).cgColor
            bg.layer?.borderColor = isDark
                ? NSColor(white: 1.0, alpha: 0.12).cgColor
                : NSColor(white: 0.0, alpha: 0.08).cgColor
            bg.layer?.borderWidth = 0.5
            bg.layer?.shadowOpacity = 0.0
        }
        button.layer?.borderWidth = 0
    }

    @discardableResult
    func ensureTabCardBackground(for button: NSView) -> TabCardBackgroundView {
        let existingBg = button.subviews.first(where: { $0.identifier == activeCardBgId })
        if let existingCard = existingBg as? TabCardBackgroundView {
            existingCard.helper = self
            return existingCard
        }
        existingBg?.removeFromSuperview()
        let newBg = TabCardBackgroundView()
        newBg.helper = self
        newBg.identifier = activeCardBgId
        newBg.translatesAutoresizingMaskIntoConstraints = false
        newBg.wantsLayer = true
        button.addSubview(newBg, positioned: .below, relativeTo: button.subviews.first)
        NSLayoutConstraint.activate([
            newBg.leadingAnchor.constraint(equalTo: button.leadingAnchor, constant: tabSideInset),
            newBg.trailingAnchor.constraint(equalTo: button.trailingAnchor, constant: -tabSideInset),
            newBg.topAnchor.constraint(equalTo: button.topAnchor, constant: 2),
            newBg.bottomAnchor.constraint(equalTo: button.bottomAnchor, constant: -2)
        ])
        newBg.layer?.cornerRadius = 12.0
        newBg.layer?.cornerCurve = .continuous
        return newBg
    }

    /// Synchronizes the layout, mask layer, and alignment of a single tab button dynamically.
    /// Called on view layout, frame changes, bounds changes, and tab refresh passes.
    func synchronizeTabLayout(for button: NSView, bg: NSView? = nil) {
        guard button.bounds.width > 12, button.bounds.height > 8 else { return }
        let bgView = bg ?? ensureTabCardBackground(for: button)

        // Remove vertical tab divider lines.
        for sub in button.subviews where sub !== bgView
            && String(describing: type(of: sub)) == "NSView"
            && sub.frame.width <= 1.5
            && sub.frame.height >= button.frame.height - 1
            && sub.layer?.backgroundColor != nil {
            sub.isHidden = true
            sub.layer?.backgroundColor = nil
        }

        // Align leftmost tab with sidebar trailing edge.
        var shift: CGFloat = 0
        let isLeftmost: Bool
        if let superview = button.superview {
            let tabButtons = superview.subviews.filter {
                let name = String(describing: type(of: $0))
                return name.contains("TabButton") && !name.contains("NewTab")
            }
            if let leftmost = tabButtons.min(by: { $0.frame.minX < $1.frame.minX }) {
                isLeftmost = (button === leftmost)
            } else {
                isLeftmost = false
            }
        } else {
            isLeftmost = false
        }

        if isLeftmost {
            var container: NSView? = button
            while let c = container, String(describing: type(of: c)) != "NSTitlebarAccessoryContainerView" {
                container = c.superview
            }
            let overlap = container.map { sidebarOverlap(of: $0) } ?? 0
            shift = overlap > 0 ? overlap + 6 : 0
        }
        if let c = button.constraints.first(where: { $0.firstItem === bgView && $0.firstAttribute == .leading }), c.constant != tabSideInset + shift {
            c.constant = tabSideInset + shift
        }

        // Reset shift on sibling tabs.
        if isLeftmost, let superview = button.superview {
            let siblings = superview.subviews.filter {
                $0 !== button && String(describing: type(of: $0)).contains("TabButton") && !String(describing: type(of: $0)).contains("NewTab")
            }
            for sib in siblings {
                if let sibBg = sib.subviews.first(where: { $0.identifier == activeCardBgId }),
                   let c = sib.constraints.first(where: { $0.firstItem === sibBg && $0.firstAttribute == .leading }),
                   c.constant != tabSideInset {
                    c.constant = tabSideInset
                    if let layer = sib.layer, let maskLayer = layer.mask as? CAShapeLayer {
                        let cardWidth = max(0, sib.bounds.width - 2 * tabSideInset)
                        let cardHeight = max(0, sib.bounds.height - 4)
                        let rect = CGRect(x: tabSideInset, y: 2, width: cardWidth, height: cardHeight)
                        maskLayer.frame = sib.bounds
                        maskLayer.path = tabCardPath(for: rect)
                    }
                    for sub in sib.subviews where String(describing: type(of: sub)) == "NSView" && sub.subviews.contains(where: { $0 is NSStackView }) {
                        if sub.bounds.origin.x != 0 {
                            sub.bounds.origin.x = 0
                        }
                    }
                }
            }
        }

        // Clip button to card shape.
        if let layer = button.layer {
            let maskLayer: CAShapeLayer
            if let existing = layer.mask as? CAShapeLayer {
                maskLayer = existing
            } else {
                maskLayer = CAShapeLayer()
                layer.mask = maskLayer
            }
            let cardWidth = max(0, button.bounds.width - 2 * tabSideInset - shift)
            let cardHeight = max(0, button.bounds.height - 4)
            let rect = CGRect(x: tabSideInset + shift, y: 2, width: cardWidth, height: cardHeight)
            maskLayer.frame = button.bounds
            maskLayer.path = tabCardPath(for: rect)
        }
        for sub in button.subviews where String(describing: type(of: sub)) == "NSView" && sub.subviews.contains(where: { $0 is NSStackView }) {
            if sub.bounds.origin.x != -shift {
                sub.bounds.origin.x = -shift
            }
            // Inset close button and center title.
            for stack in sub.subviews.compactMap({ $0 as? NSStackView }) {
                var insets = stack.edgeInsets
                if insets.left != 12 || insets.right != 12 {
                    insets.left = 12
                    insets.right = 12
                    stack.edgeInsets = insets
                }
            }
        }
    }
}

/// A rounded rect with corner radius clamped to at most half the rect's width or height.
private func tabCardPath(for rect: CGRect) -> CGPath {
    let radius = max(0, min(12, rect.width / 2, rect.height / 2))
    return CGPath(roundedRect: rect, cornerWidth: radius, cornerHeight: radius, transform: nil)
}

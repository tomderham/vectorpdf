import AppKit

/// Helper that provides clear, standard macOS Golden Gate (macOS 27) visual indications for active vs. inactive window tabs.
///
/// In macOS 27 Golden Gate, navigation layers use Liquid Glass. Per Apple's Human Interface Guidelines,
/// active elements require elevated hierarchy and accent differentiation so they don't get lost
/// in the diffused glass background:
/// - **Active/Selected Tab:** Elevated semi-opaque card fill, subtle specular border/shadow,
///   prominent text (`NSColor.labelColor` with `.medium` font weight), and an accent indicator bar
///   drawn in the user's system `NSColor.controlAccentColor`.
/// - **Inactive Tabs:** Translucent, receding into the Liquid Glass track with muted secondary text (`NSColor.secondaryLabelColor`).
@MainActor
public final class TabBarAppearanceHelper {
    public static let shared = TabBarAppearanceHelper()

    private let activeCardBgId = NSUserInterfaceItemIdentifier("VectorPDFTabBarActiveCardBg")
    private let activeIndicatorId = NSUserInterfaceItemIdentifier("VectorPDFTabBarActiveIndicator")

    private init() {
        DocumentWindowing.installTabBarPlusButtonHandler()

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
    }

    /// Refreshes the visual styling of all tabs belonging to the given window's tab group.
    public func refreshTabs(for window: NSWindow?) {
        guard let window else { return }

        if let tabGroup = window.tabGroup, tabGroup.windows.count > 1 {
            let activeWindow = tabGroup.selectedWindow ?? (window.isKeyWindow ? window : tabGroup.windows.first)
            for win in tabGroup.windows {
                let isSelected = (win === activeWindow)
                updateTabTitle(for: win, isSelected: isSelected)
            }
        } else {
            updateTabTitle(for: window, isSelected: true)
        }

        // Style the tab bar buttons in the window hierarchy
        if let frameView = window.contentView?.superview {
            styleTabButtons(in: frameView)
        }
    }

    /// Static convenience method for `shared.refreshTabs(for:)`.
    public static func refreshTabs(for window: NSWindow?) {
        shared.refreshTabs(for: window)
    }

    private func updateTabTitle(for window: NSWindow, isSelected: Bool) {
        let title = window.title.isEmpty ? "VectorPDF" : window.title
        let font = NSFont.systemFont(ofSize: 11, weight: isSelected ? .medium : .regular)
        let color = isSelected ? NSColor.labelColor : NSColor.secondaryLabelColor

        let attrTitle = NSAttributedString(string: title, attributes: [
            .font: font,
            .foregroundColor: color
        ])

        window.tab.attributedTitle = attrTitle
        window.tab.toolTip = title
    }

    private func styleTabButtons(in root: NSView) {
        let isActiveSelector = NSSelectorFromString("isActive")
        if root.responds(to: isActiveSelector) {
            let active = (root.value(forKey: "active") as? Bool) ?? false
            updateSingleTabButton(root, isActive: active)
        }
        for sub in root.subviews {
            styleTabButtons(in: sub)
        }
    }

    private func updateSingleTabButton(_ button: NSView, isActive: Bool) {
        let existingBg = button.subviews.first(where: { $0.identifier == activeCardBgId })
        let existingIndicator = button.subviews.first(where: { $0.identifier == activeIndicatorId })

        if isActive {
            let isDark = button.effectiveAppearance.bestMatch(from: [.darkAqua, .aqua]) == .darkAqua

            // 1. Elevated Card Background
            if existingBg == nil {
                let bg = NSView()
                bg.identifier = activeCardBgId
                bg.translatesAutoresizingMaskIntoConstraints = false
                bg.wantsLayer = true
                bg.layer?.backgroundColor = isDark
                    ? NSColor(white: 0.28, alpha: 0.90).cgColor
                    : NSColor(white: 1.0, alpha: 0.94).cgColor
                bg.layer?.borderColor = isDark
                    ? NSColor(white: 1.0, alpha: 0.16).cgColor
                    : NSColor(white: 0.0, alpha: 0.12).cgColor
                bg.layer?.borderWidth = 1.0
                bg.layer?.cornerRadius = 5.0
                bg.layer?.shadowColor = NSColor.black.cgColor
                bg.layer?.shadowOpacity = isDark ? 0.35 : 0.08
                bg.layer?.shadowRadius = 2.0
                bg.layer?.shadowOffset = CGSize(width: 0, height: -1)
                button.addSubview(bg, positioned: .below, relativeTo: button.subviews.first)
                NSLayoutConstraint.activate([
                    bg.leadingAnchor.constraint(equalTo: button.leadingAnchor, constant: 1),
                    bg.trailingAnchor.constraint(equalTo: button.trailingAnchor, constant: -1),
                    bg.topAnchor.constraint(equalTo: button.topAnchor, constant: 1),
                    bg.bottomAnchor.constraint(equalTo: button.bottomAnchor, constant: -1)
                ])
            } else if let bg = existingBg {
                bg.layer?.backgroundColor = isDark
                    ? NSColor(white: 0.28, alpha: 0.90).cgColor
                    : NSColor(white: 1.0, alpha: 0.94).cgColor
                bg.layer?.borderColor = isDark
                    ? NSColor(white: 1.0, alpha: 0.16).cgColor
                    : NSColor(white: 0.0, alpha: 0.12).cgColor
            }

            existingIndicator?.removeFromSuperview()
        } else {
            // Inactive tab: remove elevated card and any indicator so it recedes into glass
            existingBg?.removeFromSuperview()
            existingIndicator?.removeFromSuperview()
        }
    }
}

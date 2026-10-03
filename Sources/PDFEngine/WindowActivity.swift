import AppKit
import SwiftUI

/// Mirrors the hosting window's key state into SwiftUI (`controlActiveState` goes stale in toolbar views).
private struct WindowActivityTracker: NSViewRepresentable {
    @Binding var isActive: Bool

    func makeNSView(context: Context) -> TrackerView {
        let view = TrackerView()
        view.onChange = { value in
            if isActive != value { isActive = value }
        }
        return view
    }

    func updateNSView(_ nsView: TrackerView, context: Context) {
        nsView.onChange = { value in
            if isActive != value { isActive = value }
        }
        nsView.report()
    }

    final class TrackerView: NSView {
        var onChange: ((Bool) -> Void)?

        override func hitTest(_ point: NSPoint) -> NSView? { nil }

        override func viewDidMoveToWindow() {
            super.viewDidMoveToWindow()
            NotificationCenter.default.removeObserver(self)
            guard let window else { return }
            for name in [NSWindow.didBecomeKeyNotification, NSWindow.didResignKeyNotification,
                         NSWindow.didBecomeMainNotification, NSWindow.didResignMainNotification] {
                NotificationCenter.default.addObserver(self, selector: #selector(stateChanged), name: name, object: window)
            }
            for name in [NSApplication.didBecomeActiveNotification, NSApplication.didResignActiveNotification] {
                NotificationCenter.default.addObserver(self, selector: #selector(stateChanged), name: name, object: nil)
            }
            report()
        }

        @objc private func stateChanged(_ note: Notification) {
            report()
            // Re-check once state settles; notification order isn't guaranteed.
            DispatchQueue.main.async { [weak self] in self?.report() }
        }

        func report() {
            guard let window else { return }
            onChange?(window.isKeyWindow || (window.attachedSheet != nil && window.isMainWindow))
        }
    }
}

extension View {
    /// Keeps `isActive` in sync with the key/main/app-active state of the hosting window.
    func trackWindowActive(_ isActive: Binding<Bool>) -> some View {
        background(WindowActivityTracker(isActive: isActive).frame(width: 0, height: 0))
    }
}

import AppKit
import SwiftUI

/// Presents a full-screen, borderless alert window on every connected display,
/// above regular windows and other spaces (including apps running full-screen).
final class AlertPresenter {

    private var windows: [NSWindow] = []
    private var onDismiss: (() -> Void)?

    func present(_ meeting: UpcomingMeeting, snoozeLabel: String, onJoin: @escaping () -> Void, onSnooze: @escaping () -> Void, onDismiss: @escaping () -> Void) {
        dismiss() // guard against overlapping presentations

        self.onDismiss = onDismiss

        let view = AlertView(
            meeting: meeting,
            snoozeLabel: snoozeLabel,
            onJoin: { [weak self] in
                onJoin()
                self?.dismiss()
            },
            onSnooze: { [weak self] in
                onSnooze()
                self?.dismiss()
            },
            onDismiss: { [weak self] in
                self?.dismiss()
            }
        )

        for screen in NSScreen.screens {
            let window = NSWindow(
                contentRect: screen.frame,
                styleMask: [.borderless],
                backing: .buffered,
                defer: false,
                screen: screen
            )
            window.isOpaque = false
            window.backgroundColor = .clear
            window.hasShadow = false
            window.level = .init(Int(CGWindowLevelForKey(.maximumWindow)))
            window.collectionBehavior = [.canJoinAllSpaces, .fullScreenAuxiliary, .stationary, .ignoresCycle]
            window.ignoresMouseEvents = false
            window.isReleasedWhenClosed = false
            window.contentView = NSHostingView(rootView: view)
            window.setFrame(screen.frame, display: true)
            window.orderFrontRegardless()
            windows.append(window)
        }

        NSApp.activate(ignoringOtherApps: true)
        windows.first?.makeKey()
    }

    func dismiss() {
        windows.forEach { $0.orderOut(nil) }
        windows.removeAll()
        onDismiss?()
        onDismiss = nil
    }

    var isPresenting: Bool { !windows.isEmpty }
}

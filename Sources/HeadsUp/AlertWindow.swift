import AppKit

/// The borderless full-screen window the alert is presented in.
///
/// Exists as a subclass purely to accept keyboard input: a plain borderless NSWindow
/// returns false from `canBecomeKey`, so it can never become the key window and key
/// events never reach it at all — `makeKey()` on one is silently a no-op. Since the alert
/// covers the menu bar too (see AlertPresenter's window level), a user who can't reach the
/// on-screen buttons — e.g. because a display was just disconnected — has no way out of it
/// short of force-quitting, so a working Escape key is the app's last resort, not a nicety.
final class AlertWindow: NSWindow {

    /// Escape.
    var onCancel: (() -> Void)?

    /// Return / Enter.
    var onDefault: (() -> Void)?

    override var canBecomeKey: Bool { true }

    // Handled here rather than as SwiftUI `.keyboardShortcut` modifiers on the buttons so
    // the keys work regardless of what SwiftUI considers focused, and keep working while
    // AlertView's snooze menu is open.
    override func keyDown(with event: NSEvent) {
        switch event.keyCode {
        case 53: // Escape
            onCancel?()
        case 36, 76: // Return, keypad Enter
            onDefault?()
        default:
            super.keyDown(with: event)
        }
    }
}

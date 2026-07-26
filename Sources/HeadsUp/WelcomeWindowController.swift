import AppKit
import SwiftUI

final class WelcomeWindowController: NSWindowController {

    convenience init(onContinue: @escaping () -> Void) {
        let view = WelcomeView(onContinue: onContinue)
        let hosting = NSHostingController(rootView: view)
        let window = NSWindow(contentViewController: hosting)
        window.title = "Welcome to Heads Up"
        window.styleMask = [.titled, .closable]
        window.isReleasedWhenClosed = false
        window.center()
        self.init(window: window)
    }

    func show() {
        NSApp.activate(ignoringOtherApps: true)
        window?.makeKeyAndOrderFront(nil)
    }
}

import AppKit
import SwiftUI

final class WelcomeWindowController: NSWindowController, NSWindowDelegate {

    convenience init(onContinue: @escaping (_ launchAtLogin: Bool) -> Void) {
        let view = WelcomeView(onContinue: onContinue)
        let hosting = NSHostingController(rootView: view)
        let window = NSWindow(contentViewController: hosting)
        window.title = "Welcome to Heads Up"
        window.styleMask = [.titled, .closable]
        window.isReleasedWhenClosed = false
        window.center()
        self.init(window: window)
        window.delegate = self
    }

    func show() {
        NSApp.setActivationPolicy(.regular)
        NSApp.activate(ignoringOtherApps: true)
        window?.makeKeyAndOrderFront(nil)
    }

    func windowWillClose(_ notification: Notification) {
        NSApp.setActivationPolicy(.accessory)
    }
}

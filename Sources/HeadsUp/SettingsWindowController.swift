import AppKit
import SwiftUI
import Sparkle

final class SettingsWindowController: NSWindowController, NSWindowDelegate {

    convenience init(calendarService: CalendarService, updater: SPUUpdater) {
        let view = SettingsView(calendarService: calendarService, updater: updater)
        let hosting = NSHostingController(rootView: view)
        let window = NSWindow(contentViewController: hosting)
        window.title = "Heads Up Settings"
        window.styleMask = [.titled, .closable, .miniaturizable]
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

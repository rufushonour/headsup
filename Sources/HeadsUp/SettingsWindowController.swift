import AppKit
import SwiftUI

final class SettingsWindowController: NSWindowController {

    convenience init(calendarService: CalendarService) {
        let view = SettingsView(calendarService: calendarService)
        let hosting = NSHostingController(rootView: view)
        let window = NSWindow(contentViewController: hosting)
        window.title = "Heads Up Settings"
        window.styleMask = [.titled, .closable, .miniaturizable]
        window.isReleasedWhenClosed = false
        window.center()
        self.init(window: window)
    }

    func show() {
        NSApp.activate(ignoringOtherApps: true)
        window?.makeKeyAndOrderFront(nil)
    }
}

import AppKit
import EventKit
import Combine

/// Owns the NSStatusItem: shows the next meeting at a glance and exposes
/// quick actions plus an entry point into the Settings window.
final class MenuBarController {

    private let statusItem: NSStatusItem
    private let calendarService: CalendarService
    private var cancellables: Set<AnyCancellable> = []

    /// Fires the full-screen alert with a synthetic meeting, for previewing appearance/behavior.
    var onTestAlert: (() -> Void)?

    /// Opens the Settings window.
    var onOpenSettings: (() -> Void)?

    init(calendarService: CalendarService) {
        self.calendarService = calendarService
        self.statusItem = NSStatusBar.system.statusItem(withLength: NSStatusItem.variableLength)

        if let button = statusItem.button {
            button.image = NSImage(systemSymbolName: "bell.badge", accessibilityDescription: "Heads Up")
        }

        calendarService.$nextMeeting
            .combineLatest(calendarService.$authorized)
            .receive(on: DispatchQueue.main)
            .sink { [weak self] meeting, authorized in
                self?.updateTitle(meeting: meeting, authorized: authorized)
            }
            .store(in: &cancellables)

        statusItem.menu = buildMenu()
    }

    private func updateTitle(meeting: UpcomingMeeting?, authorized: Bool) {
        guard let button = statusItem.button else { return }
        if !authorized {
            button.title = " Calendar access needed"
        } else if let meeting {
            let formatter = DateFormatter()
            formatter.timeStyle = .short
            button.title = " \(meeting.title) at \(formatter.string(from: meeting.startDate))"
        } else {
            button.title = " No upcoming meetings"
        }
    }

    private func buildMenu() -> NSMenu {
        let menu = NSMenu()

        let openCalendar = NSMenuItem(title: "Open Calendar", action: #selector(openCalendar), keyEquivalent: "")
        openCalendar.target = self
        menu.addItem(openCalendar)

        let testAlert = NSMenuItem(title: "Send Test Alert", action: #selector(sendTestAlert), keyEquivalent: "")
        testAlert.target = self
        menu.addItem(testAlert)

        menu.addItem(.separator())

        let settings = NSMenuItem(title: "Settings…", action: #selector(openSettings), keyEquivalent: ",")
        settings.target = self
        menu.addItem(settings)

        menu.addItem(.separator())

        let quit = NSMenuItem(title: "Quit Heads Up", action: #selector(NSApplication.terminate(_:)), keyEquivalent: "q")
        menu.addItem(quit)

        return menu
    }

    @objc private func openCalendar() {
        if let url = URL(string: "ical://") {
            NSWorkspace.shared.open(url)
        }
    }

    @objc private func sendTestAlert() {
        onTestAlert?()
    }

    @objc private func openSettings() {
        onOpenSettings?()
    }
}

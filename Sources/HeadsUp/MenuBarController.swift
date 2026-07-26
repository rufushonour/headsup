import AppKit
import EventKit
import Combine

private struct CalendarLeadTimeSelection {
    let calendarIdentifier: String
    let seconds: TimeInterval? // nil = use the global default
}

/// Owns the NSStatusItem: shows the next meeting at a glance and exposes
/// lead-time preferences and quit.
final class MenuBarController {

    private let statusItem: NSStatusItem
    private let calendarService: CalendarService
    private var cancellables: Set<AnyCancellable> = []

    /// Fires the full-screen alert with a synthetic meeting, for previewing appearance/behavior.
    var onTestAlert: (() -> Void)?

    private let leadTimeOptions: [(title: String, seconds: TimeInterval)] = [
        ("At start time", 0),
        ("1 minute before", 60),
        ("2 minutes before", 120),
        ("5 minutes before", 300)
    ]

    private let snoozeDurationOptions: [(title: String, seconds: TimeInterval)] = [
        ("1 minute", 60),
        ("5 minutes", 300),
        ("10 minutes", 600),
        ("15 minutes", 900)
    ]

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

        calendarService.$availableCalendars
            .receive(on: DispatchQueue.main)
            .sink { [weak self] _ in
                guard let self else { return }
                self.statusItem.menu = self.buildMenu()
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

        let leadTimeMenu = NSMenu()
        for option in leadTimeOptions {
            let item = NSMenuItem(title: option.title, action: #selector(selectLeadTime(_:)), keyEquivalent: "")
            item.target = self
            item.representedObject = option.seconds
            item.state = calendarService.leadTime == option.seconds ? .on : .off
            leadTimeMenu.addItem(item)
        }
        let leadTimeItem = NSMenuItem(title: "Alert me", action: nil, keyEquivalent: "")
        leadTimeItem.submenu = leadTimeMenu
        menu.addItem(leadTimeItem)

        let snoozeMenu = NSMenu()
        for option in snoozeDurationOptions {
            let item = NSMenuItem(title: option.title, action: #selector(selectSnoozeDuration(_:)), keyEquivalent: "")
            item.target = self
            item.representedObject = option.seconds
            item.state = calendarService.snoozeDuration == option.seconds ? .on : .off
            snoozeMenu.addItem(item)
        }
        let snoozeItem = NSMenuItem(title: "Snooze duration", action: nil, keyEquivalent: "")
        snoozeItem.submenu = snoozeMenu
        menu.addItem(snoozeItem)

        let calendarsMenu = NSMenu()
        if calendarService.availableCalendars.isEmpty {
            let empty = NSMenuItem(title: "No calendars found", action: nil, keyEquivalent: "")
            empty.isEnabled = false
            calendarsMenu.addItem(empty)
        } else {
            for calendar in calendarService.availableCalendars {
                let item = NSMenuItem(
                    title: "\(calendar.title) — \(calendar.source.title)",
                    action: nil,
                    keyEquivalent: ""
                )
                item.submenu = buildCalendarSubmenu(for: calendar)
                item.state = calendarService.isIncluded(calendar) ? .on : .off
                calendarsMenu.addItem(item)
            }
        }
        let calendarsItem = NSMenuItem(title: "Calendars", action: nil, keyEquivalent: "")
        calendarsItem.submenu = calendarsMenu
        menu.addItem(calendarsItem)

        menu.addItem(.separator())

        let openCalendar = NSMenuItem(title: "Open Calendar", action: #selector(openCalendar), keyEquivalent: "")
        openCalendar.target = self
        menu.addItem(openCalendar)

        let testAlert = NSMenuItem(title: "Send Test Alert", action: #selector(sendTestAlert), keyEquivalent: "")
        testAlert.target = self
        menu.addItem(testAlert)

        menu.addItem(.separator())

        let quit = NSMenuItem(title: "Quit Heads Up", action: #selector(NSApplication.terminate(_:)), keyEquivalent: "q")
        menu.addItem(quit)

        return menu
    }

    private func buildCalendarSubmenu(for calendar: EKCalendar) -> NSMenu {
        let menu = NSMenu()

        let includeItem = NSMenuItem(title: "Included", action: #selector(toggleCalendarIncluded(_:)), keyEquivalent: "")
        includeItem.target = self
        includeItem.representedObject = calendar.calendarIdentifier
        includeItem.state = calendarService.isIncluded(calendar) ? .on : .off
        menu.addItem(includeItem)

        menu.addItem(.separator())

        let currentOverride = calendarService.leadTimeOverride(for: calendar)

        let defaultItem = NSMenuItem(
            title: "Use default (\(leadTimeLabel(calendarService.leadTime)))",
            action: #selector(selectCalendarLeadTime(_:)),
            keyEquivalent: ""
        )
        defaultItem.target = self
        defaultItem.representedObject = CalendarLeadTimeSelection(calendarIdentifier: calendar.calendarIdentifier, seconds: nil)
        defaultItem.state = currentOverride == nil ? .on : .off
        menu.addItem(defaultItem)

        for option in leadTimeOptions {
            let item = NSMenuItem(title: option.title, action: #selector(selectCalendarLeadTime(_:)), keyEquivalent: "")
            item.target = self
            item.representedObject = CalendarLeadTimeSelection(calendarIdentifier: calendar.calendarIdentifier, seconds: option.seconds)
            item.state = currentOverride == option.seconds ? .on : .off
            menu.addItem(item)
        }

        return menu
    }

    private func leadTimeLabel(_ seconds: TimeInterval) -> String {
        leadTimeOptions.first(where: { $0.seconds == seconds })?.title ?? "\(Int(seconds))s before"
    }

    @objc private func selectLeadTime(_ sender: NSMenuItem) {
        guard let seconds = sender.representedObject as? TimeInterval else { return }
        calendarService.leadTime = seconds
        statusItem.menu = buildMenu()
    }

    @objc private func selectSnoozeDuration(_ sender: NSMenuItem) {
        guard let seconds = sender.representedObject as? TimeInterval else { return }
        calendarService.snoozeDuration = seconds
        statusItem.menu = buildMenu()
    }

    @objc private func toggleCalendarIncluded(_ sender: NSMenuItem) {
        guard let identifier = sender.representedObject as? String,
              let calendar = calendarService.availableCalendars.first(where: { $0.calendarIdentifier == identifier }) else { return }
        calendarService.setIncluded(sender.state == .off, for: calendar)
        statusItem.menu = buildMenu()
    }

    @objc private func selectCalendarLeadTime(_ sender: NSMenuItem) {
        guard let selection = sender.representedObject as? CalendarLeadTimeSelection,
              let calendar = calendarService.availableCalendars.first(where: { $0.calendarIdentifier == selection.calendarIdentifier }) else { return }
        calendarService.setLeadTimeOverride(selection.seconds, for: calendar)
        statusItem.menu = buildMenu()
    }

    @objc private func openCalendar() {
        if let url = URL(string: "ical://") {
            NSWorkspace.shared.open(url)
        }
    }

    @objc private func sendTestAlert() {
        onTestAlert?()
    }
}

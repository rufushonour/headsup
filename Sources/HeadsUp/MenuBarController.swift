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

    /// Quits the app (equivalent to Cmd+Q / Dock Quit).
    var onQuit: (() -> Void)?

    init(calendarService: CalendarService) {
        self.calendarService = calendarService
        self.statusItem = NSStatusBar.system.statusItem(withLength: NSStatusItem.variableLength)

        if let button = statusItem.button {
            button.image = NSImage(systemSymbolName: "bell.badge", accessibilityDescription: "Heads Up")
        }

        calendarService.$nextMeeting
            .combineLatest(calendarService.$authorized, calendarService.$menuBarTitleMaxLength, calendarService.$showNoMeetingsText)
            .receive(on: DispatchQueue.main)
            .sink { [weak self] meeting, authorized, maxLength, showNoMeetingsText in
                self?.updateTitle(meeting: meeting, authorized: authorized, maxLength: maxLength, showNoMeetingsText: showNoMeetingsText)
            }
            .store(in: &cancellables)

        calendarService.$todaysMeetings
            .receive(on: DispatchQueue.main)
            .sink { [weak self] _ in
                guard let self else { return }
                self.statusItem.menu = self.buildMenu()
            }
            .store(in: &cancellables)

        statusItem.menu = buildMenu()
    }

    private func updateTitle(meeting: UpcomingMeeting?, authorized: Bool, maxLength: Int, showNoMeetingsText: Bool) {
        guard let button = statusItem.button else { return }
        if !authorized {
            button.title = " Calendar access needed"
        } else if let meeting {
            let formatter = DateFormatter()
            formatter.timeStyle = .short
            let title = truncated(meeting.title, maxLength: maxLength)
            button.title = " \(title) at \(formatter.string(from: meeting.startDate))"
        } else if showNoMeetingsText {
            button.title = " No upcoming meetings"
        } else {
            button.title = ""
        }
    }

    private func truncated(_ title: String, maxLength: Int) -> String {
        guard maxLength > 0, title.count > maxLength else { return title }
        return String(title.prefix(maxLength)) + "…"
    }

    private func buildMenu() -> NSMenu {
        let menu = NSMenu()
        menu.autoenablesItems = false

        let meetings = calendarService.todaysMeetings
        if meetings.isEmpty {
            let empty = NSMenuItem(title: "No more meetings today", action: nil, keyEquivalent: "")
            empty.isEnabled = false
            menu.addItem(empty)
        } else {
            for meeting in meetings {
                let item = NSMenuItem(
                    title: meetingTitle(for: meeting),
                    action: meeting.joinURL != nil ? #selector(joinMeeting(_:)) : nil,
                    keyEquivalent: ""
                )
                item.target = self
                item.representedObject = meeting.joinURL
                if meeting.joinURL != nil {
                    item.image = NSImage(systemSymbolName: "video.fill", accessibilityDescription: "Join")
                } else if let location = meeting.location, !location.isEmpty {
                    item.image = NSImage(systemSymbolName: "mappin.and.ellipse", accessibilityDescription: "Location")
                }
                menu.addItem(item)
            }
        }

        menu.addItem(.separator())

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

        let quit = NSMenuItem(title: "Quit Heads Up", action: #selector(quitApp), keyEquivalent: "q")
        quit.target = self
        menu.addItem(quit)

        return menu
    }

    private func meetingTitle(for meeting: UpcomingMeeting) -> String {
        let formatter = DateFormatter()
        formatter.timeStyle = .short
        var title = "\(formatter.string(from: meeting.startDate))  \(meeting.title)"
        if meeting.joinURL == nil, let location = meeting.location, !location.isEmpty {
            title += "  —  \(location)"
        }
        return title
    }

    @objc private func joinMeeting(_ sender: NSMenuItem) {
        guard let url = sender.representedObject as? URL else { return }
        NSWorkspace.shared.open(url)
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

    @objc private func quitApp() {
        onQuit?()
    }
}

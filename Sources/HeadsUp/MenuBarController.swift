import AppKit
import EventKit
import Combine

/// Owns the NSStatusItem: shows the next meeting at a glance and exposes
/// quick actions plus an entry point into the Settings window.
final class MenuBarController: NSObject, NSMenuDelegate {

    private let statusItem: NSStatusItem
    private let calendarService: CalendarService
    private var cancellables: Set<AnyCancellable> = []

    /// Fires the full-screen alert with a synthetic meeting, for previewing appearance/behavior.
    var onTestAlert: (() -> Void)?

    /// Opens the Settings window.
    var onOpenSettings: (() -> Void)?

    /// Quits the app (equivalent to Cmd+Q / Dock Quit).
    var onQuit: (() -> Void)?

    /// Requests calendar access. Handled by AppDelegate rather than here, since
    /// reliably surfacing the system dialog requires briefly promoting to a regular,
    /// active app with a window — state this controller doesn't own.
    var onRequestCalendarAccess: (() -> Void)?

    /// Triggers a Sparkle update check. Handled by AppDelegate, which owns the updater.
    var onCheckForUpdates: (() -> Void)?

    init(calendarService: CalendarService) {
        self.calendarService = calendarService
        self.statusItem = NSStatusBar.system.statusItem(withLength: NSStatusItem.variableLength)
        super.init()

        if let button = statusItem.button {
            button.image = Self.statusBarIcon(named: "bell.badge")
            // Without this, the icon's position shifts depending on whether the title is
            // empty (icon-only mode, e.g. "No upcoming meetings" text toggled off) or has
            // text — pin it explicitly so it stays put across all title states.
            button.imagePosition = .imageLeft
        }

        calendarService.$nextMeetings
            .combineLatest(calendarService.$authorized, calendarService.$menuBarTitleMaxLength, calendarService.$showNoMeetingsText)
            .receive(on: DispatchQueue.main)
            .sink { [weak self] meetings, authorized, maxLength, showNoMeetingsText in
                self?.updateTitle(meetings: meetings, authorized: authorized, maxLength: maxLength, showNoMeetingsText: showNoMeetingsText)
            }
            .store(in: &cancellables)

        calendarService.$todaysMeetings
            .combineLatest(calendarService.$authorized)
            .receive(on: DispatchQueue.main)
            .sink { [weak self] _, _ in
                guard let self else { return }
                self.statusItem.menu = self.buildMenu()
            }
            .store(in: &cancellables)

        statusItem.menu = buildMenu()
    }

    /// SF Symbols' own alignment rect isn't always vertically symmetric within its
    /// bounding box (`bell.badge` has 5pt above the glyph but only 3pt below, which reads
    /// as visibly off-center at menu bar size) — pad the shorter margin to match the
    /// longer one so the rendered glyph sits centered regardless of the symbol's own quirks.
    private static func statusBarIcon(named systemName: String) -> NSImage? {
        guard let original = NSImage(systemSymbolName: systemName, accessibilityDescription: "Heads Up") else {
            return nil
        }
        let alignmentRect = original.alignmentRect
        let topMargin = original.size.height - alignmentRect.maxY
        let bottomMargin = alignmentRect.minY
        guard abs(topMargin - bottomMargin) > 0.01 else { return original }

        let extraTop = max(0, bottomMargin - topMargin)
        let extraBottom = max(0, topMargin - bottomMargin)
        let newSize = NSSize(width: original.size.width, height: original.size.height + extraTop + extraBottom)

        let padded = NSImage(size: newSize)
        padded.lockFocus()
        original.draw(at: NSPoint(x: 0, y: extraBottom), from: .zero, operation: .sourceOver, fraction: 1.0)
        padded.unlockFocus()
        padded.isTemplate = original.isTemplate
        padded.accessibilityDescription = original.accessibilityDescription
        return padded
    }

    private func updateTitle(meetings: [UpcomingMeeting], authorized: Bool, maxLength: Int, showNoMeetingsText: Bool) {
        guard let button = statusItem.button else { return }

        let isInProgress = meetings.contains { Date() >= $0.startDate && Date() < $0.endDate }
        button.image = Self.statusBarIcon(named: isInProgress ? "bell.badge.fill" : "bell.badge")

        if !authorized {
            button.title = " Calendar access needed"
        } else if let first = meetings.first {
            let formatter = DateFormatter()
            formatter.timeStyle = .short
            // meetings.count > 1 means they overlap in time — show every one of them
            // rather than silently picking just the first, so conflicts stay visible.
            let titles = meetings.map { truncated($0.title, maxLength: maxLength) }.joined(separator: " + ")
            button.title = " \(titles) at \(formatter.string(from: first.startDate))"
        } else if showNoMeetingsText {
            button.title = " \(truncated("No upcoming meetings", maxLength: maxLength))"
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
        menu.delegate = self
        populateMenu(menu)
        return menu
    }

    /// Rebuilds `menu`'s items in place. Used both to build a fresh menu and, via
    /// `menuWillOpen`, to refresh the menu that's about to be shown synchronously —
    /// important because a calendar access grant made externally via System Settings
    /// isn't pushed to us by EventKit, so we only find out by checking on open.
    private func populateMenu(_ menu: NSMenu) {
        menu.removeAllItems()
        menu.autoenablesItems = false

        if !calendarService.authorized {
            let notice = NSMenuItem(title: "Calendar access needed", action: nil, keyEquivalent: "")
            notice.isEnabled = false
            menu.addItem(notice)

            let grantAccess = NSMenuItem(title: "Grant Calendar Access…", action: #selector(grantCalendarAccess), keyEquivalent: "")
            grantAccess.target = self
            menu.addItem(grantAccess)
        } else {
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

        if let version = Bundle.main.infoDictionary?["CFBundleShortVersionString"] as? String {
            let versionItem = NSMenuItem(title: "Version \(version)", action: nil, keyEquivalent: "")
            versionItem.isEnabled = false
            menu.addItem(versionItem)
        }

        let checkForUpdates = NSMenuItem(title: "Check for Updates…", action: #selector(checkForUpdates), keyEquivalent: "")
        checkForUpdates.target = self
        menu.addItem(checkForUpdates)

        let feedback = NSMenuItem(title: "Send Feedback…", action: #selector(sendFeedback), keyEquivalent: "")
        feedback.target = self
        menu.addItem(feedback)

        menu.addItem(.separator())

        let quit = NSMenuItem(title: "Quit Heads Up", action: #selector(quitApp), keyEquivalent: "q")
        quit.target = self
        menu.addItem(quit)
    }

    func menuWillOpen(_ menu: NSMenu) {
        calendarService.refreshAuthorizationStatus()
        populateMenu(menu)
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

    @objc private func grantCalendarAccess() {
        if calendarService.canRequestAccess {
            onRequestCalendarAccess?()
        } else if let url = URL(string: "x-apple.systempreferences:com.apple.preference.security?Privacy_Calendars") {
            // Already decided (most likely denied) — macOS won't prompt again, so send
            // the user straight to the Calendars privacy pane to flip it themselves.
            NSWorkspace.shared.open(url)
        }
    }

    @objc private func sendTestAlert() {
        onTestAlert?()
    }

    @objc private func openSettings() {
        onOpenSettings?()
    }

    @objc private func checkForUpdates() {
        onCheckForUpdates?()
    }

    @objc private func sendFeedback() {
        if let url = URL(string: "https://github.com/rufushonour/headsup/issues") {
            NSWorkspace.shared.open(url)
        }
    }

    @objc private func quitApp() {
        onQuit?()
    }
}

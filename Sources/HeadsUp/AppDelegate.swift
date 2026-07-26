import AppKit

final class AppDelegate: NSObject, NSApplicationDelegate {

    private let calendarService = CalendarService()
    private let alertPresenter = AlertPresenter()
    private var menuBarController: MenuBarController?
    private lazy var settingsWindowController = SettingsWindowController(calendarService: calendarService)

    func applicationDidFinishLaunching(_ notification: Notification) {
        NSApp.setActivationPolicy(.accessory) // menu bar only, no Dock icon

        menuBarController = MenuBarController(calendarService: calendarService)
        menuBarController?.onTestAlert = { [weak self] in
            self?.presentTestAlert()
        }
        menuBarController?.onOpenSettings = { [weak self] in
            self?.settingsWindowController.show()
        }

        calendarService.onMeetingDue = { [weak self] meeting in
            self?.presentAlert(for: meeting)
        }
        calendarService.start()
    }

    private func presentTestAlert() {
        let now = Date()
        presentAlert(for: UpcomingMeeting(
            id: "test-alert-\(now.timeIntervalSince1970)",
            title: "Test Meeting",
            startDate: now,
            endDate: now.addingTimeInterval(15 * 60),
            joinURL: URL(string: "https://zoom.us")
        ))
    }

    private func presentAlert(for meeting: UpcomingMeeting) {
        alertPresenter.present(
            meeting,
            onJoin: {
                guard let url = meeting.joinURL else { return }
                NSWorkspace.shared.open(url)
            },
            onSnooze: { [weak self] in
                self?.calendarService.snooze(meeting)
            },
            onDismiss: {}
        )
    }

    func applicationShouldTerminateAfterLastWindowClosed(_ sender: NSApplication) -> Bool {
        false
    }
}

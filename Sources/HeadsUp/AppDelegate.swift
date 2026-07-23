import AppKit

final class AppDelegate: NSObject, NSApplicationDelegate {

    private let calendarService = CalendarService()
    private let alertPresenter = AlertPresenter()
    private var menuBarController: MenuBarController?

    func applicationDidFinishLaunching(_ notification: Notification) {
        NSApp.setActivationPolicy(.accessory) // menu bar only, no Dock icon

        menuBarController = MenuBarController(calendarService: calendarService)

        calendarService.onMeetingDue = { [weak self] meeting in
            self?.presentAlert(for: meeting)
        }
        calendarService.start()
    }

    private func presentAlert(for meeting: UpcomingMeeting) {
        alertPresenter.present(
            meeting,
            onJoin: {
                guard let url = meeting.joinURL else { return }
                NSWorkspace.shared.open(url)
            },
            onSnooze: { [weak self] in
                self?.calendarService.snooze(meeting, for: 5 * 60)
            },
            onDismiss: {}
        )
    }

    func applicationShouldTerminateAfterLastWindowClosed(_ sender: NSApplication) -> Bool {
        false
    }
}

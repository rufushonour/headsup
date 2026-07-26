import AppKit

final class AppDelegate: NSObject, NSApplicationDelegate {

    private let calendarService = CalendarService()
    private let alertPresenter = AlertPresenter()
    private var menuBarController: MenuBarController?
    private lazy var settingsWindowController = SettingsWindowController(calendarService: calendarService)

    /// Set right before calling NSApp.terminate from the tray's own Quit action.
    /// Any other termination attempt (Dock "Quit", Cmd+Q, etc.) is refused so the
    /// background calendar polling and tray icon survive closing/quitting windows.
    private var quitRequestedFromTray = false

    func applicationDidFinishLaunching(_ notification: Notification) {
        NSApp.setActivationPolicy(.regular)
        NSApp.mainMenu = buildMainMenu()

        menuBarController = MenuBarController(calendarService: calendarService)
        menuBarController?.onTestAlert = { [weak self] in
            self?.presentTestAlert()
        }
        menuBarController?.onOpenSettings = { [weak self] in
            self?.settingsWindowController.show()
        }
        menuBarController?.onQuit = { [weak self] in
            self?.quitRequestedFromTray = true
            NSApp.terminate(nil)
        }

        calendarService.onMeetingDue = { [weak self] meeting in
            self?.presentAlert(for: meeting)
        }
        calendarService.start()

        settingsWindowController.show()
    }

    func applicationShouldTerminate(_ sender: NSApplication) -> NSApplication.TerminateReply {
        if quitRequestedFromTray {
            return .terminateNow
        }
        settingsWindowController.window?.close()
        return .terminateCancel
    }

    func applicationShouldHandleReopen(_ sender: NSApplication, hasVisibleWindows flag: Bool) -> Bool {
        if !flag {
            settingsWindowController.show()
        }
        return true
    }

    private func buildMainMenu() -> NSMenu {
        let mainMenu = NSMenu()

        let appMenuItem = NSMenuItem()
        let appMenu = NSMenu()
        appMenu.addItem(NSMenuItem(title: "About Heads Up", action: #selector(NSApplication.orderFrontStandardAboutPanel(_:)), keyEquivalent: ""))
        appMenu.addItem(.separator())
        let settingsItem = NSMenuItem(title: "Settings…", action: #selector(openSettingsFromMainMenu), keyEquivalent: ",")
        settingsItem.target = self
        appMenu.addItem(settingsItem)
        appMenu.addItem(.separator())
        appMenu.addItem(NSMenuItem(title: "Hide Heads Up", action: #selector(NSApplication.hide(_:)), keyEquivalent: "h"))
        appMenuItem.submenu = appMenu
        mainMenu.addItem(appMenuItem)

        let editMenuItem = NSMenuItem()
        let editMenu = NSMenu(title: "Edit")
        editMenu.addItem(NSMenuItem(title: "Cut", action: #selector(NSText.cut(_:)), keyEquivalent: "x"))
        editMenu.addItem(NSMenuItem(title: "Copy", action: #selector(NSText.copy(_:)), keyEquivalent: "c"))
        editMenu.addItem(NSMenuItem(title: "Paste", action: #selector(NSText.paste(_:)), keyEquivalent: "v"))
        editMenu.addItem(NSMenuItem(title: "Select All", action: #selector(NSText.selectAll(_:)), keyEquivalent: "a"))
        editMenuItem.submenu = editMenu
        mainMenu.addItem(editMenuItem)

        let windowMenuItem = NSMenuItem()
        let windowMenu = NSMenu(title: "Window")
        windowMenu.addItem(NSMenuItem(title: "Minimize", action: #selector(NSWindow.miniaturize(_:)), keyEquivalent: "m"))
        windowMenu.addItem(NSMenuItem(title: "Close", action: #selector(NSWindow.performClose(_:)), keyEquivalent: "w"))
        windowMenuItem.submenu = windowMenu
        mainMenu.addItem(windowMenuItem)
        NSApp.windowsMenu = windowMenu

        return mainMenu
    }

    @objc private func openSettingsFromMainMenu() {
        settingsWindowController.show()
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

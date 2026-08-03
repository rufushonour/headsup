import AppKit
import Sparkle
import ServiceManagement

final class AppDelegate: NSObject, NSApplicationDelegate {

    private let calendarService = CalendarService()
    private let alertPresenter = AlertPresenter()
    private var menuBarController: MenuBarController?
    private lazy var updaterController = SPUStandardUpdaterController(
        startingUpdater: true,
        updaterDelegate: nil,
        userDriverDelegate: nil
    )
    private lazy var settingsWindowController = SettingsWindowController(
        calendarService: calendarService,
        updater: updaterController.updater
    )
    private lazy var welcomeWindowController = WelcomeWindowController(onContinue: { [weak self] launchAtLogin in
        self?.completeOnboarding(launchAtLogin: launchAtLogin)
    })

    private static let hasCompletedOnboardingKey = "hasCompletedOnboarding"

    func applicationDidFinishLaunching(_ notification: Notification) {
        NSApp.setActivationPolicy(.accessory)
        NSApp.mainMenu = buildMainMenu()

        menuBarController = MenuBarController(calendarService: calendarService)
        menuBarController?.onTestAlert = { [weak self] in
            self?.presentTestAlert()
        }
        menuBarController?.onOpenSettings = { [weak self] in
            self?.settingsWindowController.show()
        }
        menuBarController?.onQuit = {
            NSApp.terminate(nil)
        }
        menuBarController?.onRequestCalendarAccess = { [weak self] in
            self?.requestCalendarAccessAsRegularApp()
        }
        menuBarController?.onCheckForUpdates = { [weak self] in
            self?.updaterController.updater.checkForUpdates()
        }
        calendarService.onMeetingDue = { [weak self] meeting in
            self?.presentAlert(for: meeting)
        }

        if UserDefaults.standard.bool(forKey: Self.hasCompletedOnboardingKey) {
            requestCalendarAccessAsRegularApp()
        } else {
            welcomeWindowController.show()
        }
    }

    /// As an accessory app (no Dock icon at rest, see SettingsWindowController /
    /// WelcomeWindowController for the same pattern around their own windows), the
    /// system Calendar access dialog can be created but never actually surface without
    /// an actual key window present — promoting activation policy and calling
    /// NSApp.activate alone isn't enough. Only shows Settings when we're actually about
    /// to trigger a fresh prompt (canRequestAccess), so a normal launch with access
    /// already decided doesn't pop Settings open for no reason. SettingsWindowController's
    /// own windowWillClose already reverts to accessory when the user's done with it.
    private func requestCalendarAccessAsRegularApp() {
        if calendarService.canRequestAccess {
            settingsWindowController.show()
        }
        calendarService.start()
    }

    private func completeOnboarding(launchAtLogin: Bool) {
        UserDefaults.standard.set(true, forKey: Self.hasCompletedOnboardingKey)
        if launchAtLogin {
            try? SMAppService.mainApp.register()
        }
        // Wait for the calendar access request to settle before swapping windows —
        // closing the Welcome window immediately can yank away the window the system
        // permission dialog needs to attach to, before it's had a chance to appear
        // (same underlying issue as requestCalendarAccessAsRegularApp).
        calendarService.start { [weak self] in
            guard let self else { return }
            self.welcomeWindowController.window?.close()
            self.settingsWindowController.show()
        }
    }

    func applicationShouldTerminate(_ sender: NSApplication) -> NSApplication.TerminateReply {
        .terminateNow
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
        let checkForUpdatesItem = NSMenuItem(
            title: "Check for Updates…",
            action: #selector(SPUStandardUpdaterController.checkForUpdates(_:)),
            keyEquivalent: ""
        )
        checkForUpdatesItem.target = updaterController
        appMenu.addItem(checkForUpdatesItem)
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
            joinURL: URL(string: "https://zoom.us"),
            location: nil
        ))
    }

    private func presentAlert(for meeting: UpcomingMeeting) {
        alertPresenter.present(
            meeting,
            defaultSnoozeSeconds: calendarService.snoozeDuration,
            onJoin: {
                guard let url = meeting.joinURL else { return }
                NSWorkspace.shared.open(url)
            },
            onSnooze: { [weak self] seconds in
                self?.calendarService.snooze(meeting, for: seconds)
            },
            onDismiss: {}
        )
    }

    func applicationShouldTerminateAfterLastWindowClosed(_ sender: NSApplication) -> Bool {
        false
    }
}

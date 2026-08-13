import AppKit
import SwiftUI

/// Presents a full-screen, borderless alert window on every connected display,
/// above regular windows and other spaces (including apps running full-screen).
final class AlertPresenter {

    /// One display's cover. The hosting view is held alongside its window so
    /// `refreshContent` can update the SwiftUI tree in place (see below).
    private struct Cover {
        let window: AlertWindow
        let hostingView: NSHostingView<AlertView>
    }

    /// Keyed by display ID rather than by NSScreen: AppKit hands out fresh NSScreen
    /// instances on every display reconfiguration, so the screens we built windows from
    /// can't be matched against the current ones by identity — but their display IDs are
    /// stable, which is what makes `reconcileScreens` able to tell "same display, new
    /// frame" from "display went away".
    private var covers: [CGDirectDisplayID: Cover] = [:]
    private var screenChangeObserver: NSObjectProtocol?
    private var keyDownMonitor: Any?
    private var meetings: [UpcomingMeeting] = []
    private var defaultSnoozeSeconds: TimeInterval = 300
    private var onJoin: ((UpcomingMeeting) -> Void)?
    private var onSnooze: ((UpcomingMeeting, TimeInterval) -> Void)?
    private var onDismiss: (() -> Void)?

    /// Presents `meeting` full-screen. If an alert is already up and hasn't been
    /// handled yet, `meeting` is folded into that same alert instead of tearing it down
    /// — CalendarService fires one onMeetingDue per event, so two meetings becoming due
    /// close together (e.g. an overlapping double-booking) used to mean the second call
    /// would dismiss-and-replace the first before anyone had a chance to see it.
    func present(
        _ meeting: UpcomingMeeting,
        defaultSnoozeSeconds: TimeInterval,
        onJoin: @escaping (UpcomingMeeting) -> Void,
        onSnooze: @escaping (UpcomingMeeting, TimeInterval) -> Void,
        onDismiss: @escaping () -> Void
    ) {
        if isPresenting {
            guard !meetings.contains(where: { $0.id == meeting.id }) else { return }
            meetings.append(meeting)
            refreshContent()
            return
        }

        meetings = [meeting]
        self.defaultSnoozeSeconds = defaultSnoozeSeconds
        self.onJoin = onJoin
        self.onSnooze = onSnooze
        self.onDismiss = onDismiss

        for screen in NSScreen.screens {
            guard let displayID = Self.displayID(for: screen) else { continue }
            covers[displayID] = makeCover(for: screen)
        }

        // No display to present on at the moment the alert fires: unwind rather than arm
        // the observers below, which nothing would then ever tear down. Clearing
        // `meetings` is what puts `isPresenting` back to false.
        guard !covers.isEmpty else {
            meetings.removeAll()
            self.onJoin = nil
            self.onSnooze = nil
            self.onDismiss = nil
            return
        }

        // Displays can come and go while the alert is up — see reconcileScreens.
        screenChangeObserver = NotificationCenter.default.addObserver(
            forName: NSApplication.didChangeScreenParametersNotification,
            object: nil,
            queue: .main
        ) { [weak self] _ in
            self?.reconcileScreens()
        }

        startKeyDownMonitor()

        NSApp.activate(ignoringOtherApps: true)
        makeSomeWindowKey()
    }

    /// Gives key status to the main display's cover where possible — `covers` is a
    /// dictionary, so "first" is otherwise an arbitrary display rather than the one the
    /// user is most likely looking at.
    private func makeSomeWindowKey() {
        let preferred = NSScreen.main
            .flatMap { Self.displayID(for: $0) }
            .flatMap { covers[$0]?.window }
        (preferred ?? covers.values.first?.window)?.makeKey()
    }

    /// Rebuilds the set of covers to match the displays that actually exist right now.
    ///
    /// Without this, disconnecting a display while the alert is up leaves its window
    /// orphaned: macOS relocates it onto a surviving display but keeps the *departed*
    /// display's frame, which can leave the alert's buttons off-screen entirely. Since
    /// these windows sit above the menu bar, that left the user with an undismissable
    /// cover and no way to reach the tray — force-quit was the only exit. The reverse case
    /// was broken too: a display connected mid-alert simply never got a cover.
    ///
    /// Idempotent, which matters because macOS emits this notification several times in a
    /// burst around display sleep/wake.
    private func reconcileScreens() {
        guard isPresenting else { return }

        var seen = Set<CGDirectDisplayID>()
        for screen in NSScreen.screens {
            guard let displayID = Self.displayID(for: screen) else { continue }
            seen.insert(displayID)
            if let cover = covers[displayID] {
                cover.window.setFrame(screen.frame, display: true)
            } else {
                covers[displayID] = makeCover(for: screen)
            }
        }

        for (displayID, cover) in covers where !seen.contains(displayID) {
            cover.window.orderOut(nil)
            covers.removeValue(forKey: displayID)
        }

        // Every display went away (all asleep, or a laptop's lid closed with nothing else
        // attached). Deliberately *not* a dismiss: the alert stays armed with its meetings
        // intact, and the loop above rebuilds its covers as soon as a display is back —
        // an unseen meeting alert silently disappearing is the one outcome worse than a
        // stuck one.
        guard !covers.isEmpty else { return }

        // The key window may have been on a display that just went away; hand key status
        // to a survivor so Escape keeps working.
        if !covers.values.contains(where: { $0.window.isKeyWindow }) {
            makeSomeWindowKey()
        }
    }

    private func makeCover(for screen: NSScreen) -> Cover {
        let window = AlertWindow(
            contentRect: screen.frame,
            styleMask: [.borderless],
            backing: .buffered,
            defer: false,
            screen: screen
        )
        window.isOpaque = false
        window.backgroundColor = .clear
        window.hasShadow = false
        window.level = .init(Int(CGWindowLevelForKey(.maximumWindow)))
        window.collectionBehavior = [.canJoinAllSpaces, .fullScreenAuxiliary, .stationary, .ignoresCycle]
        window.ignoresMouseEvents = false
        window.isReleasedWhenClosed = false
        window.onCancel = { [weak self] in self?.dismiss() }
        window.onDefault = { [weak self] in self?.joinSoleMeeting() }
        let hostingView = NSHostingView(rootView: makeView())
        window.contentView = hostingView
        window.setFrame(screen.frame, display: true)
        window.orderFrontRegardless()
        return Cover(window: window, hostingView: hostingView)
    }

    private static func displayID(for screen: NSScreen) -> CGDirectDisplayID? {
        guard let number = screen.deviceDescription[NSDeviceDescriptionKey("NSScreenNumber")] as? NSNumber else {
            return nil
        }
        return CGDirectDisplayID(number.uint32Value)
    }

    /// Escape, as a backstop to `AlertWindow`'s own key handling: a local monitor sees key
    /// events while the app is active even when no window holds key status, which is
    /// exactly the state the alert can end up in. Deliberately Escape-only — this exists
    /// to guarantee an exit, and swallowing any more keys app-wide isn't worth the risk.
    private func startKeyDownMonitor() {
        keyDownMonitor = NSEvent.addLocalMonitorForEvents(matching: .keyDown) { [weak self] event in
            guard let self, self.isPresenting, event.keyCode == 53 else { return event }
            self.dismiss()
            return nil
        }
    }

    /// Return only joins when there's exactly one meeting to join — on the folded
    /// multi-meeting alert there's no non-arbitrary answer to which one it would mean.
    private func joinSoleMeeting() {
        guard meetings.count == 1, let meeting = meetings.first, meeting.joinURL != nil else { return }
        onJoin?(meeting)
        dismiss()
    }

    /// Updates the already-visible windows' content in place (rather than replacing the
    /// hosting view) so SwiftUI diffs against the existing view tree — a newly-folded-in
    /// meeting doesn't restart the entrance animation or blow away an open snooze menu.
    private func refreshContent() {
        let view = makeView()
        for cover in covers.values {
            cover.hostingView.rootView = view
        }
    }

    private func makeView() -> AlertView {
        AlertView(
            meetings: meetings,
            defaultSnoozeSeconds: defaultSnoozeSeconds,
            onJoin: { [weak self] meeting in
                guard let self else { return }
                self.onJoin?(meeting)
                // Only auto-dismiss for a single-meeting alert (matches prior behavior);
                // with several meetings up, joining one shouldn't hide the others.
                if self.meetings.count <= 1 {
                    self.dismiss()
                }
            },
            onSnooze: { [weak self] seconds in
                guard let self else { return }
                for meeting in self.meetings {
                    self.onSnooze?(meeting, seconds)
                }
                self.dismiss()
            },
            onDismiss: { [weak self] in
                self?.dismiss()
            }
        )
    }

    func dismiss() {
        if let screenChangeObserver {
            NotificationCenter.default.removeObserver(screenChangeObserver)
            self.screenChangeObserver = nil
        }
        if let keyDownMonitor {
            NSEvent.removeMonitor(keyDownMonitor)
            self.keyDownMonitor = nil
        }
        covers.values.forEach { $0.window.orderOut(nil) }
        covers.removeAll()
        meetings.removeAll()
        onDismiss?()
        onJoin = nil
        onSnooze = nil
        onDismiss = nil
    }

    /// Tracks the meetings rather than the windows so an alert whose displays have all
    /// temporarily gone away still counts as presenting — that's what lets
    /// `reconcileScreens` restore its covers instead of stranding it.
    var isPresenting: Bool { !meetings.isEmpty }
}

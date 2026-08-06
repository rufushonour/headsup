import AppKit
import SwiftUI

/// Presents a full-screen, borderless alert window on every connected display,
/// above regular windows and other spaces (including apps running full-screen).
final class AlertPresenter {

    private var windows: [NSWindow] = []
    private var hostingViews: [NSHostingView<AlertView>] = []
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
            let window = NSWindow(
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
            let hostingView = NSHostingView(rootView: makeView())
            window.contentView = hostingView
            window.setFrame(screen.frame, display: true)
            window.orderFrontRegardless()
            windows.append(window)
            hostingViews.append(hostingView)
        }

        NSApp.activate(ignoringOtherApps: true)
        windows.first?.makeKey()
    }

    /// Updates the already-visible windows' content in place (rather than replacing the
    /// hosting view) so SwiftUI diffs against the existing view tree — a newly-folded-in
    /// meeting doesn't restart the entrance animation or blow away an open snooze menu.
    private func refreshContent() {
        let view = makeView()
        for hostingView in hostingViews {
            hostingView.rootView = view
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
        windows.forEach { $0.orderOut(nil) }
        windows.removeAll()
        hostingViews.removeAll()
        meetings.removeAll()
        onDismiss?()
        onJoin = nil
        onSnooze = nil
        onDismiss = nil
    }

    var isPresenting: Bool { !windows.isEmpty }
}

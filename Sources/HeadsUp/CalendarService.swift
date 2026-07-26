import Foundation
import EventKit
import Combine

struct UpcomingMeeting: Identifiable {
    let id: String
    let title: String
    let startDate: Date
    let endDate: Date
    let joinURL: URL?
}

/// Owns the EKEventStore, requests calendar access, and polls for events that are
/// about to start so the caller can fire a full-screen alert.
final class CalendarService: ObservableObject {

    @Published private(set) var authorized = false
    @Published private(set) var nextMeeting: UpcomingMeeting?

    /// How long before an event's start time the alert should fire.
    var leadTime: TimeInterval {
        didSet { UserDefaults.standard.set(leadTime, forKey: "alertLeadTimeSeconds") }
    }

    /// Called once per event when it crosses the lead-time threshold.
    var onMeetingDue: ((UpcomingMeeting) -> Void)?

    private let store = EKEventStore()
    private var pollTimer: Timer?
    private var alertedEventKeys = Set<String>()
    private let lookahead: TimeInterval = 60 * 60 // scan next 60 minutes

    init() {
        let stored = UserDefaults.standard.double(forKey: "alertLeadTimeSeconds")
        self.leadTime = stored > 0 ? stored : 60 // default: 1 minute before
    }

    func start() {
        requestAccess { [weak self] granted in
            guard let self else { return }
            self.authorized = granted
            guard granted else { return }
            self.poll()
            self.pollTimer = Timer.scheduledTimer(withTimeInterval: 15, repeats: true) { [weak self] _ in
                self?.poll()
            }
        }
    }

    func requestAccess(completion: @escaping (Bool) -> Void) {
        if #available(macOS 14.0, *) {
            store.requestFullAccessToEvents { granted, _ in
                DispatchQueue.main.async { completion(granted) }
            }
        } else {
            store.requestAccess(to: .event) { granted, _ in
                DispatchQueue.main.async { completion(granted) }
            }
        }
    }

    /// Re-arms a meeting so it fires again after `delay` (snooze).
    func snooze(_ meeting: UpcomingMeeting, for delay: TimeInterval) {
        alertedEventKeys.remove(meeting.id)
        DispatchQueue.main.asyncAfter(deadline: .now() + delay) { [weak self] in
            guard let self else { return }
            guard Date() < meeting.endDate else { return }
            self.onMeetingDue?(meeting)
            self.alertedEventKeys.insert(meeting.id)
        }
    }

    private func poll() {
        let now = Date()
        let windowEnd = now.addingTimeInterval(lookahead)
        let predicate = store.predicateForEvents(withStart: now, end: windowEnd, calendars: nil)
        let events = store.events(matching: predicate)
            .filter { !$0.isAllDay }
            .sorted { $0.startDate < $1.startDate }

        if let soonest = events.first {
            nextMeeting = makeMeeting(from: soonest)
        } else {
            nextMeeting = nil
        }

        for event in events {
            let key = eventKey(event)
            guard !alertedEventKeys.contains(key) else { continue }
            let triggerAt = event.startDate.addingTimeInterval(-leadTime)
            if now >= triggerAt {
                alertedEventKeys.insert(key)
                onMeetingDue?(makeMeeting(from: event))
            }
        }
    }

    private func eventKey(_ event: EKEvent) -> String {
        "\(event.eventIdentifier ?? event.calendarItemIdentifier)|\(event.startDate.timeIntervalSince1970)"
    }

    private func makeMeeting(from event: EKEvent) -> UpcomingMeeting {
        UpcomingMeeting(
            id: eventKey(event),
            title: event.title ?? "Untitled event",
            startDate: event.startDate,
            endDate: event.endDate,
            joinURL: MeetingLinkExtractor.link(for: event)
        )
    }
}

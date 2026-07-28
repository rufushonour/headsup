import Foundation
import EventKit
import Combine

struct UpcomingMeeting: Identifiable {
    let id: String
    let title: String
    let startDate: Date
    let endDate: Date
    let joinURL: URL?
    let location: String?
}

/// Owns the EKEventStore, requests calendar access, and polls for events that are
/// about to start so the caller can fire a full-screen alert.
final class CalendarService: ObservableObject {

    @Published private(set) var authorized = false
    @Published private(set) var nextMeeting: UpcomingMeeting?
    @Published private(set) var todaysMeetings: [UpcomingMeeting] = []
    @Published private(set) var availableCalendars: [EKCalendar] = []

    /// How long before an event's start time the alert should fire, unless a
    /// calendar-specific override applies (see `calendarLeadTimeOverrides`).
    @Published var leadTime: TimeInterval {
        didSet { UserDefaults.standard.set(leadTime, forKey: "alertLeadTimeSeconds") }
    }

    /// How long a snoozed alert waits before re-firing.
    @Published var snoozeDuration: TimeInterval {
        didSet { UserDefaults.standard.set(snoozeDuration, forKey: "snoozeDurationSeconds") }
    }

    /// Identifiers of calendars that should NOT trigger alerts. Everything is
    /// included by default; excluding is opt-out so newly added calendars just work.
    @Published private(set) var excludedCalendarIdentifiers: Set<String> {
        didSet {
            UserDefaults.standard.set(Array(excludedCalendarIdentifiers), forKey: "excludedCalendarIdentifiers")
        }
    }

    /// Per-calendar lead time, overriding the global `leadTime` for events on that calendar.
    @Published private(set) var calendarLeadTimeOverrides: [String: TimeInterval] {
        didSet {
            UserDefaults.standard.set(calendarLeadTimeOverrides, forKey: "calendarLeadTimeOverrides")
        }
    }

    /// Max characters of a meeting's title shown in the menu bar before it's truncated
    /// with an ellipsis. 0 means no limit (show the full title).
    @Published var menuBarTitleMaxLength: Int {
        didSet { UserDefaults.standard.set(menuBarTitleMaxLength, forKey: "menuBarTitleMaxLength") }
    }

    /// Whether the menu bar shows "No upcoming meetings" text when there's nothing
    /// coming up, or just the icon.
    @Published var showNoMeetingsText: Bool {
        didSet { UserDefaults.standard.set(showNoMeetingsText, forKey: "showNoMeetingsText") }
    }

    func leadTimeOverride(for calendar: EKCalendar) -> TimeInterval? {
        calendarLeadTimeOverrides[calendar.calendarIdentifier]
    }

    func setLeadTimeOverride(_ seconds: TimeInterval?, for calendar: EKCalendar) {
        if let seconds {
            calendarLeadTimeOverrides[calendar.calendarIdentifier] = seconds
        } else {
            calendarLeadTimeOverrides.removeValue(forKey: calendar.calendarIdentifier)
        }
    }

    func isIncluded(_ calendar: EKCalendar) -> Bool {
        !excludedCalendarIdentifiers.contains(calendar.calendarIdentifier)
    }

    func setIncluded(_ included: Bool, for calendar: EKCalendar) {
        if included {
            excludedCalendarIdentifiers.remove(calendar.calendarIdentifier)
        } else {
            excludedCalendarIdentifiers.insert(calendar.calendarIdentifier)
        }
        poll()
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
        let storedSnooze = UserDefaults.standard.double(forKey: "snoozeDurationSeconds")
        self.snoozeDuration = storedSnooze > 0 ? storedSnooze : 5 * 60 // default: 5 minutes
        let excluded = UserDefaults.standard.stringArray(forKey: "excludedCalendarIdentifiers") ?? []
        self.excludedCalendarIdentifiers = Set(excluded)
        let overrides = UserDefaults.standard.dictionary(forKey: "calendarLeadTimeOverrides") ?? [:]
        self.calendarLeadTimeOverrides = overrides.compactMapValues { $0 as? TimeInterval }
        let storedMaxLength = UserDefaults.standard.object(forKey: "menuBarTitleMaxLength") as? Int
        self.menuBarTitleMaxLength = storedMaxLength ?? 40 // default: ~40 characters
        let storedShowNoMeetingsText = UserDefaults.standard.object(forKey: "showNoMeetingsText") as? Bool
        self.showNoMeetingsText = storedShowNoMeetingsText ?? true // default: show the text
    }

    func start() {
        requestAccess { [weak self] granted in
            guard let self else { return }
            self.authorized = granted
            guard granted else { return }
            self.refreshAvailableCalendars()
            self.poll()
            self.pollTimer = Timer.scheduledTimer(withTimeInterval: 15, repeats: true) { [weak self] _ in
                self?.refreshAvailableCalendars()
                self?.poll()
            }
        }
    }

    private func refreshAvailableCalendars() {
        let calendars = store.calendars(for: .event).sorted {
            ($0.source.title, $0.title) < ($1.source.title, $1.title)
        }
        if calendars.map(\.calendarIdentifier) != availableCalendars.map(\.calendarIdentifier) {
            availableCalendars = calendars
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

    /// Re-arms a meeting so it fires again after `delay` (chosen on the alert itself,
    /// defaulting to `snoozeDuration` but overridable per-snooze).
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
        let endOfDay = Foundation.Calendar.current.dateInterval(of: .day, for: now)?.end ?? windowEnd
        let queryEnd = max(windowEnd, endOfDay)
        let includedCalendars = availableCalendars.filter(isIncluded)

        guard !includedCalendars.isEmpty else {
            nextMeeting = nil
            todaysMeetings = []
            return
        }

        let predicate = store.predicateForEvents(withStart: now, end: queryEnd, calendars: includedCalendars)
        let events = store.events(matching: predicate)
            .filter { !$0.isAllDay }
            .sorted { $0.startDate < $1.startDate }

        nextMeeting = events.first.map(makeMeeting)
        todaysMeetings = events.map(makeMeeting)

        for event in events where event.startDate <= windowEnd {
            let key = eventKey(event)
            guard !alertedEventKeys.contains(key) else { continue }
            let effectiveLeadTime = calendarLeadTimeOverrides[event.calendar.calendarIdentifier] ?? leadTime
            let triggerAt = event.startDate.addingTimeInterval(-effectiveLeadTime)
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
            joinURL: MeetingLinkExtractor.link(for: event),
            location: event.location
        )
    }
}

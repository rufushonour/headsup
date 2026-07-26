import SwiftUI
import EventKit

private let leadTimeOptions: [(title: String, seconds: TimeInterval)] = [
    ("At start time", 0),
    ("1 minute before", 60),
    ("2 minutes before", 120),
    ("5 minutes before", 300)
]

private let snoozeDurationOptions: [(title: String, seconds: TimeInterval)] = [
    ("1 minute", 60),
    ("5 minutes", 300),
    ("10 minutes", 600),
    ("15 minutes", 900)
]

struct SettingsView: View {
    @ObservedObject var calendarService: CalendarService

    var body: some View {
        Form {
            Section("Alerts") {
                Picker("Alert me", selection: $calendarService.leadTime) {
                    ForEach(leadTimeOptions, id: \.seconds) { option in
                        Text(option.title).tag(option.seconds)
                    }
                }
                Picker("Snooze duration", selection: $calendarService.snoozeDuration) {
                    ForEach(snoozeDurationOptions, id: \.seconds) { option in
                        Text(option.title).tag(option.seconds)
                    }
                }
            }

            Section("Calendars") {
                if calendarService.availableCalendars.isEmpty {
                    Text("No calendars found")
                        .foregroundColor(.secondary)
                } else {
                    ForEach(calendarService.availableCalendars, id: \.calendarIdentifier) { calendar in
                        CalendarRow(calendar: calendar, calendarService: calendarService)
                    }
                }
            }
        }
        .formStyle(.grouped)
        .frame(width: 480, height: 420)
    }
}

private struct CalendarRow: View {
    let calendar: EKCalendar
    @ObservedObject var calendarService: CalendarService

    private var includedBinding: Binding<Bool> {
        Binding(
            get: { calendarService.isIncluded(calendar) },
            set: { calendarService.setIncluded($0, for: calendar) }
        )
    }

    private var leadTimeBinding: Binding<TimeInterval?> {
        Binding(
            get: { calendarService.leadTimeOverride(for: calendar) },
            set: { calendarService.setLeadTimeOverride($0, for: calendar) }
        )
    }

    var body: some View {
        VStack(alignment: .leading, spacing: 4) {
            Toggle(isOn: includedBinding) {
                VStack(alignment: .leading) {
                    Text(calendar.title)
                    Text(calendar.source.title)
                        .font(.caption)
                        .foregroundColor(.secondary)
                }
            }

            if calendarService.isIncluded(calendar) {
                Picker("Alert timing", selection: leadTimeBinding) {
                    Text("Use default (\(leadTimeLabel(calendarService.leadTime)))").tag(TimeInterval?.none)
                    ForEach(leadTimeOptions, id: \.seconds) { option in
                        Text(option.title).tag(TimeInterval?.some(option.seconds))
                    }
                }
                .labelsHidden()
                .padding(.leading, 24)
            }
        }
        .padding(.vertical, 2)
    }

    private func leadTimeLabel(_ seconds: TimeInterval) -> String {
        leadTimeOptions.first(where: { $0.seconds == seconds })?.title ?? "\(Int(seconds))s before"
    }
}

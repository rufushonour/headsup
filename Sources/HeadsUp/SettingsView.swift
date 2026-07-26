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
        VStack(spacing: 0) {
            header

            Divider()

            Form {
                Section {
                    Picker(selection: $calendarService.leadTime) {
                        ForEach(leadTimeOptions, id: \.seconds) { option in
                            Text(option.title).tag(option.seconds)
                        }
                    } label: {
                        Label("Alert me", systemImage: "bell.fill")
                    }
                    Picker(selection: $calendarService.snoozeDuration) {
                        ForEach(snoozeDurationOptions, id: \.seconds) { option in
                            Text(option.title).tag(option.seconds)
                        }
                    } label: {
                        Label("Snooze duration", systemImage: "moon.zzz.fill")
                    }
                } header: {
                    Text("Defaults")
                } footer: {
                    Text("Applies to every calendar unless overridden below. You can also pick a different snooze length right on the alert itself.")
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
        }
        .frame(width: 500, height: 520)
    }

    private var header: some View {
        HStack(spacing: 14) {
            AppIconBadge(size: 44)
            VStack(alignment: .leading, spacing: 2) {
                Text("Heads Up")
                    .font(.system(size: 17, weight: .semibold))
                Text("Full-screen meeting alerts")
                    .font(.system(size: 12))
                    .foregroundColor(.secondary)
            }
            Spacer()
        }
        .padding(.horizontal, 20)
        .padding(.vertical, 16)
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

    private var calendarColor: Color {
        Color(nsColor: calendar.color)
    }

    var body: some View {
        VStack(alignment: .leading, spacing: 4) {
            Toggle(isOn: includedBinding) {
                HStack(spacing: 8) {
                    Circle()
                        .fill(calendarColor)
                        .frame(width: 9, height: 9)
                    VStack(alignment: .leading) {
                        Text(calendar.title)
                        Text(calendar.source.title)
                            .font(.caption)
                            .foregroundColor(.secondary)
                    }
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
                .padding(.leading, 26)
            }
        }
        .padding(.vertical, 2)
    }

    private func leadTimeLabel(_ seconds: TimeInterval) -> String {
        leadTimeOptions.first(where: { $0.seconds == seconds })?.title ?? "\(Int(seconds))s before"
    }
}

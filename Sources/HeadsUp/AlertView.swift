import SwiftUI

private let snoozeOptions: [(title: String, seconds: TimeInterval)] = [
    ("1 min", 60),
    ("5 min", 300),
    ("10 min", 600),
    ("15 min", 900)
]

struct AlertView: View {
    let meetings: [UpcomingMeeting]
    let defaultSnoozeSeconds: TimeInterval
    let onJoin: (UpcomingMeeting) -> Void
    let onSnooze: (TimeInterval) -> Void
    let onDismiss: () -> Void

    @State private var now = Date()
    @State private var appeared = false
    @State private var showSnoozeOptions = false
    private let timer = Timer.publish(every: 1, on: .main, in: .common).autoconnect()

    private var defaultSnoozeLabel: String {
        snoozeOptions.first(where: { $0.seconds == defaultSnoozeSeconds })?.title ?? "\(Int(defaultSnoozeSeconds / 60)) min"
    }

    // Meetings only get folded together when they're due around the same time (see
    // AlertPresenter), so treating the group's span as [earliest start, latest end] gives
    // a sensible single status line without favoring one meeting over another.
    private var earliestStart: Date { meetings.map(\.startDate).min() ?? now }
    private var latestEnd: Date { meetings.map(\.endDate).max() ?? now }

    private var statusText: String {
        let secondsUntil = earliestStart.timeIntervalSince(now)
        if secondsUntil > 1 {
            return "Starts in \(Int(secondsUntil.rounded()))s"
        } else if now < latestEnd {
            return "Starting now"
        } else {
            return "In progress"
        }
    }

    var body: some View {
        ZStack {
            LinearGradient(
                colors: [
                    Color(red: 0.11, green: 0.10, blue: 0.29),
                    Color.black
                ],
                startPoint: .top,
                endPoint: .bottom
            )
            .ignoresSafeArea()

            if showSnoozeOptions {
                Color.black.opacity(0.001)
                    .ignoresSafeArea()
                    .onTapGesture { showSnoozeOptions = false }
            }

            VStack(spacing: 32) {
                AppIconBadge(size: 72)
                    .shadow(color: .black.opacity(0.35), radius: 16, y: 8)

                VStack(spacing: 14) {
                    Text(statusText.uppercased())
                        .font(.system(size: 15, weight: .semibold))
                        .tracking(2)
                        .foregroundColor(Color(red: 0.98, green: 0.55, blue: 0.20))

                    if meetings.count == 1, let meeting = meetings.first {
                        Text(meeting.title)
                            .font(.system(size: 52, weight: .bold, design: .rounded))
                            .foregroundColor(.white)
                            .multilineTextAlignment(.center)
                            .lineLimit(3)
                            .padding(.horizontal, 80)

                        Text(meeting.startDate, style: .time)
                            .font(.system(size: 20))
                            .foregroundColor(.white.opacity(0.55))
                    } else {
                        Text("\(meetings.count) Meetings")
                            .font(.system(size: 52, weight: .bold, design: .rounded))
                            .foregroundColor(.white)

                        Text(earliestStart, style: .time)
                            .font(.system(size: 20))
                            .foregroundColor(.white.opacity(0.55))

                        ScrollView {
                            VStack(spacing: 10) {
                                ForEach(meetings) { meeting in
                                    MeetingRow(meeting: meeting, onJoin: { onJoin(meeting) })
                                }
                            }
                        }
                        .frame(maxWidth: 560, maxHeight: 280)
                        .padding(.top, 4)
                    }
                }

                HStack(alignment: .top, spacing: 16) {
                    if meetings.count == 1, let meeting = meetings.first, meeting.joinURL != nil {
                        Button(action: { onJoin(meeting) }) {
                            Label("Join Meeting", systemImage: "video.fill")
                        }
                        .buttonStyle(AlertButtonStyle(background: Color(red: 0.20, green: 0.72, blue: 0.36), foreground: .white))
                    }

                    ZStack(alignment: .top) {
                        Button(action: { showSnoozeOptions.toggle() }) {
                            HStack(spacing: 8) {
                                Text("Snooze \(defaultSnoozeLabel)")
                                Image(systemName: "chevron.down")
                                    .font(.system(size: 11, weight: .bold))
                                    .rotationEffect(.degrees(showSnoozeOptions ? 180 : 0))
                            }
                        }
                        .buttonStyle(AlertButtonStyle(background: Color.white.opacity(0.14), foreground: .white))

                        if showSnoozeOptions {
                            VStack(alignment: .leading, spacing: 0) {
                                ForEach(snoozeOptions, id: \.seconds) { option in
                                    Button {
                                        onSnooze(option.seconds)
                                        showSnoozeOptions = false
                                    } label: {
                                        Text(option.title)
                                            .frame(maxWidth: .infinity, alignment: .leading)
                                    }
                                    .buttonStyle(.plain)
                                    .padding(.horizontal, 16)
                                    .padding(.vertical, 10)
                                }
                            }
                            .frame(width: 160)
                            .background(RoundedRectangle(cornerRadius: 12, style: .continuous).fill(Color(red: 0.16, green: 0.15, blue: 0.24)))
                            .offset(y: 58)
                            .zIndex(1)
                            .transition(.opacity.combined(with: .move(edge: .top)))
                        }
                    }
                    .zIndex(showSnoozeOptions ? 1 : 0)

                    Button(action: onDismiss) {
                        Text("Dismiss")
                    }
                    .buttonStyle(AlertButtonStyle(background: Color.white.opacity(0.14), foreground: .white))
                }
                .padding(.top, 8)
            }
            .opacity(appeared ? 1 : 0)
            .scaleEffect(appeared ? 1 : 0.97)
        }
        .onReceive(timer) { now = $0 }
        .onAppear {
            now = Date()
            withAnimation(.easeOut(duration: 0.35)) {
                appeared = true
            }
        }
    }
}

private struct MeetingRow: View {
    let meeting: UpcomingMeeting
    let onJoin: () -> Void

    var body: some View {
        HStack(spacing: 14) {
            VStack(alignment: .leading, spacing: 3) {
                Text(meeting.title)
                    .font(.system(size: 19, weight: .semibold))
                    .foregroundColor(.white)
                    .lineLimit(2)
                if meeting.joinURL == nil, let location = meeting.location, !location.isEmpty {
                    Text(location)
                        .font(.system(size: 13))
                        .foregroundColor(.white.opacity(0.55))
                }
            }
            Spacer(minLength: 12)
            if meeting.joinURL != nil {
                Button(action: onJoin) {
                    Label("Join", systemImage: "video.fill")
                }
                .buttonStyle(AlertButtonStyle(
                    background: Color(red: 0.20, green: 0.72, blue: 0.36),
                    foreground: .white,
                    fontSize: 14,
                    horizontalPadding: 16,
                    verticalPadding: 9
                ))
            }
        }
        .padding(.horizontal, 18)
        .padding(.vertical, 12)
        .background(RoundedRectangle(cornerRadius: 14, style: .continuous).fill(Color.white.opacity(0.08)))
    }
}

private struct AlertButtonStyle: ButtonStyle {
    let background: Color
    let foreground: Color
    var fontSize: CGFloat = 17
    var horizontalPadding: CGFloat = 26
    var verticalPadding: CGFloat = 14

    func makeBody(configuration: Configuration) -> some View {
        configuration.label
            .font(.system(size: fontSize, weight: .semibold))
            .padding(.horizontal, horizontalPadding)
            .padding(.vertical, verticalPadding)
            .foregroundColor(foreground)
            .background(
                Capsule().fill(background.opacity(configuration.isPressed ? 0.7 : 1))
            )
    }
}

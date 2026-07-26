import SwiftUI

private let snoozeOptions: [(title: String, seconds: TimeInterval)] = [
    ("1 min", 60),
    ("5 min", 300),
    ("10 min", 600),
    ("15 min", 900)
]

struct AlertView: View {
    let meeting: UpcomingMeeting
    let defaultSnoozeSeconds: TimeInterval
    let onJoin: () -> Void
    let onSnooze: (TimeInterval) -> Void
    let onDismiss: () -> Void

    @State private var now = Date()
    @State private var appeared = false
    private let timer = Timer.publish(every: 1, on: .main, in: .common).autoconnect()

    private var defaultSnoozeLabel: String {
        snoozeOptions.first(where: { $0.seconds == defaultSnoozeSeconds })?.title ?? "\(Int(defaultSnoozeSeconds / 60)) min"
    }

    private var statusText: String {
        let secondsUntil = meeting.startDate.timeIntervalSince(now)
        if secondsUntil > 1 {
            return "Starts in \(Int(secondsUntil.rounded()))s"
        } else if now < meeting.endDate {
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

            VStack(spacing: 32) {
                AppIconBadge(size: 72)
                    .shadow(color: .black.opacity(0.35), radius: 16, y: 8)

                VStack(spacing: 14) {
                    Text(statusText.uppercased())
                        .font(.system(size: 15, weight: .semibold))
                        .tracking(2)
                        .foregroundColor(Color(red: 0.98, green: 0.55, blue: 0.20))

                    Text(meeting.title)
                        .font(.system(size: 52, weight: .bold, design: .rounded))
                        .foregroundColor(.white)
                        .multilineTextAlignment(.center)
                        .lineLimit(3)
                        .padding(.horizontal, 80)

                    Text(meeting.startDate, style: .time)
                        .font(.system(size: 20))
                        .foregroundColor(.white.opacity(0.55))
                }

                HStack(spacing: 16) {
                    if meeting.joinURL != nil {
                        Button(action: onJoin) {
                            Label("Join Meeting", systemImage: "video.fill")
                        }
                        .buttonStyle(AlertButtonStyle(background: Color(red: 0.20, green: 0.72, blue: 0.36), foreground: .white))
                    }

                    SnoozeSplitButton(
                        defaultLabel: defaultSnoozeLabel,
                        onSnooze: { onSnooze(defaultSnoozeSeconds) },
                        onSnoozeFor: onSnooze
                    )

                    Button(action: onDismiss) {
                        Text("Dismiss")
                    }
                    .buttonStyle(AlertButtonStyle(background: .clear, foreground: .white.opacity(0.65)))
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

/// A "Snooze 5 min" capsule that snoozes at the configured default on a plain click,
/// with a small chevron opening a menu to pick a different duration for this alert only.
private struct SnoozeSplitButton: View {
    let defaultLabel: String
    let onSnooze: () -> Void
    let onSnoozeFor: (TimeInterval) -> Void

    var body: some View {
        HStack(spacing: 0) {
            Button(action: onSnooze) {
                Text("Snooze \(defaultLabel)")
                    .padding(.leading, 26)
                    .padding(.trailing, 10)
                    .padding(.vertical, 14)
            }
            .buttonStyle(.plain)

            Menu {
                ForEach(snoozeOptions, id: \.seconds) { option in
                    Button(option.title) { onSnoozeFor(option.seconds) }
                }
            } label: {
                Color.clear
                    .frame(width: 8, height: 8)
                    .padding(.leading, 6)
                    .padding(.trailing, 22)
                    .padding(.vertical, 14)
            }
            .menuStyle(.borderlessButton)
            .fixedSize()
        }
        .font(.system(size: 17, weight: .semibold))
        .foregroundColor(.white)
        .background(Capsule().fill(Color.white.opacity(0.14)))
    }
}

private struct AlertButtonStyle: ButtonStyle {
    let background: Color
    let foreground: Color

    func makeBody(configuration: Configuration) -> some View {
        configuration.label
            .font(.system(size: 17, weight: .semibold))
            .padding(.horizontal, 26)
            .padding(.vertical, 14)
            .foregroundColor(foreground)
            .background(
                Capsule().fill(background.opacity(configuration.isPressed ? 0.7 : 1))
            )
    }
}

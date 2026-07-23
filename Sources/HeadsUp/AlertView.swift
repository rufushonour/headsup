import SwiftUI

struct AlertView: View {
    let meeting: UpcomingMeeting
    let onJoin: () -> Void
    let onSnooze: () -> Void
    let onDismiss: () -> Void

    @State private var now = Date()
    private let timer = Timer.publish(every: 1, on: .main, in: .common).autoconnect()

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
            Color.black.opacity(0.92).ignoresSafeArea()

            VStack(spacing: 28) {
                Text(statusText)
                    .font(.system(size: 22, weight: .medium))
                    .foregroundColor(.white.opacity(0.7))

                Text(meeting.title)
                    .font(.system(size: 56, weight: .bold))
                    .foregroundColor(.white)
                    .multilineTextAlignment(.center)
                    .lineLimit(3)
                    .padding(.horizontal, 80)

                Text(meeting.startDate, style: .time)
                    .font(.system(size: 24, weight: .regular))
                    .foregroundColor(.white.opacity(0.6))

                HStack(spacing: 20) {
                    if meeting.joinURL != nil {
                        Button(action: onJoin) {
                            Text("Join Meeting")
                                .font(.system(size: 20, weight: .semibold))
                                .padding(.horizontal, 36)
                                .padding(.vertical, 16)
                        }
                        .buttonStyle(.borderedProminent)
                        .tint(.green)
                        .controlSize(.large)
                    }

                    Button(action: onSnooze) {
                        Text("Snooze 5 min")
                            .font(.system(size: 18))
                            .padding(.horizontal, 28)
                            .padding(.vertical, 14)
                    }
                    .buttonStyle(.bordered)
                    .controlSize(.large)

                    Button(action: onDismiss) {
                        Text("Dismiss")
                            .font(.system(size: 18))
                            .padding(.horizontal, 28)
                            .padding(.vertical, 14)
                    }
                    .buttonStyle(.bordered)
                    .controlSize(.large)
                }
                .padding(.top, 12)
            }
        }
        .onReceive(timer) { now = $0 }
        .onAppear { now = Date() }
    }
}

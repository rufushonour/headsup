import SwiftUI

struct WelcomeView: View {
    let onContinue: () -> Void

    var body: some View {
        VStack(spacing: 28) {
            AppIconBadge(size: 84)
                .padding(.top, 40)
                .shadow(color: .black.opacity(0.25), radius: 12, y: 6)

            VStack(spacing: 8) {
                Text("Welcome to Heads Up")
                    .font(.system(size: 26, weight: .bold, design: .rounded))
                Text("Full-screen meeting alerts you can't miss.")
                    .font(.subheadline)
                    .foregroundColor(.secondary)
            }

            VStack(alignment: .leading, spacing: 18) {
                FeatureRow(icon: "bell.fill", text: "Blocks your screen full-screen right before each meeting")
                FeatureRow(icon: "link", text: "Automatically finds Zoom, Meet, and Teams join links")
                FeatureRow(icon: "calendar", text: "Choose exactly which calendars trigger alerts")
            }
            .padding(.horizontal, 48)

            Spacer()

            VStack(spacing: 12) {
                Text("Next, macOS will ask for Calendar access — Heads Up needs this to know when your meetings start.")
                    .font(.caption)
                    .foregroundColor(.secondary)
                    .multilineTextAlignment(.center)
                    .padding(.horizontal, 48)

                Button(action: onContinue) {
                    Text("Get Started")
                        .font(.system(size: 15, weight: .semibold))
                        .frame(maxWidth: .infinity)
                }
                .buttonStyle(.borderedProminent)
                .controlSize(.large)
                .padding(.horizontal, 64)
            }
            .padding(.bottom, 36)
        }
        .frame(width: 480, height: 560)
    }
}

private struct FeatureRow: View {
    let icon: String
    let text: String

    var body: some View {
        HStack(alignment: .top, spacing: 14) {
            Image(systemName: icon)
                .font(.system(size: 17, weight: .semibold))
                .foregroundColor(Color(red: 0.31, green: 0.27, blue: 0.90))
                .frame(width: 22)
            Text(text)
                .font(.system(size: 13.5))
            Spacer(minLength: 0)
        }
    }
}

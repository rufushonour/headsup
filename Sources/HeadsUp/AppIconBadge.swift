import SwiftUI

/// A small rendition of the app icon (indigo gradient squircle, bell, orange badge)
/// for use inside SwiftUI screens, without needing to load the bundled .icns at runtime.
struct AppIconBadge: View {
    var size: CGFloat = 48

    var body: some View {
        ZStack {
            RoundedRectangle(cornerRadius: size * 0.2237, style: .continuous)
                .fill(
                    LinearGradient(
                        colors: [
                            Color(red: 0.31, green: 0.27, blue: 0.90),
                            Color(red: 0.11, green: 0.10, blue: 0.29)
                        ],
                        startPoint: .top,
                        endPoint: .bottom
                    )
                )

            Image(systemName: "bell.fill")
                .resizable()
                .scaledToFit()
                .frame(width: size * 0.46, height: size * 0.46)
                .foregroundColor(.white)
                .offset(y: -size * 0.02)

            Circle()
                .fill(Color(red: 0.98, green: 0.45, blue: 0.09))
                .frame(width: size * 0.22, height: size * 0.22)
                .offset(x: size * 0.27, y: -size * 0.27)
        }
        .frame(width: size, height: size)
    }
}

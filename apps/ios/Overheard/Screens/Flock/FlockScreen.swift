import SwiftUI

/// The Flock tab: friends' walks. It needs the backend (Phases 2–4), so for now it says so.
struct FlockScreen: View {
    @Environment(\.theme) private var theme

    var body: some View {
        VStack(alignment: .leading, spacing: 16) {
            Text("Flock").font(.display(30)).foregroundStyle(theme.chromeInk)

            Text("Your friends' walks will appear here once sharing is ready.")
                .font(.body(17))
                .foregroundStyle(theme.chromeSoft)

            Spacer()
        }
        .padding(.horizontal, 22)
        .padding(.top, 24)
        .frame(maxWidth: .infinity, alignment: .leading)
        .background(theme.chromeBackground.ignoresSafeArea())
    }
}

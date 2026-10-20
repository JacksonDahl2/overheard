import SwiftUI

/// The four tabs under the app's own tab bar, with the chosen theme applied to everything.
struct RootView: View {
    @Bindable var listener: Listener

    @AppStorage("themeChoice") private var themeChoice: ThemeChoice = .system
    @Environment(\.colorScheme) private var systemScheme
    @State private var tab: Tab = .listen

    var body: some View {
        let theme = themeChoice.theme(for: systemScheme)

        TabView(selection: $tab) {
            ListenScreen(listener: listener)
                .tag(Tab.listen)
                .toolbar(.hidden, for: .tabBar)

            WalksScreen(listener: listener)
                .tag(Tab.journal)
                .toolbar(.hidden, for: .tabBar)

            FlockScreen()
                .tag(Tab.flock)
                .toolbar(.hidden, for: .tabBar)

            MeScreen(listener: listener, themeChoice: $themeChoice)
                .tag(Tab.me)
                .toolbar(.hidden, for: .tabBar)
        }
        .safeAreaInset(edge: .bottom, spacing: 0) { TabBar(selection: $tab) }
        .environment(\.theme, theme)
        .tint(theme.accent)
        // A fixed theme also fixes light/dark for system controls. "Match the phone" must leave it
        // unset, or `systemScheme` would report our override instead of the phone's setting.
        .preferredColorScheme(themeChoice == .system ? nil : theme.colorScheme)
    }
}

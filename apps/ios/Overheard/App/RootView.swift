import SwiftUI

/// The four tabs above the app's own tab bar, with the chosen theme applied to everything.
struct RootView: View {
    @Bindable var listener: Listener

    @AppStorage("themeChoice") private var themeChoice: ThemeChoice = .system
    @Environment(\.colorScheme) private var systemScheme
    @State private var tab: Tab = Self.startingTab

    var body: some View {
        let theme = themeChoice.theme(for: systemScheme)

        // The tab bar sits below the tabs (not over them), so every screen's bottom edge,
        // like Listen's End walk button, stays above it.
        VStack(spacing: 0) {
            tabs
            TabBar(selection: $tab)
        }
        .environment(\.theme, theme)
        .tint(theme.accent)
        // A fixed theme also fixes light/dark for system controls. "Match the phone" must leave it
        // unset, or `systemScheme` would report our override instead of the phone's setting.
        .preferredColorScheme(themeChoice == .system ? nil : theme.colorScheme)
    }

    /// Listen, unless a Debug launch asks for another (`-startTab journal`, for screenshots).
    private static var startingTab: Tab {
        #if DEBUG
            if let name = UserDefaults.standard.string(forKey: "startTab"), let tab = Tab(rawValue: name) { return tab }
        #endif
        return .listen
    }

    /// The system TabView keeps each tab's state (scroll position, navigation); its own bar is hidden.
    private var tabs: some View {
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
    }
}

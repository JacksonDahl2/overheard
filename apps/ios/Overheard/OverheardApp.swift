import SwiftUI

@main
struct OverheardApp: App {
    @State private var listener = Listener()

    var body: some Scene {
        WindowGroup {
            ListenView(listener: listener)
        }
    }
}

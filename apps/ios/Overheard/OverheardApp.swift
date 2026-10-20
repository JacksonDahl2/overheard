import OverheardKit
import SwiftData
import SwiftUI

@main
struct OverheardApp: App {
    private let container: ModelContainer
    @State private var listener: Listener
    @Environment(\.scenePhase) private var scenePhase

    init() {
        do {
            container = try WalkStore.container()
        } catch {
            fatalError("Can't open the walk store: \(error)")
        }
        _listener = State(initialValue: Listener(store: WalkStore(context: container.mainContext)))
    }

    var body: some Scene {
        WindowGroup {
            ListenView(listener: listener)
        }
        .modelContainer(container)
        .onChange(of: scenePhase) { _, phase in
            if phase == .background { listener.saveNow() }  // iOS may kill the app from here
        }
    }
}

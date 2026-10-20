import OverheardKit
import SwiftData
import SwiftUI

@main
struct OverheardApp: App {
    private let container: ModelContainer
    @State private var listener: Listener
    @Environment(\.scenePhase) private var scenePhase

    init() {
        NavigationBarStyle.apply()

        do {
            container = try WalkStore.container()
        } catch {
            fatalError("Can't open the walk store: \(error)")
        }

        let listener = Listener(store: WalkStore(context: container.mainContext))
        #if DEBUG
            if DemoWalk.isRequested, let catalog = listener.catalog {
                listener.showDemo(DemoWalk(catalog: catalog))
            }
        #endif
        _listener = State(initialValue: listener)
    }

    var body: some Scene {
        WindowGroup {
            RootView(listener: listener)
        }
        .modelContainer(container)
        .onChange(of: scenePhase) { _, phase in
            if phase == .background { listener.saveNow() }  // iOS may kill the app from here
        }
    }
}

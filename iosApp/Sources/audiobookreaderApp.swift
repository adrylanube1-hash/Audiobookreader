import SwiftUI

@main
struct audiobookreaderApp: App {
    @StateObject private var store = AppStore()

    var body: some Scene {
        WindowGroup {
            RootView(store: store)
                .preferredColorScheme(store.colorScheme)
        }
    }
}

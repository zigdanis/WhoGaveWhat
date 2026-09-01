import SwiftUI

@main
struct WhoGaveWhatApp: App {
    @State private var composition: AppComposition

    init() {
        _composition = State(initialValue: AppComposition(store: .shared))
    }

    var body: some Scene {
        WindowGroup {
            ContentView(composition: composition)
        }
    }
}

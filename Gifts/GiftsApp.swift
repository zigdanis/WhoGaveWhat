import SwiftUI

@main
struct GiftsApp: App {
    private let persistence = PersistenceController.shared
    @StateObject private var store: AppStore

    init() {
        let ctx = PersistenceController.shared.container.viewContext
        _store = StateObject(wrappedValue: AppStore(context: ctx))
    }

    var body: some Scene {
        WindowGroup {
            ContentView()
                .environmentObject(store)
                .environment(\.managedObjectContext, persistence.container.viewContext)
        }
    }
}

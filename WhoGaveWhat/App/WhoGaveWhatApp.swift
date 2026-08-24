import SwiftUI

@main
struct WhoGaveWhatApp: App {
    private let persistence = CoreDataStack.shared
    @State private var composition: AppComposition

    init() {
        _composition = State(initialValue: AppComposition(stack: .shared))
    }

    var body: some Scene {
        WindowGroup {
            ContentView(composition: composition)
                .environment(\.managedObjectContext, persistence.container.viewContext)
        }
    }
}

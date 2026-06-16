import CoreData
@testable import WhoGaveWhat

/// A fresh, isolated in-memory store seeded with the standard sample data
/// (4 family members, 6 external people, 12 gifts). Each call builds its own
/// Core Data stack, so tests can mutate freely without bleeding into each other.
@MainActor
func makeSeededStore() -> AppStore {
    let controller = PersistenceController(inMemory: true, seed: true)
    return AppStore(context: controller.container.viewContext)
}

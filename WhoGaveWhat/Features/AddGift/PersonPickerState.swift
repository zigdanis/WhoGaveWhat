import Foundation
import Observation

@MainActor
@Observable
final class PersonPickerState {
    var query = ""
    private(set) var visiblePeople: [Person]
    private(set) var selectedID: String?

    private let people: [Person]

    init(people: [Person], selectedID: String?) {
        self.people = people
        self.selectedID = selectedID
        visiblePeople = people
    }

    @discardableResult
    func updateQuery(_ query: String) -> String? {
        self.query = query
        let trimmedQuery = query.trimmingCharacters(in: .whitespacesAndNewlines)
        visiblePeople = trimmedQuery.isEmpty
            ? people
            : people.filter { $0.name.localizedCaseInsensitiveContains(trimmedQuery) }

        guard !trimmedQuery.isEmpty, let firstMatch = visiblePeople.first else {
            return nil
        }
        selectedID = firstMatch.id
        return firstMatch.id
    }

    func select(_ id: String) {
        selectedID = id
    }
}

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
        visiblePeople = people
        self.selectedID =
            selectedID.flatMap { selectedID in
                people.contains { $0.id == selectedID } ? selectedID : nil
            } ?? people.first?.id
    }

    @discardableResult
    func updateQuery(_ query: String) -> String? {
        self.query = query
        let trimmedQuery = query.trimmingCharacters(in: .whitespacesAndNewlines)
        visiblePeople =
            trimmedQuery.isEmpty
            ? people
            : people.filter { $0.name.localizedCaseInsensitiveContains(trimmedQuery) }

        selectedID = visiblePeople.first?.id
        return selectedID
    }

    func select(_ id: String) {
        selectedID = id
    }
}

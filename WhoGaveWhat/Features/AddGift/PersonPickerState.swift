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
        // UIKit may deliver the final text-field value again while the Add
        // action is dismissing the picker. Filtering the original people
        // snapshot again would clear a freshly-created selection because the
        // new person is not part of that snapshot.
        guard query != self.query else { return selectedID }
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

    @discardableResult
    func createAndSelectPerson(
        named name: String,
        create: (String) -> String?,
        select: (String) -> Void
    ) -> String? {
        guard let id = create(name) else { return nil }
        selectedID = id
        select(id)
        return id
    }
}

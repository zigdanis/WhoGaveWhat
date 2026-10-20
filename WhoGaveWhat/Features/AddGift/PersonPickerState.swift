import Foundation
import Observation

@MainActor
@Observable
final class PersonPickerState {
    var query = ""
    private(set) var visiblePeople: [Person]
    private(set) var selectedID: String?

    private let people: [Person]
    private let counterpartID: String?

    /// `counterpartID` is the person already chosen on the other side of the gift. Automatic
    /// preselection skips them, but they stay visible and can still be tapped.
    init(people: [Person], selectedID: String?, counterpartID: String? = nil) {
        self.people = people
        self.counterpartID = counterpartID
        visiblePeople = people
        self.selectedID =
            selectedID.flatMap { selectedID in
                people.contains { $0.id == selectedID } ? selectedID : nil
            } ?? Self.firstPerson(in: people, excluding: counterpartID)
    }

    private static func firstPerson(in people: [Person], excluding counterpartID: String?) -> String? {
        people.first { $0.id != counterpartID }?.id
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

        selectedID = Self.firstPerson(in: visiblePeople, excluding: counterpartID)
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

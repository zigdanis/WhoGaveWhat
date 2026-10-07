import Foundation
import Observation

@MainActor
@Observable
final class AppData {
    private(set) var gifts: [Gift] = []
    private(set) var people: [Person] = []
    private(set) var householdMembers: [Person] = []
    private(set) var contacts: [Person] = []
    private(set) var occasions: [Occasion] = AppData.defaultOccasions

    static let defaultOccasions = [
        Occasion(name: "Birthday"),
        Occasion(name: "New Year"),
        Occasion(name: "Wedding"),
        Occasion(name: "Anniversary"),
        Occasion(name: "Graduation"),
        Occasion(name: "Housewarming"),
        Occasion(name: "Just because")
    ]

    func replaceGifts(_ gifts: [Gift]) {
        self.gifts = gifts
        let savedOccasions = gifts.map(\.occasion).filter { !$0.isEmpty }
        occasions = savedOccasions.reduce(into: Self.defaultOccasions) { result, name in
            if !result.contains(where: { $0.name == name }) { result.append(Occasion(name: name)) }
        }
    }

    func replacePeople(_ snapshot: PeopleSnapshot) {
        people = snapshot.people
        householdMembers = snapshot.householdMembers
        contacts = snapshot.contacts
    }

    func addOccasion(_ occasion: String) {
        let occasion = occasion.trimmingCharacters(in: .whitespaces)
        guard !occasion.isEmpty else { return }
        if !occasions.contains(where: {
            $0.name.caseInsensitiveCompare(occasion) == .orderedSame
        }) {
            occasions.insert(Occasion(name: occasion), at: 0)
        }
    }

    var peopleSnapshot: PeopleSnapshot {
        PeopleSnapshot(people: people)
    }

    var householdIDs: Set<String> {
        Set(householdMembers.map(\.id))
    }

    func entityName(_ id: String) -> String {
        people.first { $0.id == id }?.name ?? id
    }

    func entityColorHex(_ id: String) -> UInt {
        people.first { $0.id == id }?.colorHex ?? 0x12161C
    }

    func giftSubtitle(_ gift: Gift) -> String {
        "\(entityName(gift.giverID))  →  \(entityName(gift.recipientID))"
    }

    func localizedOccasion(_ occasion: String) -> String {
        String(localized: String.LocalizationValue(occasion))
    }
}

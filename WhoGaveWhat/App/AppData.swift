import Foundation
import Observation

@MainActor
@Observable
final class AppData {
    private(set) var gifts: [Gift] = []
    private(set) var people: [Person] = []
    private(set) var selfPersonID: String?
    private(set) var occasions: [Occasion] = AppData.defaultOccasions
    /// Whether `gifts` and `people` hold a complete snapshot from the store. Until the first load
    /// succeeds both are empty without meaning that the journal is.
    private(set) var hasLoadedSnapshot = false
    /// Whether the latest load failed. The previous snapshot, if any, stays on screen meanwhile.
    private(set) var isLoadFailing = false

    static let defaultOccasions = [
        Occasion(name: "Birthday"),
        Occasion(name: "New Year"),
        Occasion(name: "Wedding"),
        Occasion(name: "Anniversary"),
        Occasion(name: "Graduation"),
        Occasion(name: "Housewarming"),
        Occasion(name: "Just because")
    ]

    /// Publishes gifts and people loaded together, so the screens never mix two loads.
    func replaceSnapshot(gifts: [Gift], people: PeopleSnapshot) {
        self.gifts = gifts
        self.people = people.people
        let savedOccasions = gifts.map(\.occasion).filter { !$0.isEmpty }
        occasions = savedOccasions.reduce(into: Self.defaultOccasions) { result, name in
            if !result.contains(where: { $0.name == name }) { result.append(Occasion(name: name)) }
        }
        hasLoadedSnapshot = true
        isLoadFailing = false
    }

    /// Keeps the last snapshot (or none) and lets the screens offer a retry.
    func noteLoadFailed() {
        isLoadFailing = true
    }

    /// The first-run welcomes stand for an empty journal, so they need a loaded snapshot that is current:
    /// after a failed load an empty snapshot may be out of date.
    var showsGiftsWelcome: Bool {
        hasLoadedSnapshot && !isLoadFailing && gifts.isEmpty
    }

    var showsPeopleWelcome: Bool {
        hasLoadedSnapshot && !isLoadFailing && people.isEmpty
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

    /// The viewpoint person when one is set and still exists.
    var selfPerson: Person? {
        guard let selfPersonID else { return nil }
        return people.first { $0.id == selfPersonID }
    }

    func isSelf(_ id: String) -> Bool {
        selfPersonID == id
    }

    func setSelfPerson(_ id: String?) {
        selfPersonID = id
    }

    func entityName(_ id: String) -> String {
        people.first { $0.id == id }?.name ?? id
    }

    func entityColorHex(_ id: String) -> UInt {
        people.first { $0.id == id }?.colorHex ?? 0x12161C
    }

    func entityImageData(_ id: String) -> Data? {
        people.first { $0.id == id }?.imageData
    }

    func giftSubtitle(_ gift: Gift) -> String {
        "\(entityName(gift.giverID))  →  \(entityName(gift.recipientID))"
    }

    func localizedOccasion(_ occasion: String) -> String {
        String(localized: String.LocalizationValue(occasion))
    }
}

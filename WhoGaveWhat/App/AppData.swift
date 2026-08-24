import Foundation
import Observation

@MainActor
@Observable
final class AppData {
    private(set) var gifts: [Gift] = []
    private(set) var members: [HouseholdMember] = []
    private(set) var people: [Person] = []
    private(set) var celebrations: [Celebration] = AppData.defaultCelebrations

    static let defaultCelebrations = [
        Celebration(name: "Birthday"),
        Celebration(name: "New Year"),
        Celebration(name: "Wedding"),
        Celebration(name: "Anniversary"),
        Celebration(name: "Graduation"),
        Celebration(name: "Housewarming"),
        Celebration(name: "Just because"),
    ]

    func replaceGifts(_ gifts: [Gift]) {
        self.gifts = gifts
        let savedCelebrations = gifts.map(\.celebration).filter { !$0.isEmpty }
        celebrations = savedCelebrations.reduce(into: Self.defaultCelebrations) { result, name in
            if !result.contains(where: { $0.name == name }) { result.append(Celebration(name: name)) }
        }
    }

    func replacePeople(_ snapshot: PeopleSnapshot) {
        members = snapshot.members
        people = snapshot.people
    }

    func addCelebration(_ celebration: String) {
        let celebration = celebration.trimmingCharacters(in: .whitespaces)
        guard !celebration.isEmpty else { return }
        if !celebrations.contains(where: {
            $0.name.caseInsensitiveCompare(celebration) == .orderedSame
        }) {
            celebrations.insert(Celebration(name: celebration), at: 0)
        }
    }

    var peopleSnapshot: PeopleSnapshot {
        PeopleSnapshot(members: members, people: people)
    }

    var householdIDs: Set<String> {
        Set(members.map(\.id))
    }

    func isHouseholdMember(_ id: String) -> Bool {
        householdIDs.contains(id)
    }

    func personName(_ id: String) -> String {
        people.first { $0.id == id }?.name ?? id
    }

    func memberName(_ id: String) -> String {
        members.first { $0.id == id }?.name ?? id
    }

    func entityName(_ id: String) -> String {
        members.first { $0.id == id }?.name ?? people.first { $0.id == id }?.name ?? id
    }

    func entityColorHex(_ id: String) -> UInt {
        members.first { $0.id == id }?.colorHex ?? people.first { $0.id == id }?.colorHex ?? 0x12161C
    }

    func giftSubtitle(_ gift: Gift) -> String {
        let giver = gift.flow == .received ? personName(gift.personId) : memberName(gift.memberId)
        let receiver = gift.flow == .received ? memberName(gift.memberId) : personName(gift.personId)
        return "\(giver)  →  \(receiver)"
    }

    func localizedCelebration(_ celebration: String) -> String {
        String(localized: String.LocalizationValue(celebration))
    }
}

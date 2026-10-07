import Foundation

enum PersonRole: String, Codable, CaseIterable, Hashable {
    case household
    case contact
}

struct Person: Identifiable, Hashable {
    let id: String
    let name: String
    let colorHex: UInt
    let role: PersonRole
}

struct PeopleSnapshot: Equatable {
    let people: [Person]

    var householdMembers: [Person] {
        people.filter { $0.role == .household }
    }

    var contacts: [Person] {
        people.filter { $0.role == .contact }
    }
}

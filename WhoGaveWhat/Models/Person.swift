import Foundation

struct Person: Identifiable, Hashable {
    let id: String
    let name: String
    let colorHex: UInt
}

struct PeopleSnapshot: Equatable {
    let members: [HouseholdMember]
    let people: [Person]
}

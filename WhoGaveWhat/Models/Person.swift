import Foundation

struct Person: Identifiable, Hashable {
    let id: String
    let name: String
    let colorHex: UInt
    let imageData: Data?

    init(id: String, name: String, colorHex: UInt, imageData: Data? = nil) {
        self.id = id
        self.name = name
        self.colorHex = colorHex
        self.imageData = imageData
    }
}

struct PeopleSnapshot: Equatable {
    let people: [Person]
}

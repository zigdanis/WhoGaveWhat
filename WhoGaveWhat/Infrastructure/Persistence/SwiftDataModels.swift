import Foundation
import SwiftData

@Model
final class StoredPerson {
    @Attribute(.unique) var id: String
    var name: String
    var colorHex: Int64
    var sortIndex: Int
    @Attribute(.externalStorage) var imageData: Data?
    @Relationship(deleteRule: .cascade, inverse: \StoredGift.giver)
    var giftsGiven: [StoredGift] = []
    @Relationship(deleteRule: .cascade, inverse: \StoredGift.recipient)
    var giftsReceived: [StoredGift] = []

    init(id: String, name: String, colorHex: Int64, sortIndex: Int, imageData: Data? = nil) {
        self.id = id
        self.name = name
        self.colorHex = colorHex
        self.sortIndex = sortIndex
        self.imageData = imageData
    }
}

@Model
final class StoredGift {
    @Attribute(.unique) var id: String
    var emoji: String
    var name: String
    var giver: StoredPerson
    var recipient: StoredPerson
    var paidByYou: Bool
    var occasion: String
    var date: Date
    var value: Double
    var createdAt: Date
    // The default lets stores created before this attribute open with a lightweight migration.
    var emojiPickedByUser: Bool = false

    init(
        id: String,
        emoji: String,
        name: String,
        giver: StoredPerson,
        recipient: StoredPerson,
        paidByYou: Bool,
        occasion: String,
        date: Date,
        value: Double,
        createdAt: Date,
        emojiPickedByUser: Bool = false
    ) {
        self.id = id
        self.emoji = emoji
        self.name = name
        self.giver = giver
        self.recipient = recipient
        self.paidByYou = paidByYou
        self.occasion = occasion
        self.date = date
        self.value = value
        self.createdAt = createdAt
        self.emojiPickedByUser = emojiPickedByUser
    }
}

import Foundation
import SwiftData
import Testing
@testable import WhoGaveWhat

@MainActor
struct SwiftDataPersistenceTests {
    @Test func seededStoreRoundTripsTheDomainSchema() throws {
        let store = try SwiftDataStore(inMemory: true, seed: true)
        let gifts = try SwiftDataGiftGateway(context: store.context).loadGifts()
        let snapshot = try SwiftDataPeopleGateway(context: store.context).loadPeople()

        #expect(gifts.count == 12)
        #expect(snapshot.householdMembers.count == 4)
        #expect(snapshot.contacts.count == 6)
        #expect(snapshot.people.allSatisfy { !$0.id.isEmpty })
        #expect(gifts.allSatisfy { !$0.giverID.isEmpty && !$0.recipientID.isEmpty })
        #expect(gifts.allSatisfy { $0.createdAt != .distantPast })
        #expect(gifts.first { $0.id == "g1" }?.giverID == "maria")
        #expect(gifts.first { $0.id == "g1" }?.recipientID == "marina")
        #expect(gifts.first { $0.id == "g1" }?.direction == .received)
        #expect(gifts.first { $0.id == "g8" }?.direction == .given)
    }

    @Test func giftGatewayRoundTripsRelationshipsAndUpdatesByStableID() throws {
        let store = try SwiftDataStore(inMemory: true)
        let peopleGateway = SwiftDataPeopleGateway(context: store.context)
        let giftGateway = SwiftDataGiftGateway(context: store.context)
        try createPerson(id: "you", role: .household, using: peopleGateway)
        try createPerson(id: "member", role: .household, sortIndex: 1, using: peopleGateway)
        try createPerson(id: "friend", role: .contact, sortIndex: 2, using: peopleGateway)
        let createdAt = Date(timeIntervalSince1970: 123)
        var gift = makeGift(
            id: "stable-gift-id",
            giverID: "you",
            recipientID: "friend",
            createdAt: createdAt
        )

        try giftGateway.save(gift)
        gift.name = "Updated gift"
        gift.value = 1_500
        gift.giverID = "member"
        try giftGateway.save(gift)

        let loaded = try giftGateway.loadGifts()
        #expect(loaded.count == 1)
        #expect(loaded.first?.id == "stable-gift-id")
        #expect(loaded.first?.name == "Updated gift")
        #expect(loaded.first?.value == 1_500)
        #expect(loaded.first?.createdAt == createdAt)
        #expect(loaded.first?.giverID == "member")
        #expect(loaded.first?.recipientID == "friend")
        #expect(loaded.first?.direction == .given)

        let stored = try store.context.fetch(FetchDescriptor<StoredGift>())
        #expect(stored.count == 1)
        #expect(stored.first?.giver.id == "member")
        #expect(stored.first?.recipient.id == "friend")
        #expect(stored.first?.giver.giftsGiven.map(\.id) == ["stable-gift-id"])
        #expect(stored.first?.recipient.giftsReceived.map(\.id) == ["stable-gift-id"])

        let storedPeople = try store.context.fetch(FetchDescriptor<StoredPerson>())
        #expect(storedPeople.first { $0.id == "you" }?.giftsGiven.isEmpty == true)
        #expect(storedPeople.first { $0.id == "member" }?.giftsGiven.map(\.id) == ["stable-gift-id"])

        try giftGateway.deleteGift(id: gift.id)
        #expect(try giftGateway.loadGifts().isEmpty)
        #expect(storedPeople.first { $0.id == "member" }?.giftsGiven.isEmpty == true)
        #expect(storedPeople.first { $0.id == "friend" }?.giftsReceived.isEmpty == true)
    }

    @Test func giftGatewayRejectsMissingAndIdenticalEndpoints() throws {
        let store = try SwiftDataStore(inMemory: true)
        let peopleGateway = SwiftDataPeopleGateway(context: store.context)
        let giftGateway = SwiftDataGiftGateway(context: store.context)
        try createPerson(id: "you", role: .household, using: peopleGateway)
        try createPerson(id: "friend", role: .contact, sortIndex: 1, using: peopleGateway)

        #expect(throws: SwiftDataPersistenceError.missingPerson(endpoint: .giver, id: "missing")) {
            try giftGateway.save(makeGift(id: "missing-giver", giverID: "missing", recipientID: "you"))
        }
        #expect(throws: SwiftDataPersistenceError.missingPerson(endpoint: .recipient, id: "missing")) {
            try giftGateway.save(makeGift(id: "missing-recipient", giverID: "you", recipientID: "missing"))
        }
        #expect(throws: SwiftDataPersistenceError.identicalGiftEndpoints(id: "you")) {
            try giftGateway.save(makeGift(id: "same", giverID: "you", recipientID: "you"))
        }
        let gifts = try giftGateway.loadGifts()
        #expect(gifts.isEmpty)
    }

    @Test func deletingPersonCascadesBothEndpointRelationshipsAtomically() throws {
        let store = try SwiftDataStore(inMemory: true)
        let peopleGateway = SwiftDataPeopleGateway(context: store.context)
        let giftGateway = SwiftDataGiftGateway(context: store.context)
        try createPerson(id: "you", role: .household, using: peopleGateway)
        try createPerson(id: "member", role: .household, sortIndex: 1, using: peopleGateway)
        try createPerson(id: "target", role: .contact, sortIndex: 2, using: peopleGateway)
        try createPerson(id: "other", role: .contact, sortIndex: 3, using: peopleGateway)

        try giftGateway.save(makeGift(id: "target-gave", giverID: "target", recipientID: "you"))
        try giftGateway.save(makeGift(id: "target-received", giverID: "member", recipientID: "target"))
        try giftGateway.save(makeGift(id: "unrelated", giverID: "member", recipientID: "other"))

        try peopleGateway.deletePerson(id: "target")

        let remainingGifts = try giftGateway.loadGifts()
        let remainingPeople = try peopleGateway.loadPeople()
        #expect(remainingGifts.map(\.id) == ["unrelated"])
        #expect(Set(remainingPeople.people.map(\.id)) == Set(["you", "member", "other"]))

        let storedPeople = try store.context.fetch(FetchDescriptor<StoredPerson>())
        #expect(storedPeople.allSatisfy { $0.id != "target" })
        #expect(storedPeople.first { $0.id == "member" }?.giftsGiven.map(\.id) == ["unrelated"])
        #expect(storedPeople.first { $0.id == "other" }?.giftsReceived.map(\.id) == ["unrelated"])
    }

    @Test func peopleGatewayPersistsRoleRenameAndDelete() throws {
        let store = try SwiftDataStore(inMemory: true)
        let gateway = SwiftDataPeopleGateway(context: store.context)
        try gateway.createPerson(
            id: "friend",
            name: "Friend",
            colorHex: 0x123456,
            role: .contact,
            sortIndex: 2
        )
        try gateway.renamePerson(id: "friend", name: "Best Friend")

        let saved = try gateway.loadPeople().people
        #expect(saved == [Person(id: "friend", name: "Best Friend", colorHex: 0x123456, role: .contact)])

        try gateway.deletePerson(id: "friend")
        let remaining = try gateway.loadPeople()
        #expect(remaining.people.isEmpty)
    }

    @Test func unseededMemoryStoreStartsEmptyAndUsesNewNamespace() throws {
        let store = try SwiftDataStore(inMemory: true)
        let gifts = try SwiftDataGiftGateway(context: store.context).loadGifts()
        let people = try SwiftDataPeopleGateway(context: store.context).loadPeople()
        #expect(gifts.isEmpty)
        #expect(people.people.isEmpty)
        #expect(SwiftDataStore.storeName == "WhoGaveWhatSwiftData")
    }

    @Test func productionStyleStoreBootstrapsOnlyTheSelfAnchor() throws {
        let store = try SwiftDataStore(inMemory: true, bootstrapsSelf: true)
        let people = try SwiftDataPeopleGateway(context: store.context).loadPeople()

        #expect(people.people.count == 1)
        #expect(people.people.first?.id == "you")
        #expect(people.people.first?.role == .household)
        #expect(try SwiftDataGiftGateway(context: store.context).loadGifts().isEmpty)
    }

    @Test func inMemoryStoresAreIsolated() throws {
        let firstStore = try SwiftDataStore(inMemory: true)
        let secondStore = try SwiftDataStore(inMemory: true)
        let firstGateway = SwiftDataPeopleGateway(context: firstStore.context)
        let secondGateway = SwiftDataPeopleGateway(context: secondStore.context)

        try createPerson(id: "only-in-first", role: .contact, using: firstGateway)

        #expect(try firstGateway.loadPeople().people.map(\.id) == ["only-in-first"])
        #expect(try secondGateway.loadPeople().people.isEmpty)
    }

    private func createPerson(
        id: String,
        role: PersonRole,
        sortIndex: Int = 0,
        using gateway: SwiftDataPeopleGateway
    ) throws {
        try gateway.createPerson(
            id: id,
            name: id,
            colorHex: 0x123456,
            role: role,
            sortIndex: sortIndex
        )
    }

    private func makeGift(
        id: String,
        giverID: String,
        recipientID: String,
        createdAt: Date = AppDate.today
    ) -> Gift {
        Gift(
            id: id,
            emoji: "🎁",
            name: id,
            direction: .received,
            giverID: giverID,
            recipientID: recipientID,
            paidByYou: false,
            occasion: "Just because",
            date: AppDate.today,
            value: 0,
            createdAt: createdAt
        )
    }
}

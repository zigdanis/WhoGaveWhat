struct RankedPerson: Identifiable, Equatable {
    let person: Person
    let value: Double
    let count: Int

    var id: String { person.id }
}

struct GiftInsights: Equatable {
    let received: [Gift]
    let given: [Gift]
    let paidByYou: [Gift]
    let circulatedValue: Double
    let topGivers: [RankedPerson]
    let topReceivers: [RankedPerson]

    var receivedValue: Double { received.totalValue }
    var givenValue: Double { given.totalValue }
}

struct BuildInsightsUseCase {
    /// Received and given gifts are relative to `selfPersonID`; without a viewpoint they are empty.
    func execute(gifts: [Gift], people: [Person], selfPersonID: String?) -> GiftInsights {
        let received = gifts.filter { $0.direction(relativeTo: selfPersonID) == .received }
        let given = gifts.filter { $0.direction(relativeTo: selfPersonID) == .given }
        return GiftInsights(
            received: received,
            given: given,
            paidByYou: gifts.filter(\.paidByYou),
            circulatedValue: gifts.totalValue,
            topGivers: ranking(direction: .received, gifts: gifts, people: people, selfPersonID: selfPersonID),
            topReceivers: ranking(direction: .given, gifts: gifts, people: people, selfPersonID: selfPersonID)
        )
    }

    private func ranking(
        direction: GiftDirection,
        gifts: [Gift],
        people: [Person],
        selfPersonID: String?
    ) -> [RankedPerson] {
        people
            .map { person in
                let matching = gifts.filter { gift in
                    guard gift.direction(relativeTo: selfPersonID) == direction else { return false }
                    return direction == .received
                        ? gift.giverID == person.id
                        : gift.recipientID == person.id
                }
                return RankedPerson(person: person, value: matching.totalValue, count: matching.count)
            }
            // RankedPerson.count is a numeric summary, not a collection.
            // swiftlint:disable:next empty_count
            .filter { $0.count > 0 }
            .sorted { $0.value > $1.value }
            .prefix(5)
            .map { $0 }
    }
}

extension Collection where Element == Gift {
    var totalValue: Double { reduce(0) { $0 + $1.value } }
}

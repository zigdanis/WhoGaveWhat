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
    let topGivers: [RankedPerson]
    let topReceivers: [RankedPerson]

    var receivedValue: Double { received.totalValue }
    var givenValue: Double { given.totalValue }
}

struct BuildInsightsUseCase {
    func execute(gifts: [Gift], people: [Person]) -> GiftInsights {
        let received = gifts.filter { $0.direction == .received }
        let given = gifts.filter { $0.direction == .given }
        return GiftInsights(
            received: received,
            given: given,
            paidByYou: gifts.filter(\.paidByYou),
            topGivers: ranking(direction: .received, gifts: gifts, people: people),
            topReceivers: ranking(direction: .given, gifts: gifts, people: people)
        )
    }

    private func ranking(direction: GiftDirection, gifts: [Gift], people: [Person]) -> [RankedPerson] {
        people
            .map { person in
                let matching = gifts.filter { gift in
                    guard gift.direction == direction else { return false }
                    return direction == .received
                        ? gift.giverID == person.id
                        : gift.recipientID == person.id
                }
                return RankedPerson(person: person, value: matching.totalValue, count: matching.count)
            }
            .filter { $0.count > 0 }
            .sorted { $0.value > $1.value }
            .prefix(5)
            .map { $0 }
    }
}

extension Collection where Element == Gift {
    var totalValue: Double { reduce(0) { $0 + $1.value } }
}

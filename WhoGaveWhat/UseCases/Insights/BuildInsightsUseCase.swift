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
        let received = gifts.filter { $0.flow == .received }
        let given = gifts.filter { $0.flow == .given }
        return GiftInsights(
            received: received,
            given: given,
            paidByYou: gifts.filter(\.paidByYou),
            topGivers: ranking(flow: .received, gifts: gifts, people: people),
            topReceivers: ranking(flow: .given, gifts: gifts, people: people)
        )
    }

    private func ranking(flow: GiftFlow, gifts: [Gift], people: [Person]) -> [RankedPerson] {
        people
            .map { person in
                let matching = gifts.filter { $0.personId == person.id && $0.flow == flow }
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

import Foundation

/// What the viewpoint person exchanged with one other person.
struct PersonBalance: Identifiable, Equatable {
    let person: Person
    /// Gifts the viewpoint person received from `person`.
    let receivedValue: Double
    let receivedCount: Int
    /// Gifts the viewpoint person gave to `person`.
    let givenValue: Double
    let givenCount: Int

    var id: String { person.id }
    /// Positive when the viewpoint person received more than they gave.
    var net: Double { receivedValue - givenValue }
    var isEven: Bool { net.rounded() == 0 }
}

/// Gifts exchanged between two people, in both directions.
struct PersonComparison: Equatable {
    let a: Person
    let b: Person
    let aToBValue: Double
    let aToBCount: Int
    let bToAValue: Double
    let bToACount: Int

    /// From A's side: positive when A received more from B than A gave to B.
    var net: Double { bToAValue - aToBValue }
    var isEven: Bool { net.rounded() == 0 }
}

/// Totals for one year. Received and given are relative to the viewpoint person
/// and stay at zero without one.
struct YearSummary: Equatable {
    let year: Int
    let circulatedValue: Double
    let giftCount: Int
    let receivedValue: Double
    let receivedCount: Int
    let givenValue: Double
    let givenCount: Int

    var net: Double { receivedValue - givenValue }
    var isEven: Bool { net.rounded() == 0 }
}

struct BuildInsightsUseCase {
    let calendar: Calendar

    init(calendar: Calendar = .current) {
        self.calendar = calendar
    }

    // MARK: Years

    /// Years that have at least one gift, newest first.
    func availableYears(gifts: [Gift]) -> [Int] {
        Set(gifts.map { calendar.component(.year, from: $0.date) }).sorted(by: >)
    }

    /// The selected year when the data still has it; otherwise the current year,
    /// or the latest year with gifts when the current year has none.
    func resolvedYear(selected: Int?, gifts: [Gift], now: Date = Date()) -> Int {
        let years = availableYears(gifts: gifts)
        if let selected, years.contains(selected) { return selected }
        let current = calendar.component(.year, from: now)
        if years.isEmpty || years.contains(current) { return current }
        return years[0]
    }

    /// Gifts dated in `year`, or all gifts when `year` is nil.
    func gifts(_ gifts: [Gift], in year: Int?) -> [Gift] {
        guard let year else { return gifts }
        return gifts.filter { calendar.component(.year, from: $0.date) == year }
    }

    // MARK: Totals

    func summary(gifts: [Gift], relativeTo selfPersonID: String?, year: Int) -> YearSummary {
        let yearGifts = self.gifts(gifts, in: year)
        let received = yearGifts.filter { $0.direction(relativeTo: selfPersonID) == .received }
        let given = yearGifts.filter { $0.direction(relativeTo: selfPersonID) == .given }
        return YearSummary(
            year: year,
            circulatedValue: yearGifts.totalValue,
            giftCount: yearGifts.count,
            receivedValue: received.totalValue,
            receivedCount: received.count,
            givenValue: given.totalValue,
            givenCount: given.count
        )
    }

    /// One entry per person the viewpoint person exchanged gifts with, largest
    /// absolute net first. People without a shared gift are left out.
    func balances(
        gifts: [Gift],
        people: [Person],
        relativeTo personID: String,
        year: Int?
    ) -> [PersonBalance] {
        let mine = self.gifts(gifts, in: year).filter { $0.direction(relativeTo: personID) != nil }
        return
            people
            .filter { $0.id != personID }
            .compactMap { person -> PersonBalance? in
                let received = mine.filter {
                    $0.direction(relativeTo: personID) == .received && $0.giverID == person.id
                }
                let given = mine.filter {
                    $0.direction(relativeTo: personID) == .given && $0.recipientID == person.id
                }
                guard !received.isEmpty || !given.isEmpty else { return nil }
                return PersonBalance(
                    person: person,
                    receivedValue: received.totalValue,
                    receivedCount: received.count,
                    givenValue: given.totalValue,
                    givenCount: given.count
                )
            }
            .sorted { lhs, rhs in
                if abs(lhs.net) != abs(rhs.net) { return abs(lhs.net) > abs(rhs.net) }
                return lhs.person.name.localizedStandardCompare(rhs.person.name) == .orderedAscending
            }
    }

    func comparison(gifts: [Gift], a: Person, b: Person, year: Int?) -> PersonComparison {
        let yearGifts = self.gifts(gifts, in: year)
        let aToB = yearGifts.filter { $0.direction(relativeTo: a.id) == .given && $0.recipientID == b.id }
        let bToA = yearGifts.filter { $0.direction(relativeTo: b.id) == .given && $0.recipientID == a.id }
        return PersonComparison(
            a: a,
            b: b,
            aToBValue: aToB.totalValue,
            aToBCount: aToB.count,
            bToAValue: bToA.totalValue,
            bToACount: bToA.count
        )
    }

    // MARK: Defaults

    /// The viewpoint person when set and present, otherwise the first person alphabetically.
    func focusPerson(people: [Person], selfPersonID: String?) -> Person? {
        if let selfPersonID, let me = people.first(where: { $0.id == selfPersonID }) { return me }
        return alphabetical(people).first
    }

    /// The counterpart with the largest absolute net for `person`, or the first
    /// other person alphabetically when they have no shared gifts that year.
    func defaultCounterpart(
        gifts: [Gift],
        people: [Person],
        for person: Person,
        year: Int?
    ) -> Person? {
        let top = balances(gifts: gifts, people: people, relativeTo: person.id, year: year).first
        return top?.person ?? alphabetical(people).first { $0.id != person.id }
    }

    func alphabetical(_ people: [Person]) -> [Person] {
        people.sorted { $0.name.localizedStandardCompare($1.name) == .orderedAscending }
    }
}

extension Collection where Element == Gift {
    var totalValue: Double { reduce(0) { $0 + $1.value } }
}

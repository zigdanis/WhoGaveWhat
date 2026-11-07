import Foundation

/// What the viewpoint person exchanged with one other person. Values are kept per currency.
struct PersonBalance: Identifiable, Equatable {
    let person: Person
    /// Gifts the viewpoint person received from `person`.
    let receivedValue: CurrencyAmounts
    let receivedCount: Int
    /// Gifts the viewpoint person gave to `person`.
    let givenValue: CurrencyAmounts
    let givenCount: Int

    var id: String { person.id }
    /// Per currency, positive when the viewpoint person received more than they gave.
    var net: CurrencyAmounts { receivedValue - givenValue }
    var isEven: Bool { net.isEven }
    /// Gift count balance, oriented like `net`: positive when the viewpoint person received
    /// more gifts from `person` than they gave them.
    var countNet: Int { receivedCount - givenCount }
    /// True when both gave the same number of gifts, whatever those gifts were worth.
    var isCountEven: Bool { countNet == 0 }
}

/// Gifts exchanged between two people, in both directions. Values are kept per currency.
struct PersonComparison: Equatable {
    let a: Person
    let b: Person
    let aToBValue: CurrencyAmounts
    let aToBCount: Int
    let bToAValue: CurrencyAmounts
    let bToACount: Int

    /// From A's side, per currency: positive when A received more from B than A gave to B.
    var net: CurrencyAmounts { bToAValue - aToBValue }
    var isEven: Bool { net.isEven }

    /// Both directions' values as plain numbers, for setting them against each other. Nil when the
    /// gifts are in more than one currency: amounts are never converted, so they cannot be compared.
    var comparableValues: (aToB: Double, bToA: Double)? {
        let currencies = Set(aToBValue.currencies + bToAValue.currencies)
        guard currencies.count <= 1 else { return nil }
        guard let currency = currencies.first else { return (0, 0) }
        return (aToBValue[currency], bToAValue[currency])
    }
}

/// Totals for one year, one per currency. Received and given are relative to the viewpoint person
/// and stay empty without one.
struct YearSummary: Equatable {
    let year: Int
    let circulatedValue: CurrencyAmounts
    let giftCount: Int
    let receivedValue: CurrencyAmounts
    let receivedCount: Int
    let givenValue: CurrencyAmounts
    let givenCount: Int

    var net: CurrencyAmounts { receivedValue - givenValue }
    var isEven: Bool { net.isEven }
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
            circulatedValue: yearGifts.totals,
            giftCount: yearGifts.count,
            receivedValue: received.totals,
            receivedCount: received.count,
            givenValue: given.totals,
            givenCount: given.count
        )
    }

    /// One entry per person the viewpoint person exchanged gifts with, largest absolute
    /// count balance first, then largest absolute money net (compared currency by currency, never
    /// converted), then by name. People without a shared gift are left out.
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
                    receivedValue: received.totals,
                    receivedCount: received.count,
                    givenValue: given.totals,
                    givenCount: given.count
                )
            }
            .sorted { lhs, rhs in
                if abs(lhs.countNet) != abs(rhs.countNet) { return abs(lhs.countNet) > abs(rhs.countNet) }
                if let larger = CurrencyAmounts.largerMagnitude(lhs.net, rhs.net) { return larger }
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
            aToBValue: aToB.totals,
            aToBCount: aToB.count,
            bToAValue: bToA.totals,
            bToACount: bToA.count
        )
    }

    // MARK: Defaults

    /// The viewpoint person when set and present, otherwise the first person alphabetically.
    func focusPerson(people: [Person], selfPersonID: String?) -> Person? {
        if let selfPersonID, let me = people.first(where: { $0.id == selfPersonID }) { return me }
        return alphabetical(people).first
    }

    /// The counterpart with the largest balance for `person` (see `balances`), or the first
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

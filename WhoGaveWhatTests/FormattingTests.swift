import Foundation
import Testing
@testable import WhoGaveWhat

/// Name + date formatting helpers. Dates are built with `Calendar.current` so
/// they round-trip deterministically regardless of the runner's time zone.
@MainActor
struct FormattingTests {

    @Test func initialsTakeFirstTwoWords() {
        let store = makeSeededStore()
        #expect(store.initials("Aunt Maria") == "AM")
        #expect(store.initials("Igor") == "I")
        #expect(store.initials("") == "")
    }

    @Test func firstReturnsLastWord() {
        let store = makeSeededStore()
        #expect(store.first("Grandpa Pavel") == "Pavel")
        #expect(store.first("Igor") == "Igor")
    }

    @Test func monthLabelDropsTheCurrentYear() {
        let store = makeSeededStore()
        let en = Locale(identifier: "en_US")
        let cal = Calendar.current
        let june2026 = cal.date(from: DateComponents(year: 2026, month: 6, day: 14))!
        #expect(store.monthLabel(june2026, locale: en) == "June")
        let dec2025 = cal.date(from: DateComponents(year: 2025, month: 12, day: 25))!
        #expect(store.monthLabel(dec2025, locale: en) == "December 2025")
    }

    @Test func shortDateFormatsMonthAndDay() {
        let store = makeSeededStore()
        let cal = Calendar.current
        let d = cal.date(from: DateComponents(year: 2026, month: 6, day: 14))!
        #expect(store.shortDate(d, locale: Locale(identifier: "en_US")) == "Jun 14")
    }

    @Test func frozenTodayIsJune14th2026() {
        let f = DateFormatter()
        f.calendar = Calendar(identifier: .gregorian)
        f.timeZone = TimeZone(identifier: "UTC")
        f.dateFormat = "yyyy-MM-dd"
        #expect(f.string(from: AppStore.today) == "2026-06-14")
    }
}

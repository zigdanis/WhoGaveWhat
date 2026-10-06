import Foundation
import Testing

@testable import WhoGaveWhat

struct FormattingTests {
    @Test func initialsTakeFirstTwoWords() {
        #expect("Aunt Maria".initials == "AM")
        #expect("Igor".initials == "I")
        #expect("".initials == "")
    }

    @Test func lastWordReturnsLastWord() {
        #expect("Grandpa Pavel".lastWord == "Pavel")
        #expect("Igor".lastWord == "Igor")
    }

    @Test func monthLabelDropsTheCurrentYear() {
        let en = Locale(identifier: "en_US")
        let cal = Calendar.current
        let june2026 = cal.date(from: DateComponents(year: 2026, month: 6, day: 14))!
        #expect(june2026.giftMonthLabel(locale: en) == "June")
        let dec2025 = cal.date(from: DateComponents(year: 2025, month: 12, day: 25))!
        #expect(dec2025.giftMonthLabel(locale: en) == "December 2025")
    }

    @Test func shortDateFormatsMonthAndDay() {
        let date = Calendar.current.date(from: DateComponents(year: 2026, month: 6, day: 14))!
        #expect(date.giftShortLabel(locale: Locale(identifier: "en_US")) == "Jun 14")
    }

    @Test func frozenTodayIsJune14th2026() {
        let formatter = DateFormatter()
        formatter.calendar = Calendar(identifier: .gregorian)
        formatter.timeZone = TimeZone(identifier: "UTC")
        formatter.dateFormat = "yyyy-MM-dd"
        #expect(formatter.string(from: AppDate.today) == "2026-06-14")
    }

    @Test func currencyFormattingUsesTheSelectedCodeAndLocale() {
        let locale = Locale(identifier: "en_US")

        #expect(formattedCurrency(1_234, code: "USD", locale: locale) == "$1,234")
        #expect(currencySymbol(code: "EUR", locale: locale) == "€")
    }
}

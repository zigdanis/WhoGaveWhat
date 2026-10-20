import Foundation
import Testing

@testable import WhoGaveWhat

struct FormattingTests {
    @Test func initialsTakeFirstTwoWords() {
        #expect("Aunt Maria".initials == "AM")
        #expect("Igor".initials == "I")
        #expect("".initials.isEmpty)
    }

    @Test func lastWordReturnsLastWord() {
        #expect("Grandpa Pavel".lastWord == "Pavel")
        #expect("Igor".lastWord == "Igor")
    }

    @Test func monthLabelDropsTheCurrentYear() {
        let en = Locale(identifier: "en_US")
        let cal = Calendar.current
        let june2026 = cal.date(from: DateComponents(year: 2026, month: 6, day: 14))!
        #expect(june2026.giftMonthLabel(displayYear: 2026, locale: en) == "June")
        let dec2025 = cal.date(from: DateComponents(year: 2025, month: 12, day: 25))!
        #expect(dec2025.giftMonthLabel(locale: en) == "December 2025")
    }

    @Test func shortDateFormatsMonthAndDay() {
        let date = Calendar.current.date(from: DateComponents(year: 2026, month: 6, day: 14))!
        #expect(date.giftShortLabel(displayYear: 2026, locale: Locale(identifier: "en_US")) == "Jun 14")
    }

    @Test func todayAndYesterdayFollowTheCurrentLocalCalendarDay() {
        let calendar = Calendar.autoupdatingCurrent
        #expect(calendar.isDate(AppDate.today, inSameDayAs: Date()))
        #expect(calendar.isDate(AppDate.yesterday, inSameDayAs: calendar.date(byAdding: .day, value: -1, to: Date())!))
        #expect(Date().giftInputLabel() == "Today")
    }

    @Test func currencyFormattingUsesTheSelectedCodeAndLocale() {
        let locale = Locale(identifier: "en_US")

        #expect(formattedCurrency(1_234, code: "USD", locale: locale) == "$1,234")
        #expect(currencySymbol(code: "EUR", locale: locale) == "€")
    }

    @Test func signedCurrencyShowsThePlusAndTypographicMinus() {
        let locale = Locale(identifier: "en_US")

        #expect(formattedSignedCurrency(40, code: "USD", locale: locale) == "+$40")
        #expect(formattedSignedCurrency(-40, code: "USD", locale: locale) == "\u{2212}$40")
        #expect(formattedSignedCurrency(0, code: "USD", locale: locale) == "$0")
        #expect(formattedSignedCurrency(0.4, code: "USD", locale: locale) == "$0")
    }

    @Test func signedCountShowsThePlusAndTypographicMinus() {
        #expect(formattedSignedCount(2) == "+2")
        #expect(formattedSignedCount(-3) == "\u{2212}3")
        #expect(formattedSignedCount(0) == "0")
    }
}

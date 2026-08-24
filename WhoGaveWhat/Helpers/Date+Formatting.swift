import Foundation

enum AppDate {
    /// Frozen prototype date retained to preserve the current product behavior.
    static let today = makeISODate("2026-06-14")
    static let yesterday = makeISODate("2026-06-13")

    private static func makeISODate(_ value: String) -> Date {
        let formatter = DateFormatter()
        formatter.calendar = Calendar(identifier: .gregorian)
        formatter.timeZone = TimeZone(identifier: "UTC")
        formatter.dateFormat = "yyyy-MM-dd"
        return formatter.date(from: value) ?? Date()
    }
}

extension Date {
    func giftMonthLabel(displayYear: Int = 2026, locale: Locale = .current) -> String {
        let year = Calendar.current.component(.year, from: self)
        let style = year == displayYear
            ? Date.FormatStyle.dateTime.month(.wide)
            : Date.FormatStyle.dateTime.month(.wide).year()
        return formatted(style.locale(locale))
    }

    func giftShortLabel(displayYear: Int = 2026, locale: Locale = .current) -> String {
        let year = Calendar.current.component(.year, from: self)
        let style = year == displayYear
            ? Date.FormatStyle.dateTime.month(.abbreviated).day()
            : Date.FormatStyle.dateTime.month(.abbreviated).day().year()
        return formatted(style.locale(locale))
    }

    func giftInputLabel(locale: Locale = .current) -> String {
        let calendar = Calendar.current
        if calendar.isDate(self, inSameDayAs: AppDate.today) {
            return String(localized: "Today")
        }
        if calendar.isDate(self, inSameDayAs: AppDate.yesterday) {
            return String(localized: "Yesterday")
        }
        return giftShortLabel(locale: locale)
    }
}

import Foundation

enum AppDate {
    /// The current day in the user's calendar and time zone, normalized to midnight.
    static var today: Date { Calendar.autoupdatingCurrent.startOfDay(for: Date()) }

    static var yesterday: Date {
        Calendar.autoupdatingCurrent.date(byAdding: .day, value: -1, to: today) ?? today
    }
}

extension Date {
    func giftMonthLabel(displayYear: Int? = nil, locale: Locale = .current) -> String {
        let year = Calendar.current.component(.year, from: self)
        let displayYear = displayYear ?? Calendar.current.component(.year, from: Date())
        let style =
            year == displayYear
            ? Date.FormatStyle.dateTime.month(.wide)
            : Date.FormatStyle.dateTime.month(.wide).year()
        return formatted(style.locale(locale))
    }

    func giftShortLabel(displayYear: Int? = nil, locale: Locale = .current) -> String {
        let year = Calendar.current.component(.year, from: self)
        let displayYear = displayYear ?? Calendar.current.component(.year, from: Date())
        let style =
            year == displayYear
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

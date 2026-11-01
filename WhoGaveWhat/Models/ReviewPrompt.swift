import Foundation

/// What the app remembers between launches to time the App Store rating request.
struct ReviewPromptState: Codable, Equatable {
    /// Distinct calendar days the app was in the foreground, the first one included.
    var activeDays = 0
    /// The last of those days as `yyyy-MM-dd` in the user's calendar.
    var lastActiveDay: String?
    var firstActiveDate: Date?
    /// App-initiated requests, oldest first; recording a new one drops those older than 365 days.
    var requestDates: [Date] = []
    /// Every app-initiated request ever made.
    var requestCount = 0
    var lastRequestVersion: String?
    /// New gifts and active days since the last request, so asking again needs fresh use.
    var giftsCreatedSinceRequest = 0
    var activeDaysSinceRequest = 0
}

/// When to ask for an App Store rating.
///
/// The system sheet is the only prompt (App Review Guideline 5.6.1 forbids custom ones and
/// filtering by sentiment), so the odds of a good rating come from the moment: someone who has
/// come back on a third separate day and has just saved a new gift, with no failure or deletion
/// in the session. Apple shows the sheet at most three times a year and never in TestFlight;
/// this policy asks less often: once per app version, at least 120 days apart, and again only
/// after a few new gifts on new days.
struct ReviewPromptPolicy: Equatable {
    var minimumActiveDays = 3
    var minimumGifts = 5
    var minimumPeople = 2
    var cooldownDays = 120
    var maximumRequestsPerYear = 3
    var newGiftsBeforeAskingAgain = 3
    var newActiveDaysBeforeAskingAgain = 2

    private static let secondsPerDay: TimeInterval = 86_400

    static func dayKey(for date: Date, calendar: Calendar) -> String {
        let components = calendar.dateComponents([.year, .month, .day], from: date)
        return String(format: "%04d-%02d-%02d", components.year ?? 0, components.month ?? 0, components.day ?? 0)
    }

    /// Counts the day of `now` once, however many times the app comes to the foreground that day.
    func recordingActiveDay(_ state: ReviewPromptState, now: Date, calendar: Calendar) -> ReviewPromptState {
        let day = Self.dayKey(for: now, calendar: calendar)
        guard state.lastActiveDay != day else { return state }
        var next = state
        next.lastActiveDay = day
        next.activeDays += 1
        next.activeDaysSinceRequest += 1
        if next.firstActiveDate == nil { next.firstActiveDate = now }
        return next
    }

    func recordingNewGift(_ state: ReviewPromptState) -> ReviewPromptState {
        var next = state
        next.giftsCreatedSinceRequest += 1
        return next
    }

    /// Whether a new gift saved now, with these totals, is the moment to ask.
    func shouldRequest(
        _ state: ReviewPromptState, now: Date, version: String, giftsCount: Int, peopleCount: Int
    ) -> Bool {
        guard state.activeDays >= minimumActiveDays, giftsCount >= minimumGifts, peopleCount >= minimumPeople
        else { return false }
        guard let lastRequest = state.requestDates.last else { return true }
        guard state.lastRequestVersion != version,
            now.timeIntervalSince(lastRequest) >= Double(cooldownDays) * Self.secondsPerDay,
            requestsInLastYear(state, now: now) < maximumRequestsPerYear
        else { return false }
        return state.giftsCreatedSinceRequest >= newGiftsBeforeAskingAgain
            && state.activeDaysSinceRequest >= newActiveDaysBeforeAskingAgain
    }

    func recordingRequest(_ state: ReviewPromptState, now: Date, version: String) -> ReviewPromptState {
        var next = state
        let yearAgo = now.addingTimeInterval(-365 * Self.secondsPerDay)
        next.requestDates = state.requestDates.filter { $0 > yearAgo } + [now]
        next.requestCount += 1
        next.lastRequestVersion = version
        next.giftsCreatedSinceRequest = 0
        next.activeDaysSinceRequest = 0
        return next
    }

    /// Whole days from the first active day to `now`, for analytics.
    func daysSinceFirstActive(_ state: ReviewPromptState, now: Date, calendar: Calendar) -> Int {
        guard let first = state.firstActiveDate else { return 0 }
        let days = calendar.dateComponents(
            [.day], from: calendar.startOfDay(for: first), to: calendar.startOfDay(for: now)
        ).day
        return max(days ?? 0, 0)
    }

    private func requestsInLastYear(_ state: ReviewPromptState, now: Date) -> Int {
        let yearAgo = now.addingTimeInterval(-365 * Self.secondsPerDay)
        return state.requestDates.filter { $0 > yearAgo }.count
    }
}

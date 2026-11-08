import Foundation
import Observation

enum AppTab: String, Equatable {
    case home
    case people
    case insights
    case settings
}

enum GiftSheetRoute: Identifiable, Equatable {
    case create
    /// A new gift from a person's screen: the sheet starts with that person already in it.
    case createWithPerson(personID: String)
    case edit(giftID: String)

    var id: String {
        switch self {
        case .create: "create"
        case .createWithPerson(let personID): "create-with-\(personID)"
        case .edit(let giftID): "edit-\(giftID)"
        }
    }

    /// The person a new gift starts with, if it was opened from their screen.
    var prefilledPersonID: String? {
        if case .createWithPerson(let personID) = self { return personID }
        return nil
    }

    var editingGiftID: String? {
        if case .edit(let giftID) = self { return giftID }
        return nil
    }

    var mode: GiftSheetMode {
        editingGiftID == nil ? .create : .edit
    }
}

@MainActor
@Observable
final class AppRouter {
    var tab: AppTab = .home
    var giftSheet: GiftSheetRoute?
    private let analytics: AnalyticsGateway

    init(
        launchEnvironment: [String: String] = ProcessInfo.processInfo.environment,
        analytics: AnalyticsGateway = NoopAnalyticsGateway()
    ) {
        self.analytics = analytics
        if let rawTab = launchEnvironment["KS_TAB"], let tab = AppTab(rawValue: rawTab) {
            self.tab = tab
        }
        if launchEnvironment["KS_SHEET"] != nil {
            giftSheet = .create
        }
    }

    /// A tap on the tab bar. Programmatic switches set `tab` directly so they are not counted.
    func selectTab(_ tab: AppTab) {
        guard self.tab != tab else { return }
        self.tab = tab
        analytics.track(.tabSelected(tab: tab.rawValue))
    }

    /// Opens a new gift; from a person's screen `personID` puts that person in the sheet up front.
    func presentNewGift(from source: GiftSheetSource, personID: String? = nil) {
        giftSheet = personID.map { .createWithPerson(personID: $0) } ?? .create
        analytics.track(.giftSheetOpened(mode: .create, source: source))
    }

    func presentEditGift(id: String) {
        giftSheet = .edit(giftID: id)
        analytics.track(.giftSheetOpened(mode: .edit, source: .giftDetail))
    }

    /// Closes the gift sheet; a swipe-down or Cancel counts as `cancelled`.
    func dismissGiftSheet(outcome: GiftSheetOutcome = .cancelled) {
        guard let route = giftSheet else { return }
        giftSheet = nil
        analytics.track(.giftSheetClosed(mode: route.mode, outcome: outcome))
    }
}

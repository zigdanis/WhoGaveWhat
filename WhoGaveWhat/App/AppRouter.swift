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
    case edit(giftID: String)

    var id: String {
        switch self {
        case .create: "create"
        case .edit(let giftID): "edit-\(giftID)"
        }
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

    func presentNewGift(from source: GiftSheetSource) {
        giftSheet = .create
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

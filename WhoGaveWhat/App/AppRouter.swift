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
}

@MainActor
@Observable
final class AppRouter {
    var tab: AppTab = .home
    var giftSheet: GiftSheetRoute?

    init(launchEnvironment: [String: String] = ProcessInfo.processInfo.environment) {
        if let rawTab = launchEnvironment["KS_TAB"], let tab = AppTab(rawValue: rawTab) {
            self.tab = tab
        }
        if launchEnvironment["KS_SHEET"] != nil {
            giftSheet = .create
        }
    }

    func selectTab(_ tab: AppTab) { self.tab = tab }
    func presentNewGift() { giftSheet = .create }
    func presentEditGift(id: String) { giftSheet = .edit(giftID: id) }
    func dismissGiftSheet() { giftSheet = nil }
}

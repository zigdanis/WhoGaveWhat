import Foundation
import Observation

enum AppScreen: Equatable {
    case onboarding
    case signIn
    case main
}

enum AppTab: String, Equatable {
    case home
    case people
    case insights
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
    var screen: AppScreen
    var tab: AppTab = .home
    var giftSheet: GiftSheetRoute?
    var showsSettings = false

    init(
        didCompleteOnboarding: Bool,
        launchEnvironment: [String: String] = ProcessInfo.processInfo.environment
    ) {
        screen = didCompleteOnboarding ? .main : .onboarding

        if let start = launchEnvironment["KS_START"] {
            switch start {
            case "app": screen = .main
            case "signin": screen = .signIn
            default: break
            }
        }
        if let rawTab = launchEnvironment["KS_TAB"], let tab = AppTab(rawValue: rawTab) {
            self.tab = tab
        }
        if launchEnvironment["KS_SHEET"] != nil {
            giftSheet = .create
        }
    }

    func showSignIn() { screen = .signIn }
    func showMainApp() { screen = .main }
    func selectTab(_ tab: AppTab) { self.tab = tab }
    func presentNewGift() { giftSheet = .create }
    func presentEditGift(id: String) { giftSheet = .edit(giftID: id) }
    func dismissGiftSheet() { giftSheet = nil }
    func presentSettings() { showsSettings = true }
    func dismissSettings() { showsSettings = false }
}

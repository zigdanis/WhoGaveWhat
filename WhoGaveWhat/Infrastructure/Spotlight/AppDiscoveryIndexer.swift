import CoreSpotlight
import Foundation
import OSLog
import UniformTypeIdentifiers

@MainActor
final class AppDiscoveryIndexer {
    static let indexName = "AppDiscovery"
    static let itemIdentifier = "pro.ziganshin.WhoGaveWhat.launch"
    static let domainIdentifier = "pro.ziganshin.WhoGaveWhat.app-discovery"

    private static let aliases = [
        "Who Gave", "Who Gave What", "WhoGaveWhat", "кто че", "кто чё"
    ]
    private static let logger = Logger(
        subsystem: "pro.ziganshin.WhoGaveWhat", category: "AppDiscovery"
    )

    private let indexItems: @MainActor ([CSSearchableItem]) async throws -> Void
    private var isIndexing = false

    convenience init() {
        let index = CSSearchableIndex(name: Self.indexName)
        self.init { items in
            try await index.indexSearchableItems(items)
        }
    }

    init(indexItems: @escaping @MainActor ([CSSearchableItem]) async throws -> Void) {
        self.indexItems = indexItems
    }

    func refresh() async {
        // Multiple active scenes can request the same launcher update concurrently.
        guard !isIndexing else { return }
        isIndexing = true
        defer { isIndexing = false }

        let title = Bundle.main.object(forInfoDictionaryKey: "CFBundleDisplayName") as? String ?? "Who Gave"
        let isAvailable = CSSearchableIndex.isIndexingAvailable()
        Self.logger.notice("Refreshing app launcher: indexingAvailable=\(isAvailable), title=\(title, privacy: .public)")
        do {
            try await indexItems([Self.makeItem(title: title)])
            Self.logger.notice("App launcher index update completed: title=\(title, privacy: .public)")
        } catch {
            Self.logger.error("Unable to index app launcher: \(error.localizedDescription, privacy: .public)")
        }
    }

    static func makeItem(title: String) -> CSSearchableItem {
        let attributes = CSSearchableItemAttributeSet(contentType: .content)
        attributes.title = title
        attributes.displayName = title
        attributes.alternateNames = aliases
        attributes.keywords = aliases + ["who", "gave", "what", "кто", "че", "чё"]

        let item = CSSearchableItem(
            uniqueIdentifier: itemIdentifier,
            domainIdentifier: domainIdentifier,
            attributeSet: attributes
        )
        item.expirationDate = .distantFuture
        return item
    }

    static func recognizes(_ activity: NSUserActivity) -> Bool {
        activity.activityType == CSSearchableItemActionType
            && activity.userInfo?[CSSearchableItemActivityIdentifier] as? String == itemIdentifier
    }
}

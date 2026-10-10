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
            #if DEBUG
                if ProcessInfo.processInfo.environment["KS_SPOTLIGHT_DIAGNOSTICS"] == "1" {
                    Task { await Self.observeIndexedLauncher() }
                }
            #endif
        }
    }

    init(indexItems: @escaping @MainActor ([CSSearchableItem]) async throws -> Void) {
        self.indexItems = indexItems
    }

    #if DEBUG
        private static func observeIndexedLauncher() async {
            let context = CSSearchQueryContext()
            context.fetchAttributes = ["title", "displayName"]
            let query = CSSearchQuery(
                queryString: "title == 'Who Gave'c || title == 'кто че'c",
                queryContext: context
            )
            logger.notice("Launcher index read-back started")
            let cancellation = Task {
                do {
                    try await Task.sleep(nanoseconds: 10_000_000_000)
                } catch {
                    return
                }
                logger.notice("Launcher index read-back timed out after 10 seconds")
                query.cancel()
            }
            defer { cancellation.cancel() }
            var launcherCount = 0
            do {
                for try await result in query.results {
                    let item = result.item
                    guard item.uniqueIdentifier == itemIdentifier else { continue }
                    launcherCount += 1
                    let title = item.attributeSet.title ?? ""
                    logger.notice("Launcher index read-back found: identifier=\(itemIdentifier, privacy: .public), title=\(title, privacy: .public)")
                }
                logger.notice("Launcher index read-back completed: count=\(launcherCount)")
            } catch {
                logger.error("Launcher index read-back failed: \(error.localizedDescription, privacy: .public)")
            }
        }
    #endif

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

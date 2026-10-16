import Foundation

/// Best-effort, opt-in icon inference. The gift name is the only request-body field.
@MainActor
final class CloudGiftIconGateway: GiftIntelligenceGateway {
    nonisolated static let endpoint = URL(string: "https://whogavewhat-icons.zigdanis.workers.dev")!
    typealias Transport = @MainActor (URLRequest) async throws -> (Data, URLResponse)

    private struct IconResponse: Decodable {
        let emoji: String?
    }

    private struct CacheEntry {
        let result: GiftIntelligenceResult?
    }

    private let preferences: PreferencesGateway
    private let baseURL: URL
    private let transport: Transport
    private let now: @MainActor () -> Date
    private var backoffUntil = Date.distantPast
    private var cache: [String: CacheEntry] = [:]
    private var cacheOrder: [String] = []
    private var cacheInstallID: String?

    init(
        preferences: PreferencesGateway,
        endpoint: URL = CloudGiftIconGateway.endpoint,
        now: @escaping @MainActor () -> Date = { Date() },
        transport: Transport? = nil
    ) {
        self.preferences = preferences
        baseURL = endpoint
        self.now = now
        if let transport {
            self.transport = transport
        } else {
            let configuration = URLSessionConfiguration.ephemeral
            configuration.timeoutIntervalForRequest = 8
            configuration.timeoutIntervalForResource = 8
            configuration.httpCookieStorage = nil
            configuration.httpShouldSetCookies = false
            configuration.urlCache = nil
            configuration.requestCachePolicy = .reloadIgnoringLocalCacheData
            let session = URLSession(configuration: configuration)
            self.transport = { request in try await session.data(for: request) }
        }
    }

    var isAvailable: Bool { preferences.cloudIconConsent == .allowed }
    func prewarm() {}

    static func normalizedName(_ name: String) -> String {
        String(name.split(whereSeparator: \.isWhitespace).joined(separator: " ").prefix(80))
            .trimmingCharacters(in: .whitespacesAndNewlines)
    }

    func suggestGift(named name: String) async -> GiftIntelligenceResult? {
        let normalized = Self.normalizedName(name)
        guard isAvailable, !Task.isCancelled, normalized.count >= 2 else { return nil }
        let installID = preferences.installID
        if cacheInstallID != installID {
            cache.removeAll()
            cacheOrder.removeAll()
            cacheInstallID = installID
        }
        if let entry = cache[normalized] { return entry.result }
        guard now() >= backoffUntil else { return nil }

        var request = URLRequest(url: baseURL.appendingPathComponent("v1/gift-icon"), timeoutInterval: 8)
        request.httpMethod = "POST"
        request.setValue("application/json", forHTTPHeaderField: "Content-Type")
        request.setValue(installID, forHTTPHeaderField: "X-Install-ID")
        request.httpBody = try? JSONEncoder().encode(["name": normalized])

        do {
            let (data, response) = try await transport(request)
            // A revoked consent or a cancelled edit must not publish or cache a late answer.
            guard !Task.isCancelled, isAvailable, preferences.installID == installID,
                let response = response as? HTTPURLResponse
            else { return nil }
            if response.statusCode == 429 {
                let retryAfter = response.value(forHTTPHeaderField: "Retry-After").flatMap(Double.init) ?? 60
                backoffUntil = now().addingTimeInterval(max(60, retryAfter))
                return nil
            }
            if response.statusCode == 503 {
                backoffUntil = now().addingTimeInterval(600)
                return nil
            }
            guard response.statusCode == 200 else { return nil }
            let decoded = try JSONDecoder().decode(IconResponse.self, from: data)
            // The server applies the confidence threshold and returns no emoji below it.
            let result = decoded.emoji.flatMap(GiftEmoji.validated)
                .map { GiftIntelligenceResult(emoji: $0, value: 0) }
            cache[normalized] = CacheEntry(result: result)
            cacheOrder.append(normalized)
            if cacheOrder.count > 100 {
                cache.removeValue(forKey: cacheOrder.removeFirst())
            }
            return result
        } catch {
            return nil
        }
    }
}

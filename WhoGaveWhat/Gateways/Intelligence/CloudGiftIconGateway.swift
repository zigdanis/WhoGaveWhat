import Foundation

/// Best-effort, opt-in icon and price inference. The request body is the gift name and the currency.
@MainActor
final class CloudGiftIconGateway: GiftIntelligenceGateway {
    nonisolated static let endpoint = URL(string: "https://whogavewhat-icons.zigdanis.workers.dev")!
    typealias Transport = @MainActor (URLRequest) async throws -> (Data, URLResponse)

    private struct IconResponse: Decodable {
        let emoji: String?
        let price: Double?

        enum CodingKeys: String, CodingKey { case emoji, price }

        init(from decoder: Decoder) throws {
            let container = try decoder.container(keyedBy: CodingKeys.self)
            emoji = try container.decodeIfPresent(String.self, forKey: .emoji)
            // A malformed price must not discard a good icon.
            price = try? container.decodeIfPresent(Double.self, forKey: .price)
        }
    }

    /// The largest amount the app accepts as an estimate; the server never returns more.
    private static let maximumPrice = 10_000_000.0

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

    func suggestGift(named name: String, currency: SupportedCurrency) async -> GiftIntelligenceResult? {
        let normalized = Self.normalizedName(name)
        guard isAvailable, !Task.isCancelled, normalized.count >= 2 else { return nil }
        let installID = preferences.installID
        if cacheInstallID != installID {
            cache.removeAll()
            cacheOrder.removeAll()
            cacheInstallID = installID
        }
        // The estimate is in the requested currency, so each currency has its own entry.
        let cacheKey = "\(currency.code)\n\(normalized)"
        if let entry = cache[cacheKey] { return entry.result }
        guard now() >= backoffUntil else { return nil }

        var request = URLRequest(url: baseURL.appendingPathComponent("v1/gift-icon"), timeoutInterval: 8)
        request.httpMethod = "POST"
        request.setValue("application/json", forHTTPHeaderField: "Content-Type")
        request.setValue(installID, forHTTPHeaderField: "X-Install-ID")
        request.httpBody = try? JSONEncoder().encode(["name": normalized, "currency": currency.code])

        do {
            let (data, response) = try await transport(request)
            // A revoked consent or a cancelled edit must not publish or cache a late answer.
            guard !Task.isCancelled, isAvailable, preferences.installID == installID,
                let response = response as? HTTPURLResponse
            else { return nil }
            if response.statusCode == 429 || response.statusCode == 503 {
                // The server says how long to wait: briefly after a provider hiccup, until tomorrow
                // for a spent budget. A rate limit is never retried sooner than a minute.
                let retryAfter = response.value(forHTTPHeaderField: "Retry-After").flatMap(Double.init) ?? 60
                let minimum: TimeInterval = response.statusCode == 429 ? 60 : 15
                backoffUntil = now().addingTimeInterval(min(max(minimum, retryAfter), 86_400))
                return nil
            }
            guard response.statusCode == 200 else { return nil }
            let decoded = try JSONDecoder().decode(IconResponse.self, from: data)
            // The server applies the confidence thresholds and returns no emoji or price below them.
            // The price is not snapped: for money it can be an amount written in the name.
            let emoji = decoded.emoji.flatMap(GiftEmoji.validated)
            let value = decoded.price.flatMap(Self.validatedPrice)
            let result = emoji == nil && value == nil ? nil : GiftIntelligenceResult(emoji: emoji, value: value)
            cache[cacheKey] = CacheEntry(result: result)
            cacheOrder.append(cacheKey)
            if cacheOrder.count > 100 {
                cache.removeValue(forKey: cacheOrder.removeFirst())
            }
            return result
        } catch {
            return nil
        }
    }

    private static func validatedPrice(_ price: Double) -> Int? {
        guard price.isFinite, price > 0, price <= maximumPrice else { return nil }
        let rounded = Int(price.rounded())
        return rounded > 0 ? rounded : nil
    }
}

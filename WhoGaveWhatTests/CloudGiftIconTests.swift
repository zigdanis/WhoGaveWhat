import Foundation
import Testing

@testable import WhoGaveWhat

@MainActor
private final class IconTransportStub {
    var body = #"{"emoji":"🎸","confidence":0.93}"#
    var status = 200
    var headers: [String: String] = [:]
    var error: Error?
    var holdsRequests = false
    private(set) var requests: [URLRequest] = []
    private var pending: CheckedContinuation<Void, Never>?

    func send(_ request: URLRequest) async throws -> (Data, URLResponse) {
        requests.append(request)
        if holdsRequests {
            await withCheckedContinuation { pending = $0 }
        }
        if let error { throw error }
        let response = HTTPURLResponse(url: CloudGiftIconGateway.endpoint, statusCode: status, httpVersion: nil, headerFields: headers)!
        return (Data(body.utf8), response)
    }

    func releaseRequest() {
        pending?.resume()
        pending = nil
    }

    func waitForRequest() async {
        for _ in 0..<500 where requests.isEmpty {
            try? await Task.sleep(for: .milliseconds(10))
        }
    }
}

@MainActor
struct CloudGiftIconTests {
    private func makeGateway(
        transport: IconTransportStub,
        preferences: TestPreferencesGateway? = nil,
        now: @escaping @MainActor () -> Date = { Date() }
    ) -> CloudGiftIconGateway {
        let preferences = preferences ?? TestPreferencesGateway()
        preferences.setCloudIconConsent(.allowed)
        return CloudGiftIconGateway(preferences: preferences, now: now, transport: { try await transport.send($0) })
    }

    @Test func sendsOnlyNormalizedNameCurrencyAndInstallHeader() async throws {
        let transport = IconTransportStub()
        let preferences = TestPreferencesGateway()
        let gateway = makeGateway(transport: transport, preferences: preferences)

        let result = await gateway.suggestGift(named: " \n guitar\t  amp \r\n", currency: .usd)

        #expect(result == GiftIntelligenceResult(emoji: "🎸", value: nil))
        let request = try #require(transport.requests.first)
        #expect(request.httpMethod == "POST")
        #expect(request.url?.absoluteString == "https://whogavewhat-icons.zigdanis.workers.dev/v1/gift-icon")
        #expect(request.value(forHTTPHeaderField: "Content-Type") == "application/json")
        #expect(request.value(forHTTPHeaderField: "X-Install-ID") == preferences.installID)
        #expect(UUID(uuidString: preferences.installID) != nil)
        #expect(request.timeoutInterval == 8)
        let body = try JSONDecoder().decode([String: String].self, from: #require(request.httpBody))
        #expect(body == ["name": "guitar amp", "currency": "USD"])
    }

    @Test func sendsTheRequestedCurrencyAndMapsTheWholePrice() async throws {
        let transport = IconTransportStub()
        transport.body = #"{"emoji":"🎸","confidence":0.93,"price":10000,"priceConfidence":0.4}"#
        let gateway = makeGateway(transport: transport)

        let result = await gateway.suggestGift(named: "guitar", currency: .rub)

        #expect(result == GiftIntelligenceResult(emoji: "🎸", value: 10_000))
        let request = try #require(transport.requests.first)
        let body = try JSONDecoder().decode([String: String].self, from: #require(request.httpBody))
        #expect(body == ["name": "guitar", "currency": "RUB"])
    }

    @Test func keepsAnExplicitAmountInsteadOfSnappingIt() async {
        let transport = IconTransportStub()
        transport.body = #"{"emoji":"💸","confidence":0.9,"price":5123,"priceConfidence":0.1}"#
        let gateway = makeGateway(transport: transport)

        #expect(await gateway.suggestGift(named: "деньги 5123", currency: .rub)?.value == 5_123)
    }

    @Test func priceAloneIsEnoughAndFractionsRound() async {
        let transport = IconTransportStub()
        transport.body = #"{"emoji":null,"confidence":0.2,"price":1499.6,"priceConfidence":0.5}"#
        let gateway = makeGateway(transport: transport)

        #expect(await gateway.suggestGift(named: "guitar", currency: .usd) == GiftIntelligenceResult(emoji: nil, value: 1_500))
    }

    @Test(arguments: ["null", "0", "-5", "0.4", "10000001", #""cheap""#, "1e400"])
    func unusablePricesAreDropped(_ price: String) async {
        let transport = IconTransportStub()
        transport.body = #"{"emoji":"🎸","confidence":0.9,"price":"# + price + "}"
        let gateway = makeGateway(transport: transport)

        // A bad price never discards a good icon.
        #expect(await gateway.suggestGift(named: "guitar", currency: .usd) == GiftIntelligenceResult(emoji: "🎸", value: nil))
        transport.body = #"{"emoji":null,"confidence":0.2,"price":"# + price + "}"
        #expect(await gateway.suggestGift(named: "guitar two", currency: .usd) == nil)
    }

    @Test func cacheSeparatesCurrencies() async {
        let transport = IconTransportStub()
        transport.body = #"{"emoji":"🎸","confidence":0.9,"price":10000}"#
        let gateway = makeGateway(transport: transport)

        #expect(await gateway.suggestGift(named: "guitar", currency: .rub)?.value == 10_000)
        transport.body = #"{"emoji":"🎸","confidence":0.9,"price":150}"#
        #expect(await gateway.suggestGift(named: "guitar", currency: .usd)?.value == 150)
        #expect(transport.requests.count == 2)

        #expect(await gateway.suggestGift(named: " guitar ", currency: .rub)?.value == 10_000)
        #expect(await gateway.suggestGift(named: "guitar", currency: .usd)?.value == 150)
        #expect(transport.requests.count == 2)
    }

    @Test func truncatesAfterCollapsingWhitespace() async throws {
        let transport = IconTransportStub()
        let gateway = makeGateway(transport: transport)
        let name = " \n" + String(repeating: "я", count: 79) + "   ёжик  "

        _ = await gateway.suggestGift(named: name, currency: .usd)

        let request = try #require(transport.requests.first)
        let body = try JSONDecoder().decode([String: String].self, from: #require(request.httpBody))
        // Truncation can land on a collapsed space; the transmitted name stays trimmed.
        #expect(body["name"] == String(repeating: "я", count: 79))
        #expect(CloudGiftIconGateway.normalizedName(String(repeating: "🎸", count: 90)).count == 80)
    }

    @Test(arguments: [
        #"{"emoji":null,"confidence":0.31}"#,
        #"{"emoji":"not an emoji","confidence":0.93}"#,
        #"{"emoji":"🎸🎁","confidence":0.93}"#,
        "not json"
    ])
    func unusableResponsesReturnNil(_ body: String) async {
        let transport = IconTransportStub()
        transport.body = body
        let gateway = makeGateway(transport: transport)

        #expect(await gateway.suggestGift(named: "guitar", currency: .usd) == nil)
    }

    @Test(arguments: [400, 401, 429, 500, 503])
    func nonSuccessReturnsNil(_ status: Int) async {
        let transport = IconTransportStub()
        transport.status = status
        let gateway = makeGateway(transport: transport)

        #expect(await gateway.suggestGift(named: "guitar", currency: .usd) == nil)
    }

    @Test func transportErrorsReturnNilWithoutRetrying() async {
        let transport = IconTransportStub()
        transport.error = URLError(.timedOut)
        let gateway = makeGateway(transport: transport)

        #expect(await gateway.suggestGift(named: "guitar", currency: .usd) == nil)
        #expect(transport.requests.count == 1)
    }

    @Test(arguments: [429, 503])
    func backsOffThenResumes(_ status: Int) async {
        let transport = IconTransportStub()
        transport.status = status
        var clock = Date(timeIntervalSince1970: 1_000)
        let gateway = makeGateway(transport: transport, now: { clock })
        // Without Retry-After, both wait a minute.
        let delay: TimeInterval = 60

        #expect(await gateway.suggestGift(named: "guitar", currency: .usd) == nil)
        transport.status = 200
        clock = clock.addingTimeInterval(delay - 1)
        #expect(await gateway.suggestGift(named: "running shoes", currency: .usd) == nil)
        #expect(transport.requests.count == 1)

        clock = clock.addingTimeInterval(1)
        #expect(await gateway.suggestGift(named: "guitar", currency: .usd)?.emoji == "🎸")
        #expect(transport.requests.count == 2)
    }

    @Test func honorsLongerRetryAfter() async {
        let transport = IconTransportStub()
        transport.status = 429
        transport.headers = ["Retry-After": "120"]
        var clock = Date(timeIntervalSince1970: 1_000)
        let gateway = makeGateway(transport: transport, now: { clock })
        _ = await gateway.suggestGift(named: "guitar", currency: .usd)
        transport.status = 200

        clock = clock.addingTimeInterval(119)
        #expect(await gateway.suggestGift(named: "guitar", currency: .usd) == nil)
        #expect(transport.requests.count == 1)
        clock = clock.addingTimeInterval(1)
        #expect(await gateway.suggestGift(named: "guitar", currency: .usd) != nil)
    }

    @Test func unavailableHonorsAShortRetryAfter() async {
        let transport = IconTransportStub()
        transport.status = 503
        transport.headers = ["Retry-After": "30"]
        var clock = Date(timeIntervalSince1970: 1_000)
        let gateway = makeGateway(transport: transport, now: { clock })
        _ = await gateway.suggestGift(named: "guitar", currency: .usd)
        transport.status = 200

        clock = clock.addingTimeInterval(29)
        #expect(await gateway.suggestGift(named: "guitar", currency: .usd) == nil)
        #expect(transport.requests.count == 1)
        clock = clock.addingTimeInterval(1)
        #expect(await gateway.suggestGift(named: "guitar", currency: .usd)?.emoji == "🎸")
    }

    @Test func spentBudgetWaitsAtMostADay() async {
        let transport = IconTransportStub()
        transport.status = 503
        transport.headers = ["Retry-After": "2592000"]
        var clock = Date(timeIntervalSince1970: 1_000)
        let gateway = makeGateway(transport: transport, now: { clock })
        _ = await gateway.suggestGift(named: "guitar", currency: .usd)
        transport.status = 200

        clock = clock.addingTimeInterval(86_399)
        #expect(await gateway.suggestGift(named: "guitar", currency: .usd) == nil)
        clock = clock.addingTimeInterval(1)
        #expect(await gateway.suggestGift(named: "guitar", currency: .usd)?.emoji == "🎸")
    }

    @Test func cacheUsesNormalizedNamesAndCachesNullAnswers() async {
        let transport = IconTransportStub()
        let gateway = makeGateway(transport: transport)

        _ = await gateway.suggestGift(named: " guitar   amp\n", currency: .usd)
        _ = await gateway.suggestGift(named: "guitar amp", currency: .usd)
        #expect(transport.requests.count == 1)

        transport.body = #"{"emoji":null,"confidence":0.31}"#
        _ = await gateway.suggestGift(named: "unknown gift", currency: .usd)
        #expect(await gateway.suggestGift(named: "unknown gift", currency: .usd) == nil)
        #expect(transport.requests.count == 2)
    }

    @Test func evictsOldestCachedName() async {
        let transport = IconTransportStub()
        let gateway = makeGateway(transport: transport)
        for index in 0..<101 {
            _ = await gateway.suggestGift(named: "gift \(index)", currency: .usd)
        }
        _ = await gateway.suggestGift(named: "gift 100", currency: .usd)
        #expect(transport.requests.count == 101)
        _ = await gateway.suggestGift(named: "gift 0", currency: .usd)
        #expect(transport.requests.count == 102)
    }

    @Test func requiresConsentAndAtLeastTwoCharacters() async {
        let transport = IconTransportStub()
        let preferences = TestPreferencesGateway()
        let gateway = CloudGiftIconGateway(preferences: preferences, transport: { try await transport.send($0) })
        #expect(gateway.isAvailable == false)
        #expect(await gateway.suggestGift(named: "guitar", currency: .usd) == nil)
        preferences.setCloudIconConsent(.declined)
        #expect(await gateway.suggestGift(named: "guitar", currency: .usd) == nil)
        preferences.setCloudIconConsent(.allowed)
        #expect(gateway.isAvailable)
        #expect(await gateway.suggestGift(named: " \nя ", currency: .usd) == nil)
        #expect(transport.requests.isEmpty)
    }

    @Test func cancelledAnswerIsNotPublishedOrCached() async {
        let transport = IconTransportStub()
        transport.holdsRequests = true
        let gateway = makeGateway(transport: transport)
        let request = Task { await gateway.suggestGift(named: "guitar", currency: .usd) }
        await transport.waitForRequest()
        request.cancel()
        transport.releaseRequest()
        #expect(await request.value == nil)

        transport.holdsRequests = false
        #expect(await gateway.suggestGift(named: "guitar", currency: .usd) != nil)
        #expect(transport.requests.count == 2)
    }

    @Test func revokingConsentDiscardsLateAnswerAndOldCache() async {
        let transport = IconTransportStub()
        let preferences = TestPreferencesGateway()
        let gateway = makeGateway(transport: transport, preferences: preferences)
        _ = await gateway.suggestGift(named: "cached guitar", currency: .usd)
        transport.holdsRequests = true
        let request = Task { await gateway.suggestGift(named: "guitar", currency: .usd) }
        // The first request is already cached; wait for the new transport to suspend.
        for _ in 0..<500 where transport.requests.count < 2 {
            try? await Task.sleep(for: .milliseconds(10))
        }
        preferences.setCloudIconConsent(.declined)
        preferences.setCloudIconConsent(.allowed)
        transport.releaseRequest()
        #expect(await request.value == nil)

        transport.holdsRequests = false
        _ = await gateway.suggestGift(named: "cached guitar", currency: .usd)
        #expect(transport.requests.count == 3)
        #expect(transport.requests.first?.value(forHTTPHeaderField: "X-Install-ID") != preferences.installID)
        #expect(transport.requests.last?.value(forHTTPHeaderField: "X-Install-ID") == preferences.installID)
    }
}

@MainActor
struct PreferredGiftIntelligenceTests {
    @Test(arguments: [CloudIconConsent.undecided, .declined, .allowed])
    func routesByConsent(_ consent: CloudIconConsent) async {
        let preferences = TestPreferencesGateway()
        preferences.setCloudIconConsent(consent)
        let cloud = ScriptedIntelligenceGateway()
        let onDevice = ScriptedIntelligenceGateway()
        cloud.results["guitar"] = GiftIntelligenceResult(emoji: "🎸", value: nil)
        onDevice.results["guitar"] = GiftIntelligenceResult(emoji: "🎵", value: 1_000)
        let gateway = PreferredGiftIntelligenceGateway(preferences: preferences, cloud: cloud, onDevice: onDevice)

        #expect(gateway.isAvailable)
        gateway.prewarm()
        let result = await gateway.suggestGift(named: "guitar", currency: .rub)
        #expect(result?.emoji == (consent == .allowed ? "🎸" : "🎵"))
        #expect((consent == .allowed ? cloud : onDevice).currencies == [.rub])
        #expect(cloud.requests.count == (consent == .allowed ? 1 : 0))
        #expect(onDevice.requests.count == (consent == .allowed ? 0 : 1))
        #expect(cloud.prewarmCount == (consent == .allowed ? 1 : 0))
        #expect(onDevice.prewarmCount == (consent == .allowed ? 0 : 1))
    }

    @Test func unavailableOnDeviceModelUsesHeuristicUntilConsentChanges() async {
        let preferences = TestPreferencesGateway()
        let cloud = ScriptedIntelligenceGateway()
        let onDevice = ScriptedIntelligenceGateway()
        onDevice.isAvailable = false
        let gateway = PreferredGiftIntelligenceGateway(preferences: preferences, cloud: cloud, onDevice: onDevice)

        #expect(gateway.isAvailable == false)
        #expect(await gateway.suggestGift(named: "guitar", currency: .usd) == nil)
        preferences.setCloudIconConsent(.declined)
        #expect(gateway.isAvailable == false)
        preferences.setCloudIconConsent(.allowed)
        #expect(gateway.isAvailable)
    }

    @Test func cloudNilDoesNotFallThroughToOnDevice() async {
        let preferences = TestPreferencesGateway()
        preferences.setCloudIconConsent(.allowed)
        let cloud = ScriptedIntelligenceGateway()
        let onDevice = ScriptedIntelligenceGateway()
        let gateway = PreferredGiftIntelligenceGateway(preferences: preferences, cloud: cloud, onDevice: onDevice)

        #expect(await gateway.suggestGift(named: "guitar", currency: .usd) == nil)
        #expect(cloud.requests == ["guitar"])
        #expect(onDevice.requests.isEmpty)
    }
}

@MainActor
struct CloudIconPreferencesTests {
    @Test func privacyManifestIsBundledWithTheApp() throws {
        let url = try #require(Bundle.main.url(forResource: "PrivacyInfo", withExtension: "xcprivacy"))
        let data = try Data(contentsOf: url)
        let manifest = try #require(PropertyListSerialization.propertyList(from: data, format: nil) as? [String: Any])
        #expect(manifest["NSPrivacyTracking"] as? Bool == false)
        let collected = try #require(manifest["NSPrivacyCollectedDataTypes"] as? [[String: Any]])
        let content = try #require(collected.first { $0["NSPrivacyCollectedDataType"] as? String == "NSPrivacyCollectedDataTypeOtherUserContent" })
        #expect(content["NSPrivacyCollectedDataTypeLinked"] as? Bool == false)
        #expect(content["NSPrivacyCollectedDataTypeTracking"] as? Bool == false)
        #expect(content["NSPrivacyCollectedDataTypePurposes"] as? [String] == ["NSPrivacyCollectedDataTypePurposeAppFunctionality"])
        let accessed = try #require(manifest["NSPrivacyAccessedAPITypes"] as? [[String: Any]])
        let defaults = try #require(accessed.first { $0["NSPrivacyAccessedAPIType"] as? String == "NSPrivacyAccessedAPICategoryUserDefaults" })
        #expect(defaults["NSPrivacyAccessedAPITypeReasons"] as? [String] == ["CA92.1"])
    }

    @Test func persistsConsentAndRotatesInstallIDWhenDeclined() throws {
        let suite = "CloudIconPreferencesTests.\(UUID().uuidString)"
        let defaults = try #require(UserDefaults(suiteName: suite))
        defer { defaults.removePersistentDomain(forName: suite) }
        let preferences = UserDefaultsPreferencesGateway(defaults: defaults)
        #expect(preferences.cloudIconConsent == .undecided)
        let originalID = preferences.installID
        #expect(UUID(uuidString: originalID) != nil)
        #expect(UserDefaultsPreferencesGateway(defaults: defaults).installID == originalID)

        preferences.setCloudIconConsent(.allowed)
        #expect(UserDefaultsPreferencesGateway(defaults: defaults).cloudIconConsent == .allowed)
        #expect(preferences.installID == originalID)

        preferences.setCloudIconConsent(.declined)
        #expect(preferences.installID != originalID)
        #expect(UUID(uuidString: preferences.installID) != nil)
        let reloaded = UserDefaultsPreferencesGateway(defaults: defaults)
        #expect(reloaded.cloudIconConsent == .declined)
        #expect(reloaded.installID == preferences.installID)

        let rotatedID = preferences.installID
        preferences.setCloudIconConsent(.allowed)
        #expect(preferences.installID == rotatedID)
    }

    @Test func unknownStoredConsentDefaultsToUndecided() throws {
        let suite = "CloudIconPreferencesTests.\(UUID().uuidString)"
        let defaults = try #require(UserDefaults(suiteName: suite))
        defer { defaults.removePersistentDomain(forName: suite) }
        defaults.set("unknown", forKey: "cloudIconConsent")
        #expect(UserDefaultsPreferencesGateway(defaults: defaults).cloudIconConsent == .undecided)
    }
}

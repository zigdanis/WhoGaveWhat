import Foundation

/// A value an analytics property can carry. Only these scalar kinds exist, so free text such
/// as a person's name or a gift title cannot slip into an event by accident.
enum AnalyticsValue: Equatable {
    case string(String)
    case int(Int)
    case bool(Bool)
}

enum GiftSheetMode: String, Equatable {
    case create
    case edit
}

/// Which control opened the gift sheet.
enum GiftSheetSource: String, Equatable {
    case welcomeCard = "welcome_card"
    case floatingButton = "floating_button"
    case toolbarButton = "toolbar_button"
    case giftDetail = "gift_detail"
    case insightsWelcome = "insights_welcome"
    /// The floating or toolbar button on a person's screen.
    case personDetail = "person_detail"
}

/// How the gift sheet closed. A failed save keeps the sheet open, so it is not an outcome;
/// `gift_save_failed` records it instead.
enum GiftSheetOutcome: String, Equatable {
    case saved
    case cancelled
}

/// A picker inside the gift sheet.
enum GiftPickerKind: String, Equatable {
    case giver
    case recipient
    case occasion
    case icon
    case date
}

enum GiftDeletionSource: String, Equatable {
    case home
    case personDetail = "person_detail"
    case giftDetail = "gift_detail"
}

enum PersonCreationSource: String, Equatable {
    case peopleTab = "people_tab"
    case giftPicker = "gift_picker"
    case peopleWelcome = "people_welcome"
}

enum PersonDeletionSource: String, Equatable {
    case peopleList = "people_list"
    case personEditor = "person_editor"
}

enum PersonPhotoChange: String, Equatable {
    case added
    case replaced
    case removed
    case unchanged
}

enum SuggestionProvider: String, Equatable {
    case cloud
    case onDevice = "on_device"
}

/// The gift relative to the viewpoint person, or why there is no direction.
enum GiftSavedDirection: String, Equatable {
    case received
    case given
    case unrelated
    case noViewpoint = "no_viewpoint"
}

enum GiftIconSource: String, Equatable {
    case user
    case inferred
}

enum GiftValueSource: String, Equatable {
    case user
    case estimate
    case none
}

/// How far the gift date is from today, in coarse buckets.
enum GiftDateOffset: String, Equatable {
    case today
    case pastWeek = "past_week"
    case pastMonth = "past_month"
    case older
    case future

    static func bucket(for date: Date, today: Date, calendar: Calendar = .autoupdatingCurrent) -> GiftDateOffset {
        let day = calendar.startOfDay(for: date)
        let days = calendar.dateComponents([.day], from: calendar.startOfDay(for: today), to: day).day ?? 0
        switch days {
        case 1...: return .future
        case 0: return .today
        case -7..<0: return .pastWeek
        case -31..<(-7): return .pastMonth
        default: return .older
        }
    }
}

/// What a saved gift looked like, without the text, people or amount it holds.
struct GiftSavedProperties: Equatable {
    var mode: GiftSheetMode
    var direction: GiftSavedDirection
    var iconSource: GiftIconSource
    var valueSource: GiftValueSource
    /// The built-in occasion in snake_case, or `custom` for one the user typed.
    var occasion: String
    /// The ISO code of the gift's currency, never its amount.
    var currency: String
    var paidByYou: Bool
    var dateOffset: GiftDateOffset
    var giftsCount: Int

    /// Built-in occasions keep their English key; anything else is `custom`.
    static func occasionLabel(_ occasion: String, defaults: [String]) -> String {
        guard defaults.contains(occasion) else { return "custom" }
        return occasion.lowercased().replacingOccurrences(of: " ", with: "_")
    }
}

/// Every product event the app records. Names are snake_case; properties never carry
/// names, gift titles, amounts, photos or dates, only categories and counts.
enum AnalyticsEvent: Equatable {
    case tabSelected(tab: String)
    case giftSheetOpened(mode: GiftSheetMode, source: GiftSheetSource)
    case giftSheetClosed(mode: GiftSheetMode, outcome: GiftSheetOutcome)
    case giftDetailViewed
    case personDetailViewed(isSelf: Bool, giftsCount: Int)
    case openedFromSpotlight
    case giftPickerOpened(GiftPickerKind)
    case giftIconPicked(custom: Bool)
    case giftPriceEdited(hadEstimate: Bool)
    /// `afterSave` marks an answer that arrived after a quick Save had already closed the sheet.
    case giftSuggestionCompleted(
        provider: SuggestionProvider, hasIcon: Bool, hasPrice: Bool, latencyMilliseconds: Int, afterSave: Bool = false)
    case occasionAdded
    /// The swap button turned the gift's giver and recipient around.
    case giftPeopleSwapped
    /// Save was tapped with a complete form; `giftSaved` or `giftSaveFailed` follows.
    case giftSaveAttempted(mode: GiftSheetMode)
    case giftSaved(GiftSavedProperties)
    /// The store refused the gift, or the records on screen could not be reloaded first; the sheet stays
    /// open with everything entered.
    case giftSaveFailed(mode: GiftSheetMode)
    case giftDeleted(source: GiftDeletionSource, giftsCount: Int)
    case personCreated(source: PersonCreationSource, peopleCount: Int)
    case personUpdated(nameChanged: Bool, photo: PersonPhotoChange)
    case personDeleted(source: PersonDeletionSource, giftsRemoved: Int, peopleCount: Int)
    case viewpointChanged(isSet: Bool)
    case insightsPersonPicked(slot: String)
    case insightsYearChanged(isCurrentYear: Bool)
    case currencyChanged(currency: String)
    case privacyPolicyOpened
    case licensesOpened
    /// Settings → Export all data wrote the file for the share sheet.
    case dataExported(peopleCount: Int, giftsCount: Int)
    /// A backup from iCloud or a file was added to the journal; counts only, nothing about the records.
    case dataRestored(source: DataRestoreSource, peopleAdded: Int, giftsAdded: Int, intoEmptyJournal: Bool)
    case iCloudBackupToggled(isOn: Bool)
    /// The app asked the system for an App Store rating; whether the sheet appeared is not known.
    case reviewPromptRequested(
        activeDays: Int, daysSinceFirstLaunch: Int, giftsCount: Int, peopleCount: Int, requestNumber: Int)

    var name: String {
        switch self {
        case .tabSelected: "tab_selected"
        case .giftSheetOpened: "gift_sheet_opened"
        case .giftSheetClosed: "gift_sheet_closed"
        case .giftDetailViewed: "gift_detail_viewed"
        case .personDetailViewed: "person_detail_viewed"
        case .openedFromSpotlight: "app_opened_from_spotlight"
        case .giftPickerOpened: "gift_picker_opened"
        case .giftIconPicked: "gift_icon_picked"
        case .giftPriceEdited: "gift_price_edited"
        case .giftSuggestionCompleted: "gift_suggestion_completed"
        case .occasionAdded: "occasion_added"
        case .giftPeopleSwapped: "gift_people_swapped"
        case .giftSaveAttempted: "gift_save_attempted"
        case .giftSaved: "gift_saved"
        case .giftSaveFailed: "gift_save_failed"
        case .giftDeleted: "gift_deleted"
        case .personCreated: "person_created"
        case .personUpdated: "person_updated"
        case .personDeleted: "person_deleted"
        case .viewpointChanged: "viewpoint_changed"
        case .insightsPersonPicked: "insights_person_picked"
        case .insightsYearChanged: "insights_year_changed"
        case .currencyChanged: "currency_changed"
        case .privacyPolicyOpened: "privacy_policy_opened"
        case .licensesOpened: "licenses_opened"
        case .dataExported: "data_exported"
        case .dataRestored: "data_restored"
        case .iCloudBackupToggled: "icloud_backup_toggled"
        case .reviewPromptRequested: "review_prompt_requested"
        }
    }

    var properties: [String: AnalyticsValue] {
        switch self {
        case .tabSelected(let tab):
            ["tab": .string(tab)]
        case .giftSheetOpened(let mode, let source):
            ["mode": .string(mode.rawValue), "source": .string(source.rawValue)]
        case .giftSheetClosed(let mode, let outcome):
            ["mode": .string(mode.rawValue), "outcome": .string(outcome.rawValue)]
        case .giftDetailViewed, .openedFromSpotlight, .occasionAdded, .giftPeopleSwapped, .privacyPolicyOpened,
            .licensesOpened:
            [:]
        case .personDetailViewed(let isSelf, let giftsCount):
            ["is_self": .bool(isSelf), "gifts_count": .int(giftsCount)]
        case .giftSaveAttempted(let mode), .giftSaveFailed(let mode):
            ["mode": .string(mode.rawValue)]
        case .giftPickerOpened(let picker):
            ["picker": .string(picker.rawValue)]
        case .giftIconPicked(let custom):
            ["source": .string(custom ? "custom" : "list")]
        case .giftPriceEdited(let hadEstimate):
            ["had_estimate": .bool(hadEstimate)]
        case .giftSuggestionCompleted(let provider, let hasIcon, let hasPrice, let latency, let afterSave):
            [
                "provider": .string(provider.rawValue),
                "outcome": .string(hasIcon || hasPrice ? "suggested" : "empty"),
                "has_icon": .bool(hasIcon),
                "has_price": .bool(hasPrice),
                "latency_ms": .int(latency),
                "after_save": .bool(afterSave)
            ]
        case .giftSaved(let gift):
            [
                "mode": .string(gift.mode.rawValue),
                "direction": .string(gift.direction.rawValue),
                "icon_source": .string(gift.iconSource.rawValue),
                "value_source": .string(gift.valueSource.rawValue),
                "occasion": .string(gift.occasion),
                "currency": .string(gift.currency),
                "paid_by_you": .bool(gift.paidByYou),
                "date_offset": .string(gift.dateOffset.rawValue),
                "gifts_count": .int(gift.giftsCount)
            ]
        case .giftDeleted(let source, let giftsCount):
            ["source": .string(source.rawValue), "gifts_count": .int(giftsCount)]
        case .personCreated(let source, let peopleCount):
            ["source": .string(source.rawValue), "people_count": .int(peopleCount)]
        case .personUpdated(let nameChanged, let photo):
            ["name_changed": .bool(nameChanged), "photo": .string(photo.rawValue)]
        case .personDeleted(let source, let giftsRemoved, let peopleCount):
            ["source": .string(source.rawValue), "gifts_removed": .int(giftsRemoved), "people_count": .int(peopleCount)]
        case .viewpointChanged(let isSet):
            ["is_set": .bool(isSet)]
        case .insightsPersonPicked(let slot):
            ["slot": .string(slot)]
        case .insightsYearChanged(let isCurrentYear):
            ["is_current_year": .bool(isCurrentYear)]
        case .currencyChanged(let currency):
            ["currency": .string(currency)]
        case .dataExported(let peopleCount, let giftsCount):
            ["people_count": .int(peopleCount), "gifts_count": .int(giftsCount)]
        case .dataRestored(let source, let peopleAdded, let giftsAdded, let intoEmptyJournal):
            [
                "source": .string(source.rawValue),
                "people_added": .int(peopleAdded),
                "gifts_added": .int(giftsAdded),
                "into_empty_journal": .bool(intoEmptyJournal)
            ]
        case .iCloudBackupToggled(let isOn):
            ["is_on": .bool(isOn)]
        case .reviewPromptRequested(let activeDays, let daysSinceFirstLaunch, let giftsCount, let peopleCount, let requestNumber):
            [
                "active_days": .int(activeDays),
                "days_since_first_launch": .int(daysSinceFirstLaunch),
                "gifts_count": .int(giftsCount),
                "people_count": .int(peopleCount),
                "request_number": .int(requestNumber)
            ]
        }
    }
}

import Foundation

@MainActor
struct SuggestGiftUseCase {
    let intelligenceGateway: GiftIntelligenceGateway

    var isIntelligenceAvailable: Bool {
        intelligenceGateway.isAvailable
    }

    func instantSuggestion(for name: String) -> GiftSuggestion {
        let normalizedName = name.lowercased()
        return Self.catalog.first { suggestion in
            suggestion.keywords.contains { normalizedName.contains($0) }
        } ?? GiftSuggestion(keywords: [], emoji: "🎁", value: 2_000)
    }

    func intelligentSuggestion(for name: String) async -> GiftIntelligenceResult? {
        await intelligenceGateway.suggestGift(named: name)
    }

    private static let catalog: [GiftSuggestion] = [
        GiftSuggestion(keywords: ["bouquet", "flower", "rose", "букет", "цвет", "роза", "роз"], emoji: "💐", value: 1_800),
        GiftSuggestion(keywords: ["watch", "часы"], emoji: "⌚", value: 9_000),
        GiftSuggestion(keywords: ["book", "книг", "книж"], emoji: "📚", value: 900),
        GiftSuggestion(keywords: ["teddy", "bear", "plush", "игрушк", "мишк", "медвед", "плюш"], emoji: "🧸", value: 1_500),
        GiftSuggestion(keywords: ["chocolate", "candy", "sweets", "шокол", "конфет", "сладост"], emoji: "🍫", value: 700),
        GiftSuggestion(keywords: ["wine", "вино", "вина"], emoji: "🍷", value: 1_900),
        GiftSuggestion(keywords: ["perfume", "духи", "парфюм"], emoji: "🌸", value: 3_500),
        GiftSuggestion(keywords: ["necklace", "ring", "jewel", "bracelet", "earring", "кольц", "ожерель", "колье", "брасле", "серьг", "серёж", "украшен", "цепочк"], emoji: "💍", value: 6_000),
        GiftSuggestion(keywords: ["phone", "iphone", "телефон", "айфон", "смартфон"], emoji: "📱", value: 40_000),
        GiftSuggestion(keywords: ["headphone", "earbud", "airpod", "наушник"], emoji: "🎧", value: 5_000),
        GiftSuggestion(keywords: ["money", "cash", "envelope", "деньг", "купюр", "конверт", "налич"], emoji: "💸", value: 5_000),
        GiftSuggestion(keywords: ["card", "voucher", "ticket", "билет", "сертификат", "ваучер"], emoji: "🎟️", value: 3_000),
        GiftSuggestion(keywords: ["cake", "торт"], emoji: "🎂", value: 1_200),
        GiftSuggestion(keywords: ["plant", "pot", "растен", "горшк"], emoji: "🪴", value: 1_200),
        GiftSuggestion(keywords: ["mug", "cup", "coffee", "кружк", "чашк", "кофе"], emoji: "☕", value: 800),
        GiftSuggestion(keywords: ["doll", "matryoshka", "кукл", "матрёшк", "матрешк"], emoji: "🪆", value: 1_400),
        GiftSuggestion(keywords: ["lego", "blocks", "лего", "конструктор"], emoji: "🧱", value: 4_000),
        GiftSuggestion(keywords: ["scarf", "шарф", "платок"], emoji: "🧣", value: 2_200),
        GiftSuggestion(keywords: ["candle", "свеч"], emoji: "🕯️", value: 1_000),
        GiftSuggestion(keywords: ["game", "console", "игра", "игров", "пристав", "консол"], emoji: "🎮", value: 5_500),
        GiftSuggestion(keywords: ["pizza", "пицц"], emoji: "🍕", value: 900),
        GiftSuggestion(keywords: ["coffee beans", "tea", "чай"], emoji: "🍵", value: 700),
    ]
}

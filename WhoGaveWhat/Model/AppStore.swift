import SwiftUI
import CoreData

enum Screen { case onboarding, signin, app }
enum Tab: String { case home, people, insights }

/// Which tap-to-reveal picker the Add sheet is showing.
enum PickerKind: String, Identifiable {
    case person, member, celeb, emoji, date
    var id: String { rawValue }
}

/// Draft state for the "Add a gift" sheet. Fields stay quiet (nil → "Choose")
/// until the user fills them in.
struct AddForm {
    var flow: Flow = .received
    var name: String = ""
    var emoji: String? = nil            // chosen emoji; nil → use the suggestion
    var value: Int? = nil
    var valueTouched: Bool = false
    var personId: String? = nil
    var memberId: String? = nil         // nil → "Choose"; defaults to "you" on save
    var paidByYou: Bool = true
    var celebration: String? = nil      // nil → "Choose"
    var date: Date = AppStore.today
}

/// The whole app's observable state. Reads from and writes through Core Data;
/// the view layer keeps consuming lightweight value types (`Gift`, `Member`, `Person`).
final class AppStore: ObservableObject {
    // Navigation / UI
    @Published var screen: Screen = .onboarding
    @Published var onbStep: Int = 0
    @Published var tab: Tab = .home
    @Published var filter: String = "all"          // all / received / given
    @Published var detailId: String? = nil
    @Published var detailFlow: Flow = .received
    @Published var sheetOpen: Bool = false
    @Published var picker: PickerKind? = nil
    @Published var showSettings: Bool = false
    @Published var revealTotal: Bool = false
    @Published var add = AddForm()

    // Settings toggles
    @Published var notifEnabled: Bool = true
    @Published var cloudEnabled: Bool = true

    // Data (loaded from Core Data)
    @Published var gifts: [Gift] = []
    @Published var members: [Member] = []
    @Published var people: [Person] = []
    @Published var celebrations: [String] = ["Birthday", "New Year", "Wedding", "Anniversary",
                                             "Graduation", "Housewarming", "Just because"]

    private let context: NSManagedObjectContext

    let displayYear = "2026"

    /// Colour palette assigned to people/members created on the fly.
    private let newEntityPalette: [Int64] = [0x7A5CCB, 0x0E7C8C, 0x2F6FAE, 0xC26B2D, 0x12805C, 0x5B6573]

    let emojiChoices = ["🎁","💐","⌚","📚","🧸","🍫","🍷","🌸","💍","📱","🎧","💸","🎟️","🎂","🪴","☕",
                        "🪆","🧱","🧣","🕯️","🎮","👟","🧴","🍾","🖼️","🧦","🚲","🎨","🧶","🪀"]

    let suggestMap: [Suggestion] = [
        Suggestion(keywords: ["bouquet", "flower", "rose"], emoji: "💐", value: 1800),
        Suggestion(keywords: ["watch"], emoji: "⌚", value: 9000),
        Suggestion(keywords: ["book"], emoji: "📚", value: 900),
        Suggestion(keywords: ["teddy", "bear", "plush"], emoji: "🧸", value: 1500),
        Suggestion(keywords: ["chocolate", "candy", "sweets"], emoji: "🍫", value: 700),
        Suggestion(keywords: ["wine"], emoji: "🍷", value: 1900),
        Suggestion(keywords: ["perfume"], emoji: "🌸", value: 3500),
        Suggestion(keywords: ["necklace", "ring", "jewel", "bracelet", "earring"], emoji: "💍", value: 6000),
        Suggestion(keywords: ["phone", "iphone"], emoji: "📱", value: 40000),
        Suggestion(keywords: ["headphone", "earbud", "airpod"], emoji: "🎧", value: 5000),
        Suggestion(keywords: ["money", "cash", "envelope"], emoji: "💸", value: 5000),
        Suggestion(keywords: ["card", "voucher", "ticket"], emoji: "🎟️", value: 3000),
        Suggestion(keywords: ["cake"], emoji: "🎂", value: 1200),
        Suggestion(keywords: ["plant", "pot"], emoji: "🪴", value: 1200),
        Suggestion(keywords: ["mug", "cup", "coffee"], emoji: "☕", value: 800),
        Suggestion(keywords: ["doll", "matryoshka"], emoji: "🪆", value: 1400),
        Suggestion(keywords: ["lego", "blocks"], emoji: "🧱", value: 4000),
        Suggestion(keywords: ["scarf"], emoji: "🧣", value: 2200),
        Suggestion(keywords: ["candle"], emoji: "🕯️", value: 1000),
        Suggestion(keywords: ["game", "console"], emoji: "🎮", value: 5500),
    ]

    init(context: NSManagedObjectContext) {
        self.context = context
        reload()

        // UI-testing / preview entry points (e.g. -setenv KS_START app).
        let env = ProcessInfo.processInfo.environment
        if let start = env["KS_START"] {
            switch start {
            case "app":      screen = .app
            case "signin":   screen = .signin
            default:         break
            }
        }
        if let t = env["KS_TAB"], let tab = Tab(rawValue: t) { self.tab = tab }
        if env["KS_SHEET"] != nil { sheetOpen = true }
        if let d = env["KS_DETAIL"] { detailId = d }
    }

    // MARK: - Core Data load

    func reload() {
        let peopleReq = CDPerson.fetchRequest()
        peopleReq.sortDescriptors = [NSSortDescriptor(key: "sortIndex", ascending: true)]
        let cdPeople = (try? context.fetch(peopleReq)) ?? []
        members = cdPeople.filter { $0.isFamily }.map(Member.init)
        people  = cdPeople.filter { !$0.isFamily }.map(Person.init)

        let giftReq = CDGift.fetchRequest()
        giftReq.sortDescriptors = [NSSortDescriptor(key: "date", ascending: false)]
        let cdGifts = (try? context.fetch(giftReq)) ?? []
        gifts = cdGifts.map(Gift.init)

        // Surface any occasions already used by saved gifts.
        for g in gifts where !celebrations.contains(g.celebration) && !g.celebration.isEmpty {
            celebrations.append(g.celebration)
        }
    }

    // MARK: - Helpers

    func suggest(_ name: String) -> Suggestion {
        let n = name.lowercased()
        for s in suggestMap where s.keywords.contains(where: { n.contains($0) }) {
            return s
        }
        return Suggestion(keywords: [], emoji: "🎁", value: 2000)
    }

    func flowMeta(_ f: Flow) -> FlowMeta {
        f == .received
            ? FlowMeta(main: KS.recv, deep: KS.recvDeep, tint: KS.recvTint, label: "Received", arrow: "↙")
            : FlowMeta(main: KS.give, deep: KS.giveDeep, tint: KS.giveTint, label: "Given",    arrow: "↗")
    }

    /// Effective emoji shown in the Add hero: chosen → name suggestion → gift.
    func effEmoji(_ a: AddForm) -> String {
        if let e = a.emoji { return e }
        return a.name.trimmingCharacters(in: .whitespaces).isEmpty ? "🎁" : suggest(a.name).emoji
    }

    func initials(_ name: String) -> String {
        let letters = name.split(separator: " ").compactMap { $0.first }
        return String(letters.prefix(2)).uppercased()
    }

    func first(_ name: String) -> String {
        String(name.split(separator: " ").last ?? "")
    }

    func personName(_ id: String) -> String { people.first { $0.id == id }?.name ?? id }
    func memberName(_ id: String) -> String { members.first { $0.id == id }?.name ?? id }

    func entityColor(_ id: String) -> Color {
        members.first { $0.id == id }?.color ?? people.first { $0.id == id }?.color ?? KS.give
    }

    func isMember(_ id: String) -> Bool { members.contains { $0.id == id } }

    /// Month (+ year unless it's the display year). Localized to `locale` so the
    /// month name and ordering follow the user's language; tests pin `en_US`.
    func monthLabel(_ date: Date, locale: Locale = .current) -> String {
        let year = Calendar.current.component(.year, from: date)
        let style = year == 2026
            ? Date.FormatStyle.dateTime.month(.wide)
            : Date.FormatStyle.dateTime.month(.wide).year()
        return date.formatted(style.locale(locale))
    }

    /// Abbreviated month + day (+ year unless the display year), localized.
    func shortDate(_ date: Date, locale: Locale = .current) -> String {
        let year = Calendar.current.component(.year, from: date)
        let style = year == 2026
            ? Date.FormatStyle.dateTime.month(.abbreviated).day()
            : Date.FormatStyle.dateTime.month(.abbreviated).day().year()
        return date.formatted(style.locale(locale))
    }

    /// "Today" / "Yesterday" / short date — used by the Add sheet date field.
    func dateLabel(_ date: Date, locale: Locale = .current) -> String {
        let cal = Calendar.current
        if cal.isDate(date, inSameDayAs: Self.today) { return String(localized: "Today") }
        if cal.isDate(date, inSameDayAs: Self.yesterday) { return String(localized: "Yesterday") }
        return shortDate(date, locale: locale)
    }

    // MARK: - Localized display helpers

    /// Localized "N gifts" / "N people" with correct plural forms per language.
    func giftsCount(_ n: Int) -> String { String(localized: "\(n) gifts") }
    func peopleCount(_ n: Int) -> String { String(localized: "\(n) people") }

    /// Localize a known occasion (stored canonically in English); custom
    /// user-entered occasions fall back to their own text.
    func locCeleb(_ raw: String) -> String { String(localized: String.LocalizationValue(raw)) }
    func locCeleb(_ raw: String?) -> String? { raw.map(locCeleb) }

    /// Subtitle shown under a gift row (received: from → member, given: to person · member).
    func giftSubtitle(_ g: Gift) -> String {
        if g.flow == .received {
            return "\(personName(g.personId))  →  \(memberName(g.memberId))"
        } else {
            let suffix = g.memberId != "you" ? "  ·  \(memberName(g.memberId))" : ""
            return String(localized: "to \(personName(g.personId))") + suffix
        }
    }

    /// Trailing meta on a gift row — just the date, per the design.
    func giftMeta(_ g: Gift) -> String { shortDate(g.date) }

    // MARK: - Derived data

    func sum(_ arr: [Gift]) -> Double { arr.reduce(0) { $0 + $1.value } }

    var received: [Gift] { gifts.filter { $0.flow == .received } }
    var given: [Gift] { gifts.filter { $0.flow == .given } }

    /// Filtered + month-grouped timeline for Home.
    struct MonthGroup: Identifiable { let id: String; let label: String; let items: [Gift] }

    var timeline: [MonthGroup] {
        let filtered = gifts
            .filter { filter == "all" || $0.flow.rawValue == filter }
            .sorted { $0.date > $1.date }
        var order: [String] = []
        var map: [String: [Gift]] = [:]
        for g in filtered {
            let lbl = monthLabel(g.date)
            if map[lbl] == nil { order.append(lbl) }
            map[lbl, default: []].append(g)
        }
        return order.map { MonthGroup(id: $0, label: $0, items: map[$0] ?? []) }
    }

    // MARK: - Navigation actions

    func blankAdd() -> AddForm { AddForm() }

    func onbNext() {
        if onbStep < 2 { onbStep += 1 } else { screen = .signin }
    }
    func onbSkip() { screen = .signin }
    func enterApp() { screen = .app }

    func setTab(_ t: Tab) { tab = t; detailId = nil }
    func openDetail(_ id: String) { withAnimation(.easeOut(duration: 0.26)) { detailId = id; detailFlow = .received } }
    func closeDetail() { withAnimation(.easeOut(duration: 0.2)) { detailId = nil } }
    func setDetailFlow(_ f: Flow) { withAnimation(.easeOut(duration: 0.18)) { detailFlow = f } }
    func openSettings() { showSettings = true }
    func closeSettings() { showSettings = false }
    func openSheet() { add = blankAdd(); sheetOpen = true }
    func closeSheet() { sheetOpen = false; picker = nil }
    func setFilter(_ f: String) { withAnimation(.easeOut(duration: 0.18)) { filter = f } }
    func toggleTotal() { withAnimation(.easeInOut(duration: 0.45)) { revealTotal.toggle() } }

    // MARK: - Picker actions

    func openPicker(_ k: PickerKind) { picker = k }
    func closePicker() { picker = nil }

    func selectEmoji(_ e: String) { add.emoji = e; picker = nil }
    func selectPerson(_ id: String) { add.personId = id; picker = nil }
    func selectMember(_ id: String) { add.memberId = id; picker = nil }
    func selectCeleb(_ c: String) { add.celebration = c; picker = nil }
    func selectDate(_ d: Date) { add.date = d; picker = nil }

    /// First extended grapheme cluster of an arbitrary string (so a typed emoji
    /// or foreign letter fits one icon slot).
    func firstGrapheme(_ s: String) -> String {
        let t = s.trimmingCharacters(in: .whitespacesAndNewlines)
        return t.first.map(String.init) ?? ""
    }

    func useCustomEmoji(_ raw: String) {
        let g = firstGrapheme(raw)
        guard !g.isEmpty else { return }
        add.emoji = g
        picker = nil
    }

    func addCustomCeleb(_ raw: String) {
        let v = raw.trimmingCharacters(in: .whitespaces)
        guard !v.isEmpty else { return }
        if !celebrations.contains(where: { $0.caseInsensitiveCompare(v) == .orderedSame }) {
            celebrations.insert(v, at: 0)
        }
        add.celebration = v
        picker = nil
    }

    func addCustomPerson(_ raw: String, isFamily: Bool) {
        let v = raw.trimmingCharacters(in: .whitespaces)
        guard !v.isEmpty else { return }
        let id = (isFamily ? "m" : "p") + String(Int(Date().timeIntervalSince1970 * 1000))
        let color = newEntityPalette.randomElement() ?? 0x5B6573
        let p = CDPerson(context: context)
        p.id = id
        p.name = v
        p.colorHex = color
        p.isFamily = isFamily
        p.sortIndex = Int64((isFamily ? members.count : people.count) + 100)
        try? context.save()
        reload()
        if isFamily { add.memberId = id } else { add.personId = id }
        picker = nil
    }

    // MARK: - Save

    func canSave() -> Bool {
        !add.name.trimmingCharacters(in: .whitespaces).isEmpty && add.personId != nil
    }

    func saveGift() {
        guard canSave(), let personId = add.personId else { return }
        let sug = suggest(add.name)
        let value = add.valueTouched ? Double(add.value ?? 0) : sug.value
        let emoji = add.emoji ?? sug.emoji

        let gift = CDGift(context: context)
        gift.id = "g\(Int(Date().timeIntervalSince1970 * 1000))"
        gift.emoji = emoji
        gift.name = add.name.trimmingCharacters(in: .whitespaces)
        gift.flow = add.flow.rawValue
        gift.person = fetchPerson(personId)
        gift.member = fetchPerson(add.memberId ?? "you")
        gift.paidByYou = add.flow == .given ? add.paidByYou : false
        gift.celebration = add.celebration ?? "Just because"
        gift.date = add.date
        gift.value = value

        do { try context.save() } catch { context.rollback() }

        reload()
        sheetOpen = false
        picker = nil
        tab = .home
        filter = "all"
        detailId = nil
        add = blankAdd()
    }

    private func fetchPerson(_ id: String) -> CDPerson? {
        let req = CDPerson.fetchRequest()
        req.predicate = NSPredicate(format: "id == %@", id)
        req.fetchLimit = 1
        return try? context.fetch(req).first ?? nil
    }

    /// Frozen "today" used as the default for newly added gifts (14 Jun 2026).
    static let today: Date = isoDate("2026-06-14")
    static let yesterday: Date = isoDate("2026-06-13")

    private static func isoDate(_ s: String) -> Date {
        let f = DateFormatter()
        f.calendar = Calendar(identifier: .gregorian)
        f.timeZone = TimeZone(identifier: "UTC")
        f.dateFormat = "yyyy-MM-dd"
        return f.date(from: s) ?? Date()
    }
}

// MARK: - Mapping Core Data → value types

private extension Member {
    init(_ cd: CDPerson) {
        self.init(id: cd.id ?? "", name: cd.name ?? "", color: Color(hex: UInt(bitPattern: Int(cd.colorHex))))
    }
}

private extension Person {
    init(_ cd: CDPerson) {
        self.init(id: cd.id ?? "", name: cd.name ?? "", color: Color(hex: UInt(bitPattern: Int(cd.colorHex))))
    }
}

private extension Gift {
    init(_ cd: CDGift) {
        self.init(
            id: cd.id ?? UUID().uuidString,
            emoji: cd.emoji ?? "🎁",
            name: cd.name ?? "",
            flow: Flow(rawValue: cd.flow ?? "received") ?? .received,
            personId: cd.person?.id ?? "",
            memberId: cd.member?.id ?? "you",
            paidByYou: cd.paidByYou,
            celebration: cd.celebration ?? "",
            date: cd.date ?? AppStore.today,
            value: cd.value
        )
    }
}

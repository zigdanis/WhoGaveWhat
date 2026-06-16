import SwiftUI
import CoreData

enum Screen { case onboarding, signin, app }
enum Tab: String { case home, people, insights }

/// Which tap-to-reveal picker the Add sheet is showing.
enum PickerKind: String, Identifiable {
    case from, to, celeb, emoji, date
    var id: String { rawValue }
}

/// Draft state for the "Add a gift" sheet. Fields stay quiet (nil → "Choose")
/// until the user fills them in.
///
/// Direction is no longer a manual toggle: the user picks who gave it (`fromId`)
/// and who got it (`toId`); each can be "you", a family member, or an outside
/// person. Received vs Given is derived from whichever side is the household —
/// see `AppStore.addFlow`.
struct AddForm {
    var name: String = ""
    var emoji: String? = nil            // chosen emoji; nil → use AI / suggestion
    var value: Int? = nil
    var valueTouched: Bool = false
    var fromId: String? = nil           // giver  (nil → "Choose")
    var toId: String? = nil             // receiver (nil → "Choose")
    var paidByYou: Bool = false         // did the app user foot the bill themselves?
    var celebration: String? = nil      // nil → "Choose"
    var date: Date = AppStore.today

    // On-device (Apple Intelligence) enrichment of the typed name. Filled in
    // asynchronously; sits *between* a user's explicit choice and the keyword
    // heuristic so it never overrides what the user picked themselves.
    var aiEmoji: String? = nil
    var aiValue: Double? = nil
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
    @Published var add = AddForm()
    /// When set, the Add sheet is editing this existing gift instead of creating one.
    @Published var editingGiftId: String? = nil

    /// In-flight on-device enrichment of the Add sheet's gift name (debounced).
    private var aiTask: Task<Void, Never>?
    /// True while the on-device model is actively thinking about the typed name,
    /// so the Add sheet can show a small spinner on the icon + estimate.
    @Published var aiLoading: Bool = false

    /// Persists that the user has seen onboarding, so it only shows on first launch.
    private let onboardedKey = "didOnboard"

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

    // Keyword heuristic for instant emoji + rough estimate. Matched as
    // case-insensitive substrings, so partial Russian stems ("шокол") catch all
    // inflections ("шоколад", "шоколадка", "шоколадные"). Order matters: the
    // first entry that matches wins, so put toys ("игрушк") before games ("игра").
    let suggestMap: [Suggestion] = [
        Suggestion(keywords: ["bouquet", "flower", "rose", "букет", "цвет", "роза", "роз"], emoji: "💐", value: 1800),
        Suggestion(keywords: ["watch", "часы"], emoji: "⌚", value: 9000),
        Suggestion(keywords: ["book", "книг", "книж"], emoji: "📚", value: 900),
        Suggestion(keywords: ["teddy", "bear", "plush", "игрушк", "мишк", "медвед", "плюш"], emoji: "🧸", value: 1500),
        Suggestion(keywords: ["chocolate", "candy", "sweets", "шокол", "конфет", "сладост"], emoji: "🍫", value: 700),
        Suggestion(keywords: ["wine", "вино", "вина"], emoji: "🍷", value: 1900),
        Suggestion(keywords: ["perfume", "духи", "парфюм"], emoji: "🌸", value: 3500),
        Suggestion(keywords: ["necklace", "ring", "jewel", "bracelet", "earring",
                              "кольц", "ожерель", "колье", "брасле", "серьг", "серёж", "украшен", "цепочк"], emoji: "💍", value: 6000),
        Suggestion(keywords: ["phone", "iphone", "телефон", "айфон", "смартфон"], emoji: "📱", value: 40000),
        Suggestion(keywords: ["headphone", "earbud", "airpod", "наушник"], emoji: "🎧", value: 5000),
        Suggestion(keywords: ["money", "cash", "envelope", "деньг", "купюр", "конверт", "налич"], emoji: "💸", value: 5000),
        Suggestion(keywords: ["card", "voucher", "ticket", "билет", "сертификат", "ваучер"], emoji: "🎟️", value: 3000),
        Suggestion(keywords: ["cake", "торт"], emoji: "🎂", value: 1200),
        Suggestion(keywords: ["plant", "pot", "растен", "горшк"], emoji: "🪴", value: 1200),
        Suggestion(keywords: ["mug", "cup", "coffee", "кружк", "чашк", "кофе"], emoji: "☕", value: 800),
        Suggestion(keywords: ["doll", "matryoshka", "кукл", "матрёшк", "матрешк"], emoji: "🪆", value: 1400),
        Suggestion(keywords: ["lego", "blocks", "лего", "конструктор"], emoji: "🧱", value: 4000),
        Suggestion(keywords: ["scarf", "шарф", "платок"], emoji: "🧣", value: 2200),
        Suggestion(keywords: ["candle", "свеч"], emoji: "🕯️", value: 1000),
        Suggestion(keywords: ["game", "console", "игра", "игров", "пристав", "консол"], emoji: "🎮", value: 5500),
        Suggestion(keywords: ["pizza", "пицц"], emoji: "🍕", value: 900),
        Suggestion(keywords: ["coffee beans", "tea", "чай"], emoji: "🍵", value: 700),
    ]

    init(context: NSManagedObjectContext) {
        self.context = context
        reload()

        // Onboarding shows only on the very first launch; afterwards go straight
        // into the app (the user already chose how to start).
        if UserDefaults.standard.bool(forKey: onboardedKey) { screen = .app }

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

    // MARK: - From → To direction

    /// True when `id` is a household member (includes "you").
    func isHousehold(_ id: String?) -> Bool {
        guard let id else { return false }
        return members.contains { $0.id == id }
    }

    /// Display name for any entity id (household member or outside person).
    func anyName(_ id: String) -> String {
        members.first { $0.id == id }?.name ?? people.first { $0.id == id }?.name ?? id
    }

    /// Received vs Given derived from the From → To pickers, from the user's
    /// household perspective: value coming *in* to the household is Received,
    /// value going *out* is Given. Defaults to Received until a side is chosen.
    var addFlow: Flow {
        let fromHH = isHousehold(add.fromId)
        let toHH = isHousehold(add.toId)
        if toHH && !fromHH { return .received }
        if fromHH && !toHH { return .given }
        if add.fromId == "you" { return .given }
        if add.toId == "you" { return .received }
        return .received
    }

    /// "Paid by you" is always offered: whoever the giver or receiver is, the app
    /// user may have footed the bill and wants to count it as their own spending.
    var showPaidToggle: Bool { true }

    /// Effective emoji shown in the Add hero: chosen → AI guess → keyword → gift.
    func effEmoji(_ a: AddForm) -> String {
        if let e = a.emoji { return e }
        if let e = a.aiEmoji { return e }
        return a.name.trimmingCharacters(in: .whitespaces).isEmpty ? "🎁" : suggest(a.name).emoji
    }

    /// Estimated value shown while the user hasn't typed one: AI guess → keyword.
    func effValue(_ a: AddForm) -> Double {
        a.aiValue ?? suggest(a.name).value
    }

    // MARK: - On-device enrichment

    /// Update the draft name and (debounced) ask the on-device model for a better
    /// emoji + price. Stale AI guesses are cleared immediately so the keyword
    /// heuristic fills the gap until the model answers.
    func setName(_ s: String) {
        add.name = s
        add.aiEmoji = nil
        add.aiValue = nil
        scheduleEnrichment(for: s)
    }

    private func scheduleEnrichment(for name: String) {
        aiTask?.cancel()
        aiLoading = false
        let trimmed = name.trimmingCharacters(in: .whitespacesAndNewlines)
        guard trimmed.count >= 2 else { return }
        // No on-device model on this device (older hardware, Apple Intelligence
        // off, model not downloaded) → keep the instant keyword heuristic and
        // don't show a spinner that would never resolve.
        guard GiftParser.isAvailable else { return }
        aiTask = Task { @MainActor [weak self] in
            try? await Task.sleep(nanoseconds: 600_000_000)   // debounce typing
            guard let self, !Task.isCancelled else { return }
            guard self.add.name.trimmingCharacters(in: .whitespacesAndNewlines) == trimmed else { return }
            self.aiLoading = true
            let result = await GiftParser.parse(trimmed)
            guard !Task.isCancelled,
                  self.add.name.trimmingCharacters(in: .whitespacesAndNewlines) == trimmed else {
                self.aiLoading = false
                return
            }
            if let result {
                self.add.aiEmoji = result.emoji
                if result.value > 0 { self.add.aiValue = result.value }
            }
            self.aiLoading = false
        }
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

    /// Display name for any entity id, whether a household member or an outsider.
    func entityName(_ id: String) -> String {
        members.first { $0.id == id }?.name ?? people.first { $0.id == id }?.name ?? id
    }

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

    /// Subtitle shown under a gift row — always "giver → receiver", regardless of
    /// direction. Received: outside person → household member. Given: household
    /// member → outside person.
    func giftSubtitle(_ g: Gift) -> String {
        let fromName = g.flow == .received ? personName(g.personId) : memberName(g.memberId)
        let toName   = g.flow == .received ? memberName(g.memberId) : personName(g.personId)
        return "\(fromName)  →  \(toName)"
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
            .sorted(by: Gift.newestFirst)
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
    func enterApp() {
        UserDefaults.standard.set(true, forKey: onboardedKey)
        screen = .app
    }

    func setTab(_ t: Tab) { tab = t; detailId = nil }
    func openDetail(_ id: String) { withAnimation(.easeOut(duration: 0.26)) { detailId = id; detailFlow = .received } }
    func closeDetail() { withAnimation(.easeOut(duration: 0.2)) { detailId = nil } }
    func setDetailFlow(_ f: Flow) { withAnimation(.easeOut(duration: 0.18)) { detailFlow = f } }
    func openSettings() { showSettings = true }
    func closeSettings() { showSettings = false }
    func openSheet() { aiTask?.cancel(); aiLoading = false; editingGiftId = nil; add = blankAdd(); sheetOpen = true }
    func closeSheet() { aiTask?.cancel(); aiLoading = false; sheetOpen = false; picker = nil; editingGiftId = nil }

    /// Open the Add sheet pre-filled to edit an existing gift.
    func openEditSheet(_ g: Gift) {
        aiTask?.cancel()
        aiLoading = false
        editingGiftId = g.id
        add = formFrom(g)
        sheetOpen = true
    }

    /// Build a draft form from a saved gift (the inverse of `saveGift`).
    /// Received: from = the outside person, to = the household member.
    /// Given:    from = the household member, to = the outside person.
    func formFrom(_ g: Gift) -> AddForm {
        var f = AddForm()
        f.name = g.name
        f.emoji = g.emoji
        f.value = Int(g.value)
        f.valueTouched = true
        if g.flow == .received {
            f.fromId = g.personId
            f.toId = g.memberId
        } else {
            f.fromId = g.memberId
            f.toId = g.personId
        }
        f.paidByYou = g.paidByYou
        f.celebration = g.celebration
        f.date = g.date
        return f
    }

    /// "You" is the household anchor and can never be deleted.
    func canDeletePerson(_ id: String) -> Bool { id != "you" }

    /// How many gifts would be removed along with this person (those they gave or
    /// received) — used to warn before an irreversible delete.
    func giftsCountInvolving(_ id: String) -> Int {
        gifts.filter { $0.personId == id || $0.memberId == id }.count
    }

    /// Delete a person and every gift they gave or received. Irreversible.
    func deletePerson(_ id: String) {
        guard canDeletePerson(id) else { return }
        // Remove their gifts explicitly — the relationship rule only nullifies.
        let giftReq = CDGift.fetchRequest()
        giftReq.predicate = NSPredicate(format: "person.id == %@ OR member.id == %@", id, id)
        for g in (try? context.fetch(giftReq)) ?? [] { context.delete(g) }

        let personReq = CDPerson.fetchRequest()
        personReq.predicate = NSPredicate(format: "id == %@", id)
        personReq.fetchLimit = 1
        if let p = try? context.fetch(personReq).first { context.delete(p) }

        do { try context.save() } catch { context.rollback() }
        reload()
    }

    /// Rename a person, keeping names unique. No-op if blank or already taken by
    /// someone else.
    func renamePerson(_ id: String, to newName: String) {
        let v = newName.trimmingCharacters(in: .whitespaces)
        guard !v.isEmpty else { return }
        if let other = existingEntityId(named: v), other != id { return }   // name taken
        let req = CDPerson.fetchRequest()
        req.predicate = NSPredicate(format: "id == %@", id)
        req.fetchLimit = 1
        if let p = try? context.fetch(req).first {
            p.name = v
            do { try context.save() } catch { context.rollback() }
            reload()
        }
    }

    /// Delete a saved gift and refresh.
    func deleteGift(_ id: String) {
        let req = CDGift.fetchRequest()
        req.predicate = NSPredicate(format: "id == %@", id)
        req.fetchLimit = 1
        if let cd = try? context.fetch(req).first {
            context.delete(cd)
            do { try context.save() } catch { context.rollback() }
            reload()
        }
    }
    func setFilter(_ f: String) { withAnimation(.easeOut(duration: 0.18)) { filter = f } }

    // MARK: - Picker actions

    func openPicker(_ k: PickerKind) { picker = k }
    func closePicker() { picker = nil }

    func selectEmoji(_ e: String) { add.emoji = e; picker = nil }
    func selectFrom(_ id: String) {
        add.fromId = id
        // You as the giver → you paid for it by default (still user-editable).
        add.paidByYou = (id == "you")
        picker = nil
    }
    func selectTo(_ id: String) { add.toId = id; picker = nil }
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

    /// Id of an existing member/person whose name matches (case-insensitive).
    /// Names are unique across the whole roster.
    func existingEntityId(named name: String) -> String? {
        let v = name.trimmingCharacters(in: .whitespaces)
        if let m = members.first(where: { $0.name.caseInsensitiveCompare(v) == .orderedSame }) { return m.id }
        if let p = people.first(where: { $0.name.caseInsensitiveCompare(v) == .orderedSame }) { return p.id }
        return nil
    }

    /// Create a new person/member record and return its id (no selection side
    /// effects), so the From/To pickers can assign it to the right side. If a
    /// person with that name already exists, reuse it instead of duplicating.
    @discardableResult
    func createPerson(_ raw: String, isFamily: Bool) -> String? {
        let v = raw.trimmingCharacters(in: .whitespaces)
        guard !v.isEmpty else { return nil }
        if let existing = existingEntityId(named: v) { return existing }
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
        return id
    }

    /// Add a new outside person and put them on the From (giver) side.
    func addCustomFrom(_ raw: String) {
        if let id = createPerson(raw, isFamily: false) {
            add.fromId = id
            add.paidByYou = (id == "you")
            picker = nil
        }
    }

    /// Add a new outside person and put them on the To (receiver) side.
    func addCustomTo(_ raw: String) {
        if let id = createPerson(raw, isFamily: false) { add.toId = id; picker = nil }
    }

    // MARK: - Save

    func canSave() -> Bool {
        !add.name.trimmingCharacters(in: .whitespaces).isEmpty
            && add.fromId != nil && add.toId != nil && add.fromId != add.toId
    }

    func saveGift() {
        guard canSave(), let fromId = add.fromId, let toId = add.toId else { return }
        aiTask?.cancel()
        aiLoading = false
        let sug = suggest(add.name)
        let value = add.valueTouched ? Double(add.value ?? 0) : (add.aiValue ?? sug.value)
        let emoji = add.emoji ?? add.aiEmoji ?? sug.emoji

        // Map From/To onto the stored shape: `member` is the household side,
        // `person` is the outside party; `flow` is the household's perspective.
        let flow = addFlow
        let memberId = flow == .received ? toId : fromId
        let personId = flow == .received ? fromId : toId
        // You giving → you paid by definition; otherwise honour the toggle as set
        // (it's always available now, in any direction).
        let paid: Bool = (fromId == "you") || add.paidByYou

        // Editing reuses the existing record (keeping its id); otherwise create one.
        let gift: CDGift
        if let editId = editingGiftId, let existing = fetchGift(editId) {
            gift = existing
        } else {
            gift = CDGift(context: context)
            gift.id = "g\(Int(Date().timeIntervalSince1970 * 1000))"
        }
        gift.emoji = emoji
        gift.name = add.name.trimmingCharacters(in: .whitespaces)
        gift.flow = flow.rawValue
        gift.person = fetchPerson(personId)
        gift.member = fetchPerson(memberId)
        gift.paidByYou = paid
        gift.celebration = add.celebration ?? "Just because"
        gift.date = add.date
        gift.value = value

        do { try context.save() } catch { context.rollback() }

        reload()
        sheetOpen = false
        picker = nil
        // A fresh save jumps Home back to the unfiltered timeline; an edit leaves
        // the current tab/filter alone so the open detail screen stays put.
        if editingGiftId == nil {
            tab = .home
            filter = "all"
            detailId = nil
        }
        editingGiftId = nil
        add = blankAdd()
    }

    private func fetchPerson(_ id: String) -> CDPerson? {
        let req = CDPerson.fetchRequest()
        req.predicate = NSPredicate(format: "id == %@", id)
        req.fetchLimit = 1
        return try? context.fetch(req).first ?? nil
    }

    private func fetchGift(_ id: String) -> CDGift? {
        let req = CDGift.fetchRequest()
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

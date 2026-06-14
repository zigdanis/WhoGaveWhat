import SwiftUI
import CoreData

enum Screen { case onboarding, signin, app }
enum Tab: String { case home, people, insights }

/// Draft state for the "Add a gift" sheet.
struct AddForm {
    var flow: Flow = .received
    var name: String = ""
    var value: Int? = nil
    var valueTouched: Bool = false
    var personId: String? = nil
    var memberId: String = "you"
    var paidByYou: Bool = true
    var celebration: String = "Birthday"
    var date: String = "Today"   // Today / Yesterday / Earlier
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
    @Published var sheetOpen: Bool = false
    @Published var add = AddForm()

    // Data (loaded from Core Data)
    @Published var gifts: [Gift] = []
    @Published var members: [Member] = []
    @Published var people: [Person] = []

    private let context: NSManagedObjectContext

    // Static display copy (frozen "today" from the design)
    let greetingName = "Anton"
    let todayLabel = "Saturday, 14 June"
    let displayYear = "2026"

    let celebrations = ["Birthday", "New Year", "Wedding", "Anniversary",
                        "Graduation", "Housewarming", "Just because"]

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

    func monthLabel(_ date: Date) -> String {
        let comps = Calendar.current.dateComponents([.year, .month], from: date)
        let names = ["January", "February", "March", "April", "May", "June",
                     "July", "August", "September", "October", "November", "December"]
        let m = names[(comps.month ?? 1) - 1]
        let y = comps.year ?? 2026
        return y == 2026 ? m : "\(m) \(y)"
    }

    func shortDate(_ date: Date) -> String {
        let comps = Calendar.current.dateComponents([.month, .day], from: date)
        let names = ["Jan", "Feb", "Mar", "Apr", "May", "Jun",
                     "Jul", "Aug", "Sep", "Oct", "Nov", "Dec"]
        return "\(names[(comps.month ?? 1) - 1]) \(comps.day ?? 1)"
    }

    /// Subtitle shown under a gift row (received: from → member, given: to person · member).
    func giftSubtitle(_ g: Gift) -> String {
        if g.flow == .received {
            return "\(personName(g.personId))  →  \(memberName(g.memberId))"
        } else {
            let suffix = g.memberId != "you" ? "  ·  \(memberName(g.memberId))" : ""
            return "to \(personName(g.personId))\(suffix)"
        }
    }

    func giftMeta(_ g: Gift) -> String {
        "\(g.celebration)  ·  \(shortDate(g.date))"
    }

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

    // MARK: - Actions

    func blankAdd() -> AddForm { AddForm() }

    func onbNext() {
        if onbStep < 2 {
            onbStep += 1
        } else {
            screen = .signin
        }
    }
    func onbSkip() { screen = .signin }
    func enterApp() { screen = .app }

    func setTab(_ t: Tab) { tab = t; detailId = nil }
    func openDetail(_ id: String) { withAnimation(.easeOut(duration: 0.26)) { detailId = id } }
    func closeDetail() { withAnimation(.easeOut(duration: 0.2)) { detailId = nil } }
    func openSheet() { add = blankAdd(); withAnimation(.spring(response: 0.34, dampingFraction: 0.82)) { sheetOpen = true } }
    func closeSheet() { withAnimation(.easeOut(duration: 0.22)) { sheetOpen = false } }
    func setFilter(_ f: String) { filter = f }

    func canSave() -> Bool {
        !add.name.trimmingCharacters(in: .whitespaces).isEmpty && add.personId != nil
    }

    func saveGift() {
        guard canSave(), let personId = add.personId else { return }
        let sug = suggest(add.name)
        let value = add.valueTouched ? Double(add.value ?? 0) : sug.value

        let gift = CDGift(context: context)
        gift.id = "g\(Int(Date().timeIntervalSince1970 * 1000))"
        gift.emoji = sug.emoji
        gift.name = add.name.trimmingCharacters(in: .whitespaces)
        gift.flow = add.flow.rawValue
        gift.person = fetchPerson(personId)
        gift.member = fetchPerson(add.memberId)
        gift.paidByYou = add.flow == .given ? add.paidByYou : false
        gift.celebration = add.celebration
        gift.date = Self.today
        gift.value = value

        do {
            try context.save()
        } catch {
            context.rollback()
        }

        withAnimation(.easeOut(duration: 0.25)) {
            reload()
            sheetOpen = false
            tab = .home
            filter = "all"
            detailId = nil
        }
        add = blankAdd()
    }

    private func fetchPerson(_ id: String) -> CDPerson? {
        let req = CDPerson.fetchRequest()
        req.predicate = NSPredicate(format: "id == %@", id)
        req.fetchLimit = 1
        return try? context.fetch(req).first ?? nil
    }

    /// Frozen "today" used for newly added gifts, matching the design (14 Jun 2026).
    static let today: Date = {
        let f = DateFormatter()
        f.calendar = Calendar(identifier: .gregorian)
        f.timeZone = TimeZone(identifier: "UTC")
        f.dateFormat = "yyyy-MM-dd"
        return f.date(from: "2026-06-14") ?? Date()
    }()
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

import CoreData

/// Standard Core Data stack for Who Gave What. A fresh install starts EMPTY —
/// the user fills in their own people and gifts. Previews and tests opt into the
/// sample dataset via `seed:` so they have something to render / assert against.
struct PersistenceController {
    static let shared = PersistenceController()

    /// In-memory stack for previews / tests, seeded with the sample dataset.
    static let preview = PersistenceController(inMemory: true, seed: true)

    let container: NSPersistentContainer

    init(inMemory: Bool = false, seed: Bool = false) {
        container = NSPersistentContainer(name: "WhoGaveWhat")
        if inMemory {
            container.persistentStoreDescriptions.first?.url = URL(fileURLWithPath: "/dev/null")
        }
        container.loadPersistentStores { _, error in
            if let error = error as NSError? {
                fatalError("Core Data store failed to load: \(error), \(error.userInfo)")
            }
        }
        container.viewContext.automaticallyMergesChangesFromParent = true
        if seed {
            seedIfNeeded()
        } else if !inMemory {
            // Real install: no sample data, but ensure the "You" household member
            // exists so given/received gifts always have a coherent owner.
            ensureSelf()
        }
    }

    // MARK: - Self member (fresh install)

    /// Creates the single "You" family member if the store has no people yet, so
    /// the app starts empty-but-coherent (the household is just you, to begin).
    func ensureSelf() {
        let ctx = container.viewContext
        let count = (try? ctx.count(for: CDPerson.fetchRequest())) ?? 0
        guard count == 0 else { return }
        let you = CDPerson(context: ctx)
        you.id = "you"
        you.name = String(localized: "You")
        you.colorHex = 0x12161C
        you.isFamily = true
        you.sortIndex = 0
        try? ctx.save()
    }

    // MARK: - Seeding

    func seedIfNeeded() {
        let ctx = container.viewContext
        let count = (try? ctx.count(for: CDPerson.fetchRequest())) ?? 0
        guard count == 0 else { return }

        // Localize the sample dataset's display text so a fresh install reads in
        // the user's language. Occasions stay canonical English (see below) so
        // they group/translate consistently with the picker.
        func loc(_ s: String) -> String { String(localized: String.LocalizationValue(s)) }

        var byId: [String: CDPerson] = [:]
        func makePerson(_ id: String, _ name: String, _ color: Int64, family: Bool, _ idx: Int) {
            let p = CDPerson(context: ctx)
            p.id = id; p.name = name; p.colorHex = color; p.isFamily = family; p.sortIndex = Int64(idx)
            byId[id] = p
        }

        // Family members
        let members: [(String, String, Int64)] = [
            ("you", "You", 0x12161C), ("marina", "Marina", 0x12805C),
            ("sofia", "Sofia", 0x5B6573), ("alisa", "Alisa", 0x2F6FAE),
        ]
        for (i, m) in members.enumerated() { makePerson(m.0, loc(m.1), m.2, family: true, i) }

        // External people
        let people: [(String, String, Int64)] = [
            ("maria", "Aunt Maria", 0x12161C), ("pavel", "Grandpa Pavel", 0x12805C),
            ("igor", "Igor", 0x2F6FAE), ("olga", "Olga", 0x5B6573),
            ("lena", "Lena", 0x7A5CCB), ("dmitri", "Dmitri", 0x0E7C8C),
        ]
        for (i, p) in people.enumerated() { makePerson(p.0, loc(p.1), p.2, family: false, i) }

        // Gifts: (id, emoji, name, flow, personId, memberId, paid, celebration, iso, value)
        let gifts: [(String, String, String, String, String, String, Bool, String, String, Double)] = [
            ("g1", "💐", "Bouquet of roses", "received", "maria", "marina", false, "Birthday", "2026-05-12", 2000),
            ("g2", "⌚", "Wristwatch", "received", "pavel", "you", false, "Birthday", "2026-04-03", 9500),
            ("g3", "🧸", "Teddy bear", "received", "maria", "alisa", false, "New Year", "2026-01-02", 1500),
            ("g4", "📚", "Book set", "received", "igor", "you", false, "Graduation", "2026-03-20", 1800),
            ("g5", "🍷", "Bottle of wine", "received", "dmitri", "you", false, "Housewarming", "2026-02-15", 1900),
            ("g6", "🪴", "Potted plant", "received", "olga", "marina", false, "Just because", "2026-05-28", 1200),
            ("g7", "🪆", "Matryoshka doll", "received", "pavel", "sofia", false, "New Year", "2026-01-02", 1400),
            ("g8", "🧱", "Lego set", "given", "lena", "sofia", true, "Birthday", "2026-06-02", 1500),
            ("g9", "💍", "Silver necklace", "given", "maria", "marina", true, "Anniversary", "2026-02-14", 4500),
            ("g10", "🍫", "Box of chocolates", "given", "olga", "you", true, "Just because", "2026-05-28", 700),
            ("g11", "🍷", "Bottle of wine", "given", "igor", "you", true, "Birthday", "2026-04-18", 2100),
            ("g12", "🎟️", "Concert tickets", "given", "dmitri", "you", true, "Birthday", "2026-03-09", 3000),
        ]
        let f = DateFormatter()
        f.calendar = Calendar(identifier: .gregorian)
        f.timeZone = TimeZone(identifier: "UTC")
        f.dateFormat = "yyyy-MM-dd"

        for g in gifts {
            let gift = CDGift(context: ctx)
            gift.id = g.0; gift.emoji = g.1; gift.name = loc(g.2); gift.flow = g.3
            gift.person = byId[g.4]; gift.member = byId[g.5]
            gift.paidByYou = g.6; gift.celebration = g.7
            gift.date = f.date(from: g.8); gift.value = g.9
        }

        try? ctx.save()
    }
}

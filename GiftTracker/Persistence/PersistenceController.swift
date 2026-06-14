import CoreData

/// Standard Core Data stack for Gift Tracker, plus first-run seeding so the
/// timeline isn't empty on a fresh install.
struct PersistenceController {
    static let shared = PersistenceController()

    /// In-memory stack for previews / tests.
    static let preview: PersistenceController = {
        let controller = PersistenceController(inMemory: true)
        controller.seedIfNeeded()
        return controller
    }()

    let container: NSPersistentContainer

    init(inMemory: Bool = false) {
        container = NSPersistentContainer(name: "GiftTracker")
        if inMemory {
            container.persistentStoreDescriptions.first?.url = URL(fileURLWithPath: "/dev/null")
        }
        container.loadPersistentStores { _, error in
            if let error = error as NSError? {
                fatalError("Core Data store failed to load: \(error), \(error.userInfo)")
            }
        }
        container.viewContext.automaticallyMergesChangesFromParent = true
        seedIfNeeded()
    }

    // MARK: - Seeding

    func seedIfNeeded() {
        let ctx = container.viewContext
        let count = (try? ctx.count(for: CDPerson.fetchRequest())) ?? 0
        guard count == 0 else { return }

        var byId: [String: CDPerson] = [:]
        func makePerson(_ id: String, _ name: String, _ color: Int64, family: Bool, _ idx: Int) {
            let p = CDPerson(context: ctx)
            p.id = id; p.name = name; p.colorHex = color; p.isFamily = family; p.sortIndex = Int64(idx)
            byId[id] = p
        }

        // Family members
        let members: [(String, String, Int64)] = [
            ("you", "You", 0xBE6A4D), ("marina", "Marina", 0x6E8E66),
            ("sofia", "Sofia", 0xC79A45), ("alisa", "Alisa", 0x7E96B4),
        ]
        for (i, m) in members.enumerated() { makePerson(m.0, m.1, m.2, family: true, i) }

        // External people
        let people: [(String, String, Int64)] = [
            ("maria", "Aunt Maria", 0xBE6A4D), ("pavel", "Grandpa Pavel", 0x6E8E66),
            ("igor", "Igor", 0x7E96B4), ("olga", "Olga", 0xC79A45),
            ("lena", "Lena", 0xB07CA8), ("dmitri", "Dmitri", 0x5E9B8C),
        ]
        for (i, p) in people.enumerated() { makePerson(p.0, p.1, p.2, family: false, i) }

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
            gift.id = g.0; gift.emoji = g.1; gift.name = g.2; gift.flow = g.3
            gift.person = byId[g.4]; gift.member = byId[g.5]
            gift.paidByYou = g.6; gift.celebration = g.7
            gift.date = f.date(from: g.8); gift.value = g.9
        }

        try? ctx.save()
    }
}

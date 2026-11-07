#if DEBUG
    import Foundation

    /// Debug-only verification switch for the save and delete error states. `KS_FAIL_SAVE=N` fails the
    /// next N gift saves and `KS_FAIL_DELETE=N` the next N gift or person deletions; later attempts go
    /// through, so a retry can be shown too. Release builds do not contain this code.
    @MainActor
    final class WriteFailureInjection {
        private var remainingSaves: Int
        private var remainingDeletes: Int

        init(launchEnvironment: [String: String]) {
            remainingSaves = max(0, Int(launchEnvironment["KS_FAIL_SAVE"] ?? "") ?? 0)
            remainingDeletes = max(0, Int(launchEnvironment["KS_FAIL_DELETE"] ?? "") ?? 0)
        }

        var isActive: Bool { remainingSaves > 0 || remainingDeletes > 0 }

        /// Wraps the gateways only when a failure was asked for.
        func wrap(gifts: GiftGateway, people: PeopleGateway) -> (GiftGateway, PeopleGateway) {
            guard isActive else { return (gifts, people) }
            return (
                FailureInjectingGiftGateway(base: gifts, injection: self),
                FailureInjectingPeopleGateway(base: people, injection: self)
            )
        }

        fileprivate func failSave() throws {
            guard remainingSaves > 0 else { return }
            remainingSaves -= 1
            throw InjectedWriteFailure.save
        }

        fileprivate func failDelete() throws {
            guard remainingDeletes > 0 else { return }
            remainingDeletes -= 1
            throw InjectedWriteFailure.delete
        }
    }

    /// Carries no user data, like a real failure after sanitizing.
    enum InjectedWriteFailure: Error {
        case save
        case delete
    }

    @MainActor
    private final class FailureInjectingGiftGateway: GiftGateway {
        private let base: GiftGateway
        private let injection: WriteFailureInjection

        init(base: GiftGateway, injection: WriteFailureInjection) {
            self.base = base
            self.injection = injection
        }

        func loadGifts() throws -> [Gift] { try base.loadGifts() }

        func save(_ gift: Gift) throws {
            try injection.failSave()
            try base.save(gift)
        }

        func deleteGift(id: String) throws {
            try injection.failDelete()
            try base.deleteGift(id: id)
        }
    }

    @MainActor
    private final class FailureInjectingPeopleGateway: PeopleGateway {
        private let base: PeopleGateway
        private let injection: WriteFailureInjection

        init(base: PeopleGateway, injection: WriteFailureInjection) {
            self.base = base
            self.injection = injection
        }

        func loadPeople() throws -> PeopleSnapshot { try base.loadPeople() }

        func createPerson(id: String, name: String, colorHex: UInt, sortIndex: Int) throws {
            try base.createPerson(id: id, name: name, colorHex: colorHex, sortIndex: sortIndex)
        }

        func renamePerson(id: String, name: String) throws {
            try base.renamePerson(id: id, name: name)
        }

        func updatePerson(id: String, name: String, imageData: Data?) throws {
            try base.updatePerson(id: id, name: name, imageData: imageData)
        }

        func deletePerson(id: String) throws {
            try injection.failDelete()
            try base.deletePerson(id: id)
        }
    }
#endif

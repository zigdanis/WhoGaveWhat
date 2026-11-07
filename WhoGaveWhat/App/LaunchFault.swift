#if DEBUG
    import Foundation

    /// Debug-only verification launches that make the store fail once, so the recovery screens can be
    /// walked on a simulator without touching the data there. `KS_STORE_FAULT=open` fails the first attempt
    /// to open the store, `load` the first gifts fetch and `people` the first people fetch (with the gifts
    /// already fetched); the next attempt works. A launcher that cannot set the environment passes
    /// `-KS_STORE_FAULT open` as launch arguments instead. Release builds compile none of this, so the
    /// setting does nothing there, and like every `KS_` launch it keeps monitoring off.
    struct LaunchFault {
        enum Kind: String {
            case open
            case load
            case people
        }

        struct InjectedError: Error {}

        let kind: Kind

        init?(
            environment: [String: String] = ProcessInfo.processInfo.environment,
            arguments: [String] = ProcessInfo.processInfo.arguments
        ) {
            let flag = arguments.firstIndex(of: "-KS_STORE_FAULT").flatMap { index in
                arguments.indices.contains(index + 1) ? arguments[index + 1] : nil
            }
            guard let kind = (environment["KS_STORE_FAULT"] ?? flag).flatMap(Kind.init(rawValue:)) else { return nil }
            self.kind = kind
        }

        @MainActor
        func wrapOpen(_ open: @escaping () throws -> SwiftDataStore) -> () throws -> SwiftDataStore {
            guard kind == .open else { return open }
            let once = FailOnce()
            return {
                try once.check()
                return try open()
            }
        }

        @MainActor
        func wrap(_ gateway: GiftGateway) -> GiftGateway {
            kind == .load ? FailingOnceGiftGateway(base: gateway) : gateway
        }

        @MainActor
        func wrap(_ gateway: PeopleGateway) -> PeopleGateway {
            kind == .people ? FailingOncePeopleGateway(base: gateway) : gateway
        }
    }

    @MainActor
    private final class FailOnce {
        private var hasFailed = false

        func check() throws {
            guard !hasFailed else { return }
            hasFailed = true
            throw LaunchFault.InjectedError()
        }
    }

    @MainActor
    private final class FailingOnceGiftGateway: GiftGateway {
        private let base: GiftGateway
        private let once = FailOnce()

        init(base: GiftGateway) { self.base = base }

        func loadGifts() throws -> [Gift] {
            try once.check()
            return try base.loadGifts()
        }
        func save(_ gift: Gift) throws { try base.save(gift) }
        func deleteGift(id: String) throws { try base.deleteGift(id: id) }
    }

    @MainActor
    private final class FailingOncePeopleGateway: PeopleGateway {
        private let base: PeopleGateway
        private let once = FailOnce()

        init(base: PeopleGateway) { self.base = base }

        func loadPeople() throws -> PeopleSnapshot {
            try once.check()
            return try base.loadPeople()
        }
        func createPerson(id: String, name: String, colorHex: UInt, sortIndex: Int) throws {
            try base.createPerson(id: id, name: name, colorHex: colorHex, sortIndex: sortIndex)
        }
        func renamePerson(id: String, name: String) throws { try base.renamePerson(id: id, name: name) }
        func updatePerson(id: String, name: String, imageData: Data?) throws {
            try base.updatePerson(id: id, name: name, imageData: imageData)
        }
        func deletePerson(id: String) throws { try base.deletePerson(id: id) }
    }
#endif

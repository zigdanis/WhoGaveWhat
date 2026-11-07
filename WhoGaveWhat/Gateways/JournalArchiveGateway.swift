import Foundation

/// Reads the whole journal for a backup and adds a backup's records to it.
@MainActor
protocol JournalArchiveGateway: AnyObject {
    /// Every stored person (in People order, with photos) and every gift, straight from the store.
    func loadArchive() throws -> (people: [DataBackup.Person], gifts: [DataBackup.Gift])
    /// Adds the backup's people and gifts that the journal does not have yet, in one save, and changes
    /// nothing else: a record already in the journal wins over the backup's copy. When the save fails,
    /// nothing is added and the error is thrown.
    @discardableResult
    func restore(_ backup: DataBackup) throws -> DataRestoreSummary
}

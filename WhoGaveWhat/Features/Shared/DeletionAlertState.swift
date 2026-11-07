/// What a screen does around a confirmed deletion: it leaves only once the record is gone, and otherwise
/// stays where it is and shows that nothing was deleted.
struct DeletionAlertState: Equatable {
    var isShowingError = false

    /// Runs the deletion and says whether the screen may leave; after a failure it shows the error instead.
    @MainActor
    mutating func confirm(_ delete: () -> DeletionResult) -> Bool {
        let deleted = delete() == .deleted
        isShowingError = !deleted
        return deleted
    }
}

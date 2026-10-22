/// A person picker on the Insights screen; each one remembers its own recent picks.
enum InsightsPickerSlot: String, CaseIterable, Identifiable, Sendable {
    case subject
    case compareA
    case compareB

    var id: Self { self }
}

enum AddGiftPicker: Identifiable, Hashable {
    case from
    case to
    case occasion
    case emoji
    case date

    var id: Self { self }
}

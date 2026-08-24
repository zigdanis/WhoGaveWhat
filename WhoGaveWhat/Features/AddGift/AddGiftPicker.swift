enum AddGiftPicker: Identifiable {
    case from
    case to
    case celeb
    case emoji
    case date

    var id: Self { self }
}

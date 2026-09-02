struct Occasion: Identifiable, Hashable {
    let name: String
    var id: String { name }
}

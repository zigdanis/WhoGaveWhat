import Foundation

@MainActor
struct CreatePersonUseCase {
    let gateway: PeopleGateway

    private let palette: [UInt] = [0x7A5CCB, 0x0E7C8C, 0x2F6FAE, 0xC26B2D, 0x12805C, 0x5B6573]

    func execute(name: String, isFamily: Bool, current: PeopleSnapshot) throws -> String? {
        let trimmedName = name.trimmingCharacters(in: .whitespaces)
        guard !trimmedName.isEmpty else { return nil }
        if let existingID = existingID(named: trimmedName, in: current) {
            return existingID
        }

        let id = (isFamily ? "m" : "p") + String(Int(Date().timeIntervalSince1970 * 1_000))
        let role: PersonRole = isFamily ? .household : .contact
        let count = current.people.filter { $0.role == role }.count
        try gateway.createPerson(
            id: id,
            name: trimmedName,
            colorHex: palette.randomElement() ?? 0x5B6573,
            role: role,
            sortIndex: count + 100
        )
        return id
    }

    func existingID(named name: String, in current: PeopleSnapshot) -> String? {
        let trimmedName = name.trimmingCharacters(in: .whitespaces)
        return current.people.first(where: {
            $0.name.caseInsensitiveCompare(trimmedName) == .orderedSame
        })?.id
    }
}

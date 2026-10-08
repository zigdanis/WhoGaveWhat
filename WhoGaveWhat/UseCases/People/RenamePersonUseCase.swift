import Foundation

@MainActor
struct RenamePersonUseCase {
    let gateway: PeopleGateway
    let createPerson: CreatePersonUseCase

    func execute(id: String, newName: String, current: PeopleSnapshot) throws {
        let trimmedName = newName.trimmingCharacters(in: .whitespaces)
        guard !trimmedName.isEmpty else { return }
        if let existingID = createPerson.existingID(named: trimmedName, in: current), existingID != id {
            throw PersonUpdateError.duplicateName
        }
        try gateway.renamePerson(id: id, name: trimmedName)
    }

    func update(id: String, newName: String, imageData: Data?, current: PeopleSnapshot) throws {
        let trimmedName = newName.trimmingCharacters(in: .whitespaces)
        guard !trimmedName.isEmpty else { return }
        if let existingID = createPerson.existingID(named: trimmedName, in: current), existingID != id {
            throw PersonUpdateError.duplicateName
        }
        try gateway.updatePerson(id: id, name: trimmedName, imageData: imageData)
    }
}

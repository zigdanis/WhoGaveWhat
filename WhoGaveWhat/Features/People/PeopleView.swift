import SwiftUI

/// Everyone you track as one flat alphabetical list, as a native `List` so a person can be swiped away.
/// Deleting a person is irreversible and also wipes every gift they gave or
/// received, so it's gated behind a big, hard-to-miss warning.
struct PeopleView: View {
    let composition: AppComposition
    /// Person id awaiting the irreversible delete warning (set by the swipe).
    @State private var pendingDelete: String?
    @State private var isAddingPerson = false

    var body: some View {
        List {
            ForEach(sortedPeople) { person in
                personRow(person)
            }
        }
        .listStyle(.insetGrouped)
        .scrollContentBackground(.hidden)
        .scrollEdgeEffectStyle(.soft, for: .bottom)
        .background(Color.appBackground)
        .safeAreaInset(edge: .bottom) {
            AddPersonFloatingAction {
                isAddingPerson = true
            }
        }
        .sheet(isPresented: $isAddingPerson) {
            PersonEditorSheet(
                title: "Add person",
                initialName: "",
                showsPhoto: false,
                onCancel: { isAddingPerson = false },
                onSave: { name, _ in
                    guard composition.createPerson(name: name) != nil else {
                        throw CocoaError(.validationMissingMandatoryProperty)
                    }
                    isAddingPerson = false
                }
            )
        }
        .confirmationDialog(
            personDeleteTitle,
            isPresented: deleteBinding,
            titleVisibility: .visible,
            presenting: pendingDelete
        ) { id in
            Button(
                deletePersonActionLabel(giftsCount(involving: id)),
                role: .destructive
            ) {
                composition.deletePerson(id: id)
                pendingDelete = nil
            }
            Button("Cancel", role: .cancel) { pendingDelete = nil }
        } message: { id in
            Text(
                personDeleteMessage(
                    composition.data.entityName(id),
                    count: giftsCount(involving: id)))
        }
    }

    private var sortedPeople: [Person] {
        composition.data.people.sorted {
            $0.name.localizedStandardCompare($1.name) == .orderedAscending
        }
    }

    private func personRow(_ person: Person) -> some View {
        NavigationLink(value: person.id) {
            PersonRow(
                entityId: person.id, name: person.name, color: person.color,
                imageData: person.imageData,
                isSelf: composition.data.isSelf(person.id),
                gifts: gifts(for: person.id),
                currencyCode: composition.currencyCode)
        }
        .listRowInsets(EdgeInsets(top: 0, leading: 14, bottom: 0, trailing: 12))
        .swipeActions(edge: .trailing, allowsFullSwipe: false) {
            if composition.deletePersonUseCase.canDelete(id: person.id) {
                Button(role: .destructive) {
                    pendingDelete = person.id
                } label: {
                    Image(systemName: "trash")
                }
                .accessibilityLabel("Delete")
            }
        }
    }

    private var deleteBinding: Binding<Bool> {
        Binding(
            get: { pendingDelete != nil },
            set: { if !$0 { pendingDelete = nil } })
    }

    private var personDeleteTitle: String {
        guard let id = pendingDelete else { return "" }
        return String(format: NSLocalizedString("Delete %@?", comment: ""), composition.data.entityName(id))
    }

    private func personDeleteMessage(_ name: String, count: Int) -> String {
        let fmt = NSLocalizedString(
            "This permanently deletes %1$@ and all %2$lld of their gifts. This cannot be undone.",
            comment: "")
        return String(format: fmt, name, count)
    }

    private func deletePersonActionLabel(_ count: Int) -> String {
        let fmt = NSLocalizedString("Delete person and %lld gifts", comment: "")
        return String(format: fmt, count)
    }

    private func gifts(for id: String) -> [Gift] {
        composition.loadPersonGifts.execute(
            personID: id,
            gifts: composition.data.gifts
        )
    }

    private func giftsCount(involving id: String) -> Int {
        composition.data.gifts.filter { $0.giverID == id || $0.recipientID == id }.count
    }
}

private struct AddPersonFloatingAction: View {
    let action: () -> Void

    var body: some View {
        FloatingActionButton(title: "Add person", systemImage: "plus", action: action)
            .accessibilityLabel("Add person")
            .accessibilityIdentifier("people.add-person")
    }
}

struct PersonRow: View {
    let entityId: String
    let name: String
    let color: Color
    let imageData: Data?
    let isSelf: Bool
    let gifts: [Gift]
    let currencyCode: String

    var body: some View {
        let r = gifts.filter {
            GiftDirectionResolver.resolve(
                giverID: $0.giverID,
                recipientID: $0.recipientID,
                relativeTo: entityId
            ) == .received
        }.count
        let gv = gifts.filter {
            GiftDirectionResolver.resolve(
                giverID: $0.giverID,
                recipientID: $0.recipientID,
                relativeTo: entityId
            ) == .given
        }.count

        HStack(spacing: 12) {
            AvatarView(initials: name.initials, color: color, size: .regular, imageData: imageData)
            VStack(alignment: .leading, spacing: 2) {
                HStack(spacing: 6) {
                    Text(name).font(Font.app(16, .semibold)).foregroundColor(Color.textPrimary)
                        .fixedSize(horizontal: false, vertical: true)
                    if isSelf {
                        Text("You")
                            .font(Font.app(11, .semibold)).foregroundColor(Color.brand)
                            .padding(.horizontal, 7).padding(.vertical, 2)
                            .background(Capsule().fill(Color.receivedTint))
                            .fixedSize()
                            .accessibilityIdentifier("people.you-badge")
                    }
                }
                Text("\(r) received · \(gv) given")
                    .font(Font.app(13, .regular)).foregroundColor(Color.textSecondary)
                    .fixedSize(horizontal: false, vertical: true)
            }
            .frame(maxWidth: .infinity, alignment: .leading)
            Text(formattedCurrency(gifts.totalValue, code: currencyCode))
                .font(Font.app(15, .semibold, rounded: true)).foregroundColor(Color.textPrimary)
                .lineLimit(1)
                .layoutPriority(1)
        }
        .padding(.horizontal, 0).padding(.vertical, 13)
        .contentShape(Rectangle())
    }
}

import SwiftUI

/// Everyone you track, as a native `List` so a person can be swiped away.
/// Deleting a person is irreversible and also wipes every gift they gave or
/// received, so it's gated behind a big, hard-to-miss warning.
struct PeopleView: View {
    let composition: AppComposition
    /// Person id awaiting the irreversible delete warning (set by the swipe).
    @State private var pendingDelete: String?
    @State private var isAddingPerson = false

    var body: some View {
        List {
            section(
                header: "Your family",
                entities: composition.data.householdMembers.map { ($0.id, $0.name, $0.color) })
            section(
                header: "Friends & relatives",
                entities: composition.data.contacts.map { ($0.id, $0.name, $0.color) })
        }
        .listStyle(.insetGrouped)
        .scrollContentBackground(.hidden)
        .background(Color.bg)
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
                    guard composition.createPerson(name: name, isFamily: false) != nil else {
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

    @ViewBuilder
    private func section(header: String, entities: [(String, String, Color)]) -> some View {
        if !entities.isEmpty {
            Section {
                ForEach(entities, id: \.0) { e in
                    NavigationLink(value: e.0) {
                        PersonRow(
                            entityId: e.0, name: e.1, color: e.2,
                            imageData: composition.data.entityImageData(e.0),
                            gifts: gifts(for: e.0),
                            currencyCode: composition.currencyCode)
                    }
                    .listRowInsets(EdgeInsets(top: 0, leading: 14, bottom: 0, trailing: 12))
                    .swipeActions(edge: .trailing, allowsFullSwipe: false) {
                        if composition.deletePersonUseCase.canDelete(id: e.0) {
                            Button(role: .destructive) {
                                pendingDelete = e.0
                            } label: {
                                Image(systemName: "trash")
                            }
                            .accessibilityLabel("Delete")
                        }
                    }
                }
            } header: {
                Text(LocalizedStringKey(header))
                    .font(Font.app(13, .regular)).foregroundColor(Color.muted)
                    .textCase(nil)
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
        Button(action: action) {
            Label("Add person", systemImage: "plus")
                .font(Font.app(16, .semibold))
                .foregroundColor(.white)
                .padding(.horizontal, 22)
                .padding(.vertical, 13)
                .background(
                    RoundedRectangle(cornerRadius: DesignMetrics.cornerRadius, style: .continuous)
                        .fill(Color.ink)
                )
                .ksCardShadow(strong: true)
        }
        .buttonStyle(.plain)
        .padding(.bottom, 6)
        .accessibilityLabel("Add person")
        .accessibilityIdentifier("people.add-person")
    }
}

struct PersonRow: View {
    let entityId: String
    let name: String
    let color: Color
    let imageData: Data?
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
            AvatarView(initials: name.initials, color: color, size: 42, imageData: imageData)
            VStack(alignment: .leading, spacing: 2) {
                Text(name).font(Font.app(16, .semibold)).foregroundColor(Color.ink)
                Text("\(r) received · \(gv) given")
                    .font(Font.app(13, .regular)).foregroundColor(Color.muted3)
            }
            Spacer(minLength: 8)
            Text(formattedCurrency(gifts.totalValue, code: currencyCode))
                .font(Font.app(15, .semibold)).foregroundColor(Color.ink)
        }
        .padding(.horizontal, 0).padding(.vertical, 13)
        .contentShape(Rectangle())
    }
}

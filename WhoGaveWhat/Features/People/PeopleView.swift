import SwiftUI

/// Everyone you track, as a native `List` so a person can be swiped away (except
/// "you", the household anchor). Deleting a person is irreversible and also wipes
/// every gift they gave or received, so it's gated behind a big, hard-to-miss
/// warning that rises from the bottom.
struct PeopleView: View {
    let composition: AppComposition
    /// Person id awaiting the irreversible delete warning (set by the swipe).
    @State private var pendingDelete: String?

    var body: some View {
        List {
            section(header: "Your family",
                    entities: composition.data.members.map { ($0.id, $0.name, $0.color, true) })
            section(header: "Friends & relatives",
                    entities: composition.data.people.map { ($0.id, $0.name, $0.color, false) })
        }
        .listStyle(.insetGrouped)
        .scrollContentBackground(.hidden)
        .background(Color.bg)
        .floatingAddButton(composition: composition)
        .confirmationDialog(personDeleteTitle,
                            isPresented: deleteBinding,
                            titleVisibility: .visible,
                            presenting: pendingDelete) { id in
            Button(deletePersonActionLabel(giftsCount(involving: id)),
                   role: .destructive) {
                composition.deletePerson(id: id)
                pendingDelete = nil
            }
            Button("Cancel", role: .cancel) { pendingDelete = nil }
        } message: { id in
            Text(personDeleteMessage(composition.data.entityName(id),
                                     count: giftsCount(involving: id)))
        }
    }

    @ViewBuilder
    private func section(header: String, entities: [(String, String, Color, Bool)]) -> some View {
        if !entities.isEmpty {
            Section {
                ForEach(entities, id: \.0) { e in
                    NavigationLink(value: e.0) {
                        PersonRow(entityId: e.0, name: e.1, color: e.2,
                                  gifts: gifts(for: e.0, isMember: e.3))
                    }
                    .listRowInsets(EdgeInsets(top: 0, leading: 14, bottom: 0, trailing: 12))
                    // "You" is the household anchor — never deletable.
                    .swipeActions(edge: .trailing, allowsFullSwipe: false) {
                        if composition.deletePersonUseCase.canDelete(id: e.0) {
                            Button(role: .destructive) { pendingDelete = e.0 } label: {
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
        Binding(get: { pendingDelete != nil },
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

    private func gifts(for id: String, isMember: Bool) -> [Gift] {
        composition.loadPersonGifts.execute(
            personID: id,
            isHouseholdMember: isMember,
            gifts: composition.data.gifts
        )
    }

    private func giftsCount(involving id: String) -> Int {
        composition.data.gifts.filter { $0.personId == id || $0.memberId == id }.count
    }
}

struct PersonRow: View {
    let entityId: String
    let name: String
    let color: Color
    let gifts: [Gift]

    var body: some View {
        let r = gifts.filter { $0.flow == .received }.count
        let gv = gifts.filter { $0.flow == .given }.count

        HStack(spacing: 12) {
            AvatarView(initials: name.initials, color: color, size: 42)
            VStack(alignment: .leading, spacing: 2) {
                Text(name).font(Font.app(16, .semibold)).foregroundColor(Color.ink)
                Text("\(r) received · \(gv) given")
                    .font(Font.app(13, .regular)).foregroundColor(Color.muted3)
            }
            Spacer(minLength: 8)
            Text(rub(gifts.totalValue))
                .font(Font.app(15, .semibold)).foregroundColor(Color.ink)
            Chevron()
        }
        .padding(.horizontal, 0).padding(.vertical, 13)
        .contentShape(Rectangle())
    }
}

import SwiftUI

/// Everyone you track, as a native `List` so a person can be swiped away (except
/// "you", the household anchor). Deleting a person is irreversible and also wipes
/// every gift they gave or received, so it's gated behind a big, hard-to-miss
/// warning that rises from the bottom.
struct PeopleView: View {
    @EnvironmentObject var store: AppStore
    /// Person id awaiting the irreversible delete warning (set by the swipe).
    @State private var pendingDelete: String?

    var body: some View {
        List {
            section(header: "Your family",
                    entities: store.members.map { ($0.id, $0.name, $0.color, true) })
            section(header: "Friends & relatives",
                    entities: store.people.map { ($0.id, $0.name, $0.color, false) })
        }
        .listStyle(.insetGrouped)
        .scrollContentBackground(.hidden)
        .background(KS.bg)
        .floatingAddButton()
        .confirmationDialog(personDeleteTitle,
                            isPresented: deleteBinding,
                            titleVisibility: .visible,
                            presenting: pendingDelete) { id in
            Button(deletePersonActionLabel(store.giftsCountInvolving(id)),
                   role: .destructive) {
                store.deletePerson(id)
                pendingDelete = nil
            }
            Button("Cancel", role: .cancel) { pendingDelete = nil }
        } message: { id in
            Text(personDeleteMessage(store.entityName(id),
                                     count: store.giftsCountInvolving(id)))
        }
    }

    @ViewBuilder
    private func section(header: String, entities: [(String, String, Color, Bool)]) -> some View {
        if !entities.isEmpty {
            Section {
                ForEach(entities, id: \.0) { e in
                    NavigationLink(value: e.0) {
                        PersonRow(entityId: e.0, name: e.1, color: e.2, isMember: e.3)
                    }
                    .listRowInsets(EdgeInsets(top: 0, leading: 14, bottom: 0, trailing: 12))
                    // "You" is the household anchor — never deletable.
                    .swipeActions(edge: .trailing, allowsFullSwipe: false) {
                        if store.canDeletePerson(e.0) {
                            Button(role: .destructive) { pendingDelete = e.0 } label: {
                                Image(systemName: "trash")
                            }
                            .accessibilityLabel("Delete")
                        }
                    }
                }
            } header: {
                Text(LocalizedStringKey(header))
                    .font(KS.font(13, .regular)).foregroundColor(KS.muted)
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
        return String(format: NSLocalizedString("Delete %@?", comment: ""), store.entityName(id))
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
}

struct PersonRow: View {
    @EnvironmentObject var store: AppStore
    let entityId: String
    let name: String
    let color: Color
    let isMember: Bool

    var body: some View {
        let gs = store.gifts.filter { isMember ? $0.memberId == entityId : $0.personId == entityId }
        let r = gs.filter { $0.flow == .received }.count
        let gv = gs.filter { $0.flow == .given }.count

        HStack(spacing: 12) {
            AvatarView(initials: store.initials(name), color: color, size: 42)
            VStack(alignment: .leading, spacing: 2) {
                Text(name).font(KS.font(16, .semibold)).foregroundColor(KS.ink)
                Text("\(r) received · \(gv) given")
                    .font(KS.font(13, .regular)).foregroundColor(KS.muted3)
            }
            Spacer(minLength: 8)
            Text(rub(store.sum(gs)))
                .font(KS.font(15, .semibold)).foregroundColor(KS.ink)
            Chevron()
        }
        .padding(.horizontal, 0).padding(.vertical, 13)
        .contentShape(Rectangle())
    }
}

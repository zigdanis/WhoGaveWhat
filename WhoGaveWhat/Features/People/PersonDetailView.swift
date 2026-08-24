import SwiftUI

/// A person's gift history. Built as a native `List` so its rows open / swipe-to-
/// delete exactly like Home, reusing `GiftRow` + `GiftDetailView`. The header
/// (avatar, per-side stats, All/Received/Given filter) rides as a quiet section.
struct PersonDetailView: View {
    @EnvironmentObject var store: AppStore
    @Environment(\.dismiss) private var dismiss
    let entityId: String
    @State private var filter: String = "all"
    /// Gift awaiting delete confirmation (set by the swipe action).
    @State private var pendingDelete: Gift?
    /// Rename sheet state.
    @State private var renaming = false
    @State private var draftName = ""
    /// Whether the big "delete this person" warning is showing.
    @State private var confirmingPersonDelete = false

    private var filterOptions: [Segmented.Option] {
        [.init(key: "all", label: "All", accent: KS.ink),
         .init(key: "received", label: "Received", accent: KS.recv),
         .init(key: "given", label: "Given", accent: KS.ink)]
    }

    var body: some View {
        let isMember = store.isMember(entityId)
        let name = isMember ? store.memberName(entityId) : store.personName(entityId)
        let color = store.entityColor(entityId)
        let gs = store.gifts
            .filter { isMember ? $0.memberId == entityId : $0.personId == entityId }
            .sorted(by: Gift.newestFirst)
        let recv = gs.filter { $0.flow == .received }
        let given = gs.filter { $0.flow == .given }
        let list = filter == "received" ? recv : (filter == "given" ? given : gs)

        List {
            // Header + stats + filter — quiet rows, no separators.
            Section {
                VStack(spacing: 0) {
                    AvatarView(initials: store.initials(name), color: color, size: 76)
                    Text(name).font(KS.font(24, .bold)).tracking(-0.4).foregroundColor(KS.ink).padding(.top, 13)
                }
                .frame(maxWidth: .infinity)
                .padding(.top, 6)

                HStack(spacing: 10) {
                    statCard(arrow: "↙", label: "Received", color: KS.recv,
                             count: recv.count, value: store.sum(recv))
                    statCard(arrow: "↗", label: "Given", color: KS.ink,
                             count: given.count, value: store.sum(given))
                }
                .padding(.top, 18)

                Segmented(options: filterOptions, selected: filter) { key in
                    withAnimation(.easeOut(duration: 0.18)) { filter = key }
                }
                .padding(.top, 18)
            }
            .listRowInsets(EdgeInsets(top: 6, leading: 16, bottom: 8, trailing: 16))
            .listRowBackground(Color.clear)
            .listRowSeparator(.hidden)

            if list.isEmpty {
                Section {
                    Text(LocalizedStringKey(emptyText))
                        .font(KS.font(14, .regular)).foregroundColor(KS.muted4)
                        .frame(maxWidth: .infinity)
                        .padding(.vertical, 30)
                        .listRowBackground(Color.clear)
                        .listRowSeparator(.hidden)
                }
            } else {
                Section {
                    ForEach(list) { gift in
                        NavigationLink(value: gift) { GiftRow(gift: gift) }
                            .listRowInsets(EdgeInsets(top: 0, leading: 0, bottom: 0, trailing: 12))
                            .swipeActions(edge: .trailing, allowsFullSwipe: true) {
                                Button(role: .destructive) { pendingDelete = gift } label: {
                                    Image(systemName: "trash")
                                }
                                .accessibilityLabel("Delete")
                            }
                    }
                }
            }
        }
        .listStyle(.insetGrouped)
        .scrollContentBackground(.hidden)
        .background(KS.bg)
        .navigationTitle(name)
        .navigationBarTitleDisplayMode(.inline)
        .toolbar {
            if store.canDeletePerson(entityId) {
                ToolbarItem(placement: .topBarTrailing) {
                    Button {
                        draftName = name
                        renaming = true
                    } label: {
                        Image(systemName: "pencil")
                            .font(.system(size: 17, weight: .semibold))
                    }
                    .tint(KS.recv)
                    .accessibilityLabel("Edit name")
                }
            }
        }
        // Confirm deleting a single gift from the swipe.
        .confirmationDialog("Delete this gift?",
                            isPresented: giftDeleteBinding,
                            titleVisibility: .visible,
                            presenting: pendingDelete) { gift in
            Button("Delete", role: .destructive) {
                store.deleteGift(gift.id)
                pendingDelete = nil
            }
            Button("Cancel", role: .cancel) { pendingDelete = nil }
        }
        // Rename the person (with a Delete person option at the bottom).
        .sheet(isPresented: $renaming) {
            renameSheet(name: name, count: store.giftsCountInvolving(entityId))
        }
        // Big, hard-to-miss irreversible warning before deleting the person.
        .confirmationDialog(personDeleteTitle(name),
                            isPresented: $confirmingPersonDelete,
                            titleVisibility: .visible) {
            Button(deletePersonActionLabel(store.giftsCountInvolving(entityId)),
                   role: .destructive) {
                store.deletePerson(entityId)
                dismiss()
            }
            Button("Cancel", role: .cancel) { }
        } message: {
            Text(personDeleteMessage(name, count: store.giftsCountInvolving(entityId)))
        }
    }

    /// Drives the per-gift delete dialog off the optional pending gift.
    private var giftDeleteBinding: Binding<Bool> {
        Binding(get: { pendingDelete != nil },
                set: { if !$0 { pendingDelete = nil } })
    }

    // MARK: Rename + delete person

    @ViewBuilder
    private func renameSheet(name: String, count: Int) -> some View {
        NavigationStack {
            Form {
                Section {
                    TextField("Name", text: $draftName)
                        .font(KS.font(17, .regular))
                }
                Section {
                    Button(role: .destructive) {
                        renaming = false
                        // Let the sheet finish dismissing before the dialog rises.
                        confirmingPersonDelete = true
                    } label: {
                        HStack {
                            Image(systemName: "trash")
                            Text("Delete person")
                        }
                    }
                }
            }
            .navigationTitle("Edit name")
            .navigationBarTitleDisplayMode(.inline)
            .toolbar {
                ToolbarItem(placement: .topBarLeading) {
                    Button("Cancel") { renaming = false }
                }
                ToolbarItem(placement: .topBarTrailing) {
                    Button("Save") {
                        store.renamePerson(entityId, to: draftName)
                        renaming = false
                    }
                    .fontWeight(.semibold)
                    .disabled(draftName.trimmingCharacters(in: .whitespaces).isEmpty)
                }
            }
        }
        .presentationDetents([.height(260)])
    }

    private func personDeleteTitle(_ name: String) -> String {
        String(format: NSLocalizedString("Delete %@?", comment: ""), name)
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

    private var emptyText: String {
        switch filter {
        case "given": return "No gifts given yet."
        case "received": return "No gifts received yet."
        default: return "No gifts yet"
        }
    }

    private func statCard(arrow: String, label: String, color: Color, count: Int, value: Double) -> some View {
        Card {
            VStack(alignment: .leading, spacing: 0) {
                HStack(spacing: 6) {
                    Text(arrow).font(KS.font(15, .semibold))
                    Text(LocalizedStringKey(label)).font(KS.font(13, .semibold))
                }
                .foregroundColor(color)
                Text("\(count)").font(KS.font(25, .bold)).tracking(-0.4).foregroundColor(KS.ink).padding(.top, 9)
                Text("gifts · \(rub(value))").font(KS.font(13, .regular)).foregroundColor(KS.muted).padding(.top, 2)
            }
            .frame(maxWidth: .infinity, alignment: .leading)
            .padding(15)
        }
    }
}

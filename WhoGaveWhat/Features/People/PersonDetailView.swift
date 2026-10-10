import SwiftUI

/// A person's gift history. Built as a native `List` so its rows open / swipe-to-
/// delete exactly like Home, reusing `GiftRow` + `GiftDetailView`. The header
/// (avatar, per-side stats, All/Received/Given filter) rides as a quiet section.
struct PersonDetailView: View {
    @Environment(\.dismiss) private var dismiss
    let entityId: String
    let composition: AppComposition
    @State private var filter: String = "all"
    /// Gift awaiting delete confirmation (set by the swipe action).
    @State private var pendingDelete: Gift?
    /// Rename sheet state.
    @State private var renaming = false

    private var filterOptions: [Segmented.Option] {
        [
            .init(key: "all", label: "All", accent: Color.ink),
            .init(key: "received", label: "Received", accent: Color.recv),
            .init(key: "given", label: "Given", accent: Color.ink)
        ]
    }

    var body: some View {
        let name = composition.data.entityName(entityId)
        let color = Color(hex: composition.data.entityColorHex(entityId))
        let gs = composition.loadPersonGifts.execute(
            personID: entityId,
            gifts: composition.data.gifts
        )
        let recv = gs.filter {
            GiftDirectionResolver.resolve(
                giverID: $0.giverID,
                recipientID: $0.recipientID,
                relativeTo: entityId
            ) == .received
        }
        let given = gs.filter {
            GiftDirectionResolver.resolve(
                giverID: $0.giverID,
                recipientID: $0.recipientID,
                relativeTo: entityId
            ) == .given
        }
        let list = filter == "received" ? recv : (filter == "given" ? given : gs)

        List {
            // Header + stats + filter — quiet rows, no separators.
            Section {
                VStack(spacing: 0) {
                    AvatarView(initials: "", color: color, size: 76, imageData: composition.data.entityImageData(entityId))
                }
                .frame(maxWidth: .infinity)
                .padding(.top, 6)
                .accessibilityIdentifier("person-detail.hero")

                HStack(spacing: 10) {
                    statCard(
                        arrow: "↙", label: "Received", color: Color.recv,
                        count: recv.count, value: recv.totalValue)
                    statCard(
                        arrow: "↗", label: "Given", color: Color.ink,
                        count: given.count, value: given.totalValue)
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
                        .font(Font.app(14, .regular)).foregroundColor(Color.muted4)
                        .frame(maxWidth: .infinity)
                        .padding(.vertical, 30)
                        .listRowBackground(Color.clear)
                        .listRowSeparator(.hidden)
                }
            } else {
                Section {
                    ForEach(list) { gift in
                        NavigationLink(value: gift) {
                            GiftRow(
                                gift: gift,
                                subtitle: composition.data.giftSubtitle(gift),
                                dateLabel: gift.date.giftShortLabel(),
                                currencyCode: composition.currencyCode)
                        }
                        .listRowInsets(EdgeInsets(top: 0, leading: 0, bottom: 0, trailing: 12))
                        .swipeActions(edge: .trailing, allowsFullSwipe: true) {
                            Button(role: .destructive) {
                                pendingDelete = gift
                            } label: {
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
        .background(Color.bg)
        .navigationTitle(name)
        .navigationBarTitleDisplayMode(.inline)
        .toolbar {
            if composition.deletePersonUseCase.canDelete(id: entityId) {
                ToolbarItem(placement: .topBarTrailing) {
                    Button {
                        renaming = true
                    } label: {
                        Image(systemName: "pencil")
                            .font(.system(size: 17, weight: .semibold))
                    }
                    .tint(Color.recv)
                    .accessibilityLabel("Edit person")
                    .accessibilityIdentifier("person-detail.edit")
                }
            }
        }
        // Confirm deleting a single gift from the swipe.
        .confirmationDialog(
            "Delete this gift?",
            isPresented: giftDeleteBinding,
            titleVisibility: .visible,
            presenting: pendingDelete
        ) { gift in
            Button("Delete", role: .destructive) {
                composition.deleteGift(id: gift.id)
                pendingDelete = nil
            }
            Button("Cancel", role: .cancel) { pendingDelete = nil }
        }
        // Rename the person (with a Delete person option at the bottom).
        .sheet(isPresented: $renaming) {
            renameSheet(name: name, count: giftsCount)
        }
    }

    /// Drives the per-gift delete dialog off the optional pending gift.
    private var giftDeleteBinding: Binding<Bool> {
        Binding(
            get: { pendingDelete != nil },
            set: { if !$0 { pendingDelete = nil } })
    }

    // MARK: Rename + delete person

    private func renameSheet(name: String, count: Int) -> some View {
        PersonEditorSheet(
            title: "Edit person",
            initialName: name,
            initialImageData: composition.data.entityImageData(entityId),
            deleteConfirmationMessage: personDeleteMessage(name, count: count),
            focusesNameOnAppear: false,
            onCancel: { renaming = false },
            onSave: { newName, imageData in
                try composition.updatePerson(id: entityId, name: newName, imageData: imageData)
                renaming = false
            },
            onDelete: {
                composition.deletePerson(id: entityId)
                dismiss()
            }
        )
    }

    private func personDeleteMessage(_ name: String, count: Int) -> String {
        let fmt = NSLocalizedString(
            "This permanently deletes %1$@ and all %2$lld of their gifts. This cannot be undone.",
            comment: "")
        return String(format: fmt, name, count)
    }

    private var emptyText: String {
        switch filter {
        case "given": return "No gifts given yet."
        case "received": return "No gifts received yet."
        default: return "No gifts yet"
        }
    }

    private var giftsCount: Int {
        composition.data.gifts.filter { $0.giverID == entityId || $0.recipientID == entityId }.count
    }

    private func statCard(arrow: String, label: String, color: Color, count: Int, value: Double) -> some View {
        Card {
            VStack(alignment: .leading, spacing: 0) {
                HStack(spacing: 6) {
                    Text(arrow).font(Font.app(15, .semibold))
                    Text(LocalizedStringKey(label)).font(Font.app(13, .semibold))
                }
                .foregroundColor(color)
                Text("\(count)").font(Font.app(25, .bold)).tracking(-0.4).foregroundColor(Color.ink).padding(.top, 9)
                Text("gifts · \(formattedCurrency(value, code: composition.currencyCode))")
                    .font(Font.app(13, .regular)).foregroundColor(Color.muted).padding(.top, 2)
            }
            .frame(maxWidth: .infinity, alignment: .leading)
            .padding(15)
        }
    }
}

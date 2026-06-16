import SwiftUI

/// A person's gift history. Built as a native `List` so its rows open / swipe-to-
/// delete exactly like Home, reusing `GiftRow` + `GiftDetailView`. The header
/// (avatar, per-side stats, All/Received/Given filter) rides as a quiet section.
struct PersonDetailView: View {
    @EnvironmentObject var store: AppStore
    let entityId: String
    @State private var filter: String = "all"

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
            .sorted { $0.date > $1.date }
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
                            .listRowInsets(EdgeInsets(top: 0, leading: 0, bottom: 0, trailing: 0))
                            .swipeActions(edge: .trailing, allowsFullSwipe: true) {
                                Button(role: .destructive) { store.deleteGift(gift.id) } label: {
                                    Label("Delete", systemImage: "trash")
                                }
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

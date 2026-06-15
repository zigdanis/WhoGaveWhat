import SwiftUI

struct HomeView: View {
    @EnvironmentObject var store: AppStore

    private let filters: [(String, String, Color)] = [
        ("all", "All", KS.ink),
        ("received", "Received", KS.recv),
        ("given", "Given", KS.give),
    ]

    var body: some View {
        VStack(alignment: .leading, spacing: 0) {
            // Greeting
            HStack(spacing: 12) {
                VStack(alignment: .leading, spacing: 1) {
                    Text(store.todayLabel).font(KS.font(14, .heavy)).foregroundColor(KS.muted)
                    Text("Hi, \(store.greetingName) 👋").font(KS.font(28, .black)).tracking(-0.6)
                }
                Spacer()
                AvatarView(initials: "A", color: KS.give, size: 44)
            }
            .padding(.bottom, 18)

            // Summary card
            Card {
                HStack(spacing: 0) {
                    summaryColumn(arrow: "↙", label: "Received", color: KS.recv,
                                  value: rub(store.sum(store.received)), count: store.received.count)
                    Rectangle().fill(KS.hairline).frame(width: 1)
                    summaryColumn(arrow: "↗", label: "Given", color: KS.give,
                                  value: rub(store.sum(store.given)), count: store.given.count)
                }
                .padding(.vertical, 18).padding(.horizontal, 8)
            }

            Text("IN \(store.displayYear)")
                .font(KS.font(12.5, .heavy)).tracking(0.4)
                .foregroundColor(KS.muted4)
                .frame(maxWidth: .infinity)
                .padding(.top, 8)

            // Filter chips
            HStack(spacing: 9) {
                ForEach(filters, id: \.0) { key, label, accent in
                    Button { store.setFilter(key) } label: {
                        ChipView(label: label, selected: store.filter == key, accent: accent)
                    }
                    .buttonStyle(.plain)
                }
            }
            .padding(.vertical, 16)

            // Timeline groups
            ForEach(store.timeline) { group in
                VStack(alignment: .leading, spacing: 0) {
                    SectionHeader(text: group.label)
                        .padding(.bottom, 9)
                    Card {
                        VStack(spacing: 0) {
                            ForEach(Array(group.items.enumerated()), id: \.element.id) { idx, gift in
                                NavigationLink(value: gift.personId) {
                                    GiftRow(gift: gift)
                                }
                                .buttonStyle(.plain)
                                if idx < group.items.count - 1 { RowDivider() }
                            }
                        }
                    }
                }
                .padding(.top, 18)
            }
        }
        .padding(.horizontal, 20)
    }

    private func summaryColumn(arrow: String, label: String, color: Color, value: String, count: Int) -> some View {
        VStack(alignment: .leading, spacing: 0) {
            HStack(spacing: 6) {
                Text(arrow).font(KS.font(17, .black))
                Text(label).font(KS.font(13, .heavy))
            }
            .foregroundColor(color)
            Text(value).font(KS.font(23, .black)).tracking(-0.3).padding(.top, 8)
            Text("\(count) gifts").font(KS.font(13, .bold)).foregroundColor(KS.muted).padding(.top, 1)
        }
        .frame(maxWidth: .infinity, alignment: .leading)
        .padding(.horizontal, 14)
    }
}

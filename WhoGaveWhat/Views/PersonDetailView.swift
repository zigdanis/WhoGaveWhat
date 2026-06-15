import SwiftUI

struct PersonDetailView: View {
    @EnvironmentObject var store: AppStore
    let entityId: String
    @State private var flow: Flow = .received

    var body: some View {
        let isMember = store.isMember(entityId)
        let name = isMember ? store.memberName(entityId) : store.personName(entityId)
        let color = store.entityColor(entityId)
        let gs = store.gifts
            .filter { isMember ? $0.memberId == entityId : $0.personId == entityId }
            .sorted { $0.date > $1.date }
        let recv = gs.filter { $0.flow == .received }
        let given = gs.filter { $0.flow == .given }
        let bars = occasionBars(gs)
        let list = flow == .received ? recv : given

        ScrollView {
            VStack(alignment: .leading, spacing: 0) {
                // Header
                VStack(spacing: 0) {
                    AvatarView(initials: store.initials(name), color: color, size: 76)
                    Text(name).font(KS.font(24, .bold)).tracking(-0.4).foregroundColor(KS.ink).padding(.top, 13)
                }
                .frame(maxWidth: .infinity)
                .padding(.top, 6)

                // Stats: count + value per side
                HStack(spacing: 10) {
                    statCard(arrow: "↙", label: "Received", color: KS.recv,
                             count: recv.count, value: store.sum(recv))
                    statCard(arrow: "↗", label: "Given", color: KS.ink,
                             count: given.count, value: store.sum(given))
                }
                .padding(.top, 18)

                // By occasion
                if !bars.isEmpty {
                    SectionHeader(text: "By occasion").padding(.top, 22).padding(.bottom, 7)
                    Card {
                        VStack(spacing: 0) {
                            let maxV = bars.first?.1 ?? 1
                            ForEach(bars, id: \.0) { label, value in
                                VStack(spacing: 7) {
                                    HStack {
                                        Text(label).font(KS.font(13, .semibold)).foregroundColor(KS.ink)
                                        Spacer()
                                        Text(rub(value)).font(KS.font(13, .regular)).foregroundColor(KS.muted)
                                    }
                                    BarView(pct: value / maxV * 100, color: color)
                                }
                                .padding(.bottom, 14)
                            }
                        }
                        .padding(.horizontal, 16).padding(.top, 16).padding(.bottom, 2)
                    }
                }

                // Received / Given toggle
                Segmented(options: [.init(key: "received", label: "Received", accent: KS.recv),
                                    .init(key: "given", label: "Given", accent: KS.ink)],
                          selected: flow.rawValue) { key in
                    withAnimation(.easeOut(duration: 0.18)) { flow = Flow(rawValue: key) ?? .received }
                }
                .padding(.top, 22)
                .padding(.bottom, 12)

                if list.isEmpty {
                    Card {
                        Text(flow == .given ? "No gifts given yet." : "No gifts received yet.")
                            .font(KS.font(14, .regular)).foregroundColor(KS.muted4)
                            .frame(maxWidth: .infinity)
                            .padding(.vertical, 30)
                    }
                } else {
                    Card {
                        VStack(spacing: 0) {
                            ForEach(Array(list.enumerated()), id: \.element.id) { idx, gift in
                                GiftRow(gift: gift)
                                if idx < list.count - 1 { RowDivider().padding(.leading, 14) }
                            }
                        }
                    }
                }
            }
            .padding(.horizontal, 16)
            .padding(.bottom, 110)
        }
        .scrollIndicators(.hidden)
        .background(KS.bg)
        .navigationTitle(name)
        .navigationBarTitleDisplayMode(.inline)
    }

    private func statCard(arrow: String, label: String, color: Color, count: Int, value: Double) -> some View {
        Card {
            VStack(alignment: .leading, spacing: 0) {
                HStack(spacing: 6) {
                    Text(arrow).font(KS.font(15, .semibold))
                    Text(label).font(KS.font(13, .semibold))
                }
                .foregroundColor(color)
                Text("\(count)").font(KS.font(25, .bold)).tracking(-0.4).foregroundColor(KS.ink).padding(.top, 9)
                Text("gifts · \(rub(value))").font(KS.font(13, .regular)).foregroundColor(KS.muted).padding(.top, 2)
            }
            .frame(maxWidth: .infinity, alignment: .leading)
            .padding(15)
        }
    }

    private func occasionBars(_ gs: [Gift]) -> [(String, Double)] {
        var map: [String: Double] = [:]
        for g in gs { map[g.celebration, default: 0] += g.value }
        return map.map { ($0.key, $0.value) }.sorted { $0.1 > $1.1 }
    }
}

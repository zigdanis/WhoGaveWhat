import SwiftUI

struct PersonDetailView: View {
    @EnvironmentObject var store: AppStore
    let entityId: String

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

        ScrollView {
            VStack(alignment: .leading, spacing: 0) {
                    // Header
                    VStack(spacing: 0) {
                        AvatarView(initials: store.initials(name), color: color, size: 76)
                        Text(name).font(KS.font(24, .black)).tracking(-0.4).padding(.top, 13)
                        Text("\(isMember ? "Your family" : "Friends & relatives")  ·  \(gs.count) gifts")
                            .font(KS.font(14, .bold)).foregroundColor(KS.muted).padding(.top, 3)
                    }
                    .frame(maxWidth: .infinity)

                    // Stats
                    HStack(spacing: 10) {
                        statCard(big: "\(gs.count)", color: KS.ink, label: "Gifts", bigSize: 22)
                        statCard(big: rub(store.sum(recv)), color: KS.recv, label: "Received", bigSize: 18)
                        statCard(big: rub(store.sum(given)), color: KS.give, label: "Given", bigSize: 18)
                    }
                    .padding(.top, 20)

                    // By occasion
                    if !bars.isEmpty {
                        SectionHeader(text: "By occasion").padding(.top, 22).padding(.bottom, 9)
                        Card {
                            VStack(spacing: 0) {
                                let maxV = bars.first?.1 ?? 1
                                ForEach(bars, id: \.0) { label, value in
                                    VStack(spacing: 6) {
                                        HStack {
                                            Text(label).foregroundColor(KS.ink)
                                            Spacer()
                                            Text(rub(value)).foregroundColor(KS.muted3)
                                        }
                                        .font(KS.font(13, .heavy))
                                        BarView(pct: value / maxV * 100, color: color)
                                    }
                                    .padding(.bottom, 13)
                                }
                            }
                            .padding(.horizontal, 16).padding(.top, 16).padding(.bottom, 6)
                        }
                    }

                    // All gifts
                    SectionHeader(text: "All gifts").padding(.top, 22).padding(.bottom, 9)
                    Card {
                        VStack(spacing: 0) {
                            ForEach(Array(gs.enumerated()), id: \.element.id) { idx, gift in
                                GiftRow(gift: gift)
                                if idx < gs.count - 1 { RowDivider() }
                            }
                        }
                    }
            }
            .padding(.horizontal, 18)
            .padding(.top, 8)
            .padding(.bottom, 40)
        }
        .scrollIndicators(.hidden)
        .background(KS.bg)
        .navigationTitle(name)
        .navigationBarTitleDisplayMode(.inline)
    }

    private func statCard(big: String, color: Color, label: String, bigSize: CGFloat) -> some View {
        VStack(spacing: 2) {
            Text(big).font(KS.font(bigSize, .black)).foregroundColor(color)
                .minimumScaleFactor(0.6).lineLimit(1)
            Text(label).font(KS.font(12, .heavy)).foregroundColor(KS.muted)
        }
        .frame(maxWidth: .infinity)
        .padding(.vertical, 14).padding(.horizontal, 12)
        .background(RoundedRectangle(cornerRadius: KS.radius, style: .continuous).fill(KS.card))
        .ksCardShadow()
    }

    private func occasionBars(_ gs: [Gift]) -> [(String, Double)] {
        var map: [String: Double] = [:]
        for g in gs { map[g.celebration, default: 0] += g.value }
        return map.map { ($0.key, $0.value) }.sorted { $0.1 > $1.1 }
    }
}

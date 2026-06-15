import SwiftUI

struct InsightsView: View {
    @EnvironmentObject var store: AppStore

    var body: some View {
        let rv = store.sum(store.received)
        let gv = store.sum(store.given)
        let tot = max(rv + gv, 1)
        let paid = store.gifts.filter { $0.paidByYou }

        VStack(alignment: .leading, spacing: 0) {
            Text("Your year of giving, at a glance")
                .font(KS.font(15, .bold)).foregroundColor(KS.muted)
                .padding(.top, 1).padding(.bottom, 18)

            // Tracked total
            Card {
                VStack(alignment: .leading, spacing: 0) {
                    Text("TRACKED IN \(store.displayYear)")
                        .font(KS.font(12.5, .heavy)).tracking(0.6).foregroundColor(KS.muted)
                    Text(rub(rv + gv)).font(KS.font(34, .black)).tracking(-0.6).padding(.top, 6)
                    Text("\(store.gifts.count) gifts · \(store.people.count) people")
                        .font(KS.font(14, .bold)).foregroundColor(KS.muted3).padding(.top, 1)

                    // Stacked received/given bar
                    GeometryReader { geo in
                        HStack(spacing: 0) {
                            Rectangle().fill(KS.recv)
                                .frame(width: geo.size.width * CGFloat(rv / tot))
                            Rectangle().fill(KS.give)
                                .frame(width: geo.size.width * CGFloat(gv / tot))
                        }
                    }
                    .frame(height: 13)
                    .background(KS.track)
                    .clipShape(Capsule())
                    .padding(.top, 18)

                    HStack(spacing: 18) {
                        legend(color: KS.recv, label: "Received", value: rub(rv))
                        legend(color: KS.give, label: "Given", value: rub(gv))
                    }
                    .padding(.top, 12)
                }
                .padding(20)
            }

            // Who's really paying
            VStack(alignment: .leading, spacing: 0) {
                HStack(spacing: 9) {
                    Text("♡").font(.system(size: 19))
                    Text("WHO'S REALLY PAYING")
                        .font(KS.font(12.5, .heavy)).tracking(0.6).opacity(0.92)
                }
                Text("You covered \(paid.count) gifts")
                    .font(KS.font(26, .black)).tracking(-0.4).padding(.top, 12)
                Text("That's \(rub(store.sum(paid))) from your pocket — the quiet hero of the family. 💛")
                    .font(KS.font(15, .bold)).opacity(0.92).padding(.top, 3)
                    .fixedSize(horizontal: false, vertical: true)
            }
            .foregroundColor(.white)
            .padding(20)
            .frame(maxWidth: .infinity, alignment: .leading)
            .background(
                RoundedRectangle(cornerRadius: KS.radius, style: .continuous)
                    .fill(LinearGradient(colors: [KS.give, KS.giveDeep],
                                         startPoint: .topLeading, endPoint: .bottomTrailing))
                    .shadow(color: KS.give.opacity(0.28), radius: 15, x: 0, y: 14)
            )
            .padding(.top, 14)

            // Top people
            SectionHeader(text: "Top people").padding(.top, 22).padding(.bottom, 9)
            Card {
                VStack(spacing: 0) {
                    let agg = topPeople()
                    let maxV = agg.first?.1 ?? 1
                    ForEach(Array(agg.enumerated()), id: \.element.0.id) { idx, item in
                        NavigationLink(value: item.0.id) {
                            TopPersonRow(person: item.0, value: item.1, maxValue: maxV)
                        }
                        .buttonStyle(.plain)
                        if idx < agg.count - 1 { RowDivider() }
                    }
                }
            }

            // By occasion
            SectionHeader(text: "By occasion").padding(.top, 22).padding(.bottom, 9)
            Card {
                VStack(spacing: 0) {
                    let bars = celebrationBars()
                    let maxV = bars.first?.1 ?? 1
                    ForEach(bars, id: \.0) { label, value in
                        VStack(spacing: 6) {
                            HStack {
                                Text(label).foregroundColor(KS.ink)
                                Spacer()
                                Text(rub(value)).foregroundColor(KS.muted3)
                            }
                            .font(KS.font(13, .heavy))
                            BarView(pct: value / maxV * 100, color: KS.gold)
                        }
                        .padding(.bottom, 13)
                    }
                }
                .padding(.horizontal, 16).padding(.top, 16).padding(.bottom, 6)
            }
        }
        .padding(.horizontal, 20)
    }

    private func legend(color: Color, label: String, value: String) -> some View {
        HStack(spacing: 7) {
            RoundedRectangle(cornerRadius: 3).fill(color).frame(width: 11, height: 11)
            Text(label).font(KS.font(13, .heavy)).foregroundColor(KS.ink)
            Text(value).font(KS.font(13, .heavy)).foregroundColor(KS.muted3)
        }
    }

    private func topPeople() -> [(Person, Double)] {
        store.people
            .map { p in (p, store.sum(store.gifts.filter { $0.personId == p.id })) }
            .filter { $0.1 > 0 }
            .sorted { $0.1 > $1.1 }
            .prefix(5)
            .map { $0 }
    }

    private func celebrationBars() -> [(String, Double)] {
        var map: [String: Double] = [:]
        for g in store.gifts { map[g.celebration, default: 0] += g.value }
        return map.map { ($0.key, $0.value) }.sorted { $0.1 > $1.1 }
    }
}

private struct TopPersonRow: View {
    @EnvironmentObject var store: AppStore
    let person: Person
    let value: Double
    let maxValue: Double

    var body: some View {
        HStack(spacing: 12) {
            AvatarView(initials: store.initials(person.name), color: person.color, size: 38)
            VStack(alignment: .leading, spacing: 8) {
                HStack(alignment: .firstTextBaseline) {
                    Text(person.name).font(KS.font(15, .heavy))
                    Spacer()
                    Text(rub(value)).font(KS.font(14, .black))
                }
                BarView(pct: value / maxValue * 100, color: person.color, height: 7)
            }
        }
        .padding(.horizontal, 15).padding(.vertical, 13)
    }
}

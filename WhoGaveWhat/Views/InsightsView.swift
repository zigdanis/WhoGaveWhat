import SwiftUI

struct InsightsView: View {
    @EnvironmentObject var store: AppStore

    var body: some View {
        let rv = store.sum(store.received)
        let gv = store.sum(store.given)
        let tot = max(rv + gv, 1)
        let paid = store.gifts.filter { $0.paidByYou }

        VStack(alignment: .leading, spacing: 0) {
            // Circulated total — shown openly (per-person amounts below are the
            // ones hidden behind spoilers instead).
            Card {
                VStack(alignment: .leading, spacing: 0) {
                    Text("Circulated in \(store.displayYear)")
                        .font(KS.font(13, .regular)).foregroundColor(KS.muted)
                    Text(rub(rv + gv))
                        .font(KS.font(32, .bold)).tracking(-0.6).foregroundColor(KS.ink)
                        .padding(.top, 7)

                    Text(verbatim: "\(store.giftsCount(store.gifts.count)) · \(store.peopleCount(store.people.count))")
                        .font(KS.font(14, .regular)).foregroundColor(KS.muted).padding(.top, 4)

                    // Stacked received/given bar
                    GeometryReader { geo in
                        HStack(spacing: 0) {
                            Rectangle().fill(KS.recv).frame(width: geo.size.width * CGFloat(rv / tot))
                            Rectangle().fill(KS.ink).frame(width: geo.size.width * CGFloat(gv / tot))
                        }
                    }
                    .frame(height: 13)
                    .background(KS.track)
                    .clipShape(Capsule())
                    .padding(.top, 18)

                    HStack(spacing: 18) {
                        legend(color: KS.recv, label: "Received", value: rub(rv))
                        legend(color: KS.ink, label: "Given", value: rub(gv))
                    }
                    .padding(.top, 12)
                }
                .padding(20)
            }

            // Headline insight — solid ink card. When you've received more than
            // you've given, flip it to a "you're ahead" message instead of the
            // "who's really paying" one (which only lands when you've paid a lot).
            spotlightCard(received: rv, given: gv, paid: paid)
                .padding(.top, 14)

            // Top givers
            SectionHeader(text: "Top givers").padding(.top, 22).padding(.bottom, 7)
            rankCard(topPeople(flow: .received))

            // Top receivers
            SectionHeader(text: "Top receivers").padding(.top, 22).padding(.bottom, 7)
            rankCard(topPeople(flow: .given))
        }
        .padding(.horizontal, 16)
    }

    /// The big ink headline card. Two flavours, chosen by the balance of giving.
    @ViewBuilder
    private func spotlightCard(received: Double, given: Double, paid: [Gift]) -> some View {
        VStack(alignment: .leading, spacing: 0) {
            if received > given {
                // You're a net receiver — celebrate it rather than guilt-trip.
                Text("On the receiving end")
                    .font(KS.font(13, .semibold)).foregroundColor(.white.opacity(0.7))
                Text("You've received \(rub(received))")
                    .font(KS.font(24, .bold)).tracking(-0.4).foregroundColor(.white).padding(.top, 10)
                Text("That's \(rub(received - given)) more than you've given back — you're well loved. Maybe time to return the favour?")
                    .font(KS.font(15, .regular)).foregroundColor(.white.opacity(0.8)).padding(.top, 4)
                    .fixedSize(horizontal: false, vertical: true)
            } else {
                Text("Who's really paying")
                    .font(KS.font(13, .semibold)).foregroundColor(.white.opacity(0.7))
                Text("You covered \(store.giftsCount(paid.count))")
                    .font(KS.font(24, .bold)).tracking(-0.4).foregroundColor(.white).padding(.top, 10)
                Text("That's \(rub(store.sum(paid))) from your pocket — the quiet hero of the family.")
                    .font(KS.font(15, .regular)).foregroundColor(.white.opacity(0.8)).padding(.top, 4)
                    .fixedSize(horizontal: false, vertical: true)
            }
        }
        .padding(20)
        .frame(maxWidth: .infinity, alignment: .leading)
        .background(RoundedRectangle(cornerRadius: KS.radius, style: .continuous).fill(KS.ink))
    }

    @ViewBuilder
    private func rankCard(_ agg: [(Person, Double, Int)]) -> some View {
        Card {
            VStack(spacing: 0) {
                let maxV = agg.first?.1 ?? 1
                ForEach(Array(agg.enumerated()), id: \.element.0.id) { idx, item in
                    NavigationLink(value: item.0.id) {
                        RankRow(person: item.0, value: item.1, count: item.2, maxValue: maxV)
                    }
                    .buttonStyle(.plain)
                    if idx < agg.count - 1 { RowDivider().padding(.leading, 14) }
                }
            }
        }
    }

    private func legend(color: Color, label: String, value: String) -> some View {
        HStack(spacing: 7) {
            RoundedRectangle(cornerRadius: 3).fill(color).frame(width: 10, height: 10)
            Text(LocalizedStringKey(label)).font(KS.font(13, .semibold)).foregroundColor(KS.ink)
            Text(value).font(KS.font(13, .regular)).foregroundColor(KS.muted)
        }
    }

    /// Top people by total value for a flow (received = top givers, given = top receivers).
    private func topPeople(flow: Flow) -> [(Person, Double, Int)] {
        store.people
            .map { p -> (Person, Double, Int) in
                let gs = store.gifts.filter { $0.personId == p.id && $0.flow == flow }
                return (p, store.sum(gs), gs.count)
            }
            .filter { $0.2 > 0 }
            .sorted { $0.1 > $1.1 }
            .prefix(5)
            .map { $0 }
    }
}

private struct RankRow: View {
    @EnvironmentObject var store: AppStore
    let person: Person
    let value: Double
    let count: Int
    let maxValue: Double

    var body: some View {
        HStack(spacing: 12) {
            AvatarView(initials: store.initials(person.name), color: person.color, size: 38)
            VStack(alignment: .leading, spacing: 9) {
                HStack(alignment: .firstTextBaseline, spacing: 5) {
                    Text(person.name).font(KS.font(15, .semibold)).foregroundColor(KS.ink)
                    Spacer(minLength: 8)
                    Text(verbatim: "\(store.giftsCount(count)) · \(rub(value))")
                        .font(KS.font(13, .regular)).foregroundColor(KS.muted)
                }
                BarView(pct: value / maxValue * 100, color: person.color, height: 7)
            }
        }
        .padding(.horizontal, 14).padding(.vertical, 13)
        .contentShape(Rectangle())
    }
}

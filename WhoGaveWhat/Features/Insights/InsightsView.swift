import SwiftUI

struct InsightsView: View {
    let composition: AppComposition

    var body: some View {
        let insights = composition.buildInsights.execute(
            gifts: composition.data.gifts,
            people: composition.data.contacts
        )
        let rv = insights.receivedValue
        let gv = insights.givenValue
        let tot = max(rv + gv, 1)
        let paid = insights.paidByYou

        VStack(alignment: .leading, spacing: 0) {
            // Circulated total — shown openly (per-person amounts below are the
            // ones hidden behind spoilers instead).
            Card {
                VStack(alignment: .leading, spacing: 0) {
                    Text("Circulated in 2026")
                        .font(Font.app(13, .regular)).foregroundColor(Color.muted)
                    Text(formattedCurrency(rv + gv, code: composition.currencyCode))
                        .font(Font.app(32, .bold)).tracking(-0.6).foregroundColor(Color.ink)
                        .padding(.top, 7)

                    Text(verbatim: "\(LocalizedCount.gifts(composition.data.gifts.count)) · \(LocalizedCount.people(composition.data.contacts.count))")
                        .font(Font.app(14, .regular)).foregroundColor(Color.muted).padding(.top, 4)

                    // Stacked received/given bar
                    GeometryReader { geo in
                        HStack(spacing: 0) {
                            Rectangle().fill(Color.recv).frame(width: geo.size.width * CGFloat(rv / tot))
                            Rectangle().fill(Color.ink).frame(width: geo.size.width * CGFloat(gv / tot))
                        }
                    }
                    .frame(height: 13)
                    .background(Color.track)
                    .clipShape(Capsule())
                    .padding(.top, 18)

                    HStack(spacing: 18) {
                        legend(color: Color.recv, label: "Received", value: formattedCurrency(rv, code: composition.currencyCode))
                        legend(color: Color.ink, label: "Given", value: formattedCurrency(gv, code: composition.currencyCode))
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
            rankCard(insights.topGivers)

            // Top receivers
            SectionHeader(text: "Top receivers").padding(.top, 22).padding(.bottom, 7)
            rankCard(insights.topReceivers)
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
                    .font(Font.app(13, .semibold)).foregroundColor(.white.opacity(0.7))
                Text("You've received \(formattedCurrency(received, code: composition.currencyCode))")
                    .font(Font.app(24, .bold)).tracking(-0.4).foregroundColor(.white).padding(.top, 10)
                Text("That's \(formattedCurrency(received - given, code: composition.currencyCode)) more than you've given back — you're well loved. Maybe time to return the favour?")
                    .font(Font.app(15, .regular)).foregroundColor(.white.opacity(0.8)).padding(.top, 4)
                    .fixedSize(horizontal: false, vertical: true)
            } else {
                Text("Who's really paying")
                    .font(Font.app(13, .semibold)).foregroundColor(.white.opacity(0.7))
                Text("You covered \(LocalizedCount.gifts(paid.count))")
                    .font(Font.app(24, .bold)).tracking(-0.4).foregroundColor(.white).padding(.top, 10)
                Text("That's \(formattedCurrency(paid.totalValue, code: composition.currencyCode)) from your pocket — the quiet hero of the family.")
                    .font(Font.app(15, .regular)).foregroundColor(.white.opacity(0.8)).padding(.top, 4)
                    .fixedSize(horizontal: false, vertical: true)
            }
        }
        .padding(20)
        .frame(maxWidth: .infinity, alignment: .leading)
        .background(RoundedRectangle(cornerRadius: DesignMetrics.cornerRadius, style: .continuous).fill(Color.ink))
    }

    @ViewBuilder
    private func rankCard(_ rankings: [RankedPerson]) -> some View {
        Card {
            VStack(spacing: 0) {
                let maxV = rankings.first?.value ?? 1
                ForEach(Array(rankings.enumerated()), id: \.element.id) { idx, item in
                    NavigationLink(value: item.person.id) {
                        RankRow(
                            person: item.person,
                            value: item.value,
                            count: item.count,
                            maxValue: maxV,
                            currencyCode: composition.currencyCode
                        )
                    }
                    .buttonStyle(.plain)
                    if idx < rankings.count - 1 { RowDivider().padding(.leading, 14) }
                }
            }
        }
    }

    private func legend(color: Color, label: String, value: String) -> some View {
        HStack(spacing: 7) {
            RoundedRectangle(cornerRadius: 3).fill(color).frame(width: 10, height: 10)
            Text(LocalizedStringKey(label)).font(Font.app(13, .semibold)).foregroundColor(Color.ink)
            Text(value).font(Font.app(13, .regular)).foregroundColor(Color.muted)
        }
    }

}

private struct RankRow: View {
    let person: Person
    let value: Double
    let count: Int
    let maxValue: Double
    let currencyCode: String

    var body: some View {
        HStack(spacing: 12) {
            AvatarView(initials: person.name.initials, color: person.color, size: 38)
            VStack(alignment: .leading, spacing: 9) {
                HStack(alignment: .firstTextBaseline, spacing: 5) {
                    Text(person.name).font(Font.app(15, .semibold)).foregroundColor(Color.ink)
                    Spacer(minLength: 8)
                    Text(verbatim: "\(LocalizedCount.gifts(count)) · \(formattedCurrency(value, code: currencyCode))")
                        .font(Font.app(13, .regular)).foregroundColor(Color.muted)
                }
                BarView(pct: value / maxValue * 100, color: person.color, height: 7)
            }
        }
        .padding(.horizontal, 14).padding(.vertical, 13)
        .contentShape(Rectangle())
    }
}

import SwiftUI

/// Summary of one year on Home and Insights. With a viewpoint it splits received and given
/// and shows the net; without one it shows what circulated, with an optional pointer to People.
struct YearSummaryCard: View {
    let summary: YearSummary
    let hasViewpoint: Bool
    let currencyCode: String
    let years: [Int]
    @Binding var selectedYear: Int
    /// Shows the "mark yourself" hint when there is no viewpoint; nil leaves it out.
    var onMarkSelf: (() -> Void)?
    /// Whose summary this is; shown next to the year when there is a viewpoint. nil keeps the plain header.
    var owner: Person?

    var body: some View {
        Card {
            VStack(alignment: .leading, spacing: 14) {
                HStack(alignment: .center) {
                    if let owner, hasViewpoint {
                        ownerIdentity(owner)
                    } else {
                        yearCaption
                    }
                    Spacer(minLength: 8)
                    YearMenu(years: years, selection: $selectedYear)
                }
                if hasViewpoint {
                    viewpointContent
                } else {
                    circulatedContent
                }
            }
            .padding(16)
        }
        .accessibilityElement(children: .contain)
        .accessibilityIdentifier("year-summary")
    }

    private var yearCaption: some View {
        Text("Gifts in \(String(summary.year))")
            .font(Font.app(13, .regular)).foregroundColor(Color.textSecondary)
    }

    private func ownerIdentity(_ owner: Person) -> some View {
        HStack(spacing: 10) {
            AvatarView(
                initials: owner.name.initials, color: owner.color, size: .compact, imageData: owner.imageData
            )
            .accessibilityHidden(true)
            VStack(alignment: .leading, spacing: 2) {
                Text(owner.name)
                    .font(Font.app(15, .semibold)).foregroundColor(Color.textPrimary)
                    .lineLimit(1)
                yearCaption
            }
        }
        .accessibilityElement(children: .combine)
        .accessibilityIdentifier("year-summary.owner")
    }

    private var viewpointContent: some View {
        VStack(alignment: .leading, spacing: 14) {
            HStack(alignment: .top, spacing: 12) {
                flowTile(.received, value: summary.receivedValue, count: summary.receivedCount)
                flowTile(.given, value: summary.givenValue, count: summary.givenCount)
            }
            RowDivider()
            HStack {
                Text("Balance")
                    .font(Font.app(15, .semibold)).foregroundColor(Color.textPrimary)
                Spacer(minLength: 8)
                NetBadge(net: summary.net, currencyCode: currencyCode)
            }
        }
    }

    private var circulatedContent: some View {
        VStack(alignment: .leading, spacing: 10) {
            VStack(alignment: .leading, spacing: 4) {
                Text(formattedCurrency(summary.circulatedValue, code: currencyCode))
                    .font(Font.app(32, .bold, rounded: true)).tracking(-0.6).foregroundColor(Color.textPrimary)
                    .lineLimit(1).minimumScaleFactor(0.6)
                Text(verbatim: LocalizedCount.gifts(summary.giftCount))
                    .font(Font.app(14, .regular)).foregroundColor(Color.textSecondary)
            }
            .accessibilityElement(children: .combine)
            if let onMarkSelf {
                Button(action: onMarkSelf) {
                    HStack(spacing: 8) {
                        Text("Mark yourself in People to see your balance")
                            .font(Font.app(14, .regular)).foregroundColor(Color.brand)
                            .multilineTextAlignment(.leading)
                            .frame(maxWidth: .infinity, alignment: .leading)
                        Chevron()
                    }
                    .contentShape(Rectangle())
                }
                .buttonStyle(.plain)
                .accessibilityIdentifier("year-summary.mark-self")
            }
        }
    }

    private func flowTile(_ direction: GiftDirection, value: Double, count: Int) -> some View {
        let appearance = direction.appearance
        return VStack(alignment: .leading, spacing: 4) {
            HStack(spacing: 4) {
                Text(verbatim: appearance.arrow)
                if let label = appearance.label { Text(label) }
            }
            .font(Font.app(13, .semibold)).foregroundColor(appearance.main)
            Text(formattedCurrency(value, code: currencyCode))
                .font(Font.app(24, .bold, rounded: true)).foregroundColor(Color.textPrimary)
                .lineLimit(1).minimumScaleFactor(0.6)
            Text(verbatim: LocalizedCount.gifts(count))
                .font(Font.app(13, .regular)).foregroundColor(Color.textSecondary)
        }
        .frame(maxWidth: .infinity, alignment: .leading)
        .accessibilityElement(children: .combine)
    }
}

import SwiftUI

/// View / edit / delete a single saved gift. Reached by tapping a gift on Home.
/// The gift is re-resolved from app data by id, so edits made in the Add sheet
/// show immediately; the screen pops itself once the gift is deleted.
struct GiftDetailView: View {
    @Environment(\.dismiss) private var dismiss
    let giftId: String
    let composition: AppComposition

    var body: some View {
        Group {
            if let gift = composition.data.gifts.first(where: { $0.id == giftId }) {
                content(gift)
            } else {
                // Gift was deleted — nothing left to show, so pop back.
                Color.clear.onAppear { dismiss() }
            }
        }
        .background(Color.bg)
        .navigationTitle("Gift")
        .navigationBarTitleDisplayMode(.inline)
    }

    @ViewBuilder
    private func content(_ gift: Gift) -> some View {
        let fm = gift.direction.appearance
        ScrollView {
            VStack(alignment: .leading, spacing: 0) {
                heroCard(gift, fm)

                SectionHeader(text: "Details").padding(.top, 22).padding(.bottom, 7)
                detailsCard(gift, fm)

                deleteButton.padding(.top, 28)
            }
            .padding(.horizontal, 16).padding(.top, 6).padding(.bottom, 40)
        }
        .scrollIndicators(.hidden)
        .toolbar {
            ToolbarItem(placement: .topBarTrailing) {
                Button { composition.router.presentEditGift(id: gift.id) } label: {
                    Image(systemName: "pencil")
                        .font(.system(size: 17, weight: .semibold))
                }
                .tint(Color.recv)
                .accessibilityLabel("Edit")
            }
        }
    }

    // MARK: Hero (emoji + name + value)

    private func heroCard(_ g: Gift, _ fm: GiftDirectionAppearance) -> some View {
        VStack(spacing: 12) {
            HStack(alignment: .center, spacing: 14) {
                Text(g.emoji)
                    .font(.system(size: 28))
                    .frame(width: 58, height: 58)
                    .background(RoundedRectangle(cornerRadius: DesignMetrics.cornerRadius, style: .continuous).fill(.white))
                VStack(alignment: .leading, spacing: 3) {
                    Text(g.name).font(Font.app(18, .bold)).foregroundColor(Color.ink).lineLimit(2)
                    HStack(spacing: 5) {
                        Text(fm.arrow)
                        Text(fm.label)
                    }
                    .font(Font.app(13, .semibold)).foregroundColor(fm.main)
                }
                Spacer(minLength: 8)
            }
            HStack(spacing: 6) {
                Text(rub(g.value)).font(Font.app(17, .semibold)).foregroundColor(Color.ink)
                Spacer(minLength: 0)
            }
            .padding(.horizontal, 14)
            .frame(height: 50)
            .frame(maxWidth: .infinity)
            .background(RoundedRectangle(cornerRadius: DesignMetrics.cornerRadius, style: .continuous).fill(Color.card))
        }
        .padding(16)
        .frame(maxWidth: .infinity, alignment: .leading)
        .background(RoundedRectangle(cornerRadius: DesignMetrics.cornerRadius, style: .continuous).fill(fm.tint))
    }

    // MARK: Details

    private func detailsCard(_ g: Gift, _ fm: GiftDirectionAppearance) -> some View {
        // From (giver) → To (receiver), matching the Add sheet's framing.
        let fromName = composition.data.entityName(g.giverID)
        let toName = composition.data.entityName(g.recipientID)
        return Card {
            VStack(spacing: 0) {
                detailRow(fm, icon: .asset("ArrowRightFromLine"), label: "From", value: fromName)
                RowDivider().padding(.leading, 58)
                detailRow(fm, icon: .asset("ArrowRightToLine"), label: "To", value: toName)
                RowDivider().padding(.leading, 58)
                detailRow(fm, icon: .system("party.popper.fill"), label: "Occasion",
                          value: composition.data.localizedOccasion(g.occasion))
                RowDivider().padding(.leading, 58)
                detailRow(fm, icon: .system("calendar"), label: "Date", value: g.date.giftInputLabel())
            }
        }
    }

    private func detailRow(_ fm: GiftDirectionAppearance, icon: GiftDetailIcon,
                           label: String, value: String) -> some View {
        HStack(spacing: 12) {
            GiftDetailIconView(icon: icon, accent: fm.main, tint: fm.tint)
            Text(LocalizedStringKey(label)).font(Font.app(16, .regular)).foregroundColor(Color.ink)
            Spacer(minLength: 8)
            Text(value).font(Font.app(16, .semibold)).foregroundColor(fm.main).lineLimit(1)
        }
        .padding(.horizontal, 14).padding(.vertical, 12)
    }

    // MARK: Delete

    /// Quiet text button (no card background) so it doesn't draw the eye — delete
    /// happens immediately, no confirmation.
    private var deleteButton: some View {
        Button(role: .destructive) {
            composition.deleteGift(id: giftId)
            dismiss()
        } label: {
            Text("Delete gift")
                .font(Font.app(16, .regular)).foregroundColor(Color(hex: 0xE5484D))
                .frame(maxWidth: .infinity).padding(.vertical, 12)
        }
        .buttonStyle(.plain)
    }
}

private enum GiftDetailIcon {
    case system(String)
    case asset(String)
}

private struct GiftDetailIconView: View {
    let icon: GiftDetailIcon
    let accent: Color
    let tint: Color

    var body: some View {
        iconImage
            .foregroundColor(accent)
            .frame(width: 34, height: 34)
            .background(RoundedRectangle(cornerRadius: DesignMetrics.cornerRadius, style: .continuous).fill(tint))
            .accessibilityHidden(true)
    }

    @ViewBuilder
    private var iconImage: some View {
        switch icon {
        case .system(let name):
            Image(systemName: name)
                .font(.system(size: 15, weight: .semibold))
        case .asset(let name):
            Image(name)
                .resizable()
                .scaledToFit()
                .frame(width: 18, height: 18)
        }
    }
}

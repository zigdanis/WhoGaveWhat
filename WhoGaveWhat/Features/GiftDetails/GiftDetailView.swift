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
        .background(KS.bg)
        .navigationTitle("Gift")
        .navigationBarTitleDisplayMode(.inline)
    }

    @ViewBuilder
    private func content(_ gift: Gift) -> some View {
        let fm = gift.flow.appearance
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
                .tint(KS.recv)
                .accessibilityLabel("Edit")
            }
        }
    }

    // MARK: Hero (emoji + name + value)

    private func heroCard(_ g: Gift, _ fm: GiftFlowAppearance) -> some View {
        VStack(spacing: 12) {
            HStack(alignment: .center, spacing: 14) {
                Text(g.emoji)
                    .font(.system(size: 28))
                    .frame(width: 58, height: 58)
                    .background(RoundedRectangle(cornerRadius: KS.radius, style: .continuous).fill(.white))
                VStack(alignment: .leading, spacing: 3) {
                    Text(g.name).font(KS.font(18, .bold)).foregroundColor(KS.ink).lineLimit(2)
                    HStack(spacing: 5) {
                        Text(fm.arrow)
                        Text(fm.label)
                    }
                    .font(KS.font(13, .semibold)).foregroundColor(fm.main)
                }
                Spacer(minLength: 8)
            }
            HStack(spacing: 6) {
                Text(rub(g.value)).font(KS.font(17, .semibold)).foregroundColor(KS.ink)
                Spacer(minLength: 0)
            }
            .padding(.horizontal, 14)
            .frame(height: 50)
            .frame(maxWidth: .infinity)
            .background(RoundedRectangle(cornerRadius: KS.radius, style: .continuous).fill(KS.card))
        }
        .padding(16)
        .frame(maxWidth: .infinity, alignment: .leading)
        .background(RoundedRectangle(cornerRadius: KS.radius, style: .continuous).fill(fm.tint))
    }

    // MARK: Details

    private func detailsCard(_ g: Gift, _ fm: GiftFlowAppearance) -> some View {
        // From (giver) → To (receiver), matching the Add sheet's framing.
        let fromName = g.flow == .received ? composition.data.personName(g.personId) : composition.data.memberName(g.memberId)
        let toName = g.flow == .received ? composition.data.memberName(g.memberId) : composition.data.personName(g.personId)
        return Card {
            VStack(spacing: 0) {
                detailRow(fm, icon: "person.fill", label: "From", value: fromName)
                RowDivider().padding(.leading, 58)
                detailRow(fm, icon: "person.2.fill", label: "To", value: toName)
                RowDivider().padding(.leading, 58)
                detailRow(fm, icon: "party.popper.fill", label: "Occasion",
                          value: composition.data.localizedCelebration(g.celebration))
                RowDivider().padding(.leading, 58)
                detailRow(fm, icon: "calendar", label: "Date", value: g.date.giftInputLabel())
            }
        }
    }

    private func detailRow(_ fm: GiftFlowAppearance, icon: String, label: String, value: String) -> some View {
        HStack(spacing: 12) {
            Image(systemName: icon)
                .font(.system(size: 15, weight: .semibold))
                .foregroundColor(fm.main)
                .frame(width: 34, height: 34)
                .background(RoundedRectangle(cornerRadius: KS.radius, style: .continuous).fill(fm.tint))
            Text(LocalizedStringKey(label)).font(KS.font(16, .regular)).foregroundColor(KS.ink)
            Spacer(minLength: 8)
            Text(value).font(KS.font(16, .semibold)).foregroundColor(fm.main).lineLimit(1)
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
                .font(KS.font(16, .regular)).foregroundColor(Color(hex: 0xE5484D))
                .frame(maxWidth: .infinity).padding(.vertical, 12)
        }
        .buttonStyle(.plain)
    }
}

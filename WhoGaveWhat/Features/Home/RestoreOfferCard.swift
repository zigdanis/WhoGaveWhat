import SwiftUI

/// Above Home's welcome after a reinstall or on a new device: the newest backup from another install, with
/// Restore and Not now. Restore brings back that backup's gifts, people and preferences in one step;
/// Not now hides the offer for good, and Settings → Restore from iCloud still lists every backup.
struct RestoreOfferCard: View {
    let composition: AppComposition
    let backup: ICloudBackupService
    let offer: BackupCandidate
    @State private var isRestoring = false
    @State private var failure: String?
    @Environment(\.compactVerticalSpace) private var isCompact
    @Environment(\.haptics) private var haptics

    var body: some View {
        Card {
            VStack(spacing: isCompact ? 12 : 16) {
                Image(systemName: "icloud.and.arrow.down")
                    .font(.system(size: 30, weight: .semibold))
                    .foregroundStyle(Color.brand)
                    .accessibilityHidden(true)
                VStack(spacing: 6) {
                    Text("Restore from iCloud?")
                        .font(Font.app(17, .semibold))
                        .accessibilityAddTraits(.isHeader)
                    Text(verbatim: description)
                        .font(Font.app(14, .regular))
                        .foregroundStyle(Color.textSecondary)
                }
                .multilineTextAlignment(.center)
                .fixedSize(horizontal: false, vertical: true)
                VStack(spacing: 4) {
                    Button(action: restore) {
                        HStack(spacing: 8) {
                            if isRestoring { ProgressView().tint(Color.onFill) }
                            Text("Restore")
                        }
                        .font(Font.app(17, .semibold))
                        .foregroundStyle(Color.onFill)
                        .frame(maxWidth: .infinity)
                        .padding(.vertical, 4)
                    }
                    .dynamicTypeSize(...DynamicTypeSize.xxxLarge)
                    .prominentGlassButtonStyle()
                    .buttonBorderShape(.capsule)
                    .controlSize(.large)
                    .tint(Color.brandFill)
                    .disabled(isRestoring)
                    .accessibilityIdentifier("backup.offer.restore")
                    Button {
                        haptics.play(.softImpact)
                        withAnimation { backup.dismissRestoreOffer() }
                    } label: {
                        Text("Not now")
                            .font(Font.app(14, .regular))
                            .foregroundStyle(Color.brand)
                            .frame(maxWidth: .infinity, minHeight: 44)
                            .contentShape(Rectangle())
                    }
                    .buttonStyle(.plain)
                    .disabled(isRestoring)
                    .accessibilityIdentifier("backup.offer.dismiss")
                }
            }
            .frame(maxWidth: .infinity)
            .padding(.horizontal, 20)
            .padding(.top, isCompact ? 16 : 20)
            .padding(.bottom, isCompact ? 6 : 10)
        }
        .accessibilityElement(children: .contain)
        .accessibilityIdentifier("backup.offer")
        .alert("Couldn't restore the backup", isPresented: isFailing, presenting: failure) { _ in
            Button("OK", role: .cancel) {}
        } message: { message in
            Text(verbatim: message)
        }
    }

    private var description: String {
        let date = offer.summary.createdAt.formatted(date: .long, time: .omitted)
        let contents = RestoreMessages.contents(
            giftsCount: offer.summary.giftsCount, peopleCount: offer.summary.peopleCount)
        return String(
            localized: "Your backup from \(date): \(contents).",
            comment: "Home's restore offer: the backup's date and what it holds.")
    }

    private var isFailing: Binding<Bool> {
        Binding(get: { failure != nil }, set: { if !$0 { failure = nil } })
    }

    private func restore() {
        isRestoring = true
        Task {
            defer { isRestoring = false }
            let loaded: DataBackup
            do {
                loaded = try await backup.loadBackup(offer)
            } catch {
                failure = RestoreMessages.readFailure(error)
                return
            }
            if case .failed = composition.restore(loaded, source: .iCloud) {
                failure = String(localized: "Nothing was changed. Try again.")
            }
        }
    }
}

import SwiftUI

struct SignInView: View {
    let composition: AppComposition

    var body: some View {
        VStack(spacing: 0) {
            Spacer()
            IconMark(size: 96)
                .shadow(color: Color(hex: 0x10141C, alpha: 0.22), radius: 22, x: 0, y: 16)

            Text("Keep your gifts safe")
                .font(KS.font(27, .bold)).tracking(-0.5)
                .padding(.top, 26)
            Text("Sign in to back up and sync across devices — or start right now. Everything stays on this phone until you do.")
                .font(KS.font(16, .semibold))
                .foregroundColor(KS.muted2)
                .multilineTextAlignment(.center)
                .lineSpacing(4)
                .frame(maxWidth: 290)
                .padding(.top, 12)
            Spacer()

            VStack(spacing: 12) {
                // Primary, recommended path — registration is optional for now, so
                // make starting without an account the prominent, eye-catching CTA.
                Button {
                    composition.completeOnboarding.execute()
                    composition.router.showMainApp()
                } label: {
                    Text("Start without an account")
                        .font(KS.font(17, .semibold))
                        .foregroundColor(.white)
                        .frame(maxWidth: .infinity)
                        .padding(.vertical, 17)
                        .background(RoundedRectangle(cornerRadius: KS.radius, style: .continuous).fill(KS.give))
                        .shadow(color: KS.give.opacity(0.32), radius: 13, x: 0, y: 12)
                }
                .buttonStyle(.plain)

                // Sign-in isn't wired up yet — the rows below are disabled
                // placeholders so it's clear there's nothing to tap.
                Text("Sign-in is coming soon")
                    .font(KS.font(13, .semibold)).foregroundColor(KS.muted3)
                    .padding(.top, 8)

                placeholder(title: "Continue with Apple") { Image(systemName: "apple.logo") }
            }
        }
        .padding(.horizontal, 26)
        .padding(.top, 64)
        .padding(.bottom, 40)
    }

    /// A login option that isn't available yet — styled as a dimmed, inert
    /// placeholder with a "Soon" badge so users don't try to tap it.
    private func placeholder<Icon: View>(title: LocalizedStringKey,
                                         @ViewBuilder icon: () -> Icon) -> some View {
        HStack(spacing: 9) {
            icon()
            Text(title)
            Spacer(minLength: 8)
            Text("Soon")
                .font(KS.font(11, .bold)).foregroundColor(KS.muted2)
                .padding(.horizontal, 9).padding(.vertical, 3)
                .background(Capsule().fill(KS.track))
        }
        .font(KS.font(16, .semibold))
        .foregroundColor(KS.muted3)
        .frame(maxWidth: .infinity)
        .padding(.vertical, 16).padding(.horizontal, 16)
        .background(RoundedRectangle(cornerRadius: KS.radius, style: .continuous).fill(KS.card))
        .overlay(RoundedRectangle(cornerRadius: KS.radius, style: .continuous)
            .stroke(KS.border, lineWidth: 1.5))
        .opacity(0.5)
        .allowsHitTesting(false)
    }
}

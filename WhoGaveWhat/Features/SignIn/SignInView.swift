import SwiftUI

struct SignInView: View {
    let composition: AppComposition

    var body: some View {
        ScrollWhenTight {
            content
        }
        .padding(.horizontal, 26)
        .frame(maxWidth: ReadableWidth.onboarding)
        .frame(maxWidth: .infinity)
    }

    private var content: some View {
        VStack(spacing: 0) {
            Spacer()
            IconMark(size: 96)
                .softShadow(prominent: true)

            Text("Keep your gifts safe")
                .font(Font.app(27, .bold)).tracking(-0.5)
                .padding(.top, 26)
            Text("Sign in to back up and sync across devices — or start right now. Everything stays on this phone until you do.")
                .font(Font.app(16, .semibold))
                .foregroundColor(Color.textSecondary)
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
                        .font(Font.app(17, .semibold))
                        .foregroundStyle(Color.onFill)
                        .frame(maxWidth: .infinity)
                        .padding(.vertical, 6)
                }
                .buttonStyle(.glassProminent)
                .buttonBorderShape(.capsule)
                .controlSize(.large)
                .tint(Color.brandFill)

                // Sign-in isn't wired up yet — the rows below are disabled
                // placeholders so it's clear there's nothing to tap.
                Text("Sign-in is coming soon")
                    .font(Font.app(13, .semibold)).foregroundColor(Color.textSecondary)
                    .padding(.top, 8)

                placeholder(title: "Continue with Apple") { Image(systemName: "apple.logo") }
            }
        }
        .padding(.top, 64)
        .padding(.bottom, 40)
    }

    /// A login option that isn't available yet — styled as a dimmed, inert
    /// placeholder with a "Soon" badge so users don't try to tap it.
    private func placeholder<Icon: View>(
        title: LocalizedStringKey,
        @ViewBuilder icon: () -> Icon
    ) -> some View {
        HStack(spacing: 9) {
            icon()
            Text(title)
            Spacer(minLength: 8)
            Text("Soon")
                .font(Font.app(11, .bold)).foregroundColor(Color.textSecondary)
                .padding(.horizontal, 9).padding(.vertical, 3)
                .background(Capsule().fill(Color.fillTrack))
        }
        .font(Font.app(16, .semibold))
        .foregroundColor(Color.textSecondary)
        .frame(maxWidth: .infinity)
        .padding(.vertical, 16).padding(.horizontal, 16)
        .background(Capsule().fill(Color.surface))
        .overlay(Capsule().stroke(Color.separatorLine, lineWidth: 1))
        .opacity(0.5)
        .allowsHitTesting(false)
    }
}

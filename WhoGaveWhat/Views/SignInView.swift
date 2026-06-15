import SwiftUI

struct SignInView: View {
    @EnvironmentObject var store: AppStore

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

            VStack(spacing: 11) {
                Button { store.enterApp() } label: {
                    HStack(spacing: 9) {
                        Image(systemName: "apple.logo")
                        Text("Continue with Apple")
                    }
                    .font(KS.font(16, .semibold))
                    .foregroundColor(.white)
                    .frame(maxWidth: .infinity)
                    .padding(.vertical, 16)
                    .background(RoundedRectangle(cornerRadius: KS.radius, style: .continuous).fill(KS.ink))
                }

                Button { store.enterApp() } label: {
                    HStack(spacing: 9) {
                        Text("✉️").font(.system(size: 18))
                        Text("Continue with email")
                    }
                    .font(KS.font(16, .semibold))
                    .foregroundColor(KS.ink)
                    .frame(maxWidth: .infinity)
                    .padding(.vertical, 16)
                    .background(RoundedRectangle(cornerRadius: KS.radius, style: .continuous).fill(KS.card))
                    .overlay(RoundedRectangle(cornerRadius: KS.radius, style: .continuous).stroke(KS.border, lineWidth: 1.5))
                }

                Button { store.enterApp() } label: {
                    Text("Maybe later — keep it on this phone")
                        .font(KS.font(15, .semibold))
                        .foregroundColor(KS.muted)
                        .padding(.vertical, 14)
                }
            }
        }
        .padding(.horizontal, 26)
        .padding(.top, 64)
        .padding(.bottom, 40)
    }
}

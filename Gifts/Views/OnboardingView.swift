import SwiftUI

struct OnboardingView: View {
    @EnvironmentObject var store: AppStore

    var body: some View {
        VStack(spacing: 0) {
            // Skip
            HStack {
                Spacer()
                Button { store.onbSkip() } label: {
                    Text("Skip").font(KS.font(15, .bold)).foregroundColor(KS.muted)
                }
            }
            .frame(height: 22)

            Spacer()

            Group {
                switch store.onbStep {
                case 0: OnbHero()
                case 1: OnbLogged()
                default: OnbAddsUp()
                }
            }
            .id(store.onbStep)
            .transition(.opacity)

            Spacer()

            // Dots
            HStack(spacing: 7) {
                ForEach(0..<3, id: \.self) { i in
                    Capsule()
                        .fill(i == store.onbStep ? KS.give : Color(hex: 0xDDD0C2))
                        .frame(width: i == store.onbStep ? 22 : 7, height: 7)
                }
            }
            .padding(.bottom, 24)

            // CTA
            Button {
                withAnimation(.easeInOut(duration: 0.25)) { store.onbNext() }
            } label: {
                Text(store.onbStep == 2 ? "Get started" : "Continue")
                    .font(KS.font(17, .heavy))
                    .foregroundColor(.white)
                    .frame(maxWidth: .infinity)
                    .padding(.vertical, 17)
                    .background(RoundedRectangle(cornerRadius: 18, style: .continuous).fill(KS.give))
                    .shadow(color: KS.give.opacity(0.32), radius: 13, x: 0, y: 12)
            }
        }
        .padding(.horizontal, 26)
        .padding(.top, 60)
        .padding(.bottom, 30)
        .animation(.easeInOut(duration: 0.25), value: store.onbStep)
    }
}

// MARK: - Step 0: Hero

private struct OnbHero: View {
    var body: some View {
        VStack(spacing: 0) {
            ZStack {
                FloatingTile(emoji: "💐", size: 84, corner: 24, bg: .white, fontSize: 42, delay: 0)
                    .offset(x: -73, y: -33)
                FloatingTile(emoji: "⌚", size: 78, corner: 22, bg: .white, fontSize: 38, delay: 0.6)
                    .offset(x: 73, y: -67)
                FloatingTile(emoji: "🎁", size: 94, corner: 27, bg: KS.give, fontSize: 46, delay: 0.3)
                    .offset(x: 0, y: 47)
            }
            .frame(width: 230, height: 200)
            .padding(.bottom, 38)

            Text("Gifts")
                .font(KS.font(36, .black))
                .tracking(-0.6)
            Text("A warm little ledger for every gift your family gives and gets.")
                .font(KS.font(17, .semibold))
                .foregroundColor(KS.muted2)
                .multilineTextAlignment(.center)
                .lineSpacing(4)
                .frame(maxWidth: 286)
                .padding(.top, 13)
        }
    }
}

private struct FloatingTile: View {
    let emoji: String
    let size: CGFloat
    let corner: CGFloat
    let bg: Color
    let fontSize: CGFloat
    let delay: Double
    @State private var up = false

    var body: some View {
        Text(emoji)
            .font(.system(size: fontSize))
            .frame(width: size, height: size)
            .background(
                RoundedRectangle(cornerRadius: corner, style: .continuous)
                    .fill(bg)
                    .shadow(color: Color(hex: 0x785032, alpha: 0.16), radius: 16, x: 0, y: 16)
            )
            .offset(y: up ? -9 : 0)
            .onAppear {
                withAnimation(.easeInOut(duration: 2.4).repeatForever(autoreverses: true).delay(delay)) {
                    up = true
                }
            }
    }
}

// MARK: - Step 1: Logged in seconds

private struct OnbLogged: View {
    var body: some View {
        VStack(spacing: 0) {
            Card(corner: 24, strongShadow: true) {
                VStack(alignment: .leading, spacing: 0) {
                    Text("WHAT'S THE GIFT?")
                        .font(KS.font(12, .heavy)).tracking(0.7).foregroundColor(KS.muted)
                    HStack(spacing: 12) {
                        GiftSquare(emoji: "💐", tint: KS.recvTint, size: 50, fontSize: 27)
                        Text("Bouquet of roses").font(KS.font(20, .heavy))
                    }
                    .padding(.top, 11)
                    HStack(spacing: 9) {
                        Text("≈ value").font(KS.font(13, .heavy)).foregroundColor(KS.muted)
                        Text("1 800 ₽").font(KS.font(16, .black))
                        Text("we guessed")
                            .font(KS.font(11, .heavy))
                            .foregroundColor(KS.recv)
                            .padding(.horizontal, 9).padding(.vertical, 3)
                            .background(RoundedRectangle(cornerRadius: 8).fill(KS.recvTint))
                    }
                    .padding(.top, 15)
                }
                .padding(18)
            }
            .frame(width: 304)

            Text("Logged in seconds")
                .font(KS.font(27, .black)).tracking(-0.5)
                .padding(.top, 36)
            Text("Type what it was — Gifts picks the icon and guesses the value. Adjust only if you want to.")
                .font(KS.font(16, .semibold))
                .foregroundColor(KS.muted2)
                .multilineTextAlignment(.center)
                .lineSpacing(4)
                .frame(maxWidth: 292)
                .padding(.top, 11)
        }
    }
}

// MARK: - Step 2: Adds up per person

private struct OnbAddsUp: View {
    private let bars: [(String, String, Double, Color)] = [
        ("Birthday", "6 200 ₽", 0.84, KS.give),
        ("Anniversary", "4 500 ₽", 0.61, KS.gold),
        ("New Year", "4 000 ₽", 0.54, KS.recv),
    ]

    var body: some View {
        VStack(spacing: 0) {
            Card(corner: 24, strongShadow: true) {
                VStack(alignment: .leading, spacing: 0) {
                    HStack(spacing: 12) {
                        AvatarView(initials: "AM", color: KS.give, size: 46)
                        VStack(alignment: .leading, spacing: 0) {
                            Text("Aunt Maria").font(KS.font(17, .heavy))
                            Text("6 gifts together").font(KS.font(13, .bold)).foregroundColor(KS.muted3)
                        }
                        Spacer()
                        Text("14 700 ₽").font(KS.font(18, .black))
                    }
                    VStack(spacing: 10) {
                        ForEach(bars, id: \.0) { b in
                            VStack(spacing: 5) {
                                HStack {
                                    Text(b.0); Spacer(); Text(b.1)
                                }
                                .font(KS.font(12.5, .bold))
                                .foregroundColor(KS.muted2)
                                BarView(pct: b.2 * 100, color: b.3, height: 7)
                            }
                        }
                    }
                    .padding(.top, 16)
                }
                .padding(18)
            }
            .frame(width: 304)

            Text("It adds up per person")
                .font(KS.font(27, .black)).tracking(-0.5)
                .padding(.top, 34)
            Text("Every gift links to someone, so you can look back on years of giving at a glance.")
                .font(KS.font(16, .semibold))
                .foregroundColor(KS.muted2)
                .multilineTextAlignment(.center)
                .lineSpacing(4)
                .frame(maxWidth: 292)
                .padding(.top, 11)
        }
    }
}

import SwiftUI

struct OnboardingView: View {
    let router: AppRouter
    @State private var step = 0

    var body: some View {
        VStack(spacing: 0) {
            // Skip — pinned to the very top-right corner.
            HStack {
                Spacer()
                Button { router.showSignIn() } label: {
                    Text("Skip").font(KS.font(15, .bold)).foregroundColor(KS.muted)
                        .padding(.horizontal, 6).padding(.vertical, 6)
                        .contentShape(Rectangle())
                }
            }
            .padding(.top, 2)

            // Swipeable pager — drag back and forth between steps.
            TabView(selection: stepBinding) {
                page(OnbHero()).tag(0)
                page(OnbLogged()).tag(1)
                page(OnbAddsUp()).tag(2)
            }
            .tabViewStyle(.page(indexDisplayMode: .never))
            .animation(.easeInOut(duration: 0.25), value: step)

            // Dots
            HStack(spacing: 7) {
                ForEach(0..<3, id: \.self) { i in
                    Capsule()
                        .fill(i == step ? KS.give : Color(hex: 0xD7DDE5))
                        .frame(width: i == step ? 22 : 7, height: 7)
                }
            }
            .padding(.bottom, 24)

            // CTA
            Button {
                withAnimation(.easeInOut(duration: 0.25)) {
                    if step == 2 { router.showSignIn() } else { step += 1 }
                }
            } label: {
                Text(step == 2 ? "Get started" : "Continue")
                    .font(KS.font(17, .semibold))
                    .foregroundColor(.white)
                    .frame(maxWidth: .infinity)
                    .padding(.vertical, 17)
                    .background(RoundedRectangle(cornerRadius: KS.radius, style: .continuous).fill(KS.give))
                    .shadow(color: KS.give.opacity(0.32), radius: 13, x: 0, y: 12)
            }
            // Plain style: the default button fade made the CTA flicker on each tap.
            .buttonStyle(.plain)
        }
        .padding(.horizontal, 26)
        .padding(.top, 8)
        .padding(.bottom, 30)
        .animation(.easeInOut(duration: 0.25), value: step)
    }

    /// Binding that lets a swipe update the current step (and vice-versa).
    private var stepBinding: Binding<Int> {
        $step
    }

    /// Vertically centers a step's content within the pager.
    private func page<V: View>(_ content: V) -> some View {
        VStack(spacing: 0) {
            Spacer(minLength: 0)
            content
            Spacer(minLength: 0)
        }
        .frame(maxWidth: .infinity)
    }
}

// MARK: - Step 0: Hero

private struct OnbHero: View {
    var body: some View {
        VStack(spacing: 0) {
            ZStack {
                FloatingTile(emoji: "💐", size: 84, corner: KS.radius, bg: .white, fontSize: 42, delay: 0)
                    .offset(x: -73, y: -33)
                FloatingTile(emoji: "⌚", size: 78, corner: KS.radius, bg: .white, fontSize: 38, delay: 0.6)
                    .offset(x: 73, y: -67)
                FloatingMark(size: 94, delay: 0.3)
                    .offset(x: 0, y: 47)
            }
            .frame(width: 230, height: 200)
            .padding(.bottom, 38)

            Text("Who Gave What")
                .font(KS.font(36, .bold))
                .tracking(-0.6)
            Text("Never forget who gave what — or what you gave back.")
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
                    .shadow(color: Color(hex: 0x10141C, alpha: 0.16), radius: 16, x: 0, y: 16)
            )
            .offset(y: up ? -9 : 0)
            .onAppear {
                withAnimation(.easeInOut(duration: 2.4).repeatForever(autoreverses: true).delay(delay)) {
                    up = true
                }
            }
    }
}

/// The hero's center tile: the app's IconMark, floating like the others.
private struct FloatingMark: View {
    let size: CGFloat
    let delay: Double
    @State private var up = false

    var body: some View {
        IconMark(size: size)
            .shadow(color: Color(hex: 0x10141C, alpha: 0.22), radius: 16, x: 0, y: 16)
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
            Card(strongShadow: true) {
                VStack(alignment: .leading, spacing: 0) {
                    Text("WHAT'S THE GIFT?")
                        .font(KS.font(12, .semibold)).tracking(0.7).foregroundColor(KS.muted)
                    HStack(spacing: 12) {
                        GiftSquare(emoji: "💐", tint: KS.recvTint, size: 50, fontSize: 27)
                        Text("Bouquet of roses").font(KS.font(20, .semibold))
                    }
                    .padding(.top, 11)
                    HStack(spacing: 9) {
                        Text("≈ value").font(KS.font(13, .semibold)).foregroundColor(KS.muted)
                        Text("1 800 ₽").font(KS.font(16, .bold))
                        Text("we guessed")
                            .font(KS.font(11, .semibold))
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
                .font(KS.font(27, .bold)).tracking(-0.5)
                .padding(.top, 36)
            Text("Type what it was — Who Gave What picks the icon and guesses the value. Adjust only if you want to.")
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
            Card(strongShadow: true) {
                VStack(alignment: .leading, spacing: 0) {
                    HStack(spacing: 12) {
                        AvatarView(initials: "AM", color: KS.give, size: 46)
                        VStack(alignment: .leading, spacing: 0) {
                            Text("Aunt Maria").font(KS.font(17, .semibold))
                            Text("6 gifts together").font(KS.font(13, .bold)).foregroundColor(KS.muted3)
                        }
                        Spacer()
                        Text("14 700 ₽").font(KS.font(18, .bold))
                    }
                    VStack(spacing: 10) {
                        ForEach(bars, id: \.0) { b in
                            VStack(spacing: 5) {
                                HStack {
                                    Text(LocalizedStringKey(b.0)); Spacer(); Text(b.1)
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
                .font(KS.font(27, .bold)).tracking(-0.5)
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

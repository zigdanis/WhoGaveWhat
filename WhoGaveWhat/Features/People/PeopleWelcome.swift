import SwiftUI

/// People before the first person: a card whose main action adds you, since the app counts every gift as
/// received or given from your side, with adding anyone else as the quieter choice. Two tiles say what a
/// person holds. The first saved person replaces it with the list.
struct PeopleWelcome: View {
    let onAddYourself: () -> Void
    let onAddSomeoneElse: () -> Void
    @Environment(\.compactVerticalSpace) private var isCompact

    var body: some View {
        VStack(spacing: WelcomeMetrics.spacing(isCompact: isCompact)) {
            WelcomeCard(
                title: "Add yourself", identifier: "people.welcome.add-yourself",
                secondary: WelcomeSecondaryAction(
                    title: "Add someone else", identifier: "people.welcome.add-other", action: onAddSomeoneElse),
                action: onAddYourself
            ) {
                PeopleWelcomeHero(isCompact: isCompact)
            }
            WelcomeTiles {
                WelcomeTile(title: "Photo and name") {
                    PhotoAvatarIcon()
                }
                WelcomeTile(title: "Balance with each person") {
                    CountBalanceBadge(net: 0)
                        .frame(height: 48)
                }
            }
        }
        .accessibilityElement(children: .contain)
        .accessibilityIdentifier("people.welcome")
    }
}

/// Three nameless people, the middle one marked as you.
private struct PeopleWelcomeHero: View {
    let isCompact: Bool

    var body: some View {
        let side: AvatarSize = isCompact ? .compact : .regular
        let centre: AvatarSize = isCompact ? .regular : .large
        HStack(spacing: -10) {
            AvatarView(initials: "", color: Color(personHex: 0x7A5CCB), size: side)
                .offset(y: 6)
            AvatarView(initials: "", color: Color(personHex: 0x12805C), size: centre)
                .overlay(alignment: .bottom) {
                    YouBadge()
                        .overlay(Capsule().stroke(Color.surface, lineWidth: 2))
                        .offset(y: 8)
                }
                // In front of its neighbours where they overlap.
                .zIndex(1)
            AvatarView(initials: "", color: Color(personHex: 0xC26B2D), size: side)
                .offset(y: 6)
        }
        // Room for the badge hanging below the middle avatar.
        .padding(.bottom, 8)
        // The badge and the avatars are drawn to size; larger text would only push the badge out of shape.
        .dynamicTypeSize(...DynamicTypeSize.xxxLarge)
    }
}

/// A nameless avatar with a camera badge: a person can carry a photo.
private struct PhotoAvatarIcon: View {
    var body: some View {
        AvatarView(initials: "", color: Color(personHex: 0x2F6FAE), size: .regular)
            .overlay(alignment: .bottomTrailing) {
                Image(systemName: "camera.fill")
                    .font(.system(size: 10, weight: .semibold))
                    .foregroundStyle(Color.onFill)
                    .frame(width: 20, height: 20)
                    .background(Color.brandFill, in: Circle())
                    .overlay(Circle().stroke(Color.surface, lineWidth: 2))
                    .offset(x: 4, y: 2)
            }
            .frame(height: 48)
    }
}

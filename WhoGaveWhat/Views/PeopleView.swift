import SwiftUI

struct PeopleView: View {
    @EnvironmentObject var store: AppStore

    var body: some View {
        VStack(alignment: .leading, spacing: 0) {
            SectionHeader(text: "Your family").padding(.bottom, 7)
            personCard(store.members.map { ($0.id, $0.name, $0.color, true) })

            SectionHeader(text: "Friends & relatives")
                .padding(.top, 22).padding(.bottom, 7)
            personCard(store.people.map { ($0.id, $0.name, $0.color, false) })
        }
        .padding(.horizontal, 16)
        .padding(.top, 4)
    }

    private func personCard(_ entities: [(String, String, Color, Bool)]) -> some View {
        Card {
            VStack(spacing: 0) {
                ForEach(Array(entities.enumerated()), id: \.element.0) { idx, e in
                    NavigationLink(value: e.0) {
                        PersonRow(entityId: e.0, name: e.1, color: e.2, isMember: e.3)
                    }
                    .buttonStyle(.plain)
                    if idx < entities.count - 1 { RowDivider().padding(.leading, 14) }
                }
            }
        }
    }
}

struct PersonRow: View {
    @EnvironmentObject var store: AppStore
    let entityId: String
    let name: String
    let color: Color
    let isMember: Bool

    var body: some View {
        let gs = store.gifts.filter { isMember ? $0.memberId == entityId : $0.personId == entityId }
        let r = gs.filter { $0.flow == .received }.count
        let gv = gs.filter { $0.flow == .given }.count

        HStack(spacing: 12) {
            AvatarView(initials: store.initials(name), color: color, size: 42)
            VStack(alignment: .leading, spacing: 2) {
                Text(name).font(KS.font(16, .semibold)).foregroundColor(KS.ink)
                Text("\(r) received · \(gv) given")
                    .font(KS.font(13, .regular)).foregroundColor(KS.muted3)
            }
            Spacer(minLength: 8)
            Text(rub(store.sum(gs)))
                .font(KS.font(15, .semibold)).foregroundColor(KS.ink)
            Chevron()
        }
        .padding(.horizontal, 14).padding(.vertical, 13)
        .contentShape(Rectangle())
    }
}

import SwiftUI

struct PeopleView: View {
    @EnvironmentObject var store: AppStore

    var body: some View {
        VStack(alignment: .leading, spacing: 0) {
            Text("People").font(KS.font(28, .black)).tracking(-0.6)
            Text("Everyone you give to and get from")
                .font(KS.font(15, .bold)).foregroundColor(KS.muted)
                .padding(.top, 1).padding(.bottom, 18)

            SectionHeader(text: "Your family").padding(.bottom, 9)
            personCard(store.members.map { ($0.id, $0.name, $0.color, true) })

            SectionHeader(text: "Friends & relatives")
                .padding(.top, 22).padding(.bottom, 9)
            personCard(store.people.map { ($0.id, $0.name, $0.color, false) })
        }
        .padding(.horizontal, 20)
    }

    private func personCard(_ entities: [(String, String, Color, Bool)]) -> some View {
        Card {
            VStack(spacing: 0) {
                ForEach(Array(entities.enumerated()), id: \.element.0) { idx, e in
                    Button { store.openDetail(e.0) } label: {
                        PersonRow(entityId: e.0, name: e.1, color: e.2, isMember: e.3)
                    }
                    .buttonStyle(.plain)
                    if idx < entities.count - 1 { RowDivider() }
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

        HStack(spacing: 13) {
            AvatarView(initials: store.initials(name), color: color, size: 44)
            VStack(alignment: .leading, spacing: 2) {
                Text(name).font(KS.font(16, .heavy))
                Text("\(r) received · \(gv) given")
                    .font(KS.font(13, .bold)).foregroundColor(KS.muted3)
            }
            Spacer(minLength: 8)
            VStack(alignment: .trailing, spacing: 2) {
                Text(rub(store.sum(gs))).font(KS.font(15, .black))
                Text("\(gs.count) gifts").font(KS.font(12, .bold)).foregroundColor(KS.muted4)
            }
            Text("›").font(KS.font(25, .bold)).foregroundColor(KS.chevron)
        }
        .padding(.horizontal, 15).padding(.vertical, 13)
    }
}

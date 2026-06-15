import SwiftUI

/// Native sheet for adding a gift. Presentation, drag-to-dismiss, and the glass
/// toolbar come from the system; the form keeps the app's brand styling.
struct AddGiftSheet: View {
    @EnvironmentObject var store: AppStore

    var body: some View {
        NavigationStack {
            ScrollView {
                VStack(alignment: .leading, spacing: 0) {
                    flowSegment
                    fieldHeader("What's the gift?", top: 18)
                    nameField
                    valueField
                    if !store.add.valueTouched && !nameTrimmed.isEmpty {
                        Text("✦ We guessed this from the name — tap to change.")
                            .font(KS.font(12.5, .heavy)).foregroundColor(KS.recv)
                            .padding(.top, 7).padding(.leading, 4)
                    }

                    fieldHeader(store.add.flow == .received ? "Received from" : "Given to", top: 18)
                    personChips

                    fieldHeader(store.add.flow == .received ? "Who received it" : "On behalf of", top: 14)
                    memberChips

                    if store.add.flow == .given { paidToggle }

                    fieldHeader("Celebration", top: 18)
                    celebrationChips

                    fieldHeader("When", top: 18)
                    dateChips

                    saveButton
                }
                .padding(.horizontal, 20).padding(.top, 6).padding(.bottom, 28)
            }
            .scrollIndicators(.hidden)
            .background(KS.bg)
            .navigationTitle("Add a gift")
            .navigationBarTitleDisplayMode(.inline)
            .toolbar {
                ToolbarItem(placement: .cancellationAction) {
                    Button("Cancel") { store.closeSheet() }
                        .tint(KS.muted2)
                }
                ToolbarItem(placement: .confirmationAction) {
                    Button("Save") { store.saveGift() }
                        .tint(fm.main)
                        .fontWeight(.bold)
                        .disabled(!can)
                }
            }
        }
        .presentationDetents([.large])
        .presentationDragIndicator(.visible)
    }

    private var fm: FlowMeta { store.flowMeta(store.add.flow) }
    private var sug: Suggestion { store.suggest(store.add.name) }
    private var nameTrimmed: String { store.add.name.trimmingCharacters(in: .whitespaces) }
    private var can: Bool { store.canSave() }

    // MARK: Pieces

    private func fieldHeader(_ text: String, top: CGFloat) -> some View {
        Text(text.uppercased())
            .font(KS.font(12.5, .heavy)).tracking(0.5).foregroundColor(KS.muted)
            .padding(.top, top).padding(.bottom, 8).padding(.leading, 2)
    }

    private var flowSegment: some View {
        HStack(spacing: 4) {
            segment("Received", flow: .received, accent: KS.recv)
            segment("Given", flow: .given, accent: KS.give)
        }
        .padding(4)
        .background(RoundedRectangle(cornerRadius: KS.radius, style: .continuous).fill(KS.track))
    }

    private func segment(_ label: String, flow: Flow, accent: Color) -> some View {
        let sel = store.add.flow == flow
        return Button {
            withAnimation(.easeOut(duration: 0.15)) { store.add.flow = flow }
        } label: {
            Text(label)
                .font(KS.font(15, .heavy))
                .foregroundColor(sel ? accent : KS.muted3)
                .frame(maxWidth: .infinity)
                .padding(.vertical, 10)
                .background(
                    RoundedRectangle(cornerRadius: KS.radius, style: .continuous)
                        .fill(sel ? Color.white : Color.clear)
                        .shadow(color: sel ? .black.opacity(0.07) : .clear, radius: 4, x: 0, y: 2)
                )
        }
        .buttonStyle(.plain)
    }

    private var nameField: some View {
        HStack(spacing: 12) {
            Text(nameTrimmed.isEmpty ? "🎁" : sug.emoji)
                .font(.system(size: 27))
                .frame(width: 48, height: 48)
                .background(RoundedRectangle(cornerRadius: KS.radius, style: .continuous).fill(fm.tint))
            TextField("Bouquet, watch, money…", text: nameBinding)
                .font(KS.font(18, .heavy)).foregroundColor(KS.ink)
                .tint(fm.main)
        }
        .padding(.horizontal, 13).padding(.vertical, 11)
        .fieldBox()
    }

    private var valueField: some View {
        HStack(spacing: 10) {
            Text("Approx. value").font(KS.font(14, .heavy)).foregroundColor(KS.muted)
            TextField("", text: valueBinding)
                .font(KS.font(18, .black)).foregroundColor(KS.ink)
                .multilineTextAlignment(.trailing)
                .keyboardType(.numberPad)
                .tint(fm.main)
            Text("₽").font(KS.font(17, .black)).foregroundColor(KS.muted)
        }
        .padding(.horizontal, 14).padding(.vertical, 13)
        .fieldBox()
        .padding(.top, 11)
    }

    private var personChips: some View {
        ScrollView(.horizontal, showsIndicators: false) {
            HStack(spacing: 6) {
                ForEach(store.people) { p in
                    let sel = store.add.personId == p.id
                    Button { store.add.personId = p.id } label: {
                        VStack(spacing: 6) {
                            AvatarView(initials: store.initials(p.name), color: p.color, size: 48, selected: sel)
                            Text(store.first(p.name))
                                .font(KS.font(12.5, .heavy))
                                .foregroundColor(sel ? KS.ink : KS.muted3)
                                .lineLimit(1)
                        }
                        .frame(minWidth: 58)
                        .padding(2)
                    }
                    .buttonStyle(.plain)
                }
            }
            .padding(.vertical, 2)
        }
    }

    private var memberChips: some View {
        FlowLayout(spacing: 8, lineSpacing: 8) {
            ForEach(store.members) { m in
                Button { store.add.memberId = m.id } label: {
                    ChipView(label: m.name, selected: store.add.memberId == m.id, accent: fm.main)
                }
                .buttonStyle(.plain)
            }
        }
    }

    private var celebrationChips: some View {
        FlowLayout(spacing: 8, lineSpacing: 8) {
            ForEach(store.celebrations, id: \.self) { c in
                Button { store.add.celebration = c } label: {
                    ChipView(label: c, selected: store.add.celebration == c, accent: fm.main)
                }
                .buttonStyle(.plain)
            }
        }
    }

    private var dateChips: some View {
        HStack(spacing: 8) {
            ForEach(["Today", "Yesterday", "Earlier"], id: \.self) { d in
                Button { store.add.date = d } label: {
                    ChipView(label: d, selected: store.add.date == d, accent: fm.main)
                }
                .buttonStyle(.plain)
            }
        }
    }

    private var paidToggle: some View {
        Button {
            withAnimation(.easeOut(duration: 0.2)) { store.add.paidByYou.toggle() }
        } label: {
            HStack(spacing: 11) {
                Text("💳").font(.system(size: 22))
                VStack(alignment: .leading, spacing: 1) {
                    Text("Paid by you").font(KS.font(15, .heavy)).foregroundColor(KS.ink)
                    Text("Quietly track who actually covered it")
                        .font(KS.font(12.5, .bold)).foregroundColor(KS.muted3)
                }
                Spacer()
                ZStack(alignment: store.add.paidByYou ? .trailing : .leading) {
                    Capsule().fill(store.add.paidByYou ? KS.recv : Color(hex: 0xD7DDE5))
                        .frame(width: 46, height: 28)
                    Circle().fill(.white).frame(width: 22, height: 22)
                        .shadow(color: .black.opacity(0.25), radius: 1, x: 0, y: 1)
                        .padding(.horizontal, 3)
                }
            }
            .padding(.horizontal, 14).padding(.vertical, 13)
            .fieldBox()
            .padding(.top, 16)
        }
        .buttonStyle(.plain)
    }

    private var saveButton: some View {
        Button { store.saveGift() } label: {
            Text(store.add.flow == .received ? "Save received gift" : "Save given gift")
                .font(KS.font(17, .heavy)).foregroundColor(.white)
                .frame(maxWidth: .infinity).padding(.vertical, 16)
                .background(
                    RoundedRectangle(cornerRadius: KS.radius, style: .continuous)
                        .fill(can ? fm.main : Color(hex: 0xC3CAD3))
                        .shadow(color: can ? fm.tint : .clear, radius: 13, x: 0, y: 12)
                )
        }
        .buttonStyle(.plain)
        .disabled(!can)
        .padding(.top, 24)
    }

    // MARK: Bindings

    private var nameBinding: Binding<String> {
        Binding(get: { store.add.name }, set: { store.add.name = $0 })
    }

    private var valueBinding: Binding<String> {
        Binding(
            get: {
                let eff = store.add.valueTouched ? store.add.value : Int(sug.value)
                return eff.map(String.init) ?? ""
            },
            set: { newVal in
                let digits = newVal.filter(\.isNumber)
                store.add.value = digits.isEmpty ? 0 : Int(digits)
                store.add.valueTouched = true
            }
        )
    }
}

private extension View {
    func fieldBox(corner: CGFloat = KS.radius) -> some View {
        background(
            RoundedRectangle(cornerRadius: corner, style: .continuous)
                .fill(KS.card)
                .overlay(RoundedRectangle(cornerRadius: corner, style: .continuous).stroke(KS.border, lineWidth: 1.5))
        )
    }
}

import SwiftUI

/// Native sheet for adding a gift. The form is quiet: a tinted hero card for the
/// gift itself, then a grouped list of tap-to-reveal pickers (person, member,
/// occasion, date) — each opens its own bottom sheet with manual-entry support.
struct AddGiftSheet: View {
    @EnvironmentObject var store: AppStore

    var body: some View {
        NavigationStack {
            ScrollView {
                VStack(alignment: .leading, spacing: 0) {
                    flowSegment.padding(.bottom, 18)

                    heroCard

                    SectionHeader(text: "Details").padding(.top, 22).padding(.bottom, 7)
                    detailsCard

                    if store.add.flow == .given {
                        paidCard.padding(.top, 12)
                    }

                    saveButton.padding(.top, 24)
                }
                .padding(.horizontal, 16).padding(.top, 6).padding(.bottom, 30)
            }
            .scrollIndicators(.hidden)
            .background(KS.bg)
            .navigationTitle("Add a gift")
            .navigationBarTitleDisplayMode(.inline)
            .toolbar {
                ToolbarItem(placement: .cancellationAction) {
                    Button("Cancel") { store.closeSheet() }.tint(KS.muted2)
                }
            }
        }
        .presentationDetents([.large])
        .presentationDragIndicator(.visible)
        .sheet(item: pickerBinding) { kind in
            PickerSheet(kind: kind)
        }
    }

    private var fm: FlowMeta { store.flowMeta(store.add.flow) }
    private var sug: Suggestion { store.suggest(store.add.name) }
    private var can: Bool { store.canSave() }

    // MARK: Flow segment

    private var flowSegment: some View {
        Segmented(options: [.init(key: "received", label: "Received", accent: KS.recv),
                            .init(key: "given", label: "Given", accent: KS.ink)],
                  selected: store.add.flow.rawValue) { key in
            withAnimation(.easeOut(duration: 0.15)) {
                store.add.flow = Flow(rawValue: key) ?? .received
            }
        }
    }

    // MARK: Hero card (emoji + name + inline value)

    private var heroCard: some View {
        HStack(alignment: .top, spacing: 14) {
            Button { store.openPicker(.emoji) } label: { emojiTile }
                .buttonStyle(.plain)

            VStack(alignment: .leading, spacing: 7) {
                TextField("Bouquet, watch, money…", text: nameBinding)
                    .font(KS.font(19, .bold)).foregroundColor(KS.ink)
                    .tint(fm.main)
                valueRow
            }
            .padding(.top, 4)
        }
        .padding(16)
        .frame(maxWidth: .infinity, alignment: .leading)
        .background(RoundedRectangle(cornerRadius: KS.radius, style: .continuous).fill(fm.tint))
    }

    private var emojiTile: some View {
        Text(store.effEmoji(store.add))
            .font(.system(size: 28))
            .frame(width: 58, height: 58)
            .background(RoundedRectangle(cornerRadius: KS.radius, style: .continuous).fill(.white))
            .overlay(alignment: .bottomTrailing) {
                Image(systemName: "pencil")
                    .font(.system(size: 9, weight: .bold))
                    .foregroundColor(.white)
                    .frame(width: 19, height: 19)
                    .background(Circle().fill(fm.main))
                    .overlay(Circle().stroke(fm.tint, lineWidth: 2.5))
                    .offset(x: 6, y: 6)
            }
    }

    private var valueRow: some View {
        HStack(spacing: 5) {
            TextField("0", text: valueBinding)
                .font(KS.font(15, .semibold)).foregroundColor(KS.ink)
                .keyboardType(.numberPad)
                .tint(fm.main)
                .fixedSize()
            Text("₽").font(KS.font(15, .semibold)).foregroundColor(KS.muted2)
            if !store.add.valueTouched {
                Text("estimated")
                    .font(KS.font(11, .semibold)).foregroundColor(fm.main)
                    .padding(.horizontal, 7).padding(.vertical, 2)
                    .background(Capsule().fill(.white.opacity(0.75)))
            }
            Spacer(minLength: 0)
        }
    }

    // MARK: Detail pickers

    private var detailsCard: some View {
        Card {
            VStack(spacing: 0) {
                detailRow(icon: "person.fill",
                          label: store.add.flow == .received ? "Received from" : "Given to",
                          value: store.add.personId.map(store.personName)) { store.openPicker(.person) }
                RowDivider().padding(.leading, 58)
                detailRow(icon: "person.2.fill",
                          label: store.add.flow == .received ? "Who received it" : "On behalf of",
                          value: store.add.memberId.map(store.memberName)) { store.openPicker(.member) }
                RowDivider().padding(.leading, 58)
                detailRow(icon: "party.popper.fill", label: "Occasion",
                          value: store.add.celebration) { store.openPicker(.celeb) }
                RowDivider().padding(.leading, 58)
                detailRow(icon: "calendar", label: "Date",
                          value: store.dateLabel(store.add.date)) { store.openPicker(.date) }
            }
        }
    }

    private func detailRow(icon: String, label: String, value: String?,
                           action: @escaping () -> Void) -> some View {
        Button(action: action) {
            HStack(spacing: 12) {
                Image(systemName: icon)
                    .font(.system(size: 15, weight: .semibold))
                    .foregroundColor(fm.main)
                    .frame(width: 34, height: 34)
                    .background(RoundedRectangle(cornerRadius: KS.radius, style: .continuous).fill(fm.tint))
                Text(label).font(KS.font(16, .regular)).foregroundColor(KS.ink)
                Spacer(minLength: 8)
                Text(value ?? "Choose")
                    .font(KS.font(16, value == nil ? .regular : .semibold))
                    .foregroundColor(value == nil ? KS.placeholder : fm.main)
                    .lineLimit(1)
                Chevron()
            }
            .padding(.horizontal, 14).padding(.vertical, 10)
            .contentShape(Rectangle())
        }
        .buttonStyle(.plain)
    }

    // MARK: Paid toggle (given only)

    private var paidCard: some View {
        Card {
            Toggle(isOn: paidBinding) {
                VStack(alignment: .leading, spacing: 2) {
                    Text("Paid by you").font(KS.font(16, .regular)).foregroundColor(KS.ink)
                    Text("Track who actually covered it")
                        .font(KS.font(13, .regular)).foregroundColor(KS.muted3)
                }
            }
            .tint(KS.emerald)
            .padding(.horizontal, 14).padding(.vertical, 10)
        }
    }

    // MARK: Save

    private var saveButton: some View {
        Button { store.saveGift() } label: {
            Text(store.add.flow == .received ? "Save received gift" : "Save given gift")
                .font(KS.font(17, .semibold)).foregroundColor(.white)
                .frame(maxWidth: .infinity).padding(.vertical, 16)
                .background(RoundedRectangle(cornerRadius: KS.radius, style: .continuous)
                    .fill(can ? KS.ink : Color(hex: 0xC3CAD3)))
        }
        .buttonStyle(.plain)
        .disabled(!can)
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

    private var paidBinding: Binding<Bool> {
        Binding(get: { store.add.paidByYou }, set: { store.add.paidByYou = $0 })
    }

    private var pickerBinding: Binding<PickerKind?> {
        Binding(get: { store.picker }, set: { if $0 == nil { store.closePicker() } })
    }
}

// MARK: - Picker bottom sheets

/// One tap-to-reveal picker — list (person / member / occasion), emoji grid, or
/// date — each with manual-entry support so the user can add a new option inline.
private struct PickerSheet: View {
    @EnvironmentObject var store: AppStore
    let kind: PickerKind
    @State private var customText = ""
    @State private var tempDate = AppStore.today

    var body: some View {
        NavigationStack {
            content
                .background(KS.bg)
                .navigationBarTitleDisplayMode(.inline)
                .toolbar {
                    ToolbarItem(placement: .cancellationAction) {
                        Button("Cancel") { store.closePicker() }.tint(KS.muted2)
                    }
                }
        }
        .presentationDetents(kind == .date ? [.large] : [.medium, .large])
        .presentationDragIndicator(.visible)
    }

    @ViewBuilder
    private var content: some View {
        switch kind {
        case .person:
            entityPicker(title: "Received from / Given to",
                         entities: store.people.map { ($0.id, $0.name, $0.color) },
                         selected: store.add.personId, isFamily: false) { store.selectPerson($0) }
        case .member:
            entityPicker(title: "Family member",
                         entities: store.members.map { ($0.id, $0.name, $0.color) },
                         selected: store.add.memberId, isFamily: true) { store.selectMember($0) }
        case .celeb:
            celebPicker
        case .emoji:
            emojiPicker
        case .date:
            datePicker
        }
    }

    // MARK: People / members

    private func entityPicker(title: String, entities: [(String, String, Color)],
                              selected: String?, isFamily: Bool,
                              select: @escaping (String) -> Void) -> some View {
        ScrollView {
            VStack(spacing: 16) {
                Card {
                    VStack(spacing: 0) {
                        ForEach(Array(entities.enumerated()), id: \.element.0) { idx, e in
                            Button { select(e.0) } label: {
                                HStack(spacing: 12) {
                                    AvatarView(initials: store.initials(e.1), color: e.2, size: 38)
                                    Text(e.1).font(KS.font(16, .semibold)).foregroundColor(KS.ink)
                                    Spacer(minLength: 8)
                                    if selected == e.0 { checkmark }
                                }
                                .padding(.horizontal, 14).padding(.vertical, 11)
                                .contentShape(Rectangle())
                            }
                            .buttonStyle(.plain)
                            if idx < entities.count - 1 { RowDivider().padding(.leading, 14) }
                        }
                    }
                }
                addRow(placeholder: isFamily ? "Add family member" : "Add person") {
                    store.addCustomPerson($0, isFamily: isFamily)
                }
            }
            .padding(16)
        }
        .scrollIndicators(.hidden)
        .navigationTitle(title)
    }

    // MARK: Occasion

    private var celebPicker: some View {
        ScrollView {
            VStack(spacing: 16) {
                Card {
                    VStack(spacing: 0) {
                        ForEach(Array(store.celebrations.enumerated()), id: \.element) { idx, c in
                            Button { store.selectCeleb(c) } label: {
                                HStack {
                                    Text(c).font(KS.font(16, .regular)).foregroundColor(KS.ink)
                                    Spacer(minLength: 8)
                                    if store.add.celebration == c { checkmark }
                                }
                                .padding(.horizontal, 14).padding(.vertical, 12)
                                .contentShape(Rectangle())
                            }
                            .buttonStyle(.plain)
                            if idx < store.celebrations.count - 1 { RowDivider().padding(.leading, 14) }
                        }
                    }
                }
                addRow(placeholder: "Add occasion") { store.addCustomCeleb($0) }
            }
            .padding(16)
        }
        .scrollIndicators(.hidden)
        .navigationTitle("Occasion")
    }

    // MARK: Emoji

    private var emojiPicker: some View {
        ScrollView {
            VStack(spacing: 16) {
                Card {
                    LazyVGrid(columns: Array(repeating: GridItem(.flexible(), spacing: 8), count: 5), spacing: 8) {
                        ForEach(store.emojiChoices, id: \.self) { e in
                            Button { store.selectEmoji(e) } label: {
                                Text(e).font(.system(size: 26))
                                    .frame(maxWidth: .infinity).frame(height: 48)
                                    .background(RoundedRectangle(cornerRadius: KS.radius, style: .continuous)
                                        .fill(store.add.emoji == e ? KS.recvTint : KS.track))
                            }
                            .buttonStyle(.plain)
                        }
                    }
                    .padding(12)
                }
                addRow(placeholder: "Type any emoji or letter") { store.useCustomEmoji($0) }
            }
            .padding(16)
        }
        .scrollIndicators(.hidden)
        .navigationTitle("Pick an emoji")
    }

    // MARK: Date

    private var datePicker: some View {
        ScrollView {
            VStack(spacing: 16) {
                HStack(spacing: 10) {
                    quickDate("Today", AppStore.today)
                    quickDate("Yesterday", AppStore.yesterday)
                }
                Card {
                    DatePicker("", selection: $tempDate, displayedComponents: .date)
                        .datePickerStyle(.graphical)
                        .tint(KS.recv)
                        .padding(.horizontal, 10).padding(.vertical, 6)
                }
                Button { store.selectDate(tempDate) } label: {
                    Text("Use this date")
                        .font(KS.font(17, .semibold)).foregroundColor(.white)
                        .frame(maxWidth: .infinity).padding(.vertical, 15)
                        .background(RoundedRectangle(cornerRadius: KS.radius, style: .continuous).fill(KS.ink))
                }
                .buttonStyle(.plain)
            }
            .padding(16)
        }
        .scrollIndicators(.hidden)
        .navigationTitle("Pick a date")
        .onAppear { tempDate = store.add.date }
    }

    private func quickDate(_ label: String, _ date: Date) -> some View {
        Button { store.selectDate(date) } label: {
            Text(label).font(KS.font(15, .semibold)).foregroundColor(KS.ink)
                .frame(maxWidth: .infinity).padding(.vertical, 13)
                .background(RoundedRectangle(cornerRadius: KS.radius, style: .continuous).fill(KS.card))
        }
        .buttonStyle(.plain)
    }

    // MARK: Shared bits

    private var checkmark: some View {
        Image(systemName: "checkmark")
            .font(.system(size: 15, weight: .semibold))
            .foregroundColor(KS.recv)
    }

    private func addRow(placeholder: String, add: @escaping (String) -> Void) -> some View {
        Card {
            HStack(spacing: 10) {
                TextField(placeholder, text: $customText)
                    .font(KS.font(16, .regular)).tint(KS.recv)
                Button {
                    add(customText); customText = ""
                } label: {
                    Text("Add").font(KS.font(15, .semibold)).foregroundColor(.white)
                        .padding(.horizontal, 16).padding(.vertical, 8)
                        .background(Capsule().fill(addDisabled ? KS.muted4 : KS.ink))
                }
                .buttonStyle(.plain)
                .disabled(addDisabled)
            }
            .padding(.horizontal, 14).padding(.vertical, 10)
        }
    }

    private var addDisabled: Bool {
        customText.trimmingCharacters(in: .whitespaces).isEmpty
    }
}

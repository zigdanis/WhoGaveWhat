import SwiftUI

/// Native sheet for adding a gift. The form is quiet: a tinted hero card for the
/// gift itself, then a grouped list of tap-to-reveal pickers (person, member,
/// occasion, date) — each opens its own bottom sheet with manual-entry support.
struct AddGiftSheet: View {
    @EnvironmentObject var store: AppStore
    @FocusState private var focus: Field?

    /// The two inline text inputs in the hero card.
    private enum Field { case name, value }

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
            .scrollDismissesKeyboard(.interactively)
            // Tap anywhere off the keyboard (empty areas of the form) to dismiss it.
            // Sits behind the fields, so taps on the inputs still focus them.
            .background(KS.bg.contentShape(Rectangle()).onTapGesture { focus = nil })
            .navigationTitle(LocalizedStringKey(store.editingGiftId == nil ? "Add a gift" : "Edit gift"))
            .navigationBarTitleDisplayMode(.inline)
            // Paint the nav bar the same grouped grey as the body so the sheet
            // reads as one uniform surface (no white top / grey middle seam).
            .toolbarBackground(KS.bg, for: .navigationBar)
            .toolbarBackground(.visible, for: .navigationBar)
            .toolbar {
                ToolbarItem(placement: .cancellationAction) {
                    Button("Cancel") { store.closeSheet() }.tint(KS.muted2)
                }
            }
            // Opening a picker must drop keyboard focus so it doesn't bounce back
            // onto the previously-edited text field when the picker sheet closes.
            .onChange(of: store.picker) { _, _ in focus = nil }
            // Open the keyboard on the gift title the moment the sheet settles.
            .onAppear {
                DispatchQueue.main.asyncAfter(deadline: .now() + 0.4) { focus = .name }
            }
        }
        .presentationDetents([.large])
        .presentationDragIndicator(.visible)
        .presentationBackground(KS.bg)
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

    // MARK: Hero card (emoji + name + value, each its own tappable field)

    private var heroCard: some View {
        VStack(spacing: 12) {
            HStack(alignment: .center, spacing: 14) {
                Button { store.openPicker(.emoji) } label: { emojiTile }
                    .buttonStyle(.plain)
                nameField
            }
            valueField
        }
        .padding(16)
        .frame(maxWidth: .infinity, alignment: .leading)
        .background(RoundedRectangle(cornerRadius: KS.radius, style: .continuous).fill(fm.tint))
    }

    /// Gift title — a tall white field; the whole surface focuses the input so
    /// the tap target is forgiving.
    private var nameField: some View {
        TextField("Bouquet, watch, money…", text: nameBinding)
            .font(KS.font(18, .bold)).foregroundColor(KS.ink)
            .tint(fm.main)
            .focused($focus, equals: .name)
            .submitLabel(.next)
            .onSubmit { focus = .value }
            .frame(maxWidth: .infinity, alignment: .leading)
            .padding(.horizontal, 14)
            .frame(height: 58)
            .background(fieldSurface)
            .contentShape(Rectangle())
            .onTapGesture { focus = .name }
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

    /// Approximate value — its own tall white field, separated from the title so
    /// each is easy to hit. Tapping anywhere on the row focuses the number input.
    private var valueField: some View {
        HStack(spacing: 6) {
            TextField("0", text: valueBinding)
                .font(KS.font(16, .semibold)).foregroundColor(KS.ink)
                .keyboardType(.numberPad)
                .tint(fm.main)
                .focused($focus, equals: .value)
                .fixedSize()
            Text("₽").font(KS.font(16, .semibold)).foregroundColor(KS.muted2)
            if !store.add.valueTouched {
                Text("estimated")
                    .font(KS.font(11, .semibold)).foregroundColor(fm.main)
                    .padding(.horizontal, 8).padding(.vertical, 3)
                    .background(Capsule().fill(fm.tint))
            }
            Spacer(minLength: 0)
        }
        .padding(.horizontal, 14)
        .frame(height: 54)
        .frame(maxWidth: .infinity)
        .background(fieldSurface)
        .contentShape(Rectangle())
        .onTapGesture { focus = .value }
    }

    /// Shared white, lightly-bordered surface that lifts the inputs off the
    /// tinted hero card and the grouped background behind it.
    private var fieldSurface: some View {
        RoundedRectangle(cornerRadius: KS.radius, style: .continuous)
            .fill(KS.card)
            .overlay(
                RoundedRectangle(cornerRadius: KS.radius, style: .continuous)
                    .stroke(KS.border, lineWidth: 1)
            )
            .ksCardShadow()
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
                          value: store.locCeleb(store.add.celebration)) { store.openPicker(.celeb) }
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
                Text(LocalizedStringKey(label)).font(KS.font(16, .regular)).foregroundColor(KS.ink)
                Spacer(minLength: 8)
                Text(value ?? String(localized: "Choose"))
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
            Text(saveTitle)
                .font(KS.font(17, .semibold)).foregroundColor(.white)
                .frame(maxWidth: .infinity).padding(.vertical, 16)
                .background(RoundedRectangle(cornerRadius: KS.radius, style: .continuous)
                    .fill(can ? KS.ink : Color(hex: 0xC3CAD3)))
        }
        .buttonStyle(.plain)
        .disabled(!can)
    }

    private var saveTitle: LocalizedStringKey {
        if store.editingGiftId != nil { return "Save changes" }
        return store.add.flow == .received ? "Save received gift" : "Save given gift"
    }

    // MARK: Bindings

    private var nameBinding: Binding<String> {
        Binding(get: { store.add.name }, set: { store.setName($0) })
    }

    private var valueBinding: Binding<String> {
        Binding(
            get: {
                let eff = store.add.valueTouched ? store.add.value : Int(store.effValue(store.add))
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
                .toolbarBackground(KS.bg, for: .navigationBar)
                .toolbarBackground(.visible, for: .navigationBar)
        }
        // No Cancel button — these sheets are dismissed with a swipe down.
        .presentationDetents(kind == .date ? [.large] : [.medium, .large])
        .presentationDragIndicator(.visible)
        .presentationBackground(KS.bg)
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
                // Manual-entry first — add a new option from the top of the sheet.
                addRow(placeholder: isFamily ? "Add family member" : "Add person") {
                    store.addCustomPerson($0, isFamily: isFamily)
                }
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
            }
            .padding(16)
        }
        .scrollIndicators(.hidden)
        .navigationTitle(LocalizedStringKey(title))
    }

    // MARK: Occasion

    private var celebPicker: some View {
        ScrollView {
            VStack(spacing: 16) {
                // Manual-entry first — add a new option from the top of the sheet.
                addRow(placeholder: "Add occasion") { store.addCustomCeleb($0) }
                Card {
                    VStack(spacing: 0) {
                        ForEach(Array(store.celebrations.enumerated()), id: \.element) { idx, c in
                            Button { store.selectCeleb(c) } label: {
                                HStack {
                                    Text(store.locCeleb(c)).font(KS.font(16, .regular)).foregroundColor(KS.ink)
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
                // Manual-entry first — type your own before the grid of choices,
                // with a live preview of the single character that will be used.
                VStack(alignment: .leading, spacing: 7) {
                    iconAddRow
                    Text("Pick one below, or type your own — any letter or symbol fits.")
                        .font(KS.font(12, .regular)).foregroundColor(KS.muted3)
                        .padding(.horizontal, 4)
                }
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
            }
            .padding(16)
        }
        .scrollIndicators(.hidden)
        .navigationTitle("Icon")
    }

    /// Manual icon entry with a live preview tile: only the first character is
    /// used as the icon, so the preview makes that obvious as you type.
    private var iconAddRow: some View {
        Card {
            HStack(spacing: 12) {
                Text(iconPreview)
                    .font(.system(size: 24))
                    .frame(width: 46, height: 46)
                    .background(RoundedRectangle(cornerRadius: KS.radius, style: .continuous).fill(KS.track))
                TextField("Type any icon or letter", text: $customText)
                    .font(KS.font(16, .regular)).tint(KS.recv)
                Button {
                    store.useCustomEmoji(customText); customText = ""
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

    /// First character of the typed text (the part actually used), or a gift
    /// fallback while the field is empty.
    private var iconPreview: String {
        let g = store.firstGrapheme(customText)
        return g.isEmpty ? "🎁" : g
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
            Text(LocalizedStringKey(label)).font(KS.font(15, .semibold)).foregroundColor(KS.ink)
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
                TextField(LocalizedStringKey(placeholder), text: $customText)
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

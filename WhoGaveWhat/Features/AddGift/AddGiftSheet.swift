import SwiftUI

/// Native sheet for adding a gift. There's no Received/Given toggle any more —
/// the user just picks who gave it (From) and who got it (To); direction is
/// derived from whichever side belongs to the household. The
/// form is quiet: a tinted hero card for the gift itself, then a grouped list of
/// tap-to-reveal pickers (from, to, occasion, date).
struct AddGiftSheet: View {
    let composition: AppComposition
    @State private var state: AddGiftState
    @FocusState private var focus: Field?

    init(route: GiftSheetRoute, composition: AppComposition) {
        self.composition = composition
        _state = State(initialValue: AddGiftState(
            route: route,
            data: composition.data,
            suggestGift: composition.suggestGift
        ))
    }

    /// The two inline text inputs in the hero card.
    private enum Field { case name, value }

    var body: some View {
        NavigationStack {
            ScrollView {
                VStack(alignment: .leading, spacing: 0) {
                    heroCard

                    SectionHeader(text: "Details").padding(.top, 22).padding(.bottom, 7)
                    detailsCard

                    if showPaidToggle {
                        paidCard.padding(.top, 12)
                    }

                    saveButton.padding(.top, 24)
                }
                .padding(.horizontal, 16).padding(.top, 6).padding(.bottom, 30)
                // Taps on any non-interactive part of the form (card padding,
                // section headers, gaps) drop keyboard focus. Buttons and text
                // fields consume their own taps first, so this only fires on the
                // "dead" areas — closing the keyboard no matter which field was up.
                .contentShape(Rectangle())
                .onTapGesture { focus = nil }
            }
            .scrollIndicators(.hidden)
            .scrollDismissesKeyboard(.interactively)
            // Empty scroll area below the content also dismisses the keyboard.
            .background(KS.bg.contentShape(Rectangle()).onTapGesture { focus = nil })
            .navigationTitle(state.editingGiftID == nil ? "Add a gift" : "Edit gift")
            .navigationBarTitleDisplayMode(.inline)
            // Paint the nav bar the same grouped grey as the body so the sheet
            // reads as one uniform surface (no white top / grey middle seam).
            .toolbarBackground(KS.bg, for: .navigationBar)
            .toolbarBackground(.visible, for: .navigationBar)
            .toolbar {
                ToolbarItem(placement: .cancellationAction) {
                    Button("Cancel") { composition.router.dismissGiftSheet() }.tint(KS.muted2)
                }
            }
            // Opening a picker must drop keyboard focus so it doesn't bounce back
            // onto the previously-edited text field when the picker sheet closes.
            .onChange(of: state.picker) { _, _ in focus = nil }
            // Open the keyboard on the gift title the moment the sheet settles.
            .onAppear {
                DispatchQueue.main.asyncAfter(deadline: .now() + 0.4) { focus = .name }
            }
        }
        .presentationDetents([.large])
        .presentationDragIndicator(.visible)
        .presentationBackground(KS.bg)
        .sheet(item: pickerBinding) { kind in
            PickerSheet(kind: kind, state: state, composition: composition)
        }
        .onDisappear { state.cancel() }
    }

    /// Tint follows the derived direction so the hero reflects received/given.
    private var fm: GiftFlowAppearance {
        state.flow(householdIDs: composition.data.householdIDs,
                   saveGift: composition.saveGiftUseCase).appearance
    }
    private var can: Bool { state.input.canSave }
    private var showPaidToggle: Bool { state.draft.fromID != nil && state.draft.toID != nil }

    // MARK: Hero card (emoji + name + value, each its own tappable field)

    private var heroCard: some View {
        VStack(spacing: 12) {
            HStack(alignment: .center, spacing: 14) {
                Button { state.open(.emoji) } label: { emojiTile }
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

    /// Emoji preview. While the on-device model is enriching the typed name, the
    /// little corner badge becomes a spinner so the guess feels live.
    private var emojiTile: some View {
        Text(state.effectiveEmoji)
            .font(.system(size: 28))
            .frame(width: 58, height: 58)
            .background(RoundedRectangle(cornerRadius: KS.radius, style: .continuous).fill(.white))
            .overlay(alignment: .bottomTrailing) {
                Group {
                    if state.aiLoading {
                        ProgressView()
                            .controlSize(.mini)
                            .tint(.white)
                    } else {
                        Image(systemName: "pencil")
                            .font(.system(size: 9, weight: .bold))
                            .foregroundColor(.white)
                    }
                }
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
            if !state.draft.valueTouched {
                if state.aiLoading {
                    // Live estimate in progress — small spinner + "thinking…".
                    HStack(spacing: 5) {
                        ProgressView().controlSize(.mini).tint(fm.main)
                        Text("thinking…")
                            .font(KS.font(11, .semibold)).foregroundColor(fm.main)
                    }
                    .padding(.horizontal, 8).padding(.vertical, 3)
                    .background(Capsule().fill(fm.tint))
                } else {
                    Text("estimated")
                        .font(KS.font(11, .semibold)).foregroundColor(fm.main)
                        .padding(.horizontal, 8).padding(.vertical, 3)
                        .background(Capsule().fill(fm.tint))
                }
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
                detailRow(icon: "person.fill", label: "From",
                          value: state.draft.fromID.map(composition.data.entityName)) { state.open(.from) }
                RowDivider().padding(.leading, 58)
                detailRow(icon: "person.2.fill", label: "To",
                          value: state.draft.toID.map(composition.data.entityName)) { state.open(.to) }
                RowDivider().padding(.leading, 58)
                detailRow(icon: "party.popper.fill", label: "Occasion",
                          value: state.draft.celebration.map(composition.data.localizedCelebration)) { state.open(.celeb) }
                RowDivider().padding(.leading, 58)
                detailRow(icon: "calendar", label: "Date",
                          value: state.draft.date.giftInputLabel()) { state.open(.date) }
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

    // MARK: Paid toggle (family member gave a gift)

    private var paidCard: some View {
        Card {
            Toggle(isOn: paidBinding) {
                VStack(alignment: .leading, spacing: 2) {
                    Text("Paid by you").font(KS.font(16, .regular)).foregroundColor(KS.ink)
                    Text("Count this in your own giving")
                        .font(KS.font(13, .regular)).foregroundColor(KS.muted3)
                }
            }
            .tint(KS.emerald)
            .padding(.horizontal, 14).padding(.vertical, 10)
        }
    }

    // MARK: Save

    private var saveButton: some View {
        Button { state.save(using: composition) } label: {
            Text(saveTitle)
                .font(KS.font(17, .semibold)).foregroundColor(.white)
                .frame(maxWidth: .infinity).padding(.vertical, 16)
                .background(RoundedRectangle(cornerRadius: KS.radius, style: .continuous)
                    .fill(can ? KS.ink : Color(hex: 0xC3CAD3)))
        }
        .buttonStyle(.plain)
        .disabled(!can)
    }

    private var saveTitle: LocalizedStringKey { "Save" }

    // MARK: Bindings

    private var nameBinding: Binding<String> {
        Binding(get: { state.draft.name }, set: { state.setName($0) })
    }

    private var valueBinding: Binding<String> {
        Binding(
            get: {
                let value = state.draft.valueTouched ? state.draft.value : Int(state.effectiveValue)
                return value.map(String.init) ?? ""
            },
            set: { newVal in
                let digits = newVal.filter(\.isNumber)
                state.draft.value = digits.isEmpty ? 0 : Int(digits)
                state.draft.valueTouched = true
            }
        )
    }

    private var paidBinding: Binding<Bool> {
        Binding(get: { state.draft.paidByYou }, set: { state.draft.paidByYou = $0 })
    }

    private var pickerBinding: Binding<AddGiftPicker?> {
        Binding(get: { state.picker }, set: { if $0 == nil { state.closePicker() } })
    }
}

// MARK: - Picker bottom sheets

/// One tap-to-reveal picker — from / to (a unified person list), occasion, emoji
/// grid, or date — each with manual-entry support so the user can add a new
/// option inline.
private struct PickerSheet: View {
    let kind: AddGiftPicker
    let state: AddGiftState
    let composition: AppComposition
    @State private var customText = ""

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
        case .from:
            entityPicker(title: "From", selected: state.draft.fromID,
                         select: { state.selectFrom($0) }, add: { addPerson($0, selectFrom: true) })
        case .to:
            entityPicker(title: "To", selected: state.draft.toID,
                         select: { state.selectTo($0) }, add: { addPerson($0, selectFrom: false) })
        case .celeb:
            celebPicker
        case .emoji:
            emojiPicker
        case .date:
            datePicker
        }
    }

    // MARK: From / To (unified person list)

    /// A single, uncategorised list spanning the household and outside people, so
    /// either side of From → To can be anyone. "You" is always pinned to the top;
    /// manual-entry adds a new outside person straight onto the side being edited.
    private func entityPicker(title: String, selected: String?,
                              select: @escaping (String) -> Void,
                              add: @escaping (String) -> Void) -> some View {
        // You first, then the rest of the household, then everyone else.
        let you = composition.data.members.filter { $0.id == "you" }.map { ($0.id, $0.name, $0.color) }
        let otherMembers = composition.data.members.filter { $0.id != "you" }.map { ($0.id, $0.name, $0.color) }
        let outsiders = composition.data.people.map { ($0.id, $0.name, $0.color) }
        let entities = you + otherMembers + outsiders
        return ScrollView {
            VStack(spacing: 16) {
                // Manual-entry first — add a new person from the top of the sheet.
                addRow(placeholder: "Add person") { add($0) }
                entityList(entities, selected: selected, select: select)
            }
            .padding(16)
        }
        .scrollIndicators(.hidden)
        .navigationTitle(LocalizedStringKey(title))
    }

    @ViewBuilder
    private func entityList(_ entities: [(String, String, Color)],
                            selected: String?, select: @escaping (String) -> Void) -> some View {
        if !entities.isEmpty {
            Card {
                VStack(spacing: 0) {
                    ForEach(Array(entities.enumerated()), id: \.element.0) { idx, e in
                        Button { select(e.0) } label: {
                            HStack(spacing: 12) {
                                AvatarView(initials: e.1.initials, color: e.2, size: 38)
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
    }

    // MARK: Occasion

    private var celebPicker: some View {
        ScrollView {
            VStack(spacing: 16) {
                // Manual-entry first — add a new option from the top of the sheet.
                addRow(placeholder: "Add occasion") { celebration in
                    composition.data.addCelebration(celebration)
                    state.selectCelebration(celebration)
                }
                Card {
                    VStack(spacing: 0) {
                        ForEach(Array(composition.data.celebrations.enumerated()), id: \.element.id) { idx, celebration in
                            Button { state.selectCelebration(celebration.name) } label: {
                                HStack {
                                    Text(composition.data.localizedCelebration(celebration.name)).font(KS.font(16, .regular)).foregroundColor(KS.ink)
                                    Spacer(minLength: 8)
                                    if state.draft.celebration == celebration.name { checkmark }
                                }
                                .padding(.horizontal, 14).padding(.vertical, 12)
                                .contentShape(Rectangle())
                            }
                            .buttonStyle(.plain)
                            if idx < composition.data.celebrations.count - 1 { RowDivider().padding(.leading, 14) }
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
                        ForEach(emojiChoices, id: \.self) { e in
                            Button { state.selectEmoji(e) } label: {
                                Text(e).font(.system(size: 26))
                                    .frame(maxWidth: .infinity).frame(height: 48)
                                    .background(RoundedRectangle(cornerRadius: KS.radius, style: .continuous)
                                        .fill(state.draft.emoji == e ? KS.recvTint : KS.track))
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
                    state.useCustomEmoji(customText); customText = ""
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
        let g = customText.firstGrapheme
        return g.isEmpty ? "🎁" : g
    }

    // MARK: Date

    /// Today / Yesterday pills plus a graphical calendar. Tapping a pill or a day
    /// applies the date immediately and closes the sheet — there's no separate
    /// confirm button.
    private var datePicker: some View {
        ScrollView {
            VStack(spacing: 16) {
                HStack(spacing: 10) {
                    quickDate("Today", AppDate.today)
                    quickDate("Yesterday", AppDate.yesterday)
                }
                Card {
                    DatePicker("", selection: dateApplyBinding, displayedComponents: .date)
                        .datePickerStyle(.graphical)
                        .tint(KS.recv)
                        .padding(.horizontal, 10).padding(.vertical, 6)
                }
            }
            .padding(16)
        }
        .scrollIndicators(.hidden)
        .navigationTitle("Pick a date")
    }

    /// Picking a day in the calendar applies it (and dismisses) immediately.
    private var dateApplyBinding: Binding<Date> {
        Binding(get: { state.draft.date }, set: { state.selectDate($0) })
    }

    private func quickDate(_ label: String, _ date: Date) -> some View {
        let selected = Calendar.current.isDate(state.draft.date, inSameDayAs: date)
        return Button { state.selectDate(date) } label: {
            Text(LocalizedStringKey(label))
                .font(KS.font(15, .semibold))
                .foregroundColor(selected ? .white : KS.ink)
                .frame(maxWidth: .infinity).padding(.vertical, 13)
                .background(RoundedRectangle(cornerRadius: KS.radius, style: .continuous)
                    .fill(selected ? KS.ink : KS.card))
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

    private var emojiChoices: [String] {
        ["🎁", "💐", "⌚", "📚", "🧸", "🍫", "🍷", "🌸", "💍", "📱",
         "🎧", "💸", "🎟️", "🎂", "🪴", "☕", "🪆", "🧱", "🧣", "🕯️"]
    }

    private func addPerson(_ name: String, selectFrom: Bool) {
        guard let id = composition.createPerson(name: name, isFamily: false) else { return }
        if selectFrom { state.selectFrom(id) } else { state.selectTo(id) }
    }
}

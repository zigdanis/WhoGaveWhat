import SwiftUI

/// Native sheet for adding a gift. New gifts start with the current user as the
/// sender, so the first pass only asks for a name and receiver. Less frequent
/// fields remain behind the Details disclosure.
struct AddGiftSheet: View {
    let composition: AppComposition
    @State private var state: AddGiftState
    @State private var showsDetails: Bool
    @FocusState private var focus: AddGiftField?

    init(route: GiftSheetRoute, composition: AppComposition) {
        self.composition = composition
        _state = State(initialValue: AddGiftState(
            route: route,
            data: composition.data,
            suggestGift: composition.suggestGift
        ))
        _showsDetails = State(initialValue: route.editingGiftID != nil)
    }

    var body: some View {
        NavigationStack {
            ScrollView {
                VStack(alignment: .leading, spacing: 0) {
                    GiftBasicsSection(
                        name: nameBinding,
                        focus: $focus,
                        fromName: state.draft.fromID.map(composition.data.entityName) ?? String(localized: "You"),
                        toName: state.draft.toID.map(composition.data.entityName),
                        isEditing: state.editingGiftID != nil,
                        accent: fm.main,
                        tint: fm.tint,
                        onSelectFrom: { state.open(.from) },
                        onSelectTo: { state.open(.to) }
                    )
                    GiftDetailsDisclosure(isExpanded: $showsDetails) {
                        focus = nil
                    }
                    .padding(.top, 16)
                    if showsDetails {
                        GiftDetailsSection(
                            dateLabel: state.draft.date.giftInputLabel(),
                            occasionLabel: state.draft.celebration.map(composition.data.localizedCelebration),
                            value: valueBinding,
                            focus: $focus,
                            accent: fm.main,
                            tint: fm.tint,
                            onSelectDate: { state.open(.date) },
                            onSelectOccasion: { state.open(.celeb) }
                        )
                        .padding(.top, 10)
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
            .background(Color.bg.contentShape(Rectangle()).onTapGesture { focus = nil })
            .navigationTitle(state.editingGiftID == nil ? "Add a gift" : "Edit gift")
            .navigationBarTitleDisplayMode(.inline)
            // Paint the nav bar the same grouped grey as the body so the sheet
            // reads as one uniform surface (no white top / grey middle seam).
            .toolbarBackground(Color.bg, for: .navigationBar)
            .toolbarBackground(.visible, for: .navigationBar)
            .toolbar {
                ToolbarItem(placement: .cancellationAction) {
                    Button("Cancel") { composition.router.dismissGiftSheet() }.tint(Color.muted2)
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
        .presentationBackground(Color.bg)
        .sheet(item: pickerBinding) { kind in
            PickerSheet(kind: kind, state: state, composition: composition)
        }
        .onDisappear { state.cancel() }
    }

    /// Tint follows the derived direction for the form's controls.
    private var fm: GiftFlowAppearance {
        state.flow(householdIDs: composition.data.householdIDs,
                   saveGift: composition.saveGiftUseCase).appearance
    }
    private var can: Bool { state.input.canSave }

    // MARK: Save

    private var saveButton: some View {
        Button { state.save(using: composition) } label: {
            Text(saveTitle)
                .font(Font.app(17, .semibold)).foregroundColor(.white)
                .frame(maxWidth: .infinity).padding(.vertical, 16)
                .background(RoundedRectangle(cornerRadius: DesignMetrics.cornerRadius, style: .continuous)
                    .fill(can ? Color.ink : Color(hex: 0xC3CAD3)))
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

    private var pickerBinding: Binding<AddGiftPicker?> {
        Binding(get: { state.picker }, set: { if $0 == nil { state.closePicker() } })
    }
}

private enum AddGiftField: Hashable {
    case name
    case value
}

private struct GiftBasicsSection: View {
    @Binding var name: String
    @FocusState.Binding var focus: AddGiftField?
    let fromName: String
    let toName: String?
    let isEditing: Bool
    let accent: Color
    let tint: Color
    let onSelectFrom: () -> Void
    let onSelectTo: () -> Void

    var body: some View {
        VStack(spacing: 12) {
            TextField("Gift name", text: $name)
                .font(Font.app(18, .semibold)).foregroundColor(Color.ink)
                .tint(accent)
                .focused($focus, equals: .name)
                .submitLabel(.done)
                .frame(maxWidth: .infinity, alignment: .leading)
                .padding(.horizontal, 14)
                .frame(height: 58)
                .background(fieldSurface)
                .contentShape(Rectangle())
                .onTapGesture { focus = .name }

            Card {
                VStack(spacing: 0) {
                    senderRow
                    RowDivider().padding(.leading, 58)
                    GiftEntryRow(
                        icon: .asset("ArrowRightToLine"),
                        label: "To",
                        value: toName,
                        accent: accent,
                        tint: tint,
                        onTap: onSelectTo
                    )
                }
            }
        }
    }

    private var senderRow: some View {
        Group {
            if isEditing {
                Button(action: onSelectFrom) {
                    senderRowContent
                }
                .buttonStyle(.plain)
            } else {
                senderRowContent
            }
        }
    }

    private var senderRowContent: some View {
        HStack(spacing: 12) {
            GiftEntryIconView(icon: .asset("ArrowRightFromLine"), accent: accent, tint: tint)
            Text("From").font(Font.app(16, .regular)).foregroundColor(Color.ink)
            Spacer(minLength: 8)
            Text(fromName).font(Font.app(16, .semibold)).foregroundColor(accent)
            if isEditing { Chevron() }
        }
        .padding(.horizontal, 14).padding(.vertical, 10)
        .contentShape(Rectangle())
    }

    private var fieldSurface: some View {
        RoundedRectangle(cornerRadius: DesignMetrics.cornerRadius, style: .continuous)
            .fill(Color.card)
            .overlay(
                RoundedRectangle(cornerRadius: DesignMetrics.cornerRadius, style: .continuous)
                    .stroke(Color.border, lineWidth: 1)
            )
            .ksCardShadow()
    }
}

private struct GiftDetailsDisclosure: View {
    @Binding var isExpanded: Bool
    let onCollapse: () -> Void

    var body: some View {
        Button {
            withAnimation(.easeInOut(duration: 0.2)) {
                isExpanded.toggle()
                if !isExpanded { onCollapse() }
            }
        } label: {
            HStack(spacing: 8) {
                Text("Details")
                    .font(Font.app(16, .semibold))
                    .foregroundColor(Color.ink)
                Spacer(minLength: 8)
                Image(systemName: isExpanded ? "chevron.up" : "chevron.down")
                    .font(.system(size: 14, weight: .semibold))
                    .foregroundColor(Color.muted2)
            }
            .padding(.horizontal, 4)
            .contentShape(Rectangle())
        }
        .buttonStyle(.plain)
        .accessibilityValue(isExpanded ? "Shown" : "Hidden")
    }
}

private struct GiftDetailsSection: View {
    let dateLabel: String
    let occasionLabel: String?
    @Binding var value: String
    @FocusState.Binding var focus: AddGiftField?
    let accent: Color
    let tint: Color
    let onSelectDate: () -> Void
    let onSelectOccasion: () -> Void

    var body: some View {
        Card {
            VStack(spacing: 0) {
                GiftEntryRow(
                    icon: .system("calendar"),
                    label: "Date",
                    value: dateLabel,
                    accent: accent,
                    tint: tint,
                    onTap: onSelectDate
                )
                RowDivider().padding(.leading, 58)
                GiftEntryRow(
                    icon: .system("party.popper.fill"),
                    label: "Occasion",
                    value: occasionLabel,
                    accent: accent,
                    tint: tint,
                    onTap: onSelectOccasion
                )
                RowDivider().padding(.leading, 58)
                ApproximateValueRow(value: $value, focus: $focus, accent: accent, tint: tint)
            }
        }
    }
}

private struct GiftEntryRow: View {
    let icon: GiftEntryIcon
    let label: LocalizedStringKey
    let value: String?
    let accent: Color
    let tint: Color
    let onTap: () -> Void

    var body: some View {
        Button(action: onTap) {
            HStack(spacing: 12) {
                GiftEntryIconView(icon: icon, accent: accent, tint: tint)
                Text(label).font(Font.app(16, .regular)).foregroundColor(Color.ink)
                Spacer(minLength: 8)
                Text(value ?? String(localized: "Choose"))
                    .font(Font.app(16, value == nil ? .regular : .semibold))
                    .foregroundColor(value == nil ? Color.placeholder : accent)
                    .lineLimit(1)
                Chevron()
            }
            .padding(.horizontal, 14).padding(.vertical, 10)
            .contentShape(Rectangle())
        }
        .buttonStyle(.plain)
    }
}

private enum GiftEntryIcon {
    case system(String)
    case asset(String)
}

private struct GiftEntryIconView: View {
    let icon: GiftEntryIcon
    let accent: Color
    let tint: Color

    var body: some View {
        iconImage
            .foregroundColor(accent)
            .frame(width: 34, height: 34)
            .background(RoundedRectangle(cornerRadius: DesignMetrics.cornerRadius, style: .continuous).fill(tint))
            .accessibilityHidden(true)
    }

    @ViewBuilder
    private var iconImage: some View {
        switch icon {
        case .system(let name):
            Image(systemName: name)
                .font(.system(size: 15, weight: .semibold))
        case .asset(let name):
            Image(name)
                .resizable()
                .scaledToFit()
                .frame(width: 18, height: 18)
        }
    }
}

private struct ApproximateValueRow: View {
    @Binding var value: String
    @FocusState.Binding var focus: AddGiftField?
    let accent: Color
    let tint: Color

    var body: some View {
        HStack(spacing: 12) {
            Image(systemName: "rublesign.circle")
                .font(.system(size: 15, weight: .semibold))
                .foregroundColor(accent)
                .frame(width: 34, height: 34)
                .background(RoundedRectangle(cornerRadius: DesignMetrics.cornerRadius, style: .continuous).fill(tint))
            Text("Approx. value").font(Font.app(16, .regular)).foregroundColor(Color.ink)
            Spacer(minLength: 8)
            TextField("0", text: $value)
                .font(Font.app(16, .semibold)).foregroundColor(Color.ink)
                .keyboardType(.numberPad)
                .tint(accent)
                .focused($focus, equals: .value)
                .multilineTextAlignment(.trailing)
                .frame(minWidth: 60, maxWidth: 110)
            Text("₽").font(Font.app(16, .semibold)).foregroundColor(Color.muted2)
        }
        .padding(.horizontal, 14).padding(.vertical, 10)
        .contentShape(Rectangle())
        .onTapGesture { focus = .value }
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
                .background(Color.bg)
                .navigationBarTitleDisplayMode(.inline)
                .toolbarBackground(Color.bg, for: .navigationBar)
                .toolbarBackground(.visible, for: .navigationBar)
        }
        // No Cancel button — these sheets are dismissed with a swipe down.
        .presentationDetents(kind == .date ? [.large] : [.medium, .large])
        .presentationDragIndicator(.visible)
        .presentationBackground(Color.bg)
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
                                Text(e.1).font(Font.app(16, .semibold)).foregroundColor(Color.ink)
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
                                    Text(composition.data.localizedCelebration(celebration.name)).font(Font.app(16, .regular)).foregroundColor(Color.ink)
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
                        .font(Font.app(12, .regular)).foregroundColor(Color.muted3)
                        .padding(.horizontal, 4)
                }
                Card {
                    LazyVGrid(columns: Array(repeating: GridItem(.flexible(), spacing: 8), count: 5), spacing: 8) {
                        ForEach(emojiChoices, id: \.self) { e in
                            Button { state.selectEmoji(e) } label: {
                                Text(e).font(.system(size: 26))
                                    .frame(maxWidth: .infinity).frame(height: 48)
                                    .background(RoundedRectangle(cornerRadius: DesignMetrics.cornerRadius, style: .continuous)
                                        .fill(state.draft.emoji == e ? Color.recvTint : Color.track))
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
                    .background(RoundedRectangle(cornerRadius: DesignMetrics.cornerRadius, style: .continuous).fill(Color.track))
                TextField("Type any icon or letter", text: $customText)
                    .font(Font.app(16, .regular)).tint(Color.recv)
                Button {
                    state.useCustomEmoji(customText); customText = ""
                } label: {
                    Text("Add").font(Font.app(15, .semibold)).foregroundColor(.white)
                        .padding(.horizontal, 16).padding(.vertical, 8)
                        .background(Capsule().fill(addDisabled ? Color.muted4 : Color.ink))
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
                        .tint(Color.recv)
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
                .font(Font.app(15, .semibold))
                .foregroundColor(selected ? .white : Color.ink)
                .frame(maxWidth: .infinity).padding(.vertical, 13)
                .background(RoundedRectangle(cornerRadius: DesignMetrics.cornerRadius, style: .continuous)
                    .fill(selected ? Color.ink : Color.card))
        }
        .buttonStyle(.plain)
    }

    // MARK: Shared bits

    private var checkmark: some View {
        Image(systemName: "checkmark")
            .font(.system(size: 15, weight: .semibold))
            .foregroundColor(Color.recv)
    }

    private func addRow(placeholder: String, add: @escaping (String) -> Void) -> some View {
        Card {
            HStack(spacing: 10) {
                TextField(LocalizedStringKey(placeholder), text: $customText)
                    .font(Font.app(16, .regular)).tint(Color.recv)
                Button {
                    add(customText); customText = ""
                } label: {
                    Text("Add").font(Font.app(15, .semibold)).foregroundColor(.white)
                        .padding(.horizontal, 16).padding(.vertical, 8)
                        .background(Capsule().fill(addDisabled ? Color.muted4 : Color.ink))
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

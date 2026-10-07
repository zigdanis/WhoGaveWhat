import SwiftUI

/// Native sheet for adding or editing a gift. Both sides of the relationship are
/// explicit, while less frequent fields remain behind the Details disclosure.
struct AddGiftSheet: View {
    let composition: AppComposition
    @State private var state: AddGiftState
    @State private var showsDetails: Bool
    @State private var compactHeight: CGFloat = 420
    @State private var headerHeight: CGFloat = 56
    @State private var lastContentHeight: CGFloat = 0
    @State private var selectedDetent: PresentationDetent
    @FocusState private var focus: AddGiftField?

    init(route: GiftSheetRoute, composition: AppComposition) {
        self.composition = composition
        _state = State(
            initialValue: AddGiftState(
                route: route,
                data: composition.data,
                suggestGift: composition.suggestGift
            ))
        let startsExpanded = route.editingGiftID != nil
        _showsDetails = State(initialValue: startsExpanded)
        _selectedDetent = State(initialValue: startsExpanded ? .large : .height(420))
    }

    var body: some View {
        @Bindable var state = state

        IntrinsicModalScaffold(
            title: state.editingGiftID == nil ? "Add a gift" : "Edit gift",
            leadingActionTitle: "Cancel",
            onLeadingAction: composition.router.dismissGiftSheet
        ) {
            ScrollView {
                VStack(alignment: .leading, spacing: 0) {
                    GiftBasicsSection(
                        name: $state.name,
                        focus: $focus,
                        fromName: state.draft.fromID.map(composition.data.entityName),
                        toName: state.draft.toID.map(composition.data.entityName),
                        accent: fm.main,
                        tint: fm.tint,
                        fromAccessibilityIdentifier: "add-gift.from",
                        toAccessibilityIdentifier: "add-gift.to",
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
                            occasionLabel: state.draft.occasion.map(composition.data.localizedOccasion),
                            value: $state.valueText,
                            focus: $focus,
                            accent: fm.main,
                            tint: fm.tint,
                            currencyCode: composition.currencyCode,
                            onSelectDate: { state.open(.date) },
                            onSelectOccasion: { state.open(.occasion) }
                        )
                        .padding(.top, 10)
                    }
                    GiftSaveButton(
                        isEnabled: state.input.canSave,
                        onSave: { state.save(using: composition) }
                    )
                    .padding(.top, 24)
                }
                .padding(.horizontal, 16).padding(.top, 6).padding(.bottom, 30)
                .onGeometryChange(for: CGFloat.self) { geometry in
                    geometry.size.height
                } action: { contentHeight in
                    updateCompactHeight(for: contentHeight)
                }
                // Taps on any non-interactive part of the form (card padding,
                // section headers, gaps) drop keyboard focus. Buttons and text
                // fields consume their own taps first, so this only fires on the
                // "dead" areas — closing the keyboard no matter which field was up.
                .contentShape(Rectangle())
                .onTapGesture { focus = nil }
            }
            .scrollIndicators(.hidden)
            .accessibilityIdentifier("add-gift.scroll")
            .scrollDismissesKeyboard(.interactively)
            // A sheet can grow to the large presentation boundary while the
            // keyboard is up. Reserve the keyboard's approximate vertical
            // footprint inside the scroll view so the form remains scrollable
            // and Save cannot be trapped underneath the keyboard overlay.
            .safeAreaInset(edge: .bottom, spacing: 0) {
                Color.clear
                    .frame(height: focus == nil ? 0 : 300)
                    .accessibilityHidden(true)
            }
            // Empty scroll area below the content also dismisses the keyboard.
            .background(Color.bg.contentShape(Rectangle()).onTapGesture { focus = nil })
            // Opening a picker must drop keyboard focus so it doesn't bounce back
            // onto the previously-edited text field when the picker sheet closes.
            .onChange(of: state.picker) { _, _ in focus = nil }
            .onChange(of: showsDetails) { _, isExpanded in
                selectedDetent = isExpanded ? .large : .height(compactHeight)
            }
            // Open the keyboard on the gift title the moment the sheet settles.
            .onAppear {
                DispatchQueue.main.asyncAfter(deadline: .now() + 0.4) { focus = .name }
            }
        }
        .onPreferenceChange(IntrinsicModalHeaderHeightKey.self) { height in
            headerHeight = height
            if !showsDetails { updateCompactHeight(for: lastContentHeight) }
        }
        .presentationDetents([.height(compactHeight), .large], selection: $selectedDetent)
        .presentationDragIndicator(.visible)
        .presentationBackground(Color.bg)
        .sheet(item: $state.picker) { kind in
            AddGiftPickerPresentation(kind: kind, state: state, composition: composition)
        }
        .onDisappear { state.cancel() }
    }

    private func updateCompactHeight(for contentHeight: CGFloat) {
        lastContentHeight = contentHeight
        guard !showsDetails else { return }
        let measuredHeight = min(max(contentHeight + headerHeight, 360), 560)
        guard abs(measuredHeight - compactHeight) > 1 else { return }
        compactHeight = measuredHeight
        selectedDetent = .height(measuredHeight)
    }

    /// Tint follows the derived direction for the form's controls.
    private var fm: GiftDirectionAppearance {
        state.direction(
            householdIDs: composition.data.householdIDs,
            saveGift: composition.saveGiftUseCase
        ).appearance
    }
}

private enum AddGiftField: Hashable {
    case name
    case value
}

private struct GiftSaveButton: View {
    let isEnabled: Bool
    let onSave: () -> Void

    var body: some View {
        Button(action: onSave) {
            Text("Save")
                .font(Font.app(17, .semibold)).foregroundColor(.white)
                .frame(maxWidth: .infinity).padding(.vertical, 16)
                .background(
                    RoundedRectangle(cornerRadius: DesignMetrics.cornerRadius, style: .continuous)
                        .fill(isEnabled ? Color.ink : Color(hex: 0xC3CAD3)))
        }
        .buttonStyle(.plain)
        .disabled(!isEnabled)
        .accessibilityIdentifier("add-gift.save")
    }
}

private struct GiftBasicsSection: View {
    @Binding var name: String
    @FocusState.Binding var focus: AddGiftField?
    let fromName: String?
    let toName: String?
    let accent: Color
    let tint: Color
    let fromAccessibilityIdentifier: String
    let toAccessibilityIdentifier: String
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
                .accessibilityIdentifier("add-gift.name")

            Card {
                VStack(spacing: 0) {
                    GiftEntryRow(
                        icon: .asset("ArrowRightFromLine"),
                        label: "From",
                        value: fromName,
                        accent: accent,
                        tint: tint,
                        accessibilityIdentifier: fromAccessibilityIdentifier,
                        onTap: onSelectFrom
                    )
                    RowDivider().padding(.leading, 58)
                    GiftEntryRow(
                        icon: .asset("ArrowRightToLine"),
                        label: "To",
                        value: toName,
                        accent: accent,
                        tint: tint,
                        accessibilityIdentifier: toAccessibilityIdentifier,
                        onTap: onSelectTo
                    )
                }
            }
        }
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
        .accessibilityIdentifier("add-gift.details")
    }
}

private struct GiftDetailsSection: View {
    let dateLabel: String
    let occasionLabel: String?
    @Binding var value: String
    @FocusState.Binding var focus: AddGiftField?
    let accent: Color
    let tint: Color
    let currencyCode: String
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
                    accessibilityIdentifier: "add-gift.date",
                    onTap: onSelectDate
                )
                RowDivider().padding(.leading, 58)
                GiftEntryRow(
                    icon: .system("party.popper.fill"),
                    label: "Occasion",
                    value: occasionLabel,
                    accent: accent,
                    tint: tint,
                    accessibilityIdentifier: "add-gift.occasion",
                    onTap: onSelectOccasion
                )
                RowDivider().padding(.leading, 58)
                ApproximateValueRow(
                    value: $value,
                    focus: $focus,
                    accent: accent,
                    tint: tint,
                    currencyCode: currencyCode
                )
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
    let accessibilityIdentifier: String
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
        .accessibilityIdentifier(accessibilityIdentifier)
        .accessibilityValue(value ?? String(localized: "Choose"))
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
    let currencyCode: String

    var body: some View {
        HStack(spacing: 12) {
            Image(systemName: "banknote.fill")
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
                .accessibilityIdentifier("add-gift.value")
            Text(currencySymbol(code: currencyCode))
                .font(Font.app(16, .semibold)).foregroundColor(Color.muted2)
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
struct AddGiftPickerPresentation: View {
    let kind: AddGiftPicker
    let state: AddGiftState
    let composition: AppComposition

    var body: some View {
        AddGiftPickerSheet(kind: kind, state: state, composition: composition)
    }
}

private struct AddGiftPickerSheet: View {
    let kind: AddGiftPicker
    let state: AddGiftState
    let composition: AppComposition
    @State private var customText = ""
    @State private var fittedHeight: CGFloat = 520
    @State private var headerHeight: CGFloat = 56
    @State private var lastContentHeight: CGFloat = 0
    @State private var selectedDetent: PresentationDetent

    init(kind: AddGiftPicker, state: AddGiftState, composition: AppComposition) {
        self.kind = kind
        self.state = state
        self.composition = composition
        switch kind {
        case .date:
            _selectedDetent = State(initialValue: .height(520))
        default:
            _selectedDetent = State(initialValue: .medium)
        }
    }

    var body: some View {
        IntrinsicModalScaffold(title: title) {
            content
                .background(Color.bg)
                .onGeometryChange(for: CGFloat.self) { geometry in
                    geometry.size.height
                } action: { contentHeight in
                    guard isDate else { return }
                    lastContentHeight = contentHeight
                    let height = min(max(contentHeight + headerHeight, 360), 700)
                    guard abs(height - fittedHeight) > 1 else { return }
                    fittedHeight = height
                    selectedDetent = .height(height)
                }
        }
        // No Cancel button — these sheets are dismissed with a swipe down.
        .presentationDetents(detents, selection: $selectedDetent)
        .onPreferenceChange(IntrinsicModalHeaderHeightKey.self) { height in
            headerHeight = height
            guard isDate else { return }
            let fitted = min(max(lastContentHeight + height, 360), 700)
            guard abs(fitted - fittedHeight) > 1 else { return }
            fittedHeight = fitted
            selectedDetent = .height(fitted)
        }
        .presentationDragIndicator(.visible)
        .presentationBackground(Color.bg)
    }

    private var detents: Set<PresentationDetent> {
        isDate ? [.height(fittedHeight), .large] : [.medium, .large]
    }

    private var isDate: Bool {
        if case .date = kind { return true }
        return false
    }

    private var title: LocalizedStringResource {
        switch kind {
        case .from: "From"
        case .to: "To"
        case .occasion: "Occasion"
        case .emoji: "Icon"
        case .date: "Pick a date"
        }
    }

    @ViewBuilder
    private var content: some View {
        switch kind {
        case .from:
            PersonPickerContent(
                people: composition.data.people,
                selectedID: state.draft.fromID,
                onProvisionalSelection: state.previewFrom,
                onSelection: state.selectFrom,
                onCreatePerson: { composition.createPerson(name: $0, isFamily: false) }
            )
        case .to:
            PersonPickerContent(
                people: composition.data.people,
                selectedID: state.draft.toID,
                onProvisionalSelection: state.previewTo,
                onSelection: state.selectTo,
                onCreatePerson: { composition.createPerson(name: $0, isFamily: false) }
            )
        case .occasion:
            occasionPicker
        case .emoji:
            emojiPicker
        case .date:
            datePicker
        }
    }

    // MARK: Occasion

    private var occasionPicker: some View {
        ScrollView {
            VStack(spacing: 16) {
                // Manual-entry first — add a new option from the top of the sheet.
                addRow(placeholder: "Add occasion") { occasion in
                    composition.data.addOccasion(occasion)
                    state.selectOccasion(occasion)
                }
                Card {
                    VStack(spacing: 0) {
                        ForEach(Array(composition.data.occasions.enumerated()), id: \.element.id) { idx, occasion in
                            Button {
                                state.selectOccasion(occasion.name)
                            } label: {
                                HStack {
                                    Text(composition.data.localizedOccasion(occasion.name)).font(Font.app(16, .regular)).foregroundColor(Color.ink)
                                    Spacer(minLength: 8)
                                    if state.draft.occasion == occasion.name { checkmark }
                                }
                                .padding(.horizontal, 14).padding(.vertical, 12)
                                .contentShape(Rectangle())
                            }
                            .buttonStyle(.plain)
                            if idx < composition.data.occasions.count - 1 { RowDivider().padding(.leading, 14) }
                        }
                    }
                }
            }
            .padding(16)
        }
        .scrollIndicators(.hidden)
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
                            Button {
                                state.selectEmoji(e)
                            } label: {
                                Text(e).font(.system(size: 26))
                                    .frame(maxWidth: .infinity).frame(height: 48)
                                    .background(
                                        RoundedRectangle(cornerRadius: DesignMetrics.cornerRadius, style: .continuous)
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

    /// Today / Yesterday pills plus a UIKit calendar. Calendar page navigation is
    /// independent from day selection, so only an explicit day tap dismisses.
    private var datePicker: some View {
        VStack(spacing: 16) {
            HStack(spacing: 10) {
                quickDate("Today", AppDate.today, accessibilityIdentifier: "date-picker.today")
                quickDate("Yesterday", AppDate.yesterday, accessibilityIdentifier: "date-picker.yesterday")
            }
            Card {
                CalendarDatePicker(
                    selectedDate: state.draft.date,
                    onSelectDate: state.selectDate
                )
                .padding(.horizontal, 6)
                .accessibilityIdentifier("date-picker.calendar")
            }
        }
        .padding(16)
    }

    private func quickDate(
        _ label: String,
        _ date: Date,
        accessibilityIdentifier: String
    ) -> some View {
        let selected = Calendar.current.isDate(state.draft.date, inSameDayAs: date)
        return Button {
            state.selectDate(date)
        } label: {
            Text(LocalizedStringKey(label))
                .font(Font.app(15, .semibold))
                .foregroundColor(selected ? .white : Color.ink)
                .frame(maxWidth: .infinity).padding(.vertical, 13)
                .background(
                    RoundedRectangle(cornerRadius: DesignMetrics.cornerRadius, style: .continuous)
                        .fill(selected ? Color.ink : Color.card))
        }
        .buttonStyle(.plain)
        .accessibilityIdentifier(accessibilityIdentifier)
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
        [
            "🎁", "💐", "⌚", "📚", "🧸", "🍫", "🍷", "🌸", "💍", "📱",
            "🎧", "💸", "🎟️", "🎂", "🪴", "☕", "🪆", "🧱", "🧣", "🕯️"
        ]
    }

}

private struct PersonPickerContent: View {
    let onProvisionalSelection: (String?) -> Void
    let onSelection: (String) -> Void
    let onCreatePerson: (String) -> String?
    @State private var pickerState: PersonPickerState

    init(
        people: [Person],
        selectedID: String?,
        onProvisionalSelection: @escaping (String?) -> Void,
        onSelection: @escaping (String) -> Void,
        onCreatePerson: @escaping (String) -> String?
    ) {
        self.onProvisionalSelection = onProvisionalSelection
        self.onSelection = onSelection
        self.onCreatePerson = onCreatePerson
        _pickerState = State(
            initialValue: PersonPickerState(
                people: people,
                selectedID: selectedID
            ))
    }

    var body: some View {
        ScrollView {
            VStack(spacing: 16) {
                queryRow
                if !pickerState.visiblePeople.isEmpty {
                    Card {
                        VStack(spacing: 0) {
                            ForEach(pickerState.visiblePeople) { person in
                                let isSelected = pickerState.selectedID == person.id
                                Button {
                                    pickerState.select(person.id)
                                    onSelection(person.id)
                                } label: {
                                    PersonPickerRow(
                                        name: person.name,
                                        color: person.color,
                                        isSelected: isSelected
                                    )
                                }
                                .buttonStyle(.plain)
                                .accessibilityIdentifier("person-picker.person.\(person.id)")
                                .accessibilityAddTraits(isSelected ? .isSelected : [])
                                .accessibilityValue(
                                    isSelected ? Text("Selected") : Text("Not selected")
                                )

                                if person.id != pickerState.visiblePeople.last?.id {
                                    RowDivider().padding(.leading, 14)
                                }
                            }
                        }
                    }
                }
            }
            .padding(16)
        }
        .scrollIndicators(.hidden)
        .onAppear {
            onProvisionalSelection(pickerState.selectedID)
        }
    }

    private var queryRow: some View {
        Card {
            HStack(spacing: 10) {
                TextField("Add person", text: queryBinding)
                    .font(Font.app(16, .regular))
                    .tint(Color.recv)
                    .textInputAutocapitalization(.words)
                    .submitLabel(.done)
                    .accessibilityIdentifier("person-picker.query")
                Button {
                    pickerState.createAndSelectPerson(
                        named: pickerState.query,
                        create: onCreatePerson,
                        select: onSelection
                    )
                } label: {
                    Text("Add")
                        .font(Font.app(15, .semibold))
                        .foregroundColor(.white)
                        .padding(.horizontal, 16)
                        .padding(.vertical, 8)
                        .background(Capsule().fill(isAddDisabled ? Color.muted4 : Color.ink))
                }
                .buttonStyle(.plain)
                .disabled(isAddDisabled)
                .accessibilityIdentifier("person-picker.add")
            }
            .padding(.horizontal, 14)
            .padding(.vertical, 10)
        }
    }

    private var queryBinding: Binding<String> {
        Binding(
            get: { pickerState.query },
            set: { query in
                onProvisionalSelection(pickerState.updateQuery(query))
            }
        )
    }

    private var isAddDisabled: Bool {
        pickerState.query.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty
    }
}

private struct PersonPickerRow: View {
    let name: String
    let color: Color
    let isSelected: Bool

    var body: some View {
        HStack(spacing: 12) {
            AvatarView(initials: name.initials, color: color, size: 38)
            Text(name)
                .font(Font.app(16, .semibold))
                .foregroundColor(Color.ink)
            Spacer(minLength: 8)
            if isSelected {
                Image(systemName: "checkmark")
                    .font(.system(size: 15, weight: .semibold))
                    .foregroundColor(Color.recv)
                    .accessibilityHidden(true)
            }
        }
        .padding(.horizontal, 14)
        .padding(.vertical, 11)
        .contentShape(Rectangle())
    }
}

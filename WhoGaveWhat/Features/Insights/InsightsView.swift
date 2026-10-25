import SwiftUI

/// Year summary, the balance with each person, and a two-person comparison.
struct InsightsView: View {
    let composition: AppComposition
    @State private var selectedYear: Int?
    /// Person whose balances are listed when no one is marked as "You".
    @State private var subjectID: String?
    @State private var compareAID: String?
    @State private var compareBID: String?
    @State private var picker: InsightsPickerSlot?

    var body: some View {
        VStack(alignment: .leading, spacing: 24) {
            YearSummaryCard(
                summary: useCase.summary(gifts: data.gifts, relativeTo: selfPerson?.id, year: year),
                hasViewpoint: selfPerson != nil,
                currencyCode: composition.currencyCode,
                years: useCase.availableYears(gifts: data.gifts),
                selectedYear: yearBinding,
                onMarkSelf: selfPerson == nil ? { composition.router.selectTab(.people) } : nil,
                owner: selfPerson)
            balancesSection
            compareSection
        }
        .padding(.horizontal, 16)
        .sheet(item: $picker) { slot in
            InsightsPersonPicker(
                title: pickerTitle(for: slot),
                people: composition.insightsPickerPeople(for: slot, selectedID: selectedID(for: slot)),
                selectedID: selectedID(for: slot),
                onSelect: { id in
                    composition.recordInsightsPick(id, for: slot)
                    select(id, for: slot)
                    picker = nil
                })
        }
    }

    // MARK: State

    private var data: AppData { composition.data }
    private var useCase: BuildInsightsUseCase { composition.buildInsights }

    private var year: Int {
        useCase.resolvedYear(selected: selectedYear, gifts: data.gifts)
    }

    private var yearBinding: Binding<Int> {
        Binding(
            get: { year },
            set: { chosen in
                selectedYear = chosen
                let currentYear = Calendar.current.component(.year, from: Date())
                composition.analytics.track(.insightsYearChanged(isCurrentYear: chosen == currentYear))
            })
    }

    private func person(id: String?) -> Person? {
        guard let id else { return nil }
        return data.people.first { $0.id == id }
    }

    private var selfPerson: Person? {
        data.selfPerson
    }

    private func pickerTitle(for slot: InsightsPickerSlot) -> LocalizedStringResource {
        switch slot {
        case .subject: "Balances for"
        case .compareA: "Person A"
        case .compareB: "Person B"
        }
    }

    /// Whose balances are listed: you, or the person picked as "Person A".
    private var subject: Person? {
        selfPerson ?? person(id: subjectID) ?? useCase.focusPerson(people: data.people, selfPersonID: nil)
    }

    private var compareA: Person? {
        person(id: compareAID) ?? useCase.focusPerson(people: data.people, selfPersonID: data.selfPersonID)
    }

    private var compareB: Person? {
        guard let compareA else { return nil }
        if let explicit = person(id: compareBID), explicit.id != compareA.id { return explicit }
        return useCase.defaultCounterpart(gifts: data.gifts, people: data.people, for: compareA, year: year)
    }

    private func selectedID(for slot: InsightsPickerSlot) -> String? {
        switch slot {
        case .subject: subject?.id
        case .compareA: compareA?.id
        case .compareB: compareB?.id
        }
    }

    /// Choosing the person already on the other side swaps the two.
    private func select(_ id: String, for slot: InsightsPickerSlot) {
        switch slot {
        case .subject:
            subjectID = id
        case .compareA:
            let previous = compareA?.id
            if id == compareB?.id { compareBID = previous }
            compareAID = id
        case .compareB:
            let previous = compareB?.id
            if id == compareA?.id { compareAID = previous }
            compareBID = id
        }
    }

    // MARK: Balances

    private var balancesSection: some View {
        VStack(alignment: .leading, spacing: 8) {
            SectionHeader(text: "Balance with each person")
            if selfPerson == nil {
                if let subject {
                    personButton(subject, caption: "Balances for", slot: .subject)
                        .accessibilityIdentifier("insights.balances.subject")
                }
            }
            balancesCard
        }
        .accessibilityElement(children: .contain)
        .accessibilityIdentifier("insights.balances")
    }

    @ViewBuilder
    private var balancesCard: some View {
        let balances =
            subject.map {
                useCase.balances(gifts: data.gifts, people: data.people, relativeTo: $0.id, year: year)
            } ?? []
        Card {
            if balances.isEmpty {
                emptyBalancesText
                    .font(Font.app(15, .regular)).foregroundColor(Color.textSecondary)
                    .frame(maxWidth: .infinity, alignment: .leading)
                    .padding(16)
            } else {
                VStack(spacing: 0) {
                    ForEach(balances) { balance in
                        NavigationLink(value: balance.person.id) {
                            BalanceRow(balance: balance, currencyCode: composition.currencyCode)
                        }
                        .buttonStyle(.plain)
                        if balance.id != balances.last?.id { RowDivider().padding(.leading, 14) }
                    }
                }
            }
        }
    }

    private var emptyBalancesText: Text {
        guard let subject else { return Text("No gifts in \(String(year))") }
        return selfPerson == nil
            ? Text("No gifts with \(subject.name) in \(String(year))")
            : Text("No gifts of yours in \(String(year))")
    }

    // MARK: Comparison

    private var compareSection: some View {
        VStack(alignment: .leading, spacing: 8) {
            SectionHeader(text: "Compare two people")
            Card {
                VStack(alignment: .leading, spacing: 16) {
                    if let a = compareA, let b = compareB {
                        HStack(spacing: 8) {
                            personButton(a, caption: "Person A", slot: .compareA)
                                .accessibilityIdentifier("insights.compare.a")
                            swapButton
                            personButton(b, caption: "Person B", slot: .compareB)
                                .accessibilityIdentifier("insights.compare.b")
                        }
                        comparisonDetails(useCase.comparison(gifts: data.gifts, a: a, b: b, year: year))
                    } else {
                        Text("Add two people to compare them")
                            .font(Font.app(15, .regular)).foregroundColor(Color.textSecondary)
                    }
                }
                .padding(16)
                .frame(maxWidth: .infinity, alignment: .leading)
            }
        }
        .accessibilityElement(children: .contain)
        .accessibilityIdentifier("insights.compare")
    }

    /// Swaps Person A and Person B, so the flows and net read from the other side.
    private var swapButton: some View {
        Button {
            let previousA = compareA?.id
            withAnimation(.easeInOut(duration: 0.2)) {
                compareAID = compareB?.id
                compareBID = previousA
            }
        } label: {
            Image(systemName: "arrow.left.arrow.right")
                .font(.system(size: 14, weight: .semibold)).foregroundColor(Color.textSecondary)
                .frame(width: 32, height: 44)
                // Reach into the 8 pt gaps on both sides for a 44 pt target without narrowing the pickers.
                .contentShape(Rectangle().inset(by: -6))
        }
        .buttonStyle(.plain)
        .accessibilityLabel("Swap people")
        .accessibilityIdentifier("insights.compare.swap")
    }

    private func comparisonDetails(_ comparison: PersonComparison) -> some View {
        VStack(alignment: .leading, spacing: 12) {
            flowRow(
                from: comparison.a, to: comparison.b, value: comparison.aToBValue, count: comparison.aToBCount,
                color: Color.given)
            flowRow(
                from: comparison.b, to: comparison.a, value: comparison.bToAValue, count: comparison.bToACount,
                color: Color.received)
            PairBar(
                first: comparison.aToBValue,
                second: comparison.bToAValue,
                firstColor: Color.given,
                secondColor: Color.received)
            RowDivider()
            HStack {
                Text("Net for \(comparison.a.name)")
                    .font(Font.app(15, .semibold)).foregroundColor(Color.textPrimary)
                Spacer(minLength: 8)
                NetBadge(net: comparison.net, currencyCode: composition.currencyCode)
            }
        }
    }

    /// `color` is the direction as seen by Person A, shared with the bar: given by A, then received by A.
    private func flowRow(from giver: Person, to recipient: Person, value: Double, count: Int, color: Color) -> some View {
        HStack(alignment: .firstTextBaseline, spacing: 8) {
            Circle().fill(color).frame(width: 10, height: 10)
            Text(verbatim: "\(giver.name) → \(recipient.name)")
                .font(Font.app(15, .regular)).foregroundColor(Color.textPrimary)
                .frame(maxWidth: .infinity, alignment: .leading)
            VStack(alignment: .trailing, spacing: 2) {
                Text(formattedCurrency(value, code: composition.currencyCode))
                    .font(Font.app(15, .semibold, rounded: true)).foregroundColor(Color.textPrimary)
                Text(verbatim: LocalizedCount.gifts(count))
                    .font(Font.app(12, .regular)).foregroundColor(Color.textSecondary)
            }
            .fixedSize(horizontal: true, vertical: false)
        }
        .accessibilityElement(children: .combine)
    }

    private func personButton(_ person: Person, caption: LocalizedStringKey, slot: InsightsPickerSlot) -> some View {
        Button {
            picker = slot
        } label: {
            VStack(alignment: .leading, spacing: 6) {
                Text(caption)
                    .font(Font.app(12, .regular)).foregroundColor(Color.textSecondary)
                HStack(spacing: 8) {
                    AvatarView(
                        initials: person.name.initials, color: person.color, size: .compact, imageData: person.imageData)
                    Text(person.name)
                        .font(Font.app(15, .semibold)).foregroundColor(Color.textPrimary)
                        .lineLimit(2)
                        .frame(maxWidth: .infinity, alignment: .leading)
                    Image(systemName: "chevron.up.chevron.down")
                        .font(.system(size: 11, weight: .semibold)).foregroundColor(Color.textTertiary)
                }
            }
            .padding(10)
            .frame(maxWidth: .infinity, alignment: .leading)
            .background(
                Color.fillTrack,
                in: RoundedRectangle(cornerRadius: DesignMetrics.radiusMedium, style: .continuous)
            )
            .contentShape(Rectangle())
        }
        .buttonStyle(.plain)
    }
}

private struct BalanceRow: View {
    let balance: PersonBalance
    let currencyCode: String

    var body: some View {
        HStack(spacing: 12) {
            AvatarView(
                initials: balance.person.name.initials, color: balance.person.color, size: .compact,
                imageData: balance.person.imageData)
            VStack(alignment: .leading, spacing: 2) {
                Text(balance.person.name)
                    .font(Font.app(16, .semibold)).foregroundColor(Color.textPrimary)
                    .fixedSize(horizontal: false, vertical: true)
                Text(
                    "Received \(LocalizedCount.gifts(balance.receivedCount)) · Given \(LocalizedCount.gifts(balance.givenCount))"
                )
                .font(Font.app(13, .regular)).foregroundColor(Color.textSecondary)
                .fixedSize(horizontal: false, vertical: true)
            }
            .frame(maxWidth: .infinity, alignment: .leading)
            VStack(alignment: .trailing, spacing: 3) {
                CountBalanceBadge(net: balance.countNet)
                Text(verbatim: formattedSignedCurrency(balance.net, code: currencyCode))
                    .font(Font.app(12, .regular, rounded: true)).foregroundColor(Color.textSecondary)
                    .lineLimit(1)
                    .fixedSize()
            }
        }
        .padding(.horizontal, 14).padding(.vertical, 12)
        .contentShape(Rectangle())
        .accessibilityElement(children: .combine)
    }
}

/// Modal list for choosing one person, in the style of the Add gift pickers.
private struct InsightsPersonPicker: View {
    let title: LocalizedStringResource
    let people: [Person]
    let selectedID: String?
    let onSelect: (String) -> Void

    var body: some View {
        IntrinsicModalScaffold(title: title) {
            ScrollView {
                Card {
                    VStack(spacing: 0) {
                        ForEach(people) { person in
                            let isSelected = person.id == selectedID
                            Button {
                                onSelect(person.id)
                            } label: {
                                PersonPickerRow(
                                    name: person.name,
                                    color: person.color,
                                    imageData: person.imageData,
                                    isSelected: isSelected)
                            }
                            .buttonStyle(.plain)
                            .accessibilityIdentifier("insights.picker.person.\(person.id)")
                            .accessibilityAddTraits(isSelected ? .isSelected : [])
                            if person.id != people.last?.id { RowDivider().padding(.leading, 14) }
                        }
                    }
                }
                .padding(16)
            }
            .scrollIndicators(.hidden)
        }
        .presentationDetents([.medium, .large])
        .presentationDragIndicator(.visible)
        .presentationBackground(Color.appBackground)
    }
}

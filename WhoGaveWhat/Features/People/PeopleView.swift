import SwiftUI

/// Everyone you track as one flat alphabetical list, as a native `List` so a person can be swiped away.
/// Deleting a person is irreversible and also wipes every gift they gave or
/// received, so it's gated behind a big, hard-to-miss warning.
struct PeopleView: View {
    let composition: AppComposition
    @State private var addMode: PersonAddMode?
    @Environment(\.adaptiveLayout) private var layout

    var body: some View {
        List {
            ScreenHeadingSection(title: "People")
            if composition.data.isLoadFailing {
                LoadFailedListSection { composition.reloadData() }
            }
            if composition.data.showsPeopleWelcome {
                Section {
                    PeopleWelcome(
                        onAddYourself: { addMode = .yourself },
                        onAddSomeoneElse: { addMode = .welcomePerson }
                    )
                    // The row spans the full width and pads itself, like the Home welcome.
                    .padding(.horizontal, WelcomeMetrics.horizontalInset)
                    .padding(.top, 8)
                    .padding(.bottom, 24)
                    .listRowInsets(EdgeInsets())
                    .listRowBackground(Color.clear)
                    .listRowSeparator(.hidden)
                }
                .zeroHorizontalListSectionMargins()
            } else {
                ForEach(sortedPeople) { person in
                    personRow(person)
                }
            }
        }
        .listStyle(.insetGrouped)
        .readableColumn()
        .scrollContentBackground(.hidden)
        .softBottomScrollEdge()
        .background(Color.appBackground)
        .safeAreaInset(edge: .bottom) {
            // The welcome card carries the only add actions until the first person.
            if !layout.placesAddActionInToolbar, !isEmpty {
                AddPersonFloatingAction {
                    addMode = .person
                }
            }
        }
        .toolbar {
            if layout.placesAddActionInToolbar, !isEmpty {
                ToolbarItem(placement: .primaryAction) {
                    ToolbarAddButton(title: "Add person") { addMode = .person }
                        .accessibilityIdentifier("people.add-person")
                }
            }
        }
        .sheet(item: $addMode) { mode in
            PersonEditorSheet(
                title: mode == .yourself ? "Add yourself" : "Add person",
                initialName: "",
                showsPhoto: false,
                onCancel: { addMode = nil },
                onSave: { name, _ in
                    guard let id = composition.createPerson(name: name, source: mode.source) else {
                        throw CocoaError(.validationMissingMandatoryProperty)
                    }
                    if mode == .yourself {
                        composition.markSelf(true, personID: id)
                    }
                    addMode = nil
                }
            )
        }
        // The first saved person and the last deleted one swap the welcome, list and button smoothly.
        .animation(.default, value: isEmpty)
        .animation(.default, value: composition.data.isLoadFailing)
    }

    private var isEmpty: Bool {
        composition.data.people.isEmpty
    }

    private var sortedPeople: [Person] {
        composition.data.people.sorted {
            $0.name.localizedStandardCompare($1.name) == .orderedAscending
        }
    }

    private func personRow(_ person: Person) -> some View {
        let count = giftsCount(involving: person.id)
        return NavigationLink(value: person.id) {
            PersonRow(
                entityId: person.id, name: person.name, color: person.color,
                imageData: person.imageData,
                isSelf: composition.data.isSelf(person.id),
                gifts: gifts(for: person.id),
                currencyCode: composition.currencyCode)
        }
        .listRowInsets(EdgeInsets(top: 0, leading: 14, bottom: 0, trailing: 12))
        .swipeToDelete(
            title: Text(verbatim: String(format: NSLocalizedString("Delete %@?", comment: ""), person.name)),
            confirmLabel: Text(verbatim: deletePersonActionLabel(count)),
            message: Text(verbatim: personDeleteMessage(person.name, count: count)),
            allowsFullSwipe: false,
            isEnabled: composition.deletePersonUseCase.canDelete(id: person.id),
            failureTitle: Text("Could not delete this person")
        ) {
            composition.deletePerson(id: person.id, source: .peopleList)
        }
    }

    private func personDeleteMessage(_ name: String, count: Int) -> String {
        let fmt = NSLocalizedString(
            "This permanently deletes %1$@ and all %2$lld of their gifts. This cannot be undone.",
            comment: "")
        return String(format: fmt, name, count)
    }

    private func deletePersonActionLabel(_ count: Int) -> String {
        let fmt = NSLocalizedString("Delete person and %lld gifts", comment: "")
        return String(format: fmt, count)
    }

    private func gifts(for id: String) -> [Gift] {
        composition.loadPersonGifts.execute(
            personID: id,
            gifts: composition.data.gifts
        )
    }

    private func giftsCount(involving id: String) -> Int {
        composition.data.gifts.filter { $0.giverID == id || $0.recipientID == id }.count
    }
}

/// What the Add person sheet was opened for.
private enum PersonAddMode: String, Identifiable {
    /// From the floating or toolbar button.
    case person
    /// From the welcome card's "Add someone else".
    case welcomePerson
    /// From the welcome card's "Add yourself": the new person becomes the viewpoint.
    case yourself

    var id: String { rawValue }

    var source: PersonCreationSource {
        self == .person ? .peopleTab : .peopleWelcome
    }
}

private struct AddPersonFloatingAction: View {
    let action: () -> Void

    var body: some View {
        FloatingActionButton(title: "Add person", systemImage: "plus", action: action)
            .accessibilityLabel("Add person")
            .accessibilityIdentifier("people.add-person")
    }
}

struct PersonRow: View {
    let entityId: String
    let name: String
    let color: Color
    let imageData: Data?
    let isSelf: Bool
    let gifts: [Gift]
    let currencyCode: String

    var body: some View {
        let r = gifts.filter {
            GiftDirectionResolver.resolve(
                giverID: $0.giverID,
                recipientID: $0.recipientID,
                relativeTo: entityId
            ) == .received
        }.count
        let gv = gifts.filter {
            GiftDirectionResolver.resolve(
                giverID: $0.giverID,
                recipientID: $0.recipientID,
                relativeTo: entityId
            ) == .given
        }.count

        HStack(spacing: 12) {
            AvatarView(initials: name.initials, color: color, size: .regular, imageData: imageData)
            VStack(alignment: .leading, spacing: 2) {
                HStack(spacing: 6) {
                    Text(name).font(Font.app(16, .semibold)).foregroundColor(Color.textPrimary)
                        .fixedSize(horizontal: false, vertical: true)
                    if isSelf {
                        YouBadge()
                            .accessibilityIdentifier("people.you-badge")
                    }
                }
                Text("\(r) received · \(gv) given")
                    .font(Font.app(13, .regular)).foregroundColor(Color.textSecondary)
                    .fixedSize(horizontal: false, vertical: true)
            }
            .frame(maxWidth: .infinity, alignment: .leading)
            Text(formattedCurrency(gifts.totalValue, code: currencyCode))
                .font(Font.app(15, .semibold, rounded: true)).foregroundColor(Color.textPrimary)
                .lineLimit(1)
                .layoutPriority(1)
        }
        .padding(.horizontal, 0).padding(.vertical, 13)
        .contentShape(Rectangle())
    }
}

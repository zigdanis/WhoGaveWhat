import SwiftUI

/// Settings, presented as a native sheet in the Settings-app idiom: a profile
/// banner over grouped cards. Toggles are native; everything else is a quiet row.
struct SettingsView: View {
    let composition: AppComposition
    @State private var notifEnabled = true
    @State private var cloudEnabled = true

    var body: some View {
        NavigationStack {
            ScrollView {
                VStack(alignment: .leading, spacing: 0) {
                    profileCard

                    SectionHeader(text: "Preferences").padding(.top, 24).padding(.bottom, 7)
                    Card {
                        VStack(spacing: 0) {
                            NavigationLink {
                                CurrencyPickerView(composition: composition)
                            } label: {
                                valueRow(
                                    icon: "banknote.fill",
                                    tint: Color.recv,
                                    label: "Currency",
                                    value: currencyDisplayName
                                )
                            }
                            .buttonStyle(.plain)
                            .accessibilityIdentifier("settings.currency")
                            RowDivider().padding(.leading, 58)
                            toggleRow(icon: "bell.fill", tint: Color.ink, label: "Notifications", bind: notifBinding)
                            RowDivider().padding(.leading, 58)
                            valueRow(icon: "rectangle.stack.fill", tint: Color.recv, label: "Default view", value: "All gifts")
                        }
                    }

                    SectionHeader(text: "Data & sync").padding(.top, 24).padding(.bottom, 7)
                    Card {
                        VStack(spacing: 0) {
                            toggleRow(icon: "icloud.fill", tint: Color.recv, label: "iCloud sync", bind: cloudBinding)
                            RowDivider().padding(.leading, 58)
                            actionRow(icon: "square.and.arrow.up.fill", tint: Color.ink, label: "Export data")
                        }
                    }

                    SectionHeader(text: "About").padding(.top, 24).padding(.bottom, 7)
                    Card {
                        VStack(spacing: 0) {
                            actionRow(icon: "star.fill", tint: Color.recv, label: "Rate Who Gave What")
                            RowDivider().padding(.leading, 58)
                            actionRow(icon: "hand.raised.fill", tint: Color.ink, label: "Privacy Policy")
                            RowDivider().padding(.leading, 58)
                            NavigationLink {
                                ThirdPartyLicensesView()
                            } label: {
                                actionRow(icon: "doc.text.fill", tint: Color.recv, label: "Third-party licenses")
                            }
                            .buttonStyle(.plain)
                            RowDivider().padding(.leading, 58)
                            valueRow(icon: "info.circle.fill", tint: Color.gold, label: "Version", value: "2.0")
                        }
                    }

                    Button { } label: {
                        Text("Sign out")
                            .font(Font.app(16, .semibold)).foregroundColor(Color(hex: 0xE5484D))
                            .frame(maxWidth: .infinity).padding(.vertical, 15)
                            .background(RoundedRectangle(cornerRadius: DesignMetrics.cornerRadius, style: .continuous).fill(Color.card))
                    }
                    .buttonStyle(.plain)
                    .padding(.top, 24)
                }
                .padding(.horizontal, 16).padding(.top, 6).padding(.bottom, 30)
            }
            .scrollIndicators(.hidden)
            .background(Color.bg)
            .navigationTitle("Settings")
            .toolbar {
                ToolbarItem(placement: .confirmationAction) {
                    Button("Done") { composition.router.dismissSettings() }.fontWeight(.semibold).tint(Color.recv)
                }
            }
        }
    }

    private var profileCard: some View {
        Card {
            HStack(spacing: 14) {
                AvatarView(initials: "A", color: Color.ink, size: 52)
                VStack(alignment: .leading, spacing: 2) {
                    Text("Anton").font(Font.app(18, .semibold)).foregroundColor(Color.ink)
                    Text("Apple Account, iCloud & more")
                        .font(Font.app(13, .regular)).foregroundColor(Color.muted3)
                }
                Spacer(minLength: 8)
                Chevron()
            }
            .padding(.horizontal, 14).padding(.vertical, 14)
        }
    }

    private func iconTile(_ name: String, _ tint: Color) -> some View {
        Image(systemName: name)
            .font(.system(size: 14, weight: .semibold))
            .foregroundColor(.white)
            .frame(width: 30, height: 30)
            .background(RoundedRectangle(cornerRadius: 7, style: .continuous).fill(tint))
    }

    private func valueRow(icon: String, tint: Color, label: String, value: String) -> some View {
        HStack(spacing: 12) {
            iconTile(icon, tint)
            Text(LocalizedStringKey(label)).font(Font.app(16, .regular)).foregroundColor(Color.ink)
            Spacer(minLength: 8)
            Text(verbatim: value).font(Font.app(16, .regular)).foregroundColor(Color.muted)
            Chevron()
        }
        .padding(.horizontal, 14).padding(.vertical, 9)
    }

    private func actionRow(icon: String, tint: Color, label: String) -> some View {
        HStack(spacing: 12) {
            iconTile(icon, tint)
            Text(LocalizedStringKey(label)).font(Font.app(16, .regular)).foregroundColor(Color.ink)
            Spacer(minLength: 8)
            Chevron()
        }
        .padding(.horizontal, 14).padding(.vertical, 9)
    }

    private func toggleRow(icon: String, tint: Color, label: String, bind: Binding<Bool>) -> some View {
        HStack(spacing: 12) {
            iconTile(icon, tint)
            Toggle(isOn: bind) {
                Text(LocalizedStringKey(label)).font(Font.app(16, .regular)).foregroundColor(Color.ink)
            }
            .tint(Color.emerald)
        }
        .padding(.horizontal, 14).padding(.vertical, 5)
    }

    private var notifBinding: Binding<Bool> {
        $notifEnabled
    }
    private var cloudBinding: Binding<Bool> {
        $cloudEnabled
    }

    private var currencyDisplayName: String {
        let locale = Locale.autoupdatingCurrent
        let name = locale.localizedString(forCurrencyCode: composition.currencyCode)
            ?? composition.currencyCode
        return "\(name) \(currencySymbol(code: composition.currencyCode, locale: locale))"
    }
}

private struct CurrencyPickerView: View {
    let composition: AppComposition

    var body: some View {
        List(CurrencyOption.all) { option in
            Button {
                composition.setCurrencyCode(option.code)
            } label: {
                HStack(spacing: 12) {
                    Text(option.symbol)
                        .font(Font.app(16, .semibold))
                        .foregroundColor(Color.recv)
                        .frame(width: 42, alignment: .leading)
                    VStack(alignment: .leading, spacing: 2) {
                        Text(option.name)
                            .font(Font.app(16, .regular))
                            .foregroundColor(Color.ink)
                        Text(verbatim: option.code)
                            .font(Font.app(13, .regular))
                            .foregroundColor(Color.muted)
                    }
                    Spacer(minLength: 8)
                    if composition.currencyCode == option.code {
                        Image(systemName: "checkmark")
                            .font(.system(size: 15, weight: .semibold))
                            .foregroundColor(Color.recv)
                            .accessibilityHidden(true)
                    }
                }
                .contentShape(Rectangle())
            }
            .buttonStyle(.plain)
            .accessibilityIdentifier("settings.currency.\(option.code)")
        }
        .listStyle(.insetGrouped)
        .scrollContentBackground(.hidden)
        .background(Color.bg)
        .navigationTitle("Currency")
        .navigationBarTitleDisplayMode(.inline)
    }
}

private struct CurrencyOption: Identifiable {
    let code: String
    let name: String
    let symbol: String

    var id: String { code }

    static let all: [CurrencyOption] = {
        let locale = Locale.autoupdatingCurrent
        return Locale.commonISOCurrencyCodes
            .map { code in
                CurrencyOption(
                    code: code,
                    name: locale.localizedString(forCurrencyCode: code) ?? code,
                    symbol: currencySymbol(code: code, locale: locale)
                )
            }
            .sorted { lhs, rhs in
                lhs.name.localizedCaseInsensitiveCompare(rhs.name) == .orderedAscending
            }
    }()
}

import SwiftUI

/// Settings contains only destinations backed by working app behavior.
struct SettingsView: View {
    static let privacyPolicyURL = URL(string: "https://ziganshin.pro/whogavewhat/privacy-policy")!

    let composition: AppComposition

    var body: some View {
        NavigationStack {
            ScrollView {
                VStack(alignment: .leading, spacing: 0) {
                    SectionHeader(text: "Preferences").padding(.bottom, 7)
                    Card {
                        NavigationLink {
                            CurrencyPickerView(composition: composition)
                        } label: {
                            SettingsValueRow(
                                icon: "banknote.fill",
                                tint: Color.brandFill,
                                label: "Currency",
                                value: currencyDisplayName
                            )
                        }
                        .buttonStyle(.plain)
                        .accessibilityIdentifier("settings.currency")
                        .accessibilityValue(composition.currencyCode)
                    }

                    SectionHeader(text: "Gift icons").padding(.top, 24).padding(.bottom, 7)
                    Card {
                        Toggle(
                            "Cloud icon suggestions",
                            isOn: Binding(
                                get: { composition.cloudIconConsent == .allowed },
                                set: { composition.setCloudIconConsent($0 ? .allowed : .declined) }
                            )
                        )
                        .font(Font.app(16, .regular))
                        .foregroundStyle(Color.textPrimary)
                        .tint(Color.brandFill)
                        .padding(.horizontal, 14).padding(.vertical, 9)
                        .accessibilityIdentifier("settings.cloud-icons")
                    }
                    Text(
                        "Sends only the gift name, with a random app ID for rate limiting, through the WhoGaveWhat server to TypeSafe AI (Jev) to choose an icon. People, dates, amounts and occasions are never sent. TypeSafe processes requests under its terms."
                    )
                    .font(Font.app(13, .regular))
                    .foregroundStyle(Color.textSecondary)
                    .fixedSize(horizontal: false, vertical: true)
                    .padding(.horizontal, 14).padding(.top, 8)

                    SectionHeader(text: "About").padding(.top, 24).padding(.bottom, 7)
                    Card {
                        Link(destination: Self.privacyPolicyURL) {
                            SettingsActionRow(
                                icon: "hand.raised.fill",
                                tint: Color.brandFill,
                                label: "Privacy Policy"
                            )
                        }
                        .buttonStyle(.plain)
                        .accessibilityIdentifier("settings.privacy-policy")
                        RowDivider().padding(.leading, 56)
                        NavigationLink {
                            ThirdPartyLicensesView()
                        } label: {
                            SettingsActionRow(
                                icon: "doc.text.fill",
                                tint: Color.brandFill,
                                label: "Third-party licenses"
                            )
                        }
                        .buttonStyle(.plain)
                        .accessibilityIdentifier("settings.third-party-licenses")
                    }
                }
                .padding(.horizontal, 16).padding(.top, 6).padding(.bottom, 30)
            }
            .scrollIndicators(.hidden)
            .background(Color.appBackground)
            .accessibilityIdentifier("settings.screen")
            .navigationTitle("Settings")
            .toolbar {
                ToolbarItem(placement: .confirmationAction) {
                    Button("Done") { composition.router.dismissSettings() }.fontWeight(.semibold).tint(Color.brand)
                }
            }
        }
    }

    private var currencyDisplayName: String {
        let locale = Locale.autoupdatingCurrent
        let name =
            locale.localizedString(forCurrencyCode: composition.currencyCode)
            ?? composition.currencyCode
        return "\(name) \(currencySymbol(code: composition.currencyCode, locale: locale))"
    }
}

private struct SettingsValueRow: View {
    let icon: String
    let tint: Color
    let label: LocalizedStringResource
    let value: String

    var body: some View {
        HStack(spacing: 12) {
            SettingsIconTile(name: icon, tint: tint)
            Text(label).font(Font.app(16, .regular)).foregroundColor(Color.textPrimary)
            Spacer(minLength: 8)
            Text(value).font(Font.app(16, .regular)).foregroundColor(Color.textSecondary)
            Chevron()
        }
        .padding(.horizontal, 14).padding(.vertical, 9)
        .contentShape(Rectangle())
    }
}

private struct SettingsActionRow: View {
    let icon: String
    let tint: Color
    let label: LocalizedStringResource

    var body: some View {
        HStack(spacing: 12) {
            SettingsIconTile(name: icon, tint: tint)
            Text(label).font(Font.app(16, .regular)).foregroundColor(Color.textPrimary)
            Spacer(minLength: 8)
            Chevron()
        }
        .padding(.horizontal, 14).padding(.vertical, 9)
        .contentShape(Rectangle())
    }
}

private struct SettingsIconTile: View {
    let name: String
    let tint: Color

    var body: some View {
        Image(systemName: name)
            .font(.system(size: 14, weight: .semibold))
            .foregroundColor(Color.onFill)
            .frame(width: 30, height: 30)
            .background(RoundedRectangle(cornerRadius: 9, style: .continuous).fill(tint))
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
                        .foregroundColor(Color.brand)
                        .frame(width: 42, alignment: .leading)
                    VStack(alignment: .leading, spacing: 2) {
                        Text(option.name)
                            .font(Font.app(16, .regular))
                            .foregroundColor(Color.textPrimary)
                        Text(verbatim: option.code)
                            .font(Font.app(13, .regular))
                            .foregroundColor(Color.textSecondary)
                    }
                    Spacer(minLength: 8)
                    if composition.currencyCode == option.code {
                        Image(systemName: "checkmark")
                            .font(.system(size: 15, weight: .semibold))
                            .foregroundColor(Color.brand)
                            .accessibilityHidden(true)
                    }
                }
                .contentShape(Rectangle())
            }
            .buttonStyle(.plain)
            .accessibilityIdentifier("settings.currency.\(option.code)")
            .accessibilityValue(option.code)
        }
        .listStyle(.insetGrouped)
        .accessibilityIdentifier("settings.currency.list")
        .scrollContentBackground(.hidden)
        .background(Color.appBackground)
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

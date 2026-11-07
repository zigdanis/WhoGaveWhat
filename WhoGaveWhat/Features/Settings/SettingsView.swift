import SwiftUI

/// Settings contains only destinations backed by working app behavior.
struct SettingsView: View {
    static let privacyPolicyURL = URL(string: "https://ziganshin.pro/whogavewhat/privacy-policy")!

    let composition: AppComposition
    @Environment(\.openURL) private var openURL

    var body: some View {
        ScrollView {
            VStack(alignment: .leading, spacing: 0) {
                ScreenHeading(title: "Settings", topSpacing: ScreenHeading.scrollViewTopSpacing, bottomSpacing: 16)
                SectionHeader(text: "Preferences").padding(.bottom, 7)
                Card {
                    NavigationLink {
                        CurrencyPickerView(composition: composition)
                    } label: {
                        SettingsValueRow(
                            icon: "banknote.fill",
                            tint: Color.brandFill,
                            label: "Default currency",
                            value: currencyDisplayName
                        )
                    }
                    .buttonStyle(.plain)
                    .accessibilityIdentifier("settings.currency")
                    .accessibilityValue(composition.defaultCurrency.code)
                }
                SettingsFootnote(text: "settings.default-currency.footnote")
                    .padding(.top, 7)

                DataBackupSettingsSection(composition: composition)
                    .padding(.top, 24)

                SectionHeader(text: "About").padding(.top, 24).padding(.bottom, 7)
                Card {
                    VStack(spacing: 0) {
                        Button {
                            composition.analytics.track(.privacyPolicyOpened)
                            openURL(Self.privacyPolicyURL)
                        } label: {
                            SettingsActionRow(
                                icon: "hand.raised.fill",
                                tint: Color.brandFill,
                                label: "Privacy Policy",
                                opensInBrowser: true
                            )
                        }
                        .buttonStyle(.plain)
                        .accessibilityIdentifier("settings.privacy-policy")
                        RowDivider().padding(.leading, 56)
                        NavigationLink {
                            ThirdPartyLicensesView()
                                .onAppear { composition.analytics.track(.licensesOpened) }
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
            }
            .padding(.horizontal, 16).padding(.top, 6).padding(.bottom, 30)
        }
        .readableColumn()
        .scrollIndicators(.hidden)
        .background(Color.appBackground)
        .accessibilityIdentifier("settings.screen")
        .tabRootTitle("Settings")
    }

    private var currencyDisplayName: String {
        let code = composition.defaultCurrency.code
        return "\(currencyName(code: code)) \(currencySymbol(code: code))"
    }
}

/// Secondary text below a settings card, in the inset of the card's content.
struct SettingsFootnote: View {
    let text: LocalizedStringResource

    var body: some View {
        Text(text)
            .font(Font.app(13, .regular)).foregroundColor(Color.textSecondary)
            .fixedSize(horizontal: false, vertical: true)
            .padding(.horizontal, 14)
            .frame(maxWidth: .infinity, alignment: .leading)
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

struct SettingsActionRow: View {
    let icon: String
    let tint: Color
    let label: LocalizedStringResource
    var opensInBrowser = false
    /// Shows a spinner in place of the chevron while the row's action runs.
    var isBusy = false

    var body: some View {
        HStack(spacing: 12) {
            SettingsIconTile(name: icon, tint: tint)
            Text(label).font(Font.app(16, .regular)).foregroundColor(Color.textPrimary)
            Spacer(minLength: 8)
            if isBusy {
                ProgressView()
            } else if opensInBrowser {
                Image(systemName: "arrow.up.forward")
                    .font(.system(size: 14, weight: .semibold)).foregroundColor(Color.textTertiary)
            } else {
                Chevron()
            }
        }
        .padding(.horizontal, 14).padding(.vertical, 9)
        .contentShape(Rectangle())
    }
}

struct SettingsIconTile: View {
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
        List {
            Section {
                ForEach(CurrencyOption.all) { option in
                    row(option)
                }
            } footer: {
                Text("settings.default-currency.footnote")
            }
        }
        .listStyle(.insetGrouped)
        .readableColumn()
        .accessibilityIdentifier("settings.currency.list")
        .scrollContentBackground(.hidden)
        .background(Color.appBackground)
        .navigationTitle("Default currency")
        .navigationBarTitleDisplayMode(.inline)
    }

    private func row(_ option: CurrencyOption) -> some View {
        Button {
            composition.setDefaultCurrency(option.currency)
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
                if composition.defaultCurrency == option.currency {
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
}

private struct CurrencyOption: Identifiable {
    let currency: SupportedCurrency
    let name: String
    let symbol: String

    var code: String { currency.code }
    var id: String { code }

    static let all: [CurrencyOption] = {
        let locale = Locale.autoupdatingCurrent
        // Only the currencies the app supports; the icon Worker has price buckets for just these.
        return SupportedCurrency.allCases
            .map { currency in
                CurrencyOption(
                    currency: currency,
                    name: currencyName(code: currency.code, locale: locale),
                    symbol: currencySymbol(code: currency.code, locale: locale)
                )
            }
            .sorted { lhs, rhs in
                lhs.name.localizedCaseInsensitiveCompare(rhs.name) == .orderedAscending
            }
    }()
}

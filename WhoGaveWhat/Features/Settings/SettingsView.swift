import SwiftUI

/// Settings, presented as a native sheet in the Settings-app idiom: a profile
/// banner over grouped cards. Toggles are native; everything else is a quiet row.
struct SettingsView: View {
    let router: AppRouter
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
                            valueRow(icon: "rublesign.circle.fill", tint: Color.recv, label: "Currency", value: "Ruble ₽")
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
                    Button("Done") { router.dismissSettings() }.fontWeight(.semibold).tint(Color.recv)
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
            Text(LocalizedStringKey(value)).font(Font.app(16, .regular)).foregroundColor(Color.muted)
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
}

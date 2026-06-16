import SwiftUI

/// Settings, presented as a native sheet in the Settings-app idiom: a profile
/// banner over grouped cards. Toggles are native; everything else is a quiet row.
struct SettingsView: View {
    @EnvironmentObject var store: AppStore

    var body: some View {
        NavigationStack {
            ScrollView {
                VStack(alignment: .leading, spacing: 0) {
                    profileCard

                    SectionHeader(text: "Preferences").padding(.top, 24).padding(.bottom, 7)
                    Card {
                        VStack(spacing: 0) {
                            valueRow(icon: "rublesign.circle.fill", tint: KS.recv, label: "Currency", value: "Ruble ₽")
                            RowDivider().padding(.leading, 58)
                            toggleRow(icon: "bell.fill", tint: KS.ink, label: "Notifications", bind: notifBinding)
                            RowDivider().padding(.leading, 58)
                            valueRow(icon: "rectangle.stack.fill", tint: KS.recv, label: "Default view", value: "All gifts")
                        }
                    }

                    SectionHeader(text: "Data & sync").padding(.top, 24).padding(.bottom, 7)
                    Card {
                        VStack(spacing: 0) {
                            toggleRow(icon: "icloud.fill", tint: KS.recv, label: "iCloud sync", bind: cloudBinding)
                            RowDivider().padding(.leading, 58)
                            actionRow(icon: "square.and.arrow.up.fill", tint: KS.ink, label: "Export data")
                        }
                    }

                    SectionHeader(text: "About").padding(.top, 24).padding(.bottom, 7)
                    Card {
                        VStack(spacing: 0) {
                            actionRow(icon: "star.fill", tint: KS.recv, label: "Rate Who Gave What")
                            RowDivider().padding(.leading, 58)
                            actionRow(icon: "hand.raised.fill", tint: KS.ink, label: "Privacy Policy")
                            RowDivider().padding(.leading, 58)
                            valueRow(icon: "info.circle.fill", tint: KS.gold, label: "Version", value: "2.0")
                        }
                    }

                    Button { } label: {
                        Text("Sign out")
                            .font(KS.font(16, .semibold)).foregroundColor(Color(hex: 0xE5484D))
                            .frame(maxWidth: .infinity).padding(.vertical, 15)
                            .background(RoundedRectangle(cornerRadius: KS.radius, style: .continuous).fill(KS.card))
                    }
                    .buttonStyle(.plain)
                    .padding(.top, 24)
                }
                .padding(.horizontal, 16).padding(.top, 6).padding(.bottom, 30)
            }
            .scrollIndicators(.hidden)
            .background(KS.bg)
            .navigationTitle("Settings")
            .toolbar {
                ToolbarItem(placement: .confirmationAction) {
                    Button("Done") { store.closeSettings() }.fontWeight(.semibold).tint(KS.recv)
                }
            }
        }
    }

    private var profileCard: some View {
        Card {
            HStack(spacing: 14) {
                AvatarView(initials: "A", color: KS.ink, size: 52)
                VStack(alignment: .leading, spacing: 2) {
                    Text("Anton").font(KS.font(18, .semibold)).foregroundColor(KS.ink)
                    Text("Apple Account, iCloud & more")
                        .font(KS.font(13, .regular)).foregroundColor(KS.muted3)
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
            Text(LocalizedStringKey(label)).font(KS.font(16, .regular)).foregroundColor(KS.ink)
            Spacer(minLength: 8)
            Text(LocalizedStringKey(value)).font(KS.font(16, .regular)).foregroundColor(KS.muted)
            Chevron()
        }
        .padding(.horizontal, 14).padding(.vertical, 9)
    }

    private func actionRow(icon: String, tint: Color, label: String) -> some View {
        HStack(spacing: 12) {
            iconTile(icon, tint)
            Text(LocalizedStringKey(label)).font(KS.font(16, .regular)).foregroundColor(KS.ink)
            Spacer(minLength: 8)
            Chevron()
        }
        .padding(.horizontal, 14).padding(.vertical, 9)
    }

    private func toggleRow(icon: String, tint: Color, label: String, bind: Binding<Bool>) -> some View {
        HStack(spacing: 12) {
            iconTile(icon, tint)
            Toggle(isOn: bind) {
                Text(LocalizedStringKey(label)).font(KS.font(16, .regular)).foregroundColor(KS.ink)
            }
            .tint(KS.emerald)
        }
        .padding(.horizontal, 14).padding(.vertical, 5)
    }

    private var notifBinding: Binding<Bool> {
        Binding(get: { store.notifEnabled }, set: { store.notifEnabled = $0 })
    }
    private var cloudBinding: Binding<Bool> {
        Binding(get: { store.cloudEnabled }, set: { store.cloudEnabled = $0 })
    }
}

import SwiftUI

struct SectionHeader: View {
    let text: LocalizedStringResource
    var body: some View {
        Text(text)
            .font(Font.app(13, .regular)).foregroundColor(Color.textSecondary)
            .padding(.horizontal, 4)
            .frame(maxWidth: .infinity, alignment: .leading)
    }
}

struct RowDivider: View {
    var body: some View { Rectangle().fill(Color.separatorLine).frame(height: 1 / 3) }
}

struct Chevron: View {
    var body: some View {
        Image(systemName: "chevron.right")
            .font(.system(size: 14, weight: .semibold)).foregroundColor(Color.textTertiary)
    }
}

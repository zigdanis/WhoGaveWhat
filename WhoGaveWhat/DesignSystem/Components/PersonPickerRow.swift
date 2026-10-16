import SwiftUI

/// Selectable person row shared by the Add gift and Insights pickers.
struct PersonPickerRow: View {
    let name: String
    let color: Color
    let imageData: Data?
    let isSelected: Bool

    var body: some View {
        HStack(spacing: 12) {
            AvatarView(initials: name.initials, color: color, size: .compact, imageData: imageData)
            Text(name)
                .font(Font.app(16, .semibold))
                .foregroundColor(Color.textPrimary)
            Spacer(minLength: 8)
            if isSelected {
                Image(systemName: "checkmark")
                    .font(.system(size: 15, weight: .semibold))
                    .foregroundColor(Color.brand)
                    .accessibilityHidden(true)
            }
        }
        .padding(.horizontal, 14)
        .padding(.vertical, 11)
        .contentShape(Rectangle())
    }
}

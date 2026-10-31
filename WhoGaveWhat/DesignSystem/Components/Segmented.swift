import SwiftUI

struct Segmented: View {
    struct Option {
        let key: String
        let label: LocalizedStringResource
    }

    let options: [Option]
    let selected: String
    let onSelect: (String) -> Void

    @Environment(\.haptics) private var haptics

    var body: some View {
        HStack(spacing: 2) {
            ForEach(options, id: \.key) { option in
                let isSelected = option.key == selected
                Button {
                    if option.key != selected { haptics.play(.selection) }
                    onSelect(option.key)
                } label: {
                    Text(option.label)
                        .font(Font.app(14, .semibold))
                        .foregroundColor(isSelected ? Color.onFill : Color.textSecondary)
                        .lineLimit(2)
                        .multilineTextAlignment(.center)
                        .frame(maxWidth: .infinity)
                        .padding(.vertical, 8)
                        .background(Capsule().fill(isSelected ? Color.brandFill : Color.clear))
                        .contentShape(Capsule())
                }
                .buttonStyle(.plain)
            }
        }
        .padding(3)
        .background(Capsule().fill(Color.fillTrack))
    }
}

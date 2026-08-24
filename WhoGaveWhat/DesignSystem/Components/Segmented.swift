import SwiftUI

struct Segmented: View {
    struct Option {
        let key: String
        let label: LocalizedStringResource
        let accent: Color
    }

    let options: [Option]
    let selected: String
    let onSelect: (String) -> Void

    var body: some View {
        HStack(spacing: 2) {
            ForEach(options, id: \.key) { option in
                let isSelected = option.key == selected
                Button { onSelect(option.key) } label: {
                    Text(option.label)
                        .font(KS.font(14, .semibold))
                        .foregroundColor(isSelected ? .white : KS.chipText)
                        .frame(maxWidth: .infinity)
                        .padding(.vertical, 7)
                        .background(RoundedRectangle(cornerRadius: 7, style: .continuous)
                            .fill(isSelected ? KS.emerald : Color.clear)
                            .shadow(color: isSelected ? KS.emerald.opacity(0.35) : .clear,
                                    radius: 2, x: 0, y: 1))
                        .contentShape(Rectangle())
                }
                .buttonStyle(.plain)
            }
        }
        .padding(2)
        .background(RoundedRectangle(cornerRadius: 9, style: .continuous).fill(KS.track))
    }
}

import SwiftUI

/// Glass capsule menu for choosing among the years that have gifts. Hidden
/// when there is nothing to choose between.
struct YearMenu: View {
    let years: [Int]
    @Binding var selection: Int

    var body: some View {
        if years.count > 1 {
            Menu {
                Picker("Year", selection: $selection) {
                    ForEach(years, id: \.self) { year in
                        Text(verbatim: String(year)).tag(year)
                    }
                }
            } label: {
                HStack(spacing: 5) {
                    Text(verbatim: String(selection))
                    Image(systemName: "chevron.down")
                        .font(.system(size: 11, weight: .bold))
                }
                .font(Font.app(14, .semibold))
                .foregroundStyle(Color.brand)
                .padding(.horizontal, 12)
                .padding(.vertical, 7)
                .glassEffect(.regular.interactive(), in: Capsule())
            }
            .accessibilityLabel("Year")
            .accessibilityValue(String(selection))
            .accessibilityIdentifier("year-menu")
        }
    }
}

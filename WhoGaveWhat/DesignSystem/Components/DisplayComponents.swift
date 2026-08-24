import SwiftUI

struct BarView: View {
    let pct: Double
    let color: Color
    var height: CGFloat = 8

    var body: some View {
        GeometryReader { geometry in
            Capsule().fill(color)
                .frame(width: max(geometry.size.width * CGFloat(max(pct, 4) / 100), height))
        }
        .frame(height: height)
        .frame(maxWidth: .infinity, alignment: .leading)
        .background(Capsule().fill(Color.track))
    }
}

struct SectionHeader: View {
    let text: LocalizedStringResource
    var body: some View {
        Text(text)
            .font(Font.app(13, .regular)).foregroundColor(Color.muted)
            .padding(.horizontal, 4)
            .frame(maxWidth: .infinity, alignment: .leading)
    }
}

struct RowDivider: View {
    var body: some View { Rectangle().fill(Color.sep).frame(height: 1) }
}

struct Chevron: View {
    var body: some View {
        Image(systemName: "chevron.right")
            .font(.system(size: 14, weight: .semibold)).foregroundColor(Color.chevron)
    }
}

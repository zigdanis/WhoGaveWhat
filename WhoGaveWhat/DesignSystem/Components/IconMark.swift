import SwiftUI

private struct TriangleShape: Shape {
    let points: [CGPoint]
    func path(in rect: CGRect) -> Path {
        var path = Path()
        let mapped = points.map {
            CGPoint(x: rect.minX + $0.x * rect.width, y: rect.minY + $0.y * rect.height)
        }
        path.move(to: mapped[0])
        path.addLine(to: mapped[1])
        path.addLine(to: mapped[2])
        path.closeSubpath()
        return path
    }
}

struct IconMark: View {
    var size: CGFloat
    private var corner: CGFloat { size * 0.15 }
    private let give = [CGPoint(x: 0.45275, y: 0.238), CGPoint(x: 0.6715, y: 0.531), CGPoint(x: 0.234, y: 0.531)]
    private let take = [CGPoint(x: 0.328, y: 0.57), CGPoint(x: 0.7655, y: 0.57), CGPoint(x: 0.54675, y: 0.863)]

    var body: some View {
        ZStack {
            RoundedRectangle(cornerRadius: corner, style: .continuous).fill(Color.ink)
            TriangleShape(points: give).fill(Color.white)
            TriangleShape(points: take).fill(Color.emerald)
        }
        .frame(width: size, height: size)
    }
}

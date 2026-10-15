import SwiftUI
import UIKit

/// Avatar sizes shared by every screen; avatars are always circles.
enum AvatarSize {
    case compact
    case regular
    case large
    case hero

    var points: CGFloat {
        switch self {
        case .compact: 36
        case .regular: 44
        case .large: 72
        case .hero: 112
        }
    }
}

struct AvatarView: View {
    let initials: String
    let color: Color
    var size: AvatarSize = .regular
    var selected = false
    var imageData: Data?
    @State private var decodedImage: UIImage?

    init(
        initials: String,
        color: Color,
        size: AvatarSize = .regular,
        selected: Bool = false,
        imageData: Data? = nil
    ) {
        self.initials = initials
        self.color = color
        self.size = size
        self.selected = selected
        self.imageData = imageData
        _decodedImage = State(initialValue: imageData.flatMap { UIImage(data: $0) })
    }

    var body: some View {
        Group {
            if let decodedImage {
                Image(uiImage: decodedImage).resizable().scaledToFill()
            } else if initials.isEmpty {
                Image(systemName: "person.fill")
                    .font(.system(size: size.points * 0.42, weight: .medium))
                    .foregroundColor(Color.onFill.opacity(0.9))
            } else {
                Text(initials)
                    .font(.system(size: size.points * 0.4, weight: .semibold, design: .rounded))
                    .foregroundColor(Color.onFill)
                    .minimumScaleFactor(0.6)
                    .lineLimit(1)
            }
        }
        .frame(width: size.points, height: size.points)
        .background(color)
        .clipShape(Circle())
        .overlay(Circle().strokeBorder(Color.separatorLine, lineWidth: 0.5))
        .onChange(of: imageData) { _, newValue in
            decodedImage = newValue.flatMap { UIImage(data: $0) }
        }
        .overlay {
            if selected {
                Circle()
                    .strokeBorder(Color.brand, lineWidth: 2.5)
                    .padding(-4)
            }
        }
    }
}

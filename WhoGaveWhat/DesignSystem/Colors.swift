import SwiftUI
import UIKit

/// Semantic color tokens. Surfaces and text follow the system palette so they
/// adapt to light and dark appearance (and elevated sheets) automatically; the
/// brand green and the gift-direction tints carry explicit light/dark variants.
extension Color {
    // MARK: Surfaces
    static let appBackground = Color(uiColor: .systemGroupedBackground)
    static let surface = Color(uiColor: .secondarySystemGroupedBackground)
    static let surfaceElevated = Color(uiColor: .tertiarySystemGroupedBackground)

    // MARK: Text
    static let textPrimary = Color(uiColor: .label)
    static let textSecondary = Color(uiColor: .secondaryLabel)
    static let textTertiary = Color(uiColor: .tertiaryLabel)
    /// Foreground for content drawn on a saturated fill (brand, person colors).
    static let onFill = Color.white

    // MARK: Lines and fills
    static let separatorLine = Color(uiColor: .separator)
    static let fillTrack = Color(uiColor: .tertiarySystemFill)
    /// Avatar background for people without a photo or assigned color.
    static let avatarPlaceholder = Color(light: 0x8E8E93, dark: 0x636366)

    // MARK: Brand accent
    /// Accent for text, icons and tints; brightens in dark mode to stay legible.
    static let brand = Color(uiColor: .brand)
    /// Solid fill for primary controls that carry a white label in both modes.
    static let brandFill = Color(light: 0x12805C, dark: 0x117A58)

    // MARK: Gift directions
    static let received = brand
    static let receivedTint = Color(light: 0xE6F2EC, dark: 0x3DD39A, darkAlpha: 0.18)
    static let given = textPrimary
    static let givenTint = fillTrack

    // MARK: Status
    static let destructive = Color(uiColor: .systemRed)

    /// sRGB color from a hex value.
    init(hex: UInt, alpha: Double = 1) {
        self.init(uiColor: UIColor(hex: hex, alpha: alpha))
    }

    /// Person color from its stored hex; lifted in dark mode so near-black and
    /// slate swatches stay visible against dark surfaces.
    init(personHex hex: UInt) {
        self.init(
            uiColor: UIColor { traits in
                let base = UIColor(hex: hex)
                return traits.userInterfaceStyle == .dark ? base.lighter(by: 0.2) : base
            })
    }

    /// Color that resolves to `light` or `dark` with the current appearance.
    init(light: UInt, dark: UInt, darkAlpha: Double = 1) {
        self.init(
            uiColor: UIColor { traits in
                traits.userInterfaceStyle == .dark
                    ? UIColor(hex: dark, alpha: darkAlpha)
                    : UIColor(hex: light)
            })
    }
}

extension UIColor {
    /// UIKit twin of `Color.brand` for UIKit-hosted views.
    static let brand = UIColor { traits in
        traits.userInterfaceStyle == .dark ? UIColor(hex: 0x3DD39A) : UIColor(hex: 0x12805C)
    }

    fileprivate func lighter(by amount: CGFloat) -> UIColor {
        var red: CGFloat = 0
        var green: CGFloat = 0
        var blue: CGFloat = 0
        var alpha: CGFloat = 0
        getRed(&red, green: &green, blue: &blue, alpha: &alpha)
        return UIColor(
            red: red + (1 - red) * amount,
            green: green + (1 - green) * amount,
            blue: blue + (1 - blue) * amount,
            alpha: alpha)
    }

    fileprivate convenience init(hex: UInt, alpha: Double = 1) {
        self.init(
            red: CGFloat((hex >> 16) & 0xFF) / 255,
            green: CGFloat((hex >> 8) & 0xFF) / 255,
            blue: CGFloat(hex & 0xFF) / 255,
            alpha: CGFloat(alpha)
        )
    }
}

extension Person {
    var color: Color { Color(personHex: colorHex) }
}

struct GiftDirectionAppearance {
    let main: Color
    let tint: Color
    let label: LocalizedStringResource?
    let arrow: String

    /// Used when there is no viewpoint person or the viewpoint isn't part of the gift.
    static let neutral = GiftDirectionAppearance(
        main: .given,
        tint: .givenTint,
        label: nil,
        arrow: ""
    )

    static func appearance(for direction: GiftDirection?) -> GiftDirectionAppearance {
        direction?.appearance ?? .neutral
    }
}

extension GiftDirection {
    var appearance: GiftDirectionAppearance {
        switch self {
        case .received:
            GiftDirectionAppearance(
                main: .received,
                tint: .receivedTint,
                label: "Received",
                arrow: "↙"
            )
        case .given:
            GiftDirectionAppearance(
                main: .given,
                tint: .givenTint,
                label: "Given",
                arrow: "↗"
            )
        }
    }
}

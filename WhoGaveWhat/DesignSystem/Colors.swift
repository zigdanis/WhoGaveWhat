import SwiftUI

extension Color {
    // MARK: Brand palette
    static let ink = Color(hex: 0x12161C)
    static let emerald = Color(hex: 0x1FA971)
    static let emeraldDeep = Color(hex: 0x12805C)

    // MARK: Gift flows
    static let recv = emeraldDeep
    static let recvDeep = Color(hex: 0x0E6B4D)
    static let recvTint = Color(hex: 0xE6F2EC)
    static let give = ink
    static let giveDeep = Color.black
    static let giveTint = Color(hex: 0xEEF0F3)
    static let iconWell = Color(hex: 0xEEF0F3)
    static let gold = Color(hex: 0x5B6573)

    // MARK: Surfaces
    static let bg = Color(hex: 0xF2F2F7)
    static let card = Color.white
    static let pageTop = Color(hex: 0xEEF1F4)

    // MARK: Text and controls
    static let muted = Color(hex: 0x8A8F98)
    static let muted2 = Color(hex: 0x6C7280)
    static let muted3 = Color(hex: 0x8A8F98)
    static let muted4 = Color(hex: 0xAEB4BE)
    static let placeholder = Color(hex: 0xAEB4BE)
    static let chevron = Color(hex: 0xC5CAD2)
    static let chipText = Color(hex: 0x5C6573)

    // MARK: Lines and tracks
    static let sep = Color(red: 60 / 255, green: 60 / 255, blue: 67 / 255, opacity: 0.12)
    static let hairline = sep
    static let track = Color(hex: 0xEFEFF1)
    static let border = Color(hex: 0xE1E6EC)

    init(hex: UInt, alpha: Double = 1) {
        self.init(
            .sRGB,
            red: Double((hex >> 16) & 0xFF) / 255,
            green: Double((hex >> 8) & 0xFF) / 255,
            blue: Double(hex & 0xFF) / 255,
            opacity: alpha
        )
    }
}

extension HouseholdMember {
    var color: Color { Color(hex: colorHex) }
}

extension Person {
    var color: Color { Color(hex: colorHex) }
}

struct GiftFlowAppearance {
    let main: Color
    let deep: Color
    let tint: Color
    let label: LocalizedStringResource
    let arrow: String
}

extension GiftFlow {
    var appearance: GiftFlowAppearance {
        switch self {
        case .received:
            GiftFlowAppearance(
                main: .recv,
                deep: .recvDeep,
                tint: .recvTint,
                label: "Received",
                arrow: "↙"
            )
        case .given:
            GiftFlowAppearance(
                main: .give,
                deep: .giveDeep,
                tint: .giveTint,
                label: "Given",
                arrow: "↗"
            )
        }
    }
}

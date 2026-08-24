import SwiftUI

extension Color {
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
                main: KS.recv,
                deep: KS.recvDeep,
                tint: KS.recvTint,
                label: "Received",
                arrow: "↙"
            )
        case .given:
            GiftFlowAppearance(
                main: KS.give,
                deep: KS.giveDeep,
                tint: KS.giveTint,
                label: "Given",
                arrow: "↗"
            )
        }
    }
}

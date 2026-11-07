import SwiftUI

/// Money that can be in several currencies. With one currency it is a single amount, exactly as
/// before gifts had their own currencies. With several it lists one amount per currency, the
/// preferred one first, stacked one per line or joined with " · " on one line. Amounts in different
/// currencies are never added together. Callers style it like a `Text`.
struct AmountsText: View {
    enum Layout {
        case stacked
        case inline
    }

    let amounts: CurrencyAmounts
    let preferred: SupportedCurrency
    var signed = false
    var layout: Layout = .stacked
    var alignment: HorizontalAlignment = .leading

    var body: some View {
        let entries = amounts.displayed(preferred: preferred)
        if layout == .inline || entries.count == 1 {
            Text(verbatim: entries.map { formattedAmount($0, signed: signed) }.joined(separator: " · "))
        } else {
            VStack(alignment: alignment, spacing: 2) {
                ForEach(entries) { entry in
                    Text(verbatim: formattedAmount(entry, signed: signed))
                }
            }
            .accessibilityElement(children: .combine)
        }
    }
}

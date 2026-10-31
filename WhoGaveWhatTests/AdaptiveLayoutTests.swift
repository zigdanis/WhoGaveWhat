import SwiftUI
import Testing

@testable import WhoGaveWhat

struct AdaptiveLayoutTests {
    @Test func compactWindowsKeepTheIPhoneLayout() {
        for isPad in [false, true] {
            let layout = AdaptiveLayout(isRegularWidth: false, isPad: isPad)
            #expect(!layout.usesFormSheets)
            #expect(!layout.placesAddActionInToolbar)
        }
    }

    @Test func onlyARegularIPadWindowMovesAddActionsToTheToolbar() {
        let iPad = AdaptiveLayout(isRegularWidth: true, isPad: true)
        #expect(iPad.usesFormSheets)
        #expect(iPad.placesAddActionInToolbar)

        // iPhone Duo's inner display is regular width but hand-held.
        let duoInner = AdaptiveLayout(isRegularWidth: true, isPad: false)
        #expect(duoInner.usesFormSheets)
        #expect(!duoInner.placesAddActionInToolbar)
    }

    @Test func insightsSplitIntoTwoColumnsOnlyWhenBothFit() {
        #expect(InsightsLayout.columnWidth == 528)
        #expect(InsightsLayout.twoColumnMinWidth == 928)
        // iPad Pro 13" portrait and landscape, iPad mini landscape.
        #expect(InsightsLayout.usesTwoColumns(width: 1032, dynamicTypeSize: .large))
        #expect(InsightsLayout.usesTwoColumns(width: 1144, dynamicTypeSize: .large))
        #expect(InsightsLayout.usesTwoColumns(width: 1133, dynamicTypeSize: .large))
        // iPad Pro 11" portrait, iPad mini portrait, half Split View, iPhones.
        #expect(!InsightsLayout.usesTwoColumns(width: 834, dynamicTypeSize: .large))
        #expect(!InsightsLayout.usesTwoColumns(width: 900, dynamicTypeSize: .large))
        #expect(!InsightsLayout.usesTwoColumns(width: 744, dynamicTypeSize: .large))
        #expect(!InsightsLayout.usesTwoColumns(width: 402, dynamicTypeSize: .large))
    }

    @Test func accessibilityTextSizesKeepInsightsInOneColumn() {
        #expect(!InsightsLayout.usesTwoColumns(width: 1376, dynamicTypeSize: .accessibility1))
    }

    @Test func pickerPopoversFitShortListsAndCapLongOnes() {
        #expect(PickerPopover.listHeight(rows: 2) == 56 + 32 + 2 * 57)
        #expect(PickerPopover.listHeight(rows: 2, addField: true) == 56 + 32 + 76 + 2 * 57)
        #expect(PickerPopover.listHeight(rows: 40, addField: true) == 540)
    }
}

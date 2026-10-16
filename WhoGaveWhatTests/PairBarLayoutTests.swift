import CoreGraphics
import Testing

@testable import WhoGaveWhat

struct PairBarLayoutTests {
    private func widths(_ first: Double, _ second: Double, available: CGFloat = 302) -> (first: CGFloat, second: CGFloat) {
        PairBarLayout.widths(first: first, second: second, available: available, gap: 2, minimum: 4)
    }

    @Test func emptyValuesLeaveTheTrackBare() {
        #expect(widths(0, 0) == (0, 0))
        #expect(widths(-5, 0) == (0, 0))
    }

    @Test func aSingleSegmentTakesTheFullWidth() {
        #expect(widths(10, 0) == (302, 0))
        #expect(widths(0, 10) == (0, 302))
    }

    @Test func equalValuesSplitTheWidthLeftAfterTheGap() {
        #expect(widths(5, 5) == (150, 150))
    }

    @Test func proportionsFollowTheValues() {
        let result = widths(3, 1)
        #expect(result.first == 225)
        #expect(result.second == 75)
    }

    @Test func aTinySegmentKeepsTheMinimumAndTheSumFitsTheWidth() {
        let result = widths(9_999, 1)
        #expect(result.second == 4)
        #expect(result.first + result.second + 2 == 302)
    }

    @Test func swappingTheValuesMirrorsTheWidths() {
        let forward = widths(9_999, 1)
        let backward = widths(1, 9_999)
        #expect(forward.first == backward.second)
        #expect(forward.second == backward.first)
    }

    @Test func segmentsNeverExceedTheAvailableWidth() {
        for (first, second) in [(1.0, 1.0), (0.01, 100.0), (7.0, 3.0), (1.0, 1_000_000.0)] {
            for available in [6.0, 10.0, 302.0] {
                let result = widths(first, second, available: CGFloat(available))
                #expect(result.first + result.second + 2 <= CGFloat(available) + 0.0001)
                #expect(result.first > 0 && result.second > 0)
            }
        }
    }
}

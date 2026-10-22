import Testing

@testable import WhoGaveWhat

struct CompactVerticalSpaceTests {
    @Test func onlyShortWindowsAreCompact() {
        #expect(CompactVerticalSpace.isCompact(safeHeight: 634))  // iPhone Duo's outer display
        #expect(CompactVerticalSpace.isCompact(safeHeight: 647))  // iPhone SE
        #expect(!CompactVerticalSpace.isCompact(safeHeight: 760))  // the shortest regular iPhone
        #expect(!CompactVerticalSpace.isCompact(safeHeight: 0))  // not measured yet
    }
}

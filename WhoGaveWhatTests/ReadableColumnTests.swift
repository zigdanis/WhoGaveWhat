import Testing

@testable import WhoGaveWhat

struct ReadableColumnTests {
    @Test func narrowContainersGetNoMargin() {
        #expect(readableMargin(containerWidth: 402, maxWidth: ReadableWidth.content) == 0)
        #expect(readableMargin(containerWidth: 560, maxWidth: ReadableWidth.content) == 0)
    }

    @Test func wideContainersCenterTheColumn() {
        #expect(readableMargin(containerWidth: 900, maxWidth: ReadableWidth.content) == 170)
    }
}

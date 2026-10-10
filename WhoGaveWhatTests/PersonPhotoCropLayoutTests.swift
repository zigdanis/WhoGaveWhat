import CoreGraphics
import ImageIO
import Testing
import UIKit
import UniformTypeIdentifiers

@testable import WhoGaveWhat

struct PersonPhotoCropLayoutTests {
    @Test func aspectFillCoversTheViewportForPortraitAndLandscapePhotos() {
        let viewport = CGSize(width: 390, height: 844)
        let crop = CGRect(x: 18, y: 227, width: 354, height: 354)
        let landscape = PersonPhotoCropLayout(
            viewportSize: viewport,
            imageSize: CGSize(width: 1_200, height: 800),
            cropRect: crop
        )
        let portrait = PersonPhotoCropLayout(
            viewportSize: viewport,
            imageSize: CGSize(width: 800, height: 1_200),
            cropRect: crop
        )

        #expect(landscape.displaySize.width >= viewport.width)
        #expect(landscape.displaySize.height >= viewport.height)
        #expect(portrait.displaySize.width >= viewport.width)
        #expect(portrait.displaySize.height >= viewport.height)
    }

    @Test func clampedPanKeepsTheCropInsideTheSourceImage() {
        let layout = PersonPhotoCropLayout(
            viewportSize: CGSize(width: 390, height: 844),
            imageSize: CGSize(width: 1_200, height: 800),
            cropRect: CGRect(x: 18, y: 227, width: 354, height: 354)
        )

        let offset = layout.clampedOffset(CGSize(width: 10_000, height: -10_000), zoom: 2)
        let sourceRect = layout.sourceRect(zoom: 2, offset: offset)

        #expect(sourceRect.minX >= -0.000_001)
        #expect(sourceRect.minY >= -0.000_001)
        #expect(sourceRect.maxX <= layout.imageSize.width + 0.000_001)
        #expect(sourceRect.maxY <= layout.imageSize.height + 0.000_001)
        #expect(abs(sourceRect.width - sourceRect.height) < 0.001)
    }

    @Test func minimumZoomLetsTheCircularGuideUseTheWidestPossibleSourceCrop() {
        let layout = PersonPhotoCropLayout(
            viewportSize: CGSize(width: 390, height: 844),
            imageSize: CGSize(width: 800, height: 1_200),
            cropRect: CGRect(x: 18, y: 245, width: 354, height: 354)
        )

        let sourceRect = layout.sourceRect(zoom: layout.minimumZoom, offset: .zero)

        #expect(layout.minimumZoom < 1)
        #expect(sourceRect.minX >= -0.000_001)
        #expect(sourceRect.minY >= -0.000_001)
        #expect(sourceRect.maxX <= layout.imageSize.width + 0.000_001)
        #expect(sourceRect.maxY <= layout.imageSize.height + 0.000_001)
        #expect(abs(sourceRect.width - sourceRect.height) < 0.001)
    }

    @Test func outputRectangleMapsTheCircularGuideToASquareRaster() {
        let crop = CGRect(x: 18, y: 245, width: 354, height: 354)
        let layout = PersonPhotoCropLayout(
            viewportSize: CGSize(width: 390, height: 844),
            imageSize: CGSize(width: 1_200, height: 800),
            cropRect: crop
        )

        let output = layout.outputImageRect(pixelSide: 640, zoom: 1.4, offset: CGSize(width: 34, height: -20))
        let offset = CGSize(width: 34, height: -20)
        let source = layout.sourceRect(zoom: 1.4, offset: offset)
        let imageInOutput = layout.outputImageRect(pixelSide: 640, zoom: 1.4, offset: offset)
        let sourceToOutputX = imageInOutput.width / layout.imageSize.width
        let sourceToOutputY = imageInOutput.height / layout.imageSize.height
        let mappedGuide = CGRect(
            x: imageInOutput.minX + source.minX * sourceToOutputX,
            y: imageInOutput.minY + source.minY * sourceToOutputY,
            width: source.width * sourceToOutputX,
            height: source.height * sourceToOutputY
        )

        #expect(output.width > 640)
        #expect(output.height > 640)
        #expect(abs(mappedGuide.minX) < 0.000_001)
        #expect(abs(mappedGuide.minY) < 0.000_001)
        #expect(abs(mappedGuide.width - 640) < 0.000_001)
        #expect(abs(mappedGuide.height - 640) < 0.000_001)
    }

    @MainActor
    @Test func imageProcessorNormalizesExifOrientationBeforeCropping() throws {
        let format = UIGraphicsImageRendererFormat()
        format.scale = 1
        let source = UIGraphicsImageRenderer(size: CGSize(width: 80, height: 40), format: format).image { context in
            UIColor.red.setFill()
            context.fill(CGRect(x: 0, y: 0, width: 40, height: 40))
            UIColor.blue.setFill()
            context.fill(CGRect(x: 40, y: 0, width: 40, height: 40))
        }
        let data = NSMutableData()
        let destination = try #require(
            CGImageDestinationCreateWithData(data, UTType.jpeg.identifier as CFString, 1, nil)
        )
        CGImageDestinationAddImage(
            destination,
            try #require(source.cgImage),
            [kCGImagePropertyOrientation: 6] as CFDictionary
        )
        #expect(CGImageDestinationFinalize(destination))

        let normalized = try #require(PersonPhotoImageProcessor.normalizedImage(from: data as Data))

        #expect(normalized.imageOrientation == .up)
        #expect(normalized.size.width == 40)
        #expect(normalized.size.height == 80)
    }

    @MainActor
    @Test func confirmedCropIsAnOpaqueSquareJpegAtTheConfiguredSize() throws {
        let format = UIGraphicsImageRendererFormat()
        format.scale = 1
        let image = UIGraphicsImageRenderer(size: CGSize(width: 80, height: 80), format: format).image { context in
            UIColor.systemTeal.setFill()
            context.fill(CGRect(x: 0, y: 0, width: 80, height: 80))
        }
        let layout = PersonPhotoCropLayout(
            viewportSize: CGSize(width: 80, height: 80),
            imageSize: image.size,
            cropRect: CGRect(x: 10, y: 10, width: 60, height: 60)
        )

        let data = try #require(PersonPhotoImageProcessor.jpegData(for: image, layout: layout, zoom: 1, offset: .zero))
        let decoded = try #require(UIImage(data: data))
        let source = try #require(CGImageSourceCreateWithData(data as CFData, nil))

        #expect(decoded.size == CGSize(width: 640, height: 640))
        let decodedType = try #require(CGImageSourceGetType(source) as String?)
        #expect(decodedType == UTType.jpeg.identifier)
        let alphaInfo = try #require(decoded.cgImage?.alphaInfo)
        #expect([CGImageAlphaInfo.none, .noneSkipFirst, .noneSkipLast].contains(alphaInfo))
    }
}

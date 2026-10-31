import ImageIO
import SwiftUI
import UIKit

struct PersonPhotoCropSession: Identifiable {
    let id = UUID()
    let image: UIImage
}

struct PersonPhotoCropLayout {
    let viewportSize: CGSize
    let imageSize: CGSize
    let cropRect: CGRect

    var displaySize: CGSize {
        guard imageSize.width > 0, imageSize.height > 0,
            viewportSize.width > 0, viewportSize.height > 0
        else { return .zero }
        let fillScale = max(viewportSize.width / imageSize.width, viewportSize.height / imageSize.height)
        return CGSize(width: imageSize.width * fillScale, height: imageSize.height * fillScale)
    }

    var minimumZoom: CGFloat {
        guard displaySize.width > 0, displaySize.height > 0 else { return 1 }
        return min(1, max(cropRect.width / displaySize.width, cropRect.height / displaySize.height))
    }

    func imageRect(zoom: CGFloat, offset: CGSize) -> CGRect {
        let size = CGSize(width: displaySize.width * zoom, height: displaySize.height * zoom)
        return CGRect(
            x: (viewportSize.width - size.width) / 2 + offset.width,
            y: (viewportSize.height - size.height) / 2 + offset.height,
            width: size.width,
            height: size.height
        )
    }

    func clampedOffset(_ proposed: CGSize, zoom: CGFloat) -> CGSize {
        let size = CGSize(width: displaySize.width * zoom, height: displaySize.height * zoom)
        let halfWidth = max(0, (size.width - cropRect.width) / 2)
        let halfHeight = max(0, (size.height - cropRect.height) / 2)
        let centerDeltaX = cropRect.midX - viewportSize.width / 2
        let centerDeltaY = cropRect.midY - viewportSize.height / 2
        let minX = centerDeltaX - halfWidth
        let maxX = centerDeltaX + halfWidth
        let minY = centerDeltaY - halfHeight
        let maxY = centerDeltaY + halfHeight
        return CGSize(
            width: min(max(proposed.width, minX), maxX),
            height: min(max(proposed.height, minY), maxY)
        )
    }

    func sourceRect(zoom: CGFloat, offset: CGSize) -> CGRect {
        let displayedRect = imageRect(zoom: zoom, offset: offset)
        let factorX = imageSize.width / displayedRect.width
        let factorY = imageSize.height / displayedRect.height
        return CGRect(
            x: (cropRect.minX - displayedRect.minX) * factorX,
            y: (cropRect.minY - displayedRect.minY) * factorY,
            width: cropRect.width * factorX,
            height: cropRect.height * factorY
        )
    }

    func outputImageRect(pixelSide: CGFloat, zoom: CGFloat, offset: CGSize) -> CGRect {
        let displayedRect = imageRect(zoom: zoom, offset: offset)
        let outputScale = pixelSide / cropRect.width
        return CGRect(
            x: (displayedRect.minX - cropRect.minX) * outputScale,
            y: (displayedRect.minY - cropRect.minY) * outputScale,
            width: displayedRect.width * outputScale,
            height: displayedRect.height * outputScale
        )
    }
}

@MainActor
enum PersonPhotoImageProcessor {
    static func normalizedImage(from data: Data, maxPixelSide: CGFloat = 1_600) -> UIImage? {
        guard let source = CGImageSourceCreateWithData(data as CFData, nil) else { return nil }
        let options: [CFString: Any] = [
            kCGImageSourceCreateThumbnailFromImageAlways: true,
            kCGImageSourceCreateThumbnailWithTransform: true,
            kCGImageSourceThumbnailMaxPixelSize: maxPixelSide
        ]
        guard let image = CGImageSourceCreateThumbnailAtIndex(source, 0, options as CFDictionary) else {
            return nil
        }
        return UIImage(cgImage: image, scale: 1, orientation: .up)
    }

    static func jpegData(
        for image: UIImage,
        layout: PersonPhotoCropLayout,
        zoom: CGFloat,
        offset: CGSize,
        pixelSide: CGFloat = 640
    ) -> Data? {
        guard layout.cropRect.width > 0, layout.cropRect.height > 0 else { return nil }
        let rendererFormat = UIGraphicsImageRendererFormat()
        rendererFormat.scale = 1
        rendererFormat.opaque = true
        let renderer = UIGraphicsImageRenderer(size: CGSize(width: pixelSide, height: pixelSide), format: rendererFormat)
        return renderer.jpegData(withCompressionQuality: 0.82) { context in
            UIColor.white.setFill()
            context.fill(CGRect(x: 0, y: 0, width: pixelSide, height: pixelSide))
            image.draw(in: layout.outputImageRect(pixelSide: pixelSide, zoom: zoom, offset: offset))
        }
    }
}

struct PersonPhotoCropView: View {
    let image: UIImage
    let onCancel: () -> Void
    let onConfirm: (Data) -> Void

    @State private var viewportSize = CGSize.zero
    @State private var cropRect = CGRect.zero
    @State private var zoom: CGFloat = 1
    @State private var lastZoom: CGFloat = 1
    @State private var offset = CGSize.zero
    @State private var lastOffset = CGSize.zero

    private let maximumZoom: CGFloat = 6
    static let maximumCropSide: CGFloat = 520

    var body: some View {
        // The outer reader stays inside the safe area; the inner one is full-bleed and lays out
        // the photo and controls. The difference between their frames is the safe region,
        // including iPhone Duo's vertical status strip, without reading window insets.
        GeometryReader { safeProxy in
            let safeFrame = safeProxy.frame(in: .global)
            ZStack {
                GeometryReader { proxy in
                    let size = proxy.size
                    let fullFrame = proxy.frame(in: .global)
                    let safeRect = safeFrame.offsetBy(dx: -fullFrame.minX, dy: -fullFrame.minY)
                    let frame = cropFrame(in: safeRect)
                    let layout = PersonPhotoCropLayout(viewportSize: size, imageSize: image.size, cropRect: frame)

                    ZStack {
                        Color.black
                        Image(uiImage: image)
                            .resizable()
                            .frame(width: layout.displaySize.width, height: layout.displaySize.height)
                            .scaleEffect(zoom)
                            .offset(offset)
                            .frame(width: size.width, height: size.height)
                            .clipped()
                            .contentShape(Rectangle())
                            .simultaneousGesture(dragGesture(layout: layout))
                            .simultaneousGesture(magnificationGesture(layout: layout))
                            .accessibilityIdentifier("person-photo-crop.image")
                        cropGuide(frame: frame, size: size)
                            .allowsHitTesting(false)
                        cropControls(size: size, safeRect: safeRect, circle: frame)
                    }
                    .onAppear {
                        viewportSize = size
                        cropRect = frame
                    }
                    .onChange(of: size) { _, newSize in
                        updateViewport(size: newSize, safeRect: safeRect)
                    }
                    .onChange(of: safeRect) { _, newSafeRect in
                        updateViewport(size: size, safeRect: newSafeRect)
                    }
                }
                .ignoresSafeArea()
            }
        }
        .background(Color.black.ignoresSafeArea())
        .preferredColorScheme(.dark)
        .statusBarHidden()
    }

    private func updateViewport(size: CGSize, safeRect: CGRect) {
        viewportSize = size
        cropRect = cropFrame(in: safeRect)
        let layout = PersonPhotoCropLayout(viewportSize: size, imageSize: image.size, cropRect: cropRect)
        // Unfolding or rotating can enlarge the circle past the zoomed-out photo, so the zoom
        // is clamped to the new minimum before the offset.
        zoom = min(maximumZoom, max(layout.minimumZoom, zoom))
        lastZoom = zoom
        offset = layout.clampedOffset(offset, zoom: zoom)
        lastOffset = offset
    }

    /// The largest crop circle, with a margin, centered in the safe region. An iPad caps it, so the photo
    /// isn't upscaled past its pixels and the buttons stay near the circle.
    private func cropFrame(in safeRect: CGRect) -> CGRect {
        guard safeRect.width > 0, safeRect.height > 0 else { return .zero }
        let side = max(0, min(safeRect.width - 36, safeRect.height - 48, Self.maximumCropSide))
        return CGRect(x: safeRect.midX - side / 2, y: safeRect.midY - side / 2, width: side, height: side)
    }

    private var layout: PersonPhotoCropLayout {
        PersonPhotoCropLayout(viewportSize: viewportSize, imageSize: image.size, cropRect: cropRect)
    }

    private func cropGuide(frame: CGRect, size: CGSize) -> some View {
        ZStack {
            Path { path in
                path.addRect(CGRect(origin: .zero, size: size))
                path.addEllipse(in: frame)
            }
            .fill(Color.black.opacity(0.54), style: FillStyle(eoFill: true))
            Circle()
                .stroke(Color.white.opacity(0.92), lineWidth: 1)
                .frame(width: frame.width, height: frame.height)
                .position(x: frame.midX, y: frame.midY)
        }
    }

    /// Cancel and confirm sit in the bottom corners above the Home indicator, like the system's
    /// photo crop. A regular iPhone can report zero safe-area insets while the status bar is
    /// hidden, so the bottom gap never drops below the Home indicator's height.
    private func cropControls(size: CGSize, safeRect: CGRect, circle: CGRect) -> some View {
        let bottomGap = max(size.height - safeRect.maxY, 34) + 12
        return HStack {
            cropButton(symbol: "xmark", label: "Cancel", identifier: "crop.cancel", prominent: false) {
                onCancel()
            }
            Spacer()
            cropButton(symbol: "checkmark", label: "Use photo", identifier: "crop.use", prominent: true) {
                guard
                    let data = PersonPhotoImageProcessor.jpegData(
                        for: image,
                        layout: layout,
                        zoom: zoom,
                        offset: offset
                    )
                else { return }
                onConfirm(data)
            }
        }
        .padding(.horizontal, 24)
        // Under the circle's corners on a wide screen, the screen's corners on a phone.
        .frame(width: min(safeRect.width, circle.width + 2 * 24 + 2 * 48))
        .position(x: safeRect.midX, y: size.height - bottomGap - 24)
    }

    private func cropButton(
        symbol: String,
        label: LocalizedStringResource,
        identifier: String,
        prominent: Bool,
        action: @escaping () -> Void
    ) -> some View {
        Button(action: action) {
            Image(systemName: symbol)
                .font(.system(size: 20, weight: .semibold))
                .foregroundStyle(Color.white)
                .frame(width: 48, height: 48)
                .background(prominent ? Color.brandFill : Color.white.opacity(0.12), in: Circle())
                .overlay(Circle().stroke(Color.white.opacity(prominent ? 0.45 : 0.2), lineWidth: 1))
        }
        .accessibilityLabel(Text(label))
        .accessibilityIdentifier(identifier)
    }

    private func dragGesture(layout: PersonPhotoCropLayout) -> some Gesture {
        DragGesture()
            .onChanged { value in
                offset = layout.clampedOffset(
                    CGSize(
                        width: lastOffset.width + value.translation.width,
                        height: lastOffset.height + value.translation.height
                    ),
                    zoom: zoom
                )
            }
            .onEnded { _ in lastOffset = offset }
    }

    private func magnificationGesture(layout: PersonPhotoCropLayout) -> some Gesture {
        MagnifyGesture()
            .onChanged { value in
                zoom = min(maximumZoom, max(layout.minimumZoom, lastZoom * value.magnification))
                offset = layout.clampedOffset(offset, zoom: zoom)
            }
            .onEnded { _ in
                lastZoom = zoom
                lastOffset = offset
            }
    }
}

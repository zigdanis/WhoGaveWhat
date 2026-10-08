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

    var body: some View {
        GeometryReader { proxy in
            let size = proxy.size
            let frame = cropFrame(in: size)
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
                cropHeader(topInset: Self.windowSafeInsets.top)
            }
            .onAppear {
                viewportSize = size
                cropRect = frame
            }
            .onChange(of: size) { _, newSize in
                viewportSize = newSize
                cropRect = cropFrame(in: newSize)
                offset = PersonPhotoCropLayout(
                    viewportSize: newSize,
                    imageSize: image.size,
                    cropRect: cropRect
                ).clampedOffset(offset, zoom: zoom)
                lastOffset = offset
            }
        }
        .ignoresSafeArea()
        .background(Color.black.ignoresSafeArea())
        .preferredColorScheme(.dark)
        .statusBarHidden()
    }

    private func cropFrame(in size: CGSize) -> CGRect {
        guard size.width > 0, size.height > 0 else { return .zero }
        let insets = Self.windowSafeInsets
        let side = min(size.width - 36, size.height - insets.top - insets.bottom - 48)
        let centerY = (size.height + insets.top - insets.bottom) / 2
        return CGRect(x: (size.width - side) / 2, y: centerY - side / 2, width: side, height: side)
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

    private func cropHeader(topInset: CGFloat) -> some View {
        VStack {
            HStack {
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
            .padding(.horizontal, 20)
            .padding(.top, topInset + 8)
            Spacer()
        }
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
                .font(.title3.weight(.semibold))
                .foregroundStyle(Color.white)
                .frame(width: 48, height: 48)
                .background(prominent ? Color.accentColor : Color.white.opacity(0.12), in: Circle())
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

    private static var windowSafeInsets: EdgeInsets {
        let windows = UIApplication.shared.connectedScenes
            .compactMap { $0 as? UIWindowScene }
            .flatMap(\.windows)
        let window = windows.first(where: \.isKeyWindow) ?? windows.first
        let inset = window?.safeAreaInsets ?? .zero
        return EdgeInsets(top: inset.top, leading: inset.left, bottom: inset.bottom, trailing: inset.right)
    }
}

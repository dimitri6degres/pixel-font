import SwiftUI
import AppKit
import CoreImage
import CoreImage.CIFilterBuiltins

private func pixelSize(of image: NSImage) -> CGSize {
    if let rep = image.representations.first {
        let w = CGFloat(rep.pixelsWide)
        let h = CGFloat(rep.pixelsHigh)
        if w > 0 && h > 0 { return CGSize(width: w, height: h) }
    }
    return image.size
}

struct ImageImportEditor: View {
    let platformImage: NSImage
    let glyphWidth: Int
    let glyphHeight: Int
    let baseline: Int
    let initialThreshold: Double
    let initialMargin: Double
    let onApply: (_ image: NSImage, _ frameInCanvas: CGRect, _ scale: CGFloat, _ threshold: Double, _ margin: Double) -> Void
    let onCancel: () -> Void

    @State private var translation: CGSize = .zero
    @State private var scale: CGFloat = 1.0
    @State private var threshold: Double
    @State private var margin: Double

    @State private var lastCanvasScale: CGFloat = 1.0
    @State private var lastCanvasLogicalSize: CGSize = .zero

    init(platformImage: NSImage,
         glyphWidth: Int,
         glyphHeight: Int,
         baseline: Int,
         initialThreshold: Double,
         initialMargin: Double,
         onApply: @escaping (_ image: NSImage, _ frameInCanvas: CGRect, _ scale: CGFloat, _ threshold: Double, _ margin: Double) -> Void,
         onCancel: @escaping () -> Void) {
        self.platformImage = platformImage
        self.glyphWidth = glyphWidth
        self.glyphHeight = glyphHeight
        self.baseline = baseline
        self.initialThreshold = initialThreshold
        self.initialMargin = initialMargin
        self.onApply = onApply
        self.onCancel = onCancel
        _threshold = State(initialValue: initialThreshold)
        _margin = State(initialValue: initialMargin)
    }

    var body: some View {
        VStack(spacing: 12) {
            Text("Position and scale the image")
                .font(.headline)

            GeometryReader { geo in
                ZStack {
                    // Background for canvas
                    RoundedRectangle(cornerRadius: 8)
                        .fill(Color.secondary.opacity(0.08))

                    CanvasLayer(platformImage: platformImage,
                                glyphWidth: glyphWidth,
                                glyphHeight: glyphHeight,
                                baseline: baseline,
                                geoSize: geo.size,
                                translation: $translation,
                                scale: $scale,
                                threshold: threshold) { scaleVal, logicalSize in
                        lastCanvasScale = scaleVal
                        lastCanvasLogicalSize = logicalSize
                    }
                }
                .frame(maxWidth: .infinity, maxHeight: .infinity)
                .padding(8)
            }
            .frame(minHeight: 360)

            // Controls
            VStack(spacing: 8) {
                HStack {
                    Text("Threshold")
                    Slider(value: $threshold, in: 0...1)
                    Text(String(format: "%.2f", threshold)).monospacedDigit()
                }
                HStack {
                    Text("Margin")
                    Slider(value: $margin, in: 0...0.45)
                    Text(String(format: "%.2f", margin)).monospacedDigit()
                }
            }

            HStack {
                Button("Cancel") { onCancel() }
                Spacer()
                Button("Apply") {
                    // Use lastCanvasScale for consistent scaling
                    let canvasScale = lastCanvasScale
                    let imageSize = pixelSize(of: platformImage)
                    let scaledSize = CGSize(width: imageSize.width * scale, height: imageSize.height * scale)
                    // translation is origin in canvasView coords (scaled)
                    let rectInView = CGRect(origin: CGPoint(x: translation.width, y: translation.height), size: scaledSize)
                    let frameInCanvas = CGRect(x: rectInView.origin.x / canvasScale,
                                               y: rectInView.origin.y / canvasScale,
                                               width: rectInView.width / canvasScale,
                                               height: rectInView.height / canvasScale)
                    onApply(platformImage, frameInCanvas, scale, threshold, margin)
                }
                .keyboardShortcut(.defaultAction)
            }
        }
        .padding()
    }

    private func initializeTransformToFit(canvasLogicalSize: CGSize) {
        // Fit image into glyph canvas initially
        let img = pixelSize(of: platformImage)
        let canvas = canvasLogicalSize
        guard img.width > 0 && img.height > 0 else { return }
        let sx = canvas.width / img.width
        let sy = canvas.height / img.height
        let fit = min(sx, sy)
        scale = fit
        // Center at 0.5*canvas minus half scaled image
        let scaled = CGSize(width: img.width * fit, height: img.height * fit)
        let origin = CGPoint(x: (canvas.width - scaled.width)/2, y: (canvas.height - scaled.height)/2)
        translation = CGSize(width: origin.x, height: origin.y)
    }

    private func computeCanvasScale(available: CGSize, logical: CGSize) -> CGFloat {
        let padding: CGFloat = 40
        let maxW = max(1, available.width - padding)
        let maxH = max(1, available.height - padding)
        let sx = maxW / max(1, logical.width)
        let sy = maxH / max(1, logical.height)
        return min(sx, sy)
    }
}

private func computeCanvasScale(available: CGSize, logical: CGSize) -> CGFloat {
    let padding: CGFloat = 40
    let maxW = max(1, available.width - padding)
    let maxH = max(1, available.height - padding)
    let sx = maxW / max(1, logical.width)
    let sy = maxH / max(1, logical.height)
    return min(sx, sy)
}

private struct CanvasLayer: View {
    let platformImage: NSImage
    let glyphWidth: Int
    let glyphHeight: Int
    let baseline: Int
    let geoSize: CGSize
    @Binding var translation: CGSize
    @Binding var scale: CGFloat
    let threshold: Double
    var onComputed: (CGFloat, CGSize) -> Void

    var body: some View {
        let canvasLogicalSize = CGSize(width: glyphWidth, height: glyphHeight)
        let canvasScale = computeCanvasScale(available: geoSize, logical: canvasLogicalSize)
        let canvasViewSize = CGSize(width: canvasLogicalSize.width * canvasScale,
                                    height: canvasLogicalSize.height * canvasScale)
        return ZStack {
            // Draw baseline
            VStack { Spacer(minLength: 0) }
                .frame(width: canvasViewSize.width, height: canvasViewSize.height)
                .overlay(alignment: .topLeading) {
                    Path { p in
                        let y = CGFloat(baseline) * canvasScale + canvasScale / 2
                        p.addRect(CGRect(x: 0, y: y, width: canvasViewSize.width, height: 1))
                    }
                    .stroke(Color.red.opacity(0.7), lineWidth: 1)
                }

            // Grid outline
            RoundedRectangle(cornerRadius: 2)
                .stroke(Color.secondary.opacity(0.3), lineWidth: 1)
                .frame(width: canvasViewSize.width, height: canvasViewSize.height)

            // Image layer with transform
            TransformableImage(platformImage: platformImage,
                               canvasScale: canvasScale,
                               canvasViewSize: canvasViewSize,
                               translation: $translation,
                               scale: $scale,
                               threshold: threshold)
        }
        .onAppear { onComputed(canvasScale, canvasLogicalSize) }
        .onChange(of: geoSize) { newSize in
            let newScale = computeCanvasScale(available: newSize, logical: canvasLogicalSize)
            onComputed(newScale, canvasLogicalSize)
        }
    }
}

private struct TransformableImage: View {
    let platformImage: NSImage
    let canvasScale: CGFloat
    let canvasViewSize: CGSize
    @Binding var translation: CGSize // in view points (canvas space scaled)
    @Binding var scale: CGFloat
    let threshold: Double

    @State private var dragStartTranslation: CGSize = .zero
    @State private var dragStartLocation: CGPoint = .zero
    @State private var currentMagnification: CGFloat = 1.0

    var body: some View {
        let imageSize = pixelSize(of: platformImage)
        let scaledSize = CGSize(width: imageSize.width * scale, height: imageSize.height * scale)
        let origin = CGPoint(x: translation.width, y: translation.height)

        return ZStack(alignment: .topLeading) {
            // Image content - thresholded preview
            Image(nsImage: thresholdedNSImage)
                .resizable()
                .interpolation(.none)
                .frame(width: scaledSize.width, height: scaledSize.height)
                .position(x: origin.x + scaledSize.width / 2, y: origin.y + scaledSize.height / 2)
                .gesture(dragGesture())
                .gesture(magnifyGesture().simultaneously(with: dragGesture()))

            // Bounding box
            Rectangle()
                .stroke(Color.accentColor, style: StrokeStyle(lineWidth: 1, dash: [4, 3]))
                .frame(width: scaledSize.width, height: scaledSize.height)
                .position(x: origin.x + scaledSize.width / 2, y: origin.y + scaledSize.height / 2)

            // Handles
            handles(origin: origin, size: scaledSize)
        }
        .frame(width: canvasViewSize.width, height: canvasViewSize.height, alignment: .topLeading)
        .clipped()
    }

    private func dragGesture() -> some Gesture {
        DragGesture()
            .onChanged { v in
                if v.startLocation == .zero { return }
                if dragStartLocation == .zero {
                    dragStartLocation = v.startLocation
                    dragStartTranslation = translation
                }
                translation = CGSize(width: dragStartTranslation.width + (v.location.x - dragStartLocation.x),
                                     height: dragStartTranslation.height + (v.location.y - dragStartLocation.y))
            }
            .onEnded { _ in
                dragStartLocation = .zero
            }
    }

    private func magnifyGesture() -> some Gesture {
        MagnificationGesture()
            .onChanged { value in
                let delta = value / currentMagnification
                currentMagnification = value
                let newScale = min(10.0, max(0.05, scale * delta))
                scale = newScale
            }
            .onEnded { _ in currentMagnification = 1.0 }
    }

    @ViewBuilder
    private func handles(origin: CGPoint, size: CGSize) -> some View {
        let half = CGSize(width: size.width / 2, height: size.height / 2)
        let points: [(CGPoint, HandleKind)] = [
            (CGPoint(x: origin.x, y: origin.y), .topLeft),
            (CGPoint(x: origin.x + half.width, y: origin.y), .top),
            (CGPoint(x: origin.x + size.width, y: origin.y), .topRight),
            (CGPoint(x: origin.x, y: origin.y + half.height), .left),
            (CGPoint(x: origin.x + size.width, y: origin.y + half.height), .right),
            (CGPoint(x: origin.x, y: origin.y + size.height), .bottomLeft),
            (CGPoint(x: origin.x + half.width, y: origin.y + size.height), .bottom),
            (CGPoint(x: origin.x + size.width, y: origin.y + size.height), .bottomRight)
        ]
        ForEach(Array(points.enumerated()), id: \.offset) { _, item in
            let (pt, kind) = item
            ResizableHandle(position: pt) { delta in
                resize(kind: kind, delta: delta)
            }
        }
    }

    private enum HandleKind {
        case topLeft, top, topRight, left, right, bottomLeft, bottom, bottomRight
    }

    private func resize(kind: HandleKind, delta: CGSize) {
        // Uniform scale for corners, axis scale for edges relative to top-left origin
        let minScale: CGFloat = 0.05
        let maxScale: CGFloat = 20.0
        let img = pixelSize(of: platformImage)

        let dx = delta.width / 2
        let dy = delta.height / 2

        var newScale = scale
        switch kind {
        case .topLeft:
            // uniform scale based on average dx+dy
            newScale = scale * (1 - (dx + dy) / max(img.width + img.height, 1))
            translation = CGSize(width: translation.width + dx, height: translation.height + dy)
        case .topRight:
            newScale = scale * (1 + (dx - dy) / max(img.width + img.height, 1))
            translation = CGSize(width: translation.width, height: translation.height + dy)
        case .bottomLeft:
            newScale = scale * (1 + (-dx + dy) / max(img.width + img.height, 1))
            translation = CGSize(width: translation.width + dx, height: translation.height)
        case .bottomRight:
            newScale = scale * (1 + (dx + dy) / max(img.width + img.height, 1))
        case .top:
            newScale = scale * (1 - dy / max(img.height, 1))
            translation = CGSize(width: translation.width, height: translation.height + dy)
        case .bottom:
            newScale = scale * (1 + dy / max(img.height, 1))
        case .left:
            newScale = scale * (1 - dx / max(img.width, 1))
            translation = CGSize(width: translation.width + dx, height: translation.height)
        case .right:
            newScale = scale * (1 + dx / max(img.width, 1))
        }
        scale = min(max(newScale, minScale), maxScale)
    }

    private var thresholdedNSImage: NSImage {
        guard let tiffData = platformImage.tiffRepresentation else { return platformImage }
        let ciContext = CIContext(options: nil)
        guard let ciImage = CIImage(data: tiffData) else { return platformImage }

        let monoFilter = CIFilter.colorControls()
        monoFilter.inputImage = ciImage
        monoFilter.saturation = 0

        let exposureFilter = CIFilter.exposureAdjust()
        exposureFilter.inputImage = monoFilter.outputImage
        exposureFilter.ev = 0

        let intermediate = exposureFilter.outputImage ?? ciImage

        // Approximate threshold by adjusting gamma/power inversely related to threshold
        let gammaFilter = CIFilter.gammaAdjust()
        gammaFilter.inputImage = intermediate
        gammaFilter.power = Float(max(0.1, min(5.0, 5 * (1 - threshold))))

        let finalImage = gammaFilter.outputImage ?? intermediate

        if let cgimg = ciContext.createCGImage(finalImage, from: finalImage.extent) {
            return NSImage(cgImage: cgimg, size: .zero)
        }
        return platformImage
    }
}

private struct ResizableHandle: View {
    let position: CGPoint
    var onDrag: (CGSize) -> Void
    @State private var start: CGPoint = .zero

    var body: some View {
        Rectangle()
            .fill(Color.accentColor)
            .frame(width: 10, height: 10)
            .position(position)
            .gesture(
                DragGesture()
                    .onChanged { v in onDrag(v.translation) }
            )
    }
}


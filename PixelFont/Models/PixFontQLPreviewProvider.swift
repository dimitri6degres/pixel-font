import AppKit
import QuickLookThumbnailing
import Foundation

fileprivate struct Glyph: Codable {
    let character: Character?
    let pixels: [Bool]
}

fileprivate struct FontDocument: Codable {
    let glyphWidth: Int
    let glyphHeight: Int
    let baseline: Int
    let glyphs: [Glyph]
}

public struct PixFontQLPreviewProvider: QLPreviewProvider {
    public init() {}

    public func providePreview(for request: QLFilePreviewRequest) async throws -> QLPreviewReply {
        guard let url = request.fileURL else {
            return makeInvalidPreview()
        }
        let data = try Data(contentsOf: url)
        let decoder = JSONDecoder()
        let document: FontDocument
        do {
            document = try decoder.decode(FontDocument.self, from: data)
        } catch {
            return makeInvalidPreview()
        }

        // Select glyphs per instructions
        let glyphsToRender = selectGlyphs(from: document.glyphs)

        let renderTwoGlyphs: Bool
        if document.glyphHeight > document.glyphWidth {
            renderTwoGlyphs = true
        } else {
            renderTwoGlyphs = false
        }

        let image = renderGlyphsImage(document: document, glyphs: glyphsToRender, renderTwo: renderTwoGlyphs)

        guard let tiff = image.tiffRepresentation,
              let bitmap = NSBitmapImageRep(data: tiff),
              let pngData = bitmap.representation(using: .png, properties: [:]) else {
            return makeInvalidPreview()
        }

        let reply = QLPreviewReply(dataOfContentType: .png)
        reply.setData(pngData)
        return reply
    }
}

// MARK: - Helpers

fileprivate func makeInvalidPreview() -> QLPreviewReply {
    let size = NSSize(width: 512, height: 512)
    let image = NSImage(size: size)
    image.lockFocus()
    NSColor.white.setFill()
    NSBezierPath(rect: NSRect(origin: .zero, size: size)).fill()

    let paragraphStyle = NSMutableParagraphStyle()
    paragraphStyle.alignment = .center
    let attrs: [NSAttributedString.Key: Any] = [
        .foregroundColor: NSColor.black,
        .font: NSFont.systemFont(ofSize: 48, weight: .bold),
        .paragraphStyle: paragraphStyle
    ]
    let string = "Invalid .pixf"
    let rect = NSRect(x: 0, y: (size.height - 48) / 2, width: size.width, height: 48)
    string.draw(in: rect, withAttributes: attrs)
    image.unlockFocus()

    guard let tiff = image.tiffRepresentation,
          let bitmap = NSBitmapImageRep(data: tiff),
          let pngData = bitmap.representation(using: .png, properties: [:]) else {
        // If that fails, return empty reply
        return QLPreviewReply(dataOfContentType: .png)
    }

    let reply = QLPreviewReply(dataOfContentType: .png)
    reply.setData(pngData)
    return reply
}

fileprivate func selectGlyphs(from glyphs: [Glyph]) -> [Glyph] {
    // Try to find 'a'
    if let aGlyph = glyphs.first(where: { $0.character == "a" }) {
        return [aGlyph]
    }
    // Then try '2'
    if let twoGlyph = glyphs.first(where: { $0.character == "2" }) {
        return [twoGlyph]
    }
    // Else pick first one or two glyphs with a non-nil character
    let filtered = glyphs.compactMap { $0.character != nil ? $0 : nil }
    if filtered.isEmpty {
        // No glyphs with characters, fallback to first glyph if any
        if let first = glyphs.first {
            return [first]
        }
        return []
    }
    // If can render two, pick first two; else first one
    return Array(filtered.prefix(2))
}

fileprivate func renderGlyphsImage(document: FontDocument, glyphs: [Glyph], renderTwo: Bool) -> NSImage {
    // Constants
    let targetSize = NSSize(width: 512, height: 512)
    let spacingPixels = 8

    let glyphWidth = document.glyphWidth
    let glyphHeight = document.glyphHeight
    let baseline = document.baseline

    // Determine how many glyphs to render
    let glyphCount = renderTwo ? min(2, glyphs.count) : 1
    guard glyphCount > 0 else {
        return NSImage(size: targetSize) // empty image
    }

    // Calculate image pixel dimensions needed
    let totalWidth = (glyphWidth * glyphCount) + (renderTwo ? spacingPixels : 0)
    let totalHeight = glyphHeight

    // Calculate scale factor to fit into targetSize preserving aspect ratio
    let scaleX = Double(targetSize.width) / Double(totalWidth)
    let scaleY = Double(targetSize.height) / Double(totalHeight)
    let scale = min(scaleX, scaleY)

    let imageWidthPx = Int(round(Double(totalWidth) * scale))
    let imageHeightPx = Int(round(Double(totalHeight) * scale))

    let imageSize = NSSize(width: imageWidthPx, height: imageHeightPx)

    let image = NSImage(size: imageSize)
    image.lockFocus()

    NSColor.white.setFill()
    NSBezierPath(rect: NSRect(origin: .zero, size: imageSize)).fill()

    // Draw pixels in black for 'on' bits, scaled
    NSColor.black.setFill()

    func drawPixel(x: Int, y: Int, scale: Double) {
        // Invert y to draw from bottom-left origin
        let px = Double(x) * scale
        let py = Double(imageHeightPx) - (Double(y + 1) * scale)
        let rect = NSRect(x: px, y: py, width: scale, height: scale)
        NSBezierPath(rect: rect).fill()
    }

    for glyphIndex in 0..<glyphCount {
        let glyph = glyphs[glyphIndex]
        for y in 0..<glyphHeight {
            for x in 0..<glyphWidth {
                let bitIndex = y * glyphWidth + x
                if bitIndex < glyph.pixels.count, glyph.pixels[bitIndex] {
                    let px = x + (glyphIndex * (glyphWidth + (renderTwo ? spacingPixels : 0)))
                    drawPixel(x: px, y: y, scale: scale)
                }
            }
        }
    }

    // Draw baseline if it fits
    if baseline >= 0 && baseline < glyphHeight {
        let baselineY = Double(imageHeightPx) - (Double(baseline + 1) * scale)
        let path = NSBezierPath()
        path.move(to: NSPoint(x: 0, y: baselineY))
        path.line(to: NSPoint(x: Double(imageWidthPx), y: baselineY))
        NSColor(calibratedWhite: 0.5, alpha: 0.5).setStroke()
        path.lineWidth = max(1.0, scale / 4.0)
        path.stroke()
    }

    image.unlockFocus()
    return image
}

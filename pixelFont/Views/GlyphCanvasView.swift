import SwiftUI
import AppKit

struct GlyphCanvasView: View {
    let glyph: Glyph?
    var baseWidth: Int = 0
    var baseHeight: Int = 0
    var baseline: Int? = nil
    var pixelSize: CGFloat = 22
    var preview : Bool = false
    var alignLeft: Bool = false
    var onSet: (_ row: Int, _ column: Int, _ newValue: Bool) -> Void
    var beginStroke: () -> Void
    var endStroke: () -> Void

    @State private var isDragging: Bool = false
    @State private var eraseMode: Bool = false
    @State private var didBeginStroke: Bool = false
    @State private var lastRowCol: (Int, Int)? = nil

    var body: some View {
        GeometryReader { proxy in
            let availableSize = proxy.size
            let effectiveWidth = max(0, (baseWidth) + (glyph?.advanceWidthOffset ?? 0))
            let width = effectiveWidth
            let rawHeight = glyph?.height ?? 0
            let height = max(0, min(rawHeight, baseHeight > 0 ? baseHeight : rawHeight))
            let spacing: CGFloat = preview ? 0 : 1
            let cell = pixelSize
            let totalWidth = CGFloat(width) * (cell + spacing) - spacing
            let totalHeight = CGFloat(height) * (cell + spacing) - spacing
            let originX = alignLeft ? 0 : (availableSize.width - totalWidth) * 0.5
            let originY = (availableSize.height - totalHeight) * 0.5
            let origin = CGPoint(x: originX, y: originY)

            Canvas { context, _ in
                guard width > 0, height > 0 else { return }

                if let g = glyph {
                    var rect = CGRect(x: 0, y: 0, width: cell, height: cell)
                    for row in 0..<height {
                        for col in 0..<width {
                            rect.origin.x = origin.x + CGFloat(col) * (cell + spacing)
                            rect.origin.y = origin.y + CGFloat(row) * (cell + spacing)

                            let isOn: Bool = (col < g.width) ? g.pixels[row][col] : false
                            let onColor: Color = preview ? .black : .primary
                            let offColor: Color = Color(white: 0.90)
                            if isOn {
                                context.fill(Path(rect), with: .color(onColor))
                            } else {
                                context.fill(Path(rect), with: .color(offColor))
                            }
                        }
                    }
                }

                if let g = glyph, let baseline = baseline {
                    let effectiveWidth = width
                    if baseline >= 0 && baseline < height {
                        let y = origin.y + CGFloat(baseline) * (cell + spacing) + cell - 0.5
                        let x0 = origin.x
                        let x1 = origin.x + CGFloat(effectiveWidth) * (cell + spacing) - spacing
                        let path = Path(CGRect(x: x0, y: y, width: x1 - x0, height: 1))
                        context.fill(path, with: .color(.red.opacity(0.8)))
                    }
                }

                if preview {
                    let borderRect = CGRect(x: origin.x, y: origin.y, width: totalWidth, height: totalHeight)
                    context.stroke(Path(roundedRect: borderRect, cornerRadius: 0), with: .color(Color.primary.opacity(0.12)), lineWidth: 0.8)
                }
            }
            .transaction { t in t.animation = nil }

            .gesture(
                DragGesture(minimumDistance: 0)
                    .onChanged { value in
                        let isCmd = NSEvent.modifierFlags.contains(.command)
                        eraseMode = isCmd
                        let newValue = !eraseMode
                        if !didBeginStroke {
                            didBeginStroke = true
                            beginStroke()
                        }
                        let loc = value.location
                        let x = max(0, loc.x - origin.x)
                        let y = max(0, loc.y - origin.y)
                        let column = Int((x + spacing) / (cell + spacing))
                        let row = Int((y + spacing) / (cell + spacing))
                        let current = (row, column)
                        if lastRowCol.map({ $0 != current }) ?? true {
                            setPixel(row: row, column: column, to: newValue)
                            lastRowCol = current
                        }
                        isDragging = true
                    }
                    .onEnded { _ in
                        if didBeginStroke {
                            endStroke()
                            didBeginStroke = false
                        }
                        lastRowCol = nil
                        isDragging = false
                    }
            )
        }
    }

    private func setPixel(row: Int, column: Int, to newValue: Bool) {
        guard let g = glyph, row >= 0, column >= 0 else { return }
        let visibleH = (baseHeight > 0 ? baseHeight : g.height)
        guard row < visibleH else { return }
        let current: Bool = (column < g.width) ? g.pixels[row][column] : false
        if current != newValue {
            onSet(row, column, newValue)
        }
    }
}

private struct PixelView: View {
    let isOn: Bool
    let size: CGFloat

    var body: some View {
        Rectangle()
            .fill(isOn ? Color.primary : Color(white: 0.92))
            .frame(width: size, height: size)
            .overlay(
                Group {
                    if size >= 5 {
                        Rectangle()
                            .stroke(Color.primary.opacity(0.12), lineWidth: 0.8)
                    }
                }
            )
    }
}

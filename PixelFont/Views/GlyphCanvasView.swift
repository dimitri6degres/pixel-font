import SwiftUI
import AppKit

struct GlyphCanvasView: View {
    let glyph: Glyph?
    var baseWidth: Int = 0
    var baseHeight: Int = 0
    var baseline: Int? = nil
    var pixelSize: CGFloat = 22
    var brushSize: Int = 1
    var preview : Bool = false
    var alignLeft: Bool = false
    var onSet: (_ row: Int, _ column: Int, _ newValue: Bool) -> Void
    var beginStroke: () -> Void
    var endStroke: () -> Void

    @State private var isDragging: Bool = false
    @State private var eraseMode: Bool = false
    @State private var didBeginStroke: Bool = false
    @State private var lastRowCol: (Int, Int)? = nil
    @State private var hoverLocation: CGPoint? = nil
    @State private var hoverRowCol: (Int, Int)? = nil

    var body: some View {
        GeometryReader { proxy in
            let availableSize = proxy.size

            let fullW = glyph?.width ?? 0
            let fullH = glyph?.height ?? 0
            let visibleW = max(0, (baseWidth) + (glyph?.advanceWidthOffset ?? 0))
            let visibleH = max(0, min(fullH, baseHeight > 0 ? baseHeight : fullH))
            let startCol = glyph?.viewOffsetX ?? 0
            let startRow = glyph?.viewOffsetY ?? 0

            let canvasW = max(fullW, startCol + visibleW)
            let canvasH = max(fullH, startRow + visibleH)

            let spacing: CGFloat = preview ? 0 : 1
            let cell = pixelSize
            let totalWidth = CGFloat(canvasW) * (cell + spacing) - spacing
            let totalHeight = CGFloat(canvasH) * (cell + spacing) - spacing
            let originX = alignLeft ? 0 : (availableSize.width - totalWidth) * 0.5
            let originY = (availableSize.height - totalHeight) * 0.5
            let origin = CGPoint(x: originX, y: originY)

            Canvas { context, _ in
                guard canvasW > 0, canvasH > 0 else { return }

                if let g = glyph {
                    var rect = CGRect(x: 0, y: 0, width: cell, height: cell)
                    for row in 0..<canvasH {
                        for col in 0..<canvasW {
                            rect.origin.x = origin.x + CGFloat(col) * (cell + spacing)
                            rect.origin.y = origin.y + CGFloat(row) * (cell + spacing)

                            let isOn: Bool = {
                                guard row >= 0 && row < g.pixels.count else { return false }
                                let rowPixels = g.pixels[row]
                                return (col >= 0 && col < rowPixels.count) ? rowPixels[col] : false
                            }()

                            let insideVisible = (row >= startRow && row < startRow + visibleH && col >= startCol && col < startCol + visibleW)
                            let onColor: Color
                            let offColor: Color
                            if insideVisible {
                                onColor = preview ? .black : .primary
                                offColor = Color(white: 0.90)
                            } else {
                                onColor = Color.primary.opacity(0.35)
                                offColor = Color(white: 0.92).opacity(0.35)
                            }

                            if isOn {
                                context.fill(Path(rect), with: .color(onColor))
                            } else {
                                context.fill(Path(rect), with: .color(offColor))
                            }
                        }
                    }
                }

                if glyph != nil, let baseline = baseline {
                    let effectiveBaseline = startRow + baseline
                    if effectiveBaseline >= 0 && effectiveBaseline <= canvasH {
                        let y = origin.y + CGFloat(effectiveBaseline) * (cell + spacing)  - 0.5
                        let x0 = origin.x + CGFloat(startCol) * (cell + spacing)
                        let x1 = x0 + CGFloat(visibleW) * (cell + spacing) - spacing
                        let path = Path(CGRect(x: x0, y: y, width: max(0, x1 - x0), height: 1))
                        context.fill(path, with: .color(.red.opacity(0.8)))
                    }
                }

                if preview {
                    let borderRect = CGRect(x: origin.x, y: origin.y, width: totalWidth, height: totalHeight)
                    context.stroke(Path(roundedRect: borderRect, cornerRadius: 0), with: .color(Color.primary.opacity(0.12)), lineWidth: 0.8)
                } else {
                    // Draw a border for the visible window within the full area
                    let visRect = CGRect(
                        x: origin.x + CGFloat(startCol) * (cell + spacing),
                        y: origin.y + CGFloat(startRow) * (cell + spacing),
                        width: CGFloat(visibleW) * (cell + spacing) - spacing,
                        height: CGFloat(visibleH) * (cell + spacing) - spacing
                    )
                    if visRect.width > 0 && visRect.height > 0 {
                        context.stroke(Path(roundedRect: visRect, cornerRadius: 0), with: .color(Color.accentColor.opacity(0.6)), lineWidth: 1)
                    }
                }

                // Hover/brush overlay
                if !preview, let (hRow, hCol) = hoverRowCol, brushSize > 0 {
                    let maxCols = max(fullW, startCol + visibleW)
                    let maxRows = max(fullH, startRow + visibleH)
                    let b = max(1, brushSize)
                    let half = b / 2
                    let r0 = hRow - half
                    let c0 = hCol - half
                    let r1 = r0 + b - 1
                    let c1 = c0 + b - 1
                    let rr0 = max(0, r0)
                    let cc0 = max(0, c0)
                    let rr1 = min(maxRows - 1, r1)
                    let cc1 = min(maxCols - 1, c1)
                    if rr0 > rr1 || cc0 > cc1 {
                        // nothing to draw
                    } else {
                        let x = origin.x + CGFloat(cc0) * (cell + spacing)
                        let y = origin.y + CGFloat(rr0) * (cell + spacing)
                        let wRect = CGFloat(cc1 - cc0 + 1) * (cell + spacing) - spacing
                        let hRect = CGFloat(rr1 - rr0 + 1) * (cell + spacing) - spacing
                        let overlayRect = CGRect(x: x, y: y, width: wRect, height: hRect)
                        let overlayPath = Path(roundedRect: overlayRect, cornerRadius: 0)
                        context.stroke(overlayPath, with: .color(Color.accentColor), lineWidth: 1)
                        context.fill(overlayPath, with: .color(Color.accentColor.opacity(0.75)))
                    }
                }
            }
            .transaction { t in t.animation = nil }
            .contentShape(Rectangle())
            .onHover { inside in
                if !inside {
                    hoverLocation = nil
                    hoverRowCol = nil
                    return
                }
            }
            .onContinuousHover { phase in
                switch phase {
                case .active(let loc):
                    hoverLocation = loc
                case .ended:
                    hoverLocation = nil
                    hoverRowCol = nil
                }
            }
            .onChange(of: hoverLocation) { _, newLoc in
                guard let loc = newLoc else { return }
                // Recompute grid coordinates using the same layout math
                let fullW = glyph?.width ?? 0
                let fullH = glyph?.height ?? 0
                let visibleW = max(0, (baseWidth) + (glyph?.advanceWidthOffset ?? 0))
                let visibleH = max(0, min(fullH, baseHeight > 0 ? baseHeight : fullH))
                let startCol = glyph?.viewOffsetX ?? 0
                let startRow = glyph?.viewOffsetY ?? 0

                let canvasW = max(fullW, startCol + visibleW)
                let canvasH = max(fullH, startRow + visibleH)

                let spacing: CGFloat = preview ? 0 : 1
                let cell = pixelSize
                let totalWidth = CGFloat(canvasW) * (cell + spacing) - spacing
                let totalHeight = CGFloat(canvasH) * (cell + spacing) - spacing
                let originX = alignLeft ? 0 : (availableSize.width - totalWidth) * 0.5
                let originY = (availableSize.height - totalHeight) * 0.5
                let ox = originX
                let oy = originY
                let x = max(0, loc.x - ox)
                let y = max(0, loc.y - oy)
                let column = Int((x + spacing) / (cell + spacing))
                let row = Int((y + spacing) / (cell + spacing))
                let maxCols = max(fullW, startCol + visibleW)
                let maxRows = max(fullH, startRow + visibleH)
                if row >= 0 && row < maxRows && column >= 0 && column < maxCols {
                    hoverRowCol = (row, column)
                } else {
                    hoverRowCol = nil
                }
            }
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
                        let fullW = glyph?.width ?? 0
                        let fullH = glyph?.height ?? 0
                        let maxCols = max(fullW, (glyph?.viewOffsetX ?? 0) + max(0, (baseWidth) + (glyph?.advanceWidthOffset ?? 0)))
                        let maxRows = max(fullH, (glyph?.viewOffsetY ?? 0) + max(0, min(fullH, baseHeight > 0 ? baseHeight : fullH)))
                        let spacing: CGFloat = preview ? 0 : 1
                        let cell = pixelSize
                        let column = Int((x + spacing) / (cell + spacing))
                        let row = Int((y + spacing) / (cell + spacing))

                        if row >= 0 && row < maxRows && column >= 0 && column < maxCols {
                            hoverRowCol = (row, column)
                        } else {
                            hoverRowCol = nil
                        }

                        guard row >= 0 && column >= 0 else {
                            isDragging = true
                            return
                        }

                        let b = max(1, brushSize)
                        let half = b / 2
                        let r0 = row - half
                        let c0 = column - half
                        let r1 = r0 + b - 1
                        let c1 = c0 + b - 1
                        let rr0 = max(0, r0)
                        let cc0 = max(0, c0)
                        let rr1 = min(maxRows - 1, r1)
                        let cc1 = min(maxCols - 1, c1)
                        if rr0 <= rr1 && cc0 <= cc1 {
                            for rr in rr0...rr1 {
                                for cc in cc0...cc1 {
                                    setPixel(row: rr, column: cc, to: newValue)
                                }
                            }
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
        // Allow painting anywhere within the existing glyph matrix
        // guard row < g.height, column < g.width else { return }  // Removed guard to allow out of bounds

//        // Ensure row exists
//        if row >= g.height {
//            let currentHeight = g.height
//            let neededHeight = min(row + 1, (baseHeight > 0 ? baseHeight : g.height))
//            if neededHeight > currentHeight {
//                let currentRowWidth = g.width
//                let rowsToAdd = neededHeight - currentHeight
//                let emptyRow = Array(repeating: false, count: currentRowWidth)
//                // We cannot mutate glyph here directly; delegate to onSet will handle bounds. So just bail if out of current height.
//                // For simplicity in canvas view, we only set within current height; rows beyond are ignored.
//            }
//        }

        // If column exceeds current width, we will let onSet handle growing; here, read current safely
        let current: Bool = {
            if row < g.pixels.count {
                let rowPixels = g.pixels[row]
                if column < rowPixels.count { return rowPixels[column] }
            }
            return false
        }()
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


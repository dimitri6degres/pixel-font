import Foundation
import SwiftUI
import Combine
import UniformTypeIdentifiers
import AppKit
import CoreText


final class FontDocumentViewModel: ObservableObject {
    @Published var document: FontDocument
    @Published var exportOptions = ExportOptions()
    @Published var exportBaseName: String?
    @Published var selectedGlyphID: Glyph.ID?
    private var selectedIndex: Int? { document.glyphs.firstIndex(where: { $0.id == selectedGlyphID }) }
    @AppStorage("importMargin") var importMargin: Double = 0.0
    @AppStorage("importThreshold") var importThreshold: Double = 0.5
    @Published var showFontImport: Bool = false
    
    init(document: FontDocument = .sample()) {
        self.document = document
        self.selectedGlyphID = document.glyphs.first?.id
    }
    
    var selectedGlyph: Glyph? {
        guard let id = selectedGlyphID else { return nil }
        return document.glyphs.first(where: { $0.id == id })
    }
    
    func select(_ glyph: Glyph) {
        selectedGlyphID = glyph.id
    }
    
    func togglePixel(row: Int, column: Int) {
        guard let index = document.glyphs.firstIndex(where: { $0.id == selectedGlyphID }),
              row < document.glyphHeight, column < document.glyphWidth else {
            return
        }
        
        document.glyphs[index].pixels[row][column].toggle()
        objectWillChange.send()
    }
    
    func addGlyph(from character: Character) {
        let newGlyph = Glyph(character: character, width: document.glyphWidth, height: document.glyphHeight)
        document.glyphs.append(newGlyph)
        selectedGlyphID = newGlyph.id
    }
    
    
    
    func removeGlyph(at offsets: IndexSet) {
        document.glyphs.remove(atOffsets: offsets)
        selectedGlyphID = document.glyphs.first?.id
    }
    
    func removeGlyph(selectedID : Glyph.ID, undoManager: UndoManager?) {
        
        
        guard let index = document.glyphs.firstIndex(where: { $0.id == selectedID }) else {
            return
        }
        let original = document.glyphs[index]
        document.glyphs.remove(at: index)
        selectedGlyphID = document.glyphs.first?.id
        objectWillChange.send()
        
        undoManager?.registerUndo(withTarget: self) { target in
            target.document.glyphs.insert(original, at: index)
            target.selectedGlyphID = selectedID
            target.objectWillChange.send()
        }
        undoManager?.setActionName("Delete Glyph")
    }
    
    

    
    func moveGlyphs(from source: IndexSet, to destination: Int) {
        document.glyphs.move(fromOffsets: source, toOffset: destination)
        objectWillChange.send()
    }
    
    func renameSelectedGlyph(to newString: String) {
        guard let index = document.glyphs.firstIndex(where: { $0.id == selectedGlyphID }) else { return }
        let newChar = newString.first
        document.glyphs[index].character = newChar
        objectWillChange.send()
    }
    
    // MARK: - Per-glyph width adjustments
    var selectedGlyphAdvanceOffset: Int {
        guard let idx = selectedIndex else { return 0 }
        return document.glyphs[idx].advanceWidthOffset
    }
    
    func setSelectedGlyphAdvanceOffset(_ newOffset: Int, undoManager: UndoManager?) {
        guard let idx = selectedIndex else { return }
        let old = document.glyphs[idx].advanceWidthOffset
        guard old != newOffset else { return }
        document.glyphs[idx].advanceWidthOffset = newOffset
        objectWillChange.send()
        undoManager?.registerUndo(withTarget: self) { target in
            if let sidx = target.document.glyphs.firstIndex(where: { $0.id == target.selectedGlyphID }) {
                target.document.glyphs[sidx].advanceWidthOffset = old
                target.objectWillChange.send()
            }
        }
        undoManager?.setActionName("Adjust Glyph Width")
    }
    
    var selectedGlyphEffectiveWidth: Int {
        guard let g = selectedGlyph else { return document.glyphWidth }
        return max(1, min(100, document.glyphWidth + g.advanceWidthOffset))
    }
    
    func setSelectedGlyphEffectiveWidth(_ newWidth: Int, undoManager: UndoManager?) {
        let clamped = max(1, min(100, newWidth))
        let base = document.glyphWidth
        setSelectedGlyphAdvanceOffset(clamped - base, undoManager: undoManager)
    }
    
    // MARK: - Undo-enabled editing methods
    func setPixel(row: Int, column: Int, to newValue: Bool, undoManager: UndoManager?) {
        guard let index = document.glyphs.firstIndex(where: { $0.id == selectedGlyphID }),
              row >= 0, column >= 0 else { return }
        
        let maxW = 128
        let maxH = 128
        
        guard row < maxH, column < maxW else { return }
        
        // Ensure vertical size (rows)
        if row >= document.glyphs[index].height {
            let currentHeight = document.glyphs[index].height
            let neededHeight = min(row + 1, maxH)
            if neededHeight > currentHeight {
                let currentRowWidth = document.glyphs[index].width
                let rowsToAdd = neededHeight - currentHeight
                let emptyRow = Array(repeating: false, count: currentRowWidth)
                document.glyphs[index].pixels.append(contentsOf: Array(repeating: emptyRow, count: rowsToAdd))
            }
        }
        
        let neededW = min(max(column + 1, document.glyphs[index].width), maxW)
        if document.glyphs[index].width < neededW {
            for r in 0..<document.glyphs[index].height {
                let currentCount = document.glyphs[index].pixels[r].count
                if currentCount < neededW {
                    document.glyphs[index].pixels[r].append(contentsOf: Array(repeating: false, count: neededW - currentCount))
                }
            }
        }
        
        let oldValue = document.glyphs[index].pixels[row][column]
        guard oldValue != newValue else { return }
        document.glyphs[index].pixels[row][column] = newValue
        objectWillChange.send()
        
        undoManager?.registerUndo(withTarget: self) { target in
            if let idx = target.document.glyphs.firstIndex(where: { $0.id == target.selectedGlyphID }) {
                target.document.glyphs[idx].pixels[row][column] = oldValue
                target.objectWillChange.send()
            }
        }
        undoManager?.setActionName(newValue ? "Paint Pixel" : "Erase Pixel")
    }
    
    func duplicateSelectedGlyph(selectedID : Glyph.ID, undoManager: UndoManager?) {
        guard let index = document.glyphs.firstIndex(where: { $0.id == selectedID }) else {
            return
        }
        let original = document.glyphs[index]
        let newChar = original.character?.incrementedCharacter() ?? "?"
        let copy = Glyph(id: UUID(), character: newChar, pixels: original.pixels, advanceWidthOffset: original.advanceWidthOffset)
        let insertIndex = document.glyphs.index(after: index)
        document.glyphs.insert(copy, at: insertIndex)
        selectedGlyphID = copy.id
        objectWillChange.send()
        
        undoManager?.registerUndo(withTarget: self) { target in
            if let idx = target.document.glyphs.firstIndex(where: { $0.id == copy.id }) {
                target.document.glyphs.remove(at: idx)
                target.selectedGlyphID = selectedID
                target.objectWillChange.send()
            }
        }
        undoManager?.setActionName("Duplicate Glyph")
    }
    
    func resetGlyph(selectedID : Glyph.ID, undoManager: UndoManager?) {
        guard let index = document.glyphs.firstIndex(where: { $0.id == selectedID }) else {
            return
        }
        let oldGlyph = document.glyphs[index]
        let character = oldGlyph.character
        document.glyphs[index] = Glyph(character: character, width: document.glyphWidth, height: document.glyphHeight)
        objectWillChange.send()
        
        undoManager?.registerUndo(withTarget: self) { target in
            target.document.glyphs[index] = oldGlyph
            target.objectWillChange.send()
        }
        undoManager?.setActionName("Reset Glyph")
    }
    
    
    func negativeSelectedGlyph(undoManager: UndoManager?) {
        guard let index = document.glyphs.firstIndex(where: { $0.id == selectedGlyphID }) else { return }
        let before = document.glyphs[index]
        
        var g = before
        for row in 0..<g.height {
            for pixel in 0..<g.pixels[row].count {
                g.pixels[row][pixel].toggle()
            }
        }
        document.glyphs[index] = g
        objectWillChange.send()
        
        undoManager?.registerUndo(withTarget: self) { target in
            target.document.glyphs[index] = before
            target.objectWillChange.send()
        }
        undoManager?.setActionName("Negative")
    }
    
    
    func flipSelectedGlyphHorizontally(undoManager: UndoManager?) {
        guard let index = document.glyphs.firstIndex(where: { $0.id == selectedGlyphID }) else { return }
        let before = document.glyphs[index]
        var g = before
        for row in 0..<g.height { g.pixels[row].reverse() }
        document.glyphs[index] = g
        objectWillChange.send()
        
        undoManager?.registerUndo(withTarget: self) { target in
            target.document.glyphs[index] = before
            target.objectWillChange.send()
        }
        undoManager?.setActionName("Flip Horizontal")
    }
    
    func flipSelectedGlyphVertically(undoManager: UndoManager?) {
        guard let index = document.glyphs.firstIndex(where: { $0.id == selectedGlyphID }) else { return }
        let before = document.glyphs[index]
        var g = before
        g.pixels.reverse()
        document.glyphs[index] = g
        objectWillChange.send()
        
        undoManager?.registerUndo(withTarget: self) { target in
            target.document.glyphs[index] = before
            target.objectWillChange.send()
        }
        undoManager?.setActionName("Flip Vertical")
    }
    

    func rotateSelectedGlyphClockwise(undoManager: UndoManager?) {
        guard let index = document.glyphs.firstIndex(where: { $0.id == selectedGlyphID }) else { return }
        let beforeGlyph = document.glyphs[index]
        let g = beforeGlyph

        // 90° clockwise rotation: (r, c) -> (c, H-1-r)
        let oldH = g.height, oldW = g.width
        var rotated = Array(repeating: Array(repeating: false, count: oldH), count: oldW)
        for r in 0..<oldH {
            for c in 0..<oldW {
                rotated[c][oldH - 1 - r] = g.pixels[r][c]
            }
        }

        // Preserve all pixels: adjust glyph canvas if needed (without changing global dimensions)
        // Here we simply replace the pixel matrix with the rotated version (W' = oldH, H' = oldW)
        let newPixels = rotated

        document.glyphs[index] = Glyph(
            id: g.id,
            character: g.character,
            pixels: newPixels,
            advanceWidthOffset: g.advanceWidthOffset
        )
        objectWillChange.send()

        undoManager?.registerUndo(withTarget: self) { target in
            target.document.glyphs[index] = beforeGlyph
            target.objectWillChange.send()
        }
        undoManager?.setActionName("Rotate 90°")
    }

    func rotateSelectedGlyphCounterClockwise(undoManager: UndoManager?) {
        guard let index = document.glyphs.firstIndex(where: { $0.id == selectedGlyphID }) else { return }
        let beforeGlyph = document.glyphs[index]
        let g = beforeGlyph

        // 90° counter-clockwise rotation: (r, c) -> (W-1-c, r)
        let oldH = g.height, oldW = g.width
        var rotated = Array(repeating: Array(repeating: false, count: oldH), count: oldW)
        for r in 0..<oldH {
            for c in 0..<oldW {
                rotated[oldW - 1 - c][r] = g.pixels[r][c]
            }
        }

        // Preserve all pixels: adopt the rotated matrix as-is
        let newPixels = rotated

        document.glyphs[index] = Glyph(
            id: g.id,
            character: g.character,
            pixels: newPixels,
            advanceWidthOffset: g.advanceWidthOffset
        )
        objectWillChange.send()

        undoManager?.registerUndo(withTarget: self) { target in
            target.document.glyphs[index] = beforeGlyph
            target.objectWillChange.send()
        }
        undoManager?.setActionName("Rotate -90°")
    }
    
    func nudgeSelectedGlyphUp(undoManager: UndoManager?) {
        guard let index = document.glyphs.firstIndex(where: { $0.id == selectedGlyphID }) else { return }
        let before = document.glyphs[index]
        var g = before
        guard g.height > 0 else { return }
        if !g.pixels.isEmpty { g.pixels.removeFirst() }
        g.pixels.append(Array(repeating: false, count: g.width))
        document.glyphs[index] = g
        objectWillChange.send()
        
        undoManager?.registerUndo(withTarget: self) { target in
            target.document.glyphs[index] = before
            target.objectWillChange.send()
        }
        undoManager?.setActionName("Nudge Up")
    }
    
    func nudgeSelectedGlyphDown(undoManager: UndoManager?) {
        guard let index = document.glyphs.firstIndex(where: { $0.id == selectedGlyphID }) else { return }
        let before = document.glyphs[index]
        var g = before
        guard g.height > 0 else { return }
        if !g.pixels.isEmpty { g.pixels.removeLast() }
        g.pixels.insert(Array(repeating: false, count: g.width), at: 0)
        document.glyphs[index] = g
        objectWillChange.send()
        
        undoManager?.registerUndo(withTarget: self) { target in
            target.document.glyphs[index] = before
            target.objectWillChange.send()
        }
        undoManager?.setActionName("Nudge Down")
    }
    
    func nudgeSelectedGlyphLeft(undoManager: UndoManager?) {
        guard let index = document.glyphs.firstIndex(where: { $0.id == selectedGlyphID }) else { return }
        let before = document.glyphs[index]
        var g = before
        guard g.width > 0 else { return }
        for row in 0..<g.height {
            if !g.pixels[row].isEmpty { g.pixels[row].removeFirst() }
            g.pixels[row].append(false)
        }
        document.glyphs[index] = g
        objectWillChange.send()
        
        undoManager?.registerUndo(withTarget: self) { target in
            target.document.glyphs[index] = before
            target.objectWillChange.send()
        }
        undoManager?.setActionName("Nudge Left")
    }
    
    func nudgeSelectedGlyphRight(undoManager: UndoManager?) {
        guard let index = document.glyphs.firstIndex(where: { $0.id == selectedGlyphID }) else { return }
        let before = document.glyphs[index]
        var g = before
        guard g.width > 0 else { return }
        for row in 0..<g.height {
            if !g.pixels[row].isEmpty { g.pixels[row].removeLast() }
            g.pixels[row].insert(false, at: 0)
        }
        document.glyphs[index] = g
        objectWillChange.send()
        
        undoManager?.registerUndo(withTarget: self) { target in
            target.document.glyphs[index] = before
            target.objectWillChange.send()
        }
        undoManager?.setActionName("Nudge Right")
    }
    
    // MARK: - Expand/Shrink selected glyph canvas (outside visible window)
    func expandOrShrinkSelectedGlyphUp(shrink: Bool, undoManager: UndoManager?) {
        guard let index = document.glyphs.firstIndex(where: { $0.id == selectedGlyphID }) else { return }
        let before = document.glyphs[index]
        var g = before
        if shrink {
            // Remove top row if any, then shift window up by 1 to keep same content under frame
            if !g.pixels.isEmpty { g.pixels.removeFirst() }
            if g.viewOffsetY > 0 { g.viewOffsetY -= 1 }
        } else {
            // Insert empty row at top and shift window down to keep frame on existing pixels
            g.pixels.insert(Array(repeating: false, count: g.width), at: 0)
            g.viewOffsetY += 1
        }
        document.glyphs[index] = g
        objectWillChange.send()
        undoManager?.registerUndo(withTarget: self) { target in
            target.document.glyphs[index] = before
            target.objectWillChange.send()
        }
        undoManager?.setActionName(shrink ? "Shrink Up" : "Expand Up")
    }

    func expandOrShrinkSelectedGlyphDown(shrink: Bool, undoManager: UndoManager?) {
        guard let index = document.glyphs.firstIndex(where: { $0.id == selectedGlyphID }) else { return }
        let before = document.glyphs[index]
        var g = before
        if shrink {
            // Remove bottom row if any
            if !g.pixels.isEmpty { g.pixels.removeLast() }
        } else {
            // Append empty row at bottom (no offset change)
            g.pixels.append(Array(repeating: false, count: g.width))
        }
        document.glyphs[index] = g
        objectWillChange.send()
        undoManager?.registerUndo(withTarget: self) { target in
            target.document.glyphs[index] = before
            target.objectWillChange.send()
        }
        undoManager?.setActionName(shrink ? "Shrink Down" : "Expand Down")
    }

    func expandOrShrinkSelectedGlyphLeft(shrink: Bool, undoManager: UndoManager?) {
        guard let index = document.glyphs.firstIndex(where: { $0.id == selectedGlyphID }) else { return }
        let before = document.glyphs[index]
        var g = before
        if shrink {
            // Remove leftmost column if any, then shift window left by 1 to keep same content under frame
            for r in 0..<g.height { if !g.pixels[r].isEmpty { g.pixels[r].removeFirst() } }
            if g.viewOffsetX > 0 { g.viewOffsetX -= 1 }
        } else {
            // Insert empty column at left and shift window right to keep frame on existing pixels
            for r in 0..<g.height { g.pixels[r].insert(false, at: 0) }
            g.viewOffsetX += 1
        }
        document.glyphs[index] = g
        objectWillChange.send()
        undoManager?.registerUndo(withTarget: self) { target in
            target.document.glyphs[index] = before
            target.objectWillChange.send()
        }
        undoManager?.setActionName(shrink ? "Shrink Left" : "Expand Left")
    }

    func expandOrShrinkSelectedGlyphRight(shrink: Bool, undoManager: UndoManager?) {
        guard let index = document.glyphs.firstIndex(where: { $0.id == selectedGlyphID }) else { return }
        let before = document.glyphs[index]
        var g = before
        if shrink {
            // Remove rightmost column if any
            for r in 0..<g.height {
                if !g.pixels[r].isEmpty { g.pixels[r].removeLast() }
            }
        } else {
            // Append empty column at right (no offset change)
            for r in 0..<g.height {
                g.pixels[r].append(false)
            }
        }
        document.glyphs[index] = g
        objectWillChange.send()
        undoManager?.registerUndo(withTarget: self) { target in
            target.document.glyphs[index] = before
            target.objectWillChange.send()
        }
        undoManager?.setActionName(shrink ? "Shrink Right" : "Expand Right")
    }
    
    func resizeGlyphs(width newWidth: Int, height newHeight: Int, undoManager: UndoManager?) {
        guard newWidth > 0, newHeight > 0 else { return }
        let beforeGlyphs = document.glyphs
        let beforeW = document.glyphWidth
        let beforeH = document.glyphHeight
        
        document.glyphs = document.glyphs.map { $0.resized(toWidth: newWidth, height: newHeight) }
        document.glyphWidth = newWidth
        document.glyphHeight = newHeight
        objectWillChange.send()
        
        undoManager?.registerUndo(withTarget: self) { target in
            target.document.glyphs = beforeGlyphs
            target.document.glyphWidth = beforeW
            target.document.glyphHeight = beforeH
            target.objectWillChange.send()
        }
        undoManager?.setActionName("Resize Glyphs")
    }
    
    
    // MARK: - Image Import -> Glyph pixels
    /// Import an image and map it to the selected glyph's pixels using current glyph size.
    /// - Parameters:
    ///   - image: Platform image (NSImage on macOS, UIImage on iOS)
    ///   - threshold: 0...1 threshold to decide black/white from grayscale.
    ///   - margin: fraction (0...0.45) margin to apply around the glyph area
    ///   - undoManager: optional UndoManager
    func importImageToSelectedGlyph(platformImage image: Any, threshold: CGFloat? = nil, margin: CGFloat? = nil, undoManager: UndoManager?) {
        let effectiveThreshold = threshold ?? CGFloat(importThreshold)
        let effectiveMargin = margin ?? CGFloat(importMargin)
        guard let nsImage = image as? NSImage else { return }
        guard let bitmap = nsImage.toBitmapRep() else { return }
        let width = document.glyphWidth
        let height = document.glyphHeight
        let resized = bitmap.resizedAspectFit(to: NSSize(width: width, height: height), background: NSColor.white, margin: effectiveMargin)
        
        
        var newPixels = Array(repeating: Array(repeating: false, count: width), count: height)
        
        for y in 0..<height {
            for x in 0..<width {
                let gray = resized.grayscaleAt(x: x, y: y)
                newPixels[y][x] = gray < effectiveThreshold
            }
        }
        
        guard let index = document.glyphs.firstIndex(where: { $0.id == selectedGlyphID }) else { return }
        let before = document.glyphs[index]
        document.glyphs[index].pixels = newPixels
        objectWillChange.send()
        undoManager?.registerUndo(withTarget: self) { target in
            target.document.glyphs[index] = before
            target.objectWillChange.send()
        }
        undoManager?.setActionName("Import Image")
        
    }
    
    
    /// Import an image from the macOS pasteboard (bitmap or PDF), rasterize to glyph size and apply to selected glyph.
    func importFromPasteboard(undoManager: UndoManager?) {
        let pb = NSPasteboard.general
        
        // 1) Try to read a JSON glyph (string)
        let possibleString: String? = pb.string(forType: .string)

        if let str = possibleString?.trimmingCharacters(in: .whitespacesAndNewlines) {
            struct ClipboardGlyph: Decodable {
                let type: String?
                let character: String?
                let width: Int?
                let height: Int?
                let viewOffsetX: Int?
                let viewOffsetY: Int?
                let advanceWidthOffset: Int?
                let pixels: [[Int]]?
                let pixelsBool: [[Bool]]?
                enum CodingKeys: String, CodingKey { case type, character, width, height, viewOffsetX, viewOffsetY, advanceWidthOffset, pixels }
                init(from decoder: Decoder) throws {
                    let c = try decoder.container(keyedBy: CodingKeys.self)
                    type = try? c.decode(String.self, forKey: .type)
                    character = try? c.decode(String.self, forKey: .character)
                    width = try? c.decode(Int.self, forKey: .width)
                    height = try? c.decode(Int.self, forKey: .height)
                    viewOffsetX = try? c.decode(Int.self, forKey: .viewOffsetX)
                    viewOffsetY = try? c.decode(Int.self, forKey: .viewOffsetY)
                    advanceWidthOffset = try? c.decode(Int.self, forKey: .advanceWidthOffset)
                    pixels = try? c.decode([[Int]].self, forKey: .pixels)
                    pixelsBool = (pixels == nil) ? (try? c.decode([[Bool]].self, forKey: .pixels)) : nil
                }
                func resolvedPixels() -> [[Bool]]? {
                    if let ints = pixels { return ints.map { $0.map { $0 != 0 } } }
                    if let bools = pixelsBool { return bools }
                    return nil
                }
            }

            func applyClipboardGlyph(_ cg: ClipboardGlyph) -> Bool {
                guard let newPixels = cg.resolvedPixels(),
                      let index = document.glyphs.firstIndex(where: { $0.id == selectedGlyphID }) else { return false }
                let before = document.glyphs[index]
                document.glyphs[index].pixels = newPixels
//                if let chStr = cg.character, let firstChar = chStr.first { document.glyphs[index].character = firstChar }
                if let adv = cg.advanceWidthOffset { document.glyphs[index].advanceWidthOffset = adv }
                if let ox = cg.viewOffsetX { document.glyphs[index].viewOffsetX = ox }
                if let oy = cg.viewOffsetY { document.glyphs[index].viewOffsetY = oy }
                objectWillChange.send()
                undoManager?.registerUndo(withTarget: self) { target in
                    if let idx = target.document.glyphs.firstIndex(where: { $0.id == before.id }) {
                        target.document.glyphs[idx] = before
                        target.objectWillChange.send()
                    }
                }
                undoManager?.setActionName("Paste Glyph")
                return true
            }

            if let data = str.data(using: .utf8) {
                if let cg = try? JSONDecoder().decode(ClipboardGlyph.self, from: data) {
                    if applyClipboardGlyph(cg) { return }
                }
                // If unconditional decode didn't apply, try a marker check as a secondary hint
                let looksLikeGlyph = str.contains("\"pixelfont.glyph\"") || str.contains("pixelfont.glyph")
                if looksLikeGlyph, let cg2 = try? JSONDecoder().decode(ClipboardGlyph.self, from: data) {
                    if applyClipboardGlyph(cg2) { return }
                }
            }
        }
        
        // Try common bitmap types first
        if let data = pb.data(forType: .tiff), let img = NSImage(data: data) {
            importImageToSelectedGlyph(platformImage: img, undoManager: undoManager)
            return
        }
        if let data = pb.data(forType: .png), let img = NSImage(data: data) {
            importImageToSelectedGlyph(platformImage: img, undoManager: undoManager)
            return
        }
        let jpegType = NSPasteboard.PasteboardType(UTType.jpeg.identifier)
        if let data = pb.data(forType: jpegType), let img = NSImage(data: data) {
            importImageToSelectedGlyph(platformImage: img, undoManager: undoManager)
            return
        }
        
        // Fallback: try generic NSImage from pasteboard
        if let fallbackImg = NSImage(pasteboard: pb) {
            importImageToSelectedGlyph(platformImage: fallbackImg, undoManager: undoManager)
            return
        }
        
        // Try PDF (vector)
        if let pdfData = pb.data(forType: .pdf), let provider = CGDataProvider(data: pdfData as CFData), let pdf = CGPDFDocument(provider), let page = pdf.page(at: 1) {
            let width = document.glyphWidth
            let height = document.glyphHeight
            
            guard let ctx = CGContext(
                data: nil,
                width: width,
                height: height,
                bitsPerComponent: 8,
                bytesPerRow: 0,
                space: CGColorSpaceCreateDeviceRGB(),
                bitmapInfo: CGImageAlphaInfo.premultipliedLast.rawValue
            ) else { return }
            
            ctx.interpolationQuality = .high
            ctx.setFillColor(NSColor.clear.cgColor)
            ctx.fill(CGRect(x: 0, y: 0, width: width, height: height))
            
            // Fit page into glyph rect preserving aspect ratio, centered
            let box = page.getBoxRect(.mediaBox)
            let scaleX = CGFloat(width) / box.width
            let scaleY = CGFloat(height) / box.height
            let scale = min(scaleX, scaleY)
            let renderW = box.width * scale
            let renderH = box.height * scale
            let offsetX = (CGFloat(width) - renderW) * 0.5
            let offsetY = (CGFloat(height) - renderH) * 0.5
            
            ctx.saveGState()
            // PDF coordinates are bottom-left origin; our context is also bottom-left for CoreGraphics drawing
            ctx.translateBy(x: offsetX, y: offsetY)
            ctx.scaleBy(x: scale, y: scale)
            ctx.drawPDFPage(page)
            ctx.restoreGState()
            
            if let cg = ctx.makeImage() {
                let nsImage = NSImage(cgImage: cg, size: NSSize(width: width, height: height))
                importImageToSelectedGlyph(platformImage: nsImage, undoManager: undoManager)
            }
            return
        }
    }
    /// Log pasteboard types and available data sizes for debugging
    func logPasteboardContents() {
        let pb = NSPasteboard.general
        let types = pb.types ?? []
        print("---- Pasteboard Types ----")
        for t in types { print("- \(t.rawValue)") }
        print("--------------------------")
        
        if let tiffData = pb.data(forType: .tiff) {
            print("TIFF size: \(tiffData.count) bytes")
        } else {
            print("No TIFF data")
        }
        if let pngData = pb.data(forType: .png) {
            print("PNG size: \(pngData.count) bytes")
        } else {
            print("No PNG data")
        }
        let jpegType = NSPasteboard.PasteboardType(UTType.jpeg.identifier)
        if let jpegData = pb.data(forType: jpegType) {
            print("JPEG size: \(jpegData.count) bytes")
        } else {
            print("No JPEG data")
        }
        if let pdfData = pb.data(forType: .pdf) {
            print("PDF size: \(pdfData.count) bytes")
            if let provider = CGDataProvider(data: pdfData as CFData), let pdf = CGPDFDocument(provider) {
                print("PDF pages: \(pdf.numberOfPages)")
            }
        } else {
            print("No PDF data")
        }
        if let img = NSImage(pasteboard: pb) {
            print("NSImage(pasteboard:) size: \(img.size)")
        } else {
            print("NSImage(pasteboard:) returned nil")
        }
    }
    
    func exportAdafruitGFX(fontName rawName: String, options: ExportOptions? = nil) -> String {
        let effectiveOptions = options ?? exportOptions
        var copy = document
        copy.name = rawName
        return copy.exportAdafruitGFX(fontName: rawName, options: effectiveOptions)
    }
    
    // MARK: - Import .h (Adafruit GFX header)
    func openHeaderAndImport(undoManager: UndoManager?) {
        let panel = NSOpenPanel()
//        panel.allowedFileTypes = ["h"]
        panel.allowedContentTypes = [.cHeader]
        panel.allowsMultipleSelection = false
        panel.canChooseDirectories = false
        panel.canCreateDirectories = false
        panel.title = "Open Header (.h)"
        panel.message = "Choose an Adafruit GFX header exported by the app"
        if panel.runModal() == .OK, let url = panel.url {
            do {
                let text = try String(contentsOf: url, encoding: .utf8)
                try importAdafruitGFXHeader(from: text, undoManager: undoManager)
            } catch {
                NSAlert(error: error).runModal()
            }
        }
    }

    /// Import a header exported by exportAdafruitGFX(fontName:)
    /// This parser is intentionally scoped to the format we generate: a single Bitmaps array, a Glyphs array of entries `{offset, w, h, xAdv, xOff, yOff}`, and a GFXfont block with first/last char and height.
    func importAdafruitGFXHeader(from header: String, undoManager: UndoManager?) throws {
        // Helper regex builders
        func regex(_ pattern: String) throws -> NSRegularExpression { try NSRegularExpression(pattern: pattern, options: []) }
        let full = header as NSString

        // Extract font height from final GFXfont block (last line before closing): height as an integer
        let fontHeightRegex = try regex(#"const\s+GFXfont\s+\w+\s+PROGMEM\s*=\s*\{[\s\S]*?,\s*(\d+)\s*\};"#)
        guard let fh = fontHeightRegex.firstMatch(in: header, range: NSRange(location: 0, length: full.length)), fh.numberOfRanges >= 2 else {
            throw NSError(domain: "Import", code: 1, userInfo: [NSLocalizedDescriptionKey: "Could not find font height in header."])
        }
        let heightString = full.substring(with: fh.range(at: 1))
        guard let fontHeight = Int(heightString) else {
            throw NSError(domain: "Import", code: 2, userInfo: [NSLocalizedDescriptionKey: "Invalid font height value."])
        }

        // Extract first and last chars (hex) from the GFXfont block
        let firstLastRegex = try regex(#"\{[\s\S]*?,\s*0x([0-9A-Fa-f]{2}),\s*0x([0-9A-Fa-f]{2}),\s*\d+\s*\};"#)
        guard let fr = firstLastRegex.firstMatch(in: header, range: NSRange(location: 0, length: full.length)), fr.numberOfRanges >= 3 else {
            throw NSError(domain: "Import", code: 3, userInfo: [NSLocalizedDescriptionKey: "Could not find first/last char range."])
        }
        let firstHex = full.substring(with: fr.range(at: 1))
        let lastHex = full.substring(with: fr.range(at: 2))
        guard let firstChar = UInt8(firstHex, radix: 16), UInt8(lastHex, radix: 16) != nil else {
            throw NSError(domain: "Import", code: 4, userInfo: [NSLocalizedDescriptionKey: "Invalid first/last char values."])
        }

        // Extract bitmap bytes block
        let bitmapRegex = try regex(#"const\s+uint8_t\s+\w+Bitmaps\[\]\s+PROGMEM\s*=\s*\{([\s\S]*?)\};"#)
        guard let bm = bitmapRegex.firstMatch(in: header, range: NSRange(location: 0, length: full.length)), bm.numberOfRanges >= 2 else {
            throw NSError(domain: "Import", code: 5, userInfo: [NSLocalizedDescriptionKey: "Could not find bitmap data."])
        }
        let bitmapBody = full.substring(with: bm.range(at: 1))
        let byteRegex = try regex(#"0x([0-9A-Fa-f]{2})"#)
        let byteMatches = byteRegex.matches(in: bitmapBody, range: NSRange(location: 0, length: (bitmapBody as NSString).length))
        var bitmapBytes: [UInt8] = []
        for m in byteMatches { if m.numberOfRanges >= 2 { let hex = (bitmapBody as NSString).substring(with: m.range(at: 1)); if let b = UInt8(hex, radix: 16) { bitmapBytes.append(b) } } }

        // Extract glyph table entries
        let glyphsRegex = try regex(#"const\s+GFXglyph\s+\w+Glyphs\[\]\s+PROGMEM\s*=\s*\{([\s\S]*?)\};"#)
        guard let gm = glyphsRegex.firstMatch(in: header, range: NSRange(location: 0, length: full.length)), gm.numberOfRanges >= 2 else {
            throw NSError(domain: "Import", code: 6, userInfo: [NSLocalizedDescriptionKey: "Could not find glyph table."])
        }
        let glyphsBody = full.substring(with: gm.range(at: 1))
        // Entries look like: {offset, w, h, xAdv, xOff, yOff}
        let entryRegex = try regex(#"\{\s*(\d+)\s*,\s*(\d+)\s*,\s*(\d+)\s*,\s*(\d+)\s*,\s*(-?\d+)\s*,\s*(-?\d+)\s*\}"#)
        let entries = entryRegex.matches(in: glyphsBody, range: NSRange(location: 0, length: (glyphsBody as NSString).length))

        // Rebuild glyphs by unpacking bits for each entry using w,h and offset; MSB-first, row-major (as our export)
        var newGlyphs: [Glyph] = []
        let baseWidthGuess = entries.first.flatMap { match -> Int? in
            if match.numberOfRanges >= 3 { let wStr = (glyphsBody as NSString).substring(with: match.range(at: 2)); return Int(wStr) } else { return nil }
        } ?? 8

        for (i, match) in entries.enumerated() {
            guard match.numberOfRanges >= 7 else { continue }
            let offsetStr = (glyphsBody as NSString).substring(with: match.range(at: 1))
            let wStr = (glyphsBody as NSString).substring(with: match.range(at: 2))
            let hStr = (glyphsBody as NSString).substring(with: match.range(at: 3))
            let advStr = (glyphsBody as NSString).substring(with: match.range(at: 4))
            let offStr = (glyphsBody as NSString).substring(with: match.range(at: 5))
            // let yOffStr = (glyphsBody as NSString).substring(with: match.range(at: 6)) // currently unused
            guard let offset = Int(offsetStr), let gw = Int(wStr), let gh = Int(hStr), let xAdv = Int(advStr), Int(offStr) != nil else { continue }

            // Compute character code from range
            let code = Int(firstChar) + i
            let ch: Character? = (code >= 0 && code <= 255) ? Character(UnicodeScalar(code)!) : nil

            // Unpack bits for gw*gh
            var pixels = Array(repeating: Array(repeating: false, count: gw), count: gh)
            var bitIndex = 0
            for row in 0..<gh {
                for col in 0..<gw {
                    let bitPos = offset * 8 + bitIndex
                    let byteIndex = bitPos / 8
                    guard byteIndex < bitmapBytes.count else { continue }
                    let b = bitmapBytes[byteIndex]
                    let posInByte = bitPos % 8
                    let on = ((b >> (7 - posInByte)) & 0x01) == 1
                    pixels[row][col] = on
                    bitIndex += 1
                }
            }

            // advance width offset relative to base document width
            let advanceOffset = xAdv - baseWidthGuess
            let glyph = Glyph(character: ch, pixels: pixels, advanceWidthOffset: advanceOffset)
            newGlyphs.append(glyph)
        }

        // Update document with imported data
        let before = document
        document.name = "Imported"
        document.glyphWidth = baseWidthGuess
        document.glyphHeight = fontHeight
        document.glyphs = newGlyphs
        document.baseline = max(0, fontHeight - 2)
        objectWillChange.send()

        undoManager?.registerUndo(withTarget: self) { target in
            target.document = before
            target.objectWillChange.send()
        }
        undoManager?.setActionName("Import .h Header")
    }

    // MARK: - Crop selected glyph to visible window
    func cropSelectedGlyphToVisibleWindow(undoManager: UndoManager?) {
        guard let idx = document.glyphs.firstIndex(where: { $0.id == selectedGlyphID }) else { return }
        let before = document.glyphs[idx]
        let g = before
        let baseW = document.glyphWidth
        let baseH = document.glyphHeight
        let visibleW = max(0, baseW + g.advanceWidthOffset)
        let visibleH = max(0, min(g.height, baseH))
        let startCol = max(0, g.viewOffsetX)
        let startRow = max(0, g.viewOffsetY)
        guard visibleW > 0, visibleH > 0, startRow < g.height, startCol < g.width else { return }
        let endRow = min(g.height, startRow + visibleH)
        let endCol = min(g.width, startCol + visibleW)

        var newPixels: [[Bool]] = []
        newPixels.reserveCapacity(endRow - startRow)
        for r in startRow..<endRow {
            let rowSlice = Array(g.pixels[r][startCol..<endCol])
            newPixels.append(rowSlice)
        }

        var cropped = g
        cropped.pixels = newPixels
        cropped.viewOffsetX = 0
        cropped.viewOffsetY = 0
        // advanceWidthOffset remains unchanged (visibleW may equal baseW+offset already)
        document.glyphs[idx] = cropped
        objectWillChange.send()

        undoManager?.registerUndo(withTarget: self) { target in
            if let uidx = target.document.glyphs.firstIndex(where: { $0.id == before.id }) {
                target.document.glyphs[uidx] = before
                target.objectWillChange.send()
            }
        }
        undoManager?.setActionName("Crop to Frame")
    }
    
//    func cropSelectedGlyphToContent(undoManager: UndoManager?) {
//        guard let idx = document.glyphs.firstIndex(where: { $0.id == selectedGlyphID }) else { return }
//        let before = document.glyphs[idx]
//        let g = before
//        let h = g.height
//        let w = g.width
//        guard h > 0, w > 0 else { return }
//
//        var minRow = h, maxRow = -1
//        var minCol = w, maxCol = -1
//        for r in 0..<h {
//            for c in 0..<w {
//                if g.pixels[r][c] {
//                    if r < minRow { minRow = r }
//                    if r > maxRow { maxRow = r }
//                    if c < minCol { minCol = c }
//                    if c > maxCol { maxCol = c }
//                }
//            }
//        }
//
//        // If no pixels are on, keep a 1x1 empty glyph
//        if maxRow < 0 || maxCol < 0 {
//            var cropped = g
//            cropped.pixels = [[false]]
//            cropped.viewOffsetX = 0
//            cropped.viewOffsetY = 0
//            document.glyphs[idx] = cropped
//            objectWillChange.send()
//            undoManager?.registerUndo(withTarget: self) { target in
//                if let uidx = target.document.glyphs.firstIndex(where: { $0.id == before.id }) {
//                    target.document.glyphs[uidx] = before
//                    target.objectWillChange.send()
//                }
//            }
//            undoManager?.setActionName("Crop to Content")
//            return
//        }
//
//        let newH = maxRow - minRow + 1
//        let newW = maxCol - minCol + 1
//        var newPixels: [[Bool]] = Array(repeating: Array(repeating: false, count: newW), count: newH)
//        for r in 0..<newH {
//            for c in 0..<newW {
//                newPixels[r][c] = g.pixels[minRow + r][minCol + c]
//            }
//        }
//
//        var cropped = g
//        cropped.pixels = newPixels
//
//        // Preserve frame placement: shift offsets by the amount cropped from top/left
//        let oldOffX = g.viewOffsetX
//        let oldOffY = g.viewOffsetY
//        var newOffX = max(0, oldOffX - minCol)
//        var newOffY = max(0, oldOffY - minRow)
//
//        // Clamp offsets so the visible window stays within bounds
//        let visibleW = max(1, min(128, document.glyphWidth + g.advanceWidthOffset))
//        let visibleH = max(1, min(128, document.glyphHeight))
//        let maxStartX = max(0, newPixels.first?.count ?? 0 - visibleW)
//        let maxStartY = max(0, newPixels.count - visibleH)
//        if newOffX > maxStartX { newOffX = maxStartX }
//        if newOffY > maxStartY { newOffY = maxStartY }
//
//        cropped.viewOffsetX = newOffX
//        cropped.viewOffsetY = newOffY
//
//        document.glyphs[idx] = cropped
//        objectWillChange.send()
//
//        undoManager?.registerUndo(withTarget: self) { target in
//            if let uidx = target.document.glyphs.firstIndex(where: { $0.id == before.id }) {
//                target.document.glyphs[uidx] = before
//                target.objectWillChange.send()
//            }
//        }
//        undoManager?.setActionName("Crop to Content")
//    }
    
    
    func cropSelectedGlyphToContent(undoManager: UndoManager?) {
        guard let idx = document.glyphs.firstIndex(where: { $0.id == selectedGlyphID }) else { return }
        let before = document.glyphs[idx]
        let g = before

        let h = g.height
        let w = g.width
        guard h > 0, w > 0 else { return }

        // 1) Find content bounding box
        var minRow = h, maxRow = -1
        var minCol = w, maxCol = -1

        for r in 0..<h {
            for c in 0..<w {
                if g.pixels[r][c] {
                    if r < minRow { minRow = r }
                    if r > maxRow { maxRow = r }
                    if c < minCol { minCol = c }
                    if c > maxCol { maxCol = c }
                }
            }
        }

        // 2) Compute minimum reference frame (same logic as Crop to Frame)
        let baseW = document.glyphWidth
        let baseH = document.glyphHeight

        let frameW = max(1, baseW + g.advanceWidthOffset)
        let frameH = max(1, min(baseH, g.height))

        let frameMinCol = max(0, g.viewOffsetX)
        let frameMinRow = max(0, g.viewOffsetY)
        let frameMaxCol = min(g.width - 1, frameMinCol + frameW - 1)
        let frameMaxRow = min(g.height - 1, frameMinRow + frameH - 1)

        // Helper to apply + commit undo (keeps the function readable)
        func commit(_ cropped: Glyph, actionName: String) {
            document.glyphs[idx] = cropped
            objectWillChange.send()

            undoManager?.registerUndo(withTarget: self) { target in
                if let uidx = target.document.glyphs.firstIndex(where: { $0.id == before.id }) {
                    target.document.glyphs[uidx] = before
                    target.objectWillChange.send()
                }
            }
            undoManager?.setActionName(actionName)
        }

        // 3) If no pixels are on, keep an empty glyph AT LEAST the frame size
        if maxRow < 0 || maxCol < 0 {
            var cropped = g
            cropped.pixels = Array(repeating: Array(repeating: false, count: frameW), count: frameH)
            cropped.viewOffsetX = 0
            cropped.viewOffsetY = 0
            commit(cropped, actionName: "Crop to Content")
            return
        }

        // 4) Union(content bbox, frame bbox) so crop can't go smaller than the frame
        if frameMinCol <= frameMaxCol && frameMinRow <= frameMaxRow {
            minCol = min(minCol, frameMinCol)
            minRow = min(minRow, frameMinRow)
            maxCol = max(maxCol, frameMaxCol)
            maxRow = max(maxRow, frameMaxRow)
        }

        // Clamp bbox to valid bounds (extra safety)
        minCol = max(0, minCol)
        minRow = max(0, minRow)
        maxCol = min(w - 1, maxCol)
        maxRow = min(h - 1, maxRow)

        // 5) Build cropped bitmap
        let newH = maxRow - minRow + 1
        let newW = maxCol - minCol + 1
        guard newH > 0, newW > 0 else { return }

        var newPixels: [[Bool]] = Array(
            repeating: Array(repeating: false, count: newW),
            count: newH
        )

        for r in 0..<newH {
            for c in 0..<newW {
                newPixels[r][c] = g.pixels[minRow + r][minCol + c]
            }
        }

        // 6) Preserve frame placement: shift offsets by cropped amount
        let oldOffX = g.viewOffsetX
        let oldOffY = g.viewOffsetY
        var newOffX = max(0, oldOffX - minCol)
        var newOffY = max(0, oldOffY - minRow)

        // 7) Clamp offsets so the visible window stays within bounds
        let visibleW = max(1, document.glyphWidth + g.advanceWidthOffset)
        let visibleH = max(1, document.glyphHeight)

        let maxStartX = max(0, (newPixels.first?.count ?? 0) - visibleW)
        let maxStartY = max(0, newPixels.count - visibleH)

        if newOffX > maxStartX { newOffX = maxStartX }
        if newOffY > maxStartY { newOffY = maxStartY }

        var cropped = g
        cropped.pixels = newPixels
        cropped.viewOffsetX = newOffX
        cropped.viewOffsetY = newOffY

        commit(cropped, actionName: "Crop to Content")
    }
    
    
    
}



// MARK: - Image Import -> Glyph pixels

// MARK: - NSImage helpers
private extension NSImage {
    func toBitmapRep() -> NSBitmapImageRep? {
        let rect = CGRect(origin: .zero, size: size)
        guard let rep = NSBitmapImageRep(
            bitmapDataPlanes: nil,
            pixelsWide: Int(size.width),
            pixelsHigh: Int(size.height),
            bitsPerSample: 8,
            samplesPerPixel: 4,
            hasAlpha: true,
            isPlanar: false,
            colorSpaceName: .deviceRGB,
            bytesPerRow: 0,
            bitsPerPixel: 0
        ) else { return nil }
        NSGraphicsContext.saveGraphicsState()
        if let ctx = NSGraphicsContext(bitmapImageRep: rep) {
            NSGraphicsContext.current = ctx
            NSColor.clear.set()
            ctx.cgContext.fill(rect)
            self.draw(in: rect)
            NSGraphicsContext.restoreGraphicsState()
            return rep
        }
        NSGraphicsContext.restoreGraphicsState()
        return nil
    }
}

private extension NSBitmapImageRep {
    
    func resizedAspectFit(
        to targetSize: NSSize,
        background: NSColor = NSColor.white,
        margin: CGFloat
    ) -> NSBitmapImageRep {
        let targetW = Int(targetSize.width)
        let targetH = Int(targetSize.height)
        guard targetW > 0, targetH > 0 else { return self }
        guard let srcCG = self.cgImage else { return self }

        // Compute usable area with symmetric margins (left/right, top/bottom)
        let clampedMargin = max(0, min(margin, 0.45))
        let usableWidth = targetSize.width * max(0, 1 - 2 * clampedMargin)
        let usableHeight = targetSize.height * max(0, 1 - 2 * clampedMargin)

        let srcW = CGFloat(self.pixelsWide)
        let srcH = CGFloat(self.pixelsHigh)
        let scale = min(usableWidth / srcW, usableHeight / srcH)
        let renderW = srcW * scale
        let renderH = srcH * scale
        let offsetX = (targetSize.width - renderW) * 0.5
        let offsetY = (targetSize.height - renderH) * 0.5

        guard let ctx = CGContext(
            data: nil,
            width: targetW,
            height: targetH,
            bitsPerComponent: 8,
            bytesPerRow: 0,
            space: CGColorSpaceCreateDeviceRGB(),
            bitmapInfo: CGImageAlphaInfo.premultipliedLast.rawValue
        ) else { return self }

        ctx.interpolationQuality = .high
        ctx.setFillColor(background.cgColor)
        ctx.fill(CGRect(x: 0, y: 0, width: targetSize.width, height: targetSize.height))
        ctx.draw(srcCG, in: CGRect(x: offsetX, y: offsetY, width: renderW, height: renderH))

        guard let scaled = ctx.makeImage() else { return self }
        return NSBitmapImageRep(cgImage: scaled)
    }

    func grayscaleAt(x: Int, y: Int) -> CGFloat {
        guard x >= 0, y >= 0, x < pixelsWide, y < pixelsHigh else { return 1.0 }
        let color = colorAt(x: x, y: y) ?? .white
        // Convert to luminance
        let r = CGFloat(color.redComponent)
        let g = CGFloat(color.greenComponent)
        let b = CGFloat(color.blueComponent)
        // Rec. 709 luma
        return 0.2126 * r + 0.7152 * g + 0.0722 * b
    }
}




extension Character {
    
    
    func incrementedCharacter() -> Character {
        if let ascii = self.asciiValue {
            switch ascii {
            case 48...57: // '0'...'9'
                return Character(UnicodeScalar(ascii == 57 ? 48 : ascii + 1))
            case 65...90: // 'A'...'Z'
                return Character(UnicodeScalar(ascii == 90 ? 65 : ascii + 1))
            case 97...122: // 'a'...'z'
                return Character(UnicodeScalar(ascii == 122 ? 97 : ascii + 1))
            default:
                return self
            }
        }
        return self
    }
    
    
}


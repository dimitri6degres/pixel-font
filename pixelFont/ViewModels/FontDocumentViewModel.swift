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
    
    
    func exportC() -> String {
        var copy = document
        if let base = exportBaseName, !base.isEmpty {
            copy.name = base
        }
        return copy.exportC(options: exportOptions)
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
        
        let baseW = document.glyphWidth
        let offset = document.glyphs[index].advanceWidthOffset
        let horzLimit = max(1, min(100, baseW + offset))
        let vertLimit = max(1, min(100, document.glyphHeight))
        
        guard row < vertLimit, column < horzLimit else { return }
        
        // Ensure vertical size (rows)
        if row >= document.glyphs[index].height {
            let currentHeight = document.glyphs[index].height
            let neededHeight = min(row + 1, vertLimit)
            if neededHeight > currentHeight {
                let currentRowWidth = document.glyphs[index].width
                let rowsToAdd = neededHeight - currentHeight
                let emptyRow = Array(repeating: false, count: currentRowWidth)
                document.glyphs[index].pixels.append(contentsOf: Array(repeating: emptyRow, count: rowsToAdd))
            }
        }
        
        let neededW = min(max(column + 1, document.glyphs[index].width), horzLimit)
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

        // Rotation 90° horaire: (r, c) -> (c, H-1-r)
        let oldH = g.height, oldW = g.width
        var rotated = Array(repeating: Array(repeating: false, count: oldH), count: oldW)
        for r in 0..<oldH {
            for c in 0..<oldW {
                rotated[c][oldH - 1 - r] = g.pixels[r][c]
            }
        }

        // Préserver tous les pixels: ajuster le canevas du glyphe si nécessaire (sans toucher aux dimensions globales)
        // Ici, on remplace simplement la matrice de pixels par la version pivotée (W' = oldH, H' = oldW)
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

        // Rotation 90° anti-horaire: (r, c) -> (W-1-c, r)
        let oldH = g.height, oldW = g.width
        var rotated = Array(repeating: Array(repeating: false, count: oldH), count: oldW)
        for r in 0..<oldH {
            for c in 0..<oldW {
                rotated[oldW - 1 - c][r] = g.pixels[r][c]
            }
        }

        // Préserver tous les pixels: on adopte la matrice pivotée telle quelle
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
    
    func exportAdafruitGFX(fontName rawName: String) -> String {
        // Sanitize name for C identifier
        let cleaned = rawName.replacingOccurrences(of: " ", with: "_")
        let parts = cleaned.components(separatedBy: CharacterSet.alphanumerics.inverted).filter { !$0.isEmpty }
        var cName = parts.joined(separator: "_")
        if cName.isEmpty { cName = "MyFont" }
        if let first = cName.first, first.isNumber { cName = "_" + cName }
        
        // Build ascii -> glyph map
        var map: [UInt8: Glyph] = [:]
        for g in document.glyphs {
            if let a = g.character?.asciiValue { map[a] = g }
        }
        
        // Determine character range (continuous for Adafruit GFX)
        let keys = map.keys
        let firstChar: UInt8 = keys.min() ?? 0x20
        let lastChar: UInt8  = keys.max() ?? 0x7E
        
        let w = document.glyphWidth
        let h = document.glyphHeight
        
        // Prepare bitmap data and glyph table
        var bitmapBytes: [UInt8] = []
        struct G { var offset:Int; var w:Int; var h:Int; var xAdv:Int; var xOff:Int; var yOff:Int; var code: UInt8; var present: Bool }
        var glyphTable: [G] = []
        
        for code in firstChar...lastChar {
            let present = map[code] != nil
            let g = map[code] ?? Glyph.empty(width: w, height: h, character: nil)
            let xAdvance = max(1, min(255, w + g.advanceWidthOffset))
            let xOffset = 0
            let yOffset = -(h - 1)
            let startOffset = bitmapBytes.count
            
            // Pack bits MSB-first, row-major
            var bitAccumulator: UInt8 = 0
            var bitCount = 0
            for row in 0..<h {
                for col in 0..<w {
                    let on = (row < g.pixels.count && col < g.pixels[row].count) ? g.pixels[row][col] : false
                    bitAccumulator <<= 1
                    if on { bitAccumulator |= 1 }
                    bitCount += 1
                    if bitCount == 8 {
                        bitmapBytes.append(bitAccumulator)
                        bitAccumulator = 0
                        bitCount = 0
                    }
                }
            }
            if bitCount > 0 {
                bitAccumulator <<= (8 - bitCount)
                bitmapBytes.append(bitAccumulator)
            }
            
            glyphTable.append(G(offset: startOffset, w: w, h: h, xAdv: xAdvance, xOff: xOffset, yOff: yOffset, code: code, present: present))
        }
        
        // Format arrays
        func formatBytes(_ bytes: [UInt8], perLine: Int = 12) -> String {
            var lines: [String] = []
            var i = 0
            while i < bytes.count {
                let end = min(i + perLine, bytes.count)
                let slice = bytes[i..<end].map { String(format: "0x%02X", $0) }.joined(separator: ", ")
                lines.append("    " + slice + (end < bytes.count ? "," : ""))
                i = end
            }
            return lines.joined(separator: "\n")
        }
        
        var glyphLines: [String] = []
        for (index, g) in glyphTable.enumerated() {
            let ch: String
            if g.present {
                let scalar = UnicodeScalar(g.code)
                if g.code >= 0x20 && g.code <= 0x7E {
                    ch = "'\(Character(scalar))'"
                } else {
                    ch = "<0x\(String(format: "%02X", g.code))>"
                }
            } else {
                ch = "<unknown>"
            }
            let comment = "// \(ch) (0x\(String(format: "%02X", g.code)))"
            let entry = String(format: "    {%d, %d, %d, %d, %d, %d}%@ \(comment)",
                               g.offset, g.w, g.h, g.xAdv, g.xOff, g.yOff,
                               index < glyphTable.count - 1 ? "," : "")
            glyphLines.append(entry)
        }
        
        let header = """
#pragma once
#include <Adafruit_GFX.h>

const uint8_t \(cName)Bitmaps[] PROGMEM = {
\(formatBytes(bitmapBytes))
};

const GFXglyph \(cName)Glyphs[] PROGMEM = {
\(glyphLines.joined(separator: "\n"))
};

const GFXfont \(cName) PROGMEM = {
  (uint8_t*)\(cName)Bitmaps,
  (GFXglyph*)\(cName)Glyphs,
  0x\(String(format: "%02X", firstChar)),
  0x\(String(format: "%02X", lastChar)),
  \(h)
};
"""
        return header
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


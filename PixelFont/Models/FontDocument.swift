import Foundation

extension Notification.Name {
    static let fontDocumentFoundDuplicateCharacters = Notification.Name("FontDocumentFoundDuplicateCharacters")
}

struct FontDocumentDuplicateInfo {
    static let codesKey = "codes" // [UInt32]
}

struct FontDocument: Identifiable, Equatable {
    let id: UUID
    var name: String
    var glyphWidth: Int
    var glyphHeight: Int
    var glyphs: [Glyph]
    var baseline: Int

    init(id: UUID = UUID(), name: String, glyphWidth: Int, glyphHeight: Int, glyphs: [Glyph]) {
        self.id = id
        self.name = name
        self.glyphWidth = glyphWidth
        self.glyphHeight = glyphHeight
        self.glyphs = glyphs
        self.baseline = max(0, glyphHeight)
    }
    
    init(id: UUID = UUID(), name: String, glyphWidth: Int, glyphHeight: Int, glyphs: [Glyph], baseline: Int) {
        self.id = id
        self.name = name
        self.glyphWidth = glyphWidth
        self.glyphHeight = glyphHeight
        self.glyphs = glyphs
        self.baseline = max(0, min(glyphHeight, baseline))
    }
    
    // Adafruit GFX export ordering: printable ASCII 0x20 (space) to 0x7E (~)
    static let adafruitPrintableScalars: [UnicodeScalar] = (0x20...0x7E).compactMap { UnicodeScalar($0) }
    static let adafruitPrintableChars: [Character] = adafruitPrintableScalars.map(Character.init)

    static var adafruitFirstChar: Character { adafruitPrintableChars.first ?? " " }

    static func adafruitNextChar(after ch: Character) -> Character? {
        guard let idx = adafruitPrintableChars.firstIndex(of: ch) else { return nil }
        let nextIndex = adafruitPrintableChars.index(after: idx)
        return nextIndex < adafruitPrintableChars.endIndex ? adafruitPrintableChars[nextIndex] : nil
    }

    static func sample() -> FontDocument {
        var glyphs: [Glyph] = []
        let first = adafruitFirstChar
        glyphs.append(Glyph(character: first, width: 14, height: 22))
        return FontDocument(name: "Sample", glyphWidth: 14, glyphHeight: 22, glyphs: glyphs, baseline: 20)
    }
}

extension FontDocument: Codable {
    private enum CodingKeys: String, CodingKey {
        case id, name, glyphWidth, glyphHeight, glyphs, baseline
    }

    init(from decoder: Decoder) throws {
        let container = try decoder.container(keyedBy: CodingKeys.self)
        self.id = try container.decode(UUID.self, forKey: .id)
        self.name = try container.decode(String.self, forKey: .name)
        self.glyphWidth = try container.decode(Int.self, forKey: .glyphWidth)
        self.glyphHeight = try container.decode(Int.self, forKey: .glyphHeight)
        self.glyphs = try container.decode([Glyph].self, forKey: .glyphs)
        // Baseline: default for legacy files missing this key
        if let decodedBaseline = try container.decodeIfPresent(Int.self, forKey: .baseline) {
            self.baseline = max(0, min(glyphHeight, decodedBaseline))
        } else {
            self.baseline = max(0, glyphHeight)
        }
    }

    func encode(to encoder: Encoder) throws {
        var container = encoder.container(keyedBy: CodingKeys.self)
        try container.encode(id, forKey: .id)
        try container.encode(name, forKey: .name)
        try container.encode(glyphWidth, forKey: .glyphWidth)
        try container.encode(glyphHeight, forKey: .glyphHeight)
        try container.encode(glyphs, forKey: .glyphs)
        try container.encode(baseline, forKey: .baseline)
    }
}

struct ExportOptions: Codable {
    var msbFirst: Bool = true
    var invertBits: Bool = false
    var includeLineSpacing: Bool = true
    var tabSize: Int = 4
    var usePROGMEM: Bool = true
    var cropGlyphs: Bool = true
}

extension Glyph {
    func toBytes(msbFirst: Bool, invert: Bool) -> [UInt8] {
        let bits = pixels.flatMap { $0 }
        var bytes: [UInt8] = []
        var index = 0

        while index < bits.count {
            var value: UInt8 = 0
            for bitPosition in 0..<8 {
                guard index < bits.count else { break }
                let bit = bits[index] != invert
                if msbFirst {
                    value |= bit ? 1 << (7 - bitPosition) : 0
                } else {
                    value |= bit ? 1 << bitPosition : 0
                }
                index += 1
            }
            bytes.append(value)
        }

        return bytes
    }
}

extension FontDocument {
    // Returns the set of Unicode scalar values that appear more than once among glyphs with a character.
    func duplicateCharacterCodes() -> Set<UInt32> {
        var seen: Set<UInt32> = []
        var duplicates: Set<UInt32> = []
        for g in glyphs {
            guard let scalar = g.character?.unicodeScalars.first else { continue }
            let v = scalar.value
            if !seen.insert(v).inserted {
                duplicates.insert(v)
            }
        }
        return duplicates
    }

    // Returns the set of duplicate Characters (if representable) for convenience in UI.
    func duplicateCharacters() -> [Character] {
        duplicateCharacterCodes().compactMap { UnicodeScalar($0) }.map(Character.init)
    }

    // Indicates if a given glyph (by its Character) is duplicate.
    func isDuplicate(_ ch: Character) -> Bool {
        guard let code = ch.unicodeScalars.first?.value else { return false }
        return duplicateCharacterCodes().contains(code)
    }

    // Posts a Notification if duplicate characters are present.
    func notifyDuplicatesIfNeeded() {
        let dup = duplicateCharacterCodes()
        guard !dup.isEmpty else { return }
        NotificationCenter.default.post(name: .fontDocumentFoundDuplicateCharacters,
                                        object: self,
                                        userInfo: [FontDocumentDuplicateInfo.codesKey: Array(dup)])
    }

    func exportAdafruitGFX(fontName rawName: String, options: ExportOptions = ExportOptions()) -> String {
        let document = self

        // Helper to normalize C identifier
        func cIdentifier(from name: String) -> String {
            let allowed = name.unicodeScalars.map { ch -> Character in
                if CharacterSet.alphanumerics.contains(ch) { return Character(ch) }
                return "_"
            }
            var s = String(allowed)
            if let first = s.unicodeScalars.first, CharacterSet.decimalDigits.contains(first) {
                s = "_" + s
            }
            if s.isEmpty { s = "font" }
            return s
        }

        let nameC = cIdentifier(from: rawName)

        let tab = String(repeating: " ", count: options.tabSize)
        let dateString: String = {
            let f = DateFormatter()
            f.dateFormat = "dd-MM-yyyy HH:mm:ss"
            return f.string(from: Date())
        }()

        // Collect only drawn glyphs (with a character)
        let presentGlyphs = document.glyphs.compactMap { g -> (UInt32, Glyph)? in
            guard let scalar = g.character?.unicodeScalars.first else { return nil }
            return (scalar.value, g)
        }.sorted { $0.0 < $1.0 }

        // Determine first and last char code
        let firstChar = presentGlyphs.map { $0.0 }.min() ?? 0x20
        let lastChar = presentGlyphs.map { $0.0 }.max() ?? 0x7E

        let duplicateCodes: Set<UInt32> = self.duplicateCharacterCodes()
        let duplicateComments: [String] = duplicateCodes.sorted().map { code in
            if let scalar = UnicodeScalar(code), scalar.isASCII, code >= 0x20, code <= 0x7E {
                return "'\(Character(scalar))' (0x\(String(format: "%02X", code)))"
            } else {
                return "0x\(String(format: "%02X", code))"
            }
        }
        // Notify observers (e.g., UI) that duplicates exist, so they can present an alert.
        if !duplicateCodes.isEmpty {
            NotificationCenter.default.post(name: .fontDocumentFoundDuplicateCharacters,
                                            object: self,
                                            userInfo: [FontDocumentDuplicateInfo.codesKey: Array(duplicateCodes)])
        }

        // Create dictionary for quick lookup
        let glyphMap: [UInt32: Glyph] = Dictionary(presentGlyphs, uniquingKeysWith: { first, _ in first })

        struct G {
            let code: UInt32
            let bitmapOffset: Int
            let width: Int
            let height: Int
            let xAdvance: Int
            let xOffset: Int
            let yOffset: Int
        }

        var glyphs: [G] = []
        var bitmapData: [UInt8] = []

        for code in firstChar...lastChar {
            if let g = glyphMap[code] {
                let w = document.glyphWidth
                let h = document.glyphHeight

                let xAdvance = max(1, min(255, w + g.advanceWidthOffset))
                let startCol = max(0, g.viewOffsetX)
                let startRow = max(0, g.viewOffsetY)
                let frameW = max(1, min(255, w + g.advanceWidthOffset))
                let frameH = max(1, min(255, min(g.height, h)))

                // Full glyph pixel matrix boundaries
                let fullMinCol = 0
                let fullMaxCol = g.width
                let fullMinRow = 0
                let fullMaxRow = g.height

                // Base frame boundaries (window frame)
                let frameMinCol = startCol
                let frameMaxCol = startCol + frameW
                let frameMinRow = startRow
                let frameMaxRow = startRow + frameH

                // Crop rectangle to be computed
                var cropMinCol = frameMinCol
                var cropMaxCol = frameMaxCol
                var cropMinRow = frameMinRow
                var cropMaxRow = frameMaxRow

                if options.cropGlyphs {
                    // Find tightest bounding box containing any "on" pixel inside the full glyph pixel matrix
                    var found = false
                    var minCol = fullMaxCol
                    var maxCol = fullMinCol
                    var minRow = fullMaxRow
                    var maxRow = fullMinRow

                    for row in fullMinRow..<fullMaxRow {
                        for col in fullMinCol..<fullMaxCol {
                            if row < g.height && col < g.width && g.pixels[row][col] {
                                if !found {
                                    minCol = col
                                    maxCol = col
                                    minRow = row
                                    maxRow = row
                                    found = true
                                } else {
                                    if col < minCol { minCol = col }
                                    if col > maxCol { maxCol = col }
                                    if row < minRow { minRow = row }
                                    if row > maxRow { maxRow = row }
                                }
                            }
                        }
                    }
                    if found {
                        cropMinCol = minCol
                        cropMaxCol = maxCol + 1
                        cropMinRow = minRow
                        cropMaxRow = maxRow + 1
                    } else {
                        // No "on" pixel found - fallback to 1x1 empty bbox at original frame origin
                        cropMinCol = startCol
                        cropMaxCol = startCol + 1
                        cropMinRow = startRow
                        cropMaxRow = startRow + 1
                    }
                } else {
                    // Crop OFF: strictly crop to the window frame (base frame + advance)
                    cropMinCol = frameMinCol
                    cropMaxCol = frameMaxCol
                    cropMinRow = frameMinRow
                    cropMaxRow = frameMaxRow
                }

                let cropWidth = cropMaxCol - cropMinCol
                let cropHeight = cropMaxRow - cropMinRow

                // Pack bitmap bits MSB-first row-major for the final bbox only
                var bits: [Bool] = []
                for row in cropMinRow..<cropMaxRow {
                    for col in cropMinCol..<cropMaxCol {
                        let on = (row < g.height && col < g.width) ? g.pixels[row][col] : false
                        bits.append(on != options.invertBits)
                    }
                }

                var bytes: [UInt8] = []
                var bitIndex = 0
                while bitIndex < bits.count {
                    var value: UInt8 = 0
                    for bitPos in 0..<8 {
                        if bitIndex >= bits.count { break }
                        if bits[bitIndex] {
                            value |= 1 << (7 - bitPos)
                        }
                        bitIndex += 1
                    }
                    bytes.append(value)
                }

                let bitmapOffset = bitmapData.count
                bitmapData.append(contentsOf: bytes)

                // Compute Adafruit GFX metrics consistent with preview:
                let xOff = cropMinCol - startCol
                let yOff = (-document.baseline) + (cropMinRow - startRow)

                glyphs.append(G(code: code, bitmapOffset: bitmapOffset, width: cropWidth, height: cropHeight, xAdvance: xAdvance, xOffset: xOff, yOffset: yOff))
            } else {
                // Missing glyph: empty glyph entry, no bitmap bytes appended
                let bitmapOffset = bitmapData.count
                let xAdvance = max(1, min(255, document.glyphWidth))
                glyphs.append(G(code: code, bitmapOffset: bitmapOffset, width: 0, height: 0, xAdvance: xAdvance, xOffset: 0, yOffset: 0))
            }
        }

        var out: [String] = []

        out.append("// \(nameC)")
        out.append("// Font Size: \(document.glyphWidth)x\(document.glyphHeight)px")
        out.append("// Created: \(dateString)")
        out.append("")
        out.append("#include <Arduino.h>")
        out.append("#include <Adafruit_GFX.h>")
        out.append("")
        if !duplicateCodes.isEmpty {
            out.append("// WARNING: Duplicate character definitions detected for: ")
            out.append("//   " + duplicateComments.joined(separator: ", "))
            out.append("")
        }
        let progmem = options.usePROGMEM ? " PROGMEM" : ""

        // Bitmap array
        out.append("const uint8_t \(nameC)_bitmap[]\(progmem) = {")
        let bytesPerLine = 16
        var line: [String] = []
        for (i, b) in bitmapData.enumerated() {
            line.append(String(format: "0x%02X", b))
            if line.count == bytesPerLine || i == bitmapData.count - 1 {
                out.append(tab + line.joined(separator: ",") + ",")
                line.removeAll()
            }
        }
        out.append("};")
        out.append("")

        // Glyph array
        out.append("const GFXglyph \(nameC)_glyphs[]\(progmem) = {")
        for g in glyphs {
            // Emit glyph struct with readable character comment:
            // bitmapOffset, width, height, xAdvance, xOffset, yOffset
            let charComment: String
            if let scalar = UnicodeScalar(g.code), scalar.isASCII && scalar.value >= 0x20 && scalar.value <= 0x7E {
                charComment = "'\(Character(scalar))' (0x\(String(format: "%02X", g.code)))"
            } else {
                charComment = "<0x\(String(format: "%02X", g.code))>"
            }
            let dupMark = duplicateCodes.contains(g.code) ? " [DUP]" : ""
            out.append(String(format: "\(tab){ %d, %d, %d, %d, %d, %d }, // %@%@", g.bitmapOffset, g.width, g.height, g.xAdvance, g.xOffset, g.yOffset, charComment, dupMark))
        }
        out.append("};")
        out.append("")

        // Font structure
        out.append("const GFXfont \(nameC) PROGMEM = {")
        out.append(tab + "(uint8_t*)\(nameC)_bitmap,")
        out.append(tab + "(GFXglyph*)\(nameC)_glyphs,")
        out.append(tab + "0x\(String(format: "%02X", firstChar)), 0x\(String(format: "%02X", lastChar)), \(document.glyphHeight)")
        out.append("};")
        out.append("")

        return out.joined(separator: "\n")
    }
}

private struct SeededGenerator: RandomNumberGenerator {
    private var state: UInt64

    init(seed: UInt64) {
        state = seed == 0 ? 0xCAFEBABE : seed
    }

    mutating func next() -> UInt64 {
        state ^= state << 7
        state ^= state >> 9
        state ^= 0x9E3779B97F4A7C15
        return state
    }
}


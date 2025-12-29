import Foundation

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
        self.baseline = max(0, glyphHeight - 2)
    }
    
    init(id: UUID = UUID(), name: String, glyphWidth: Int, glyphHeight: Int, glyphs: [Glyph], baseline: Int) {
        self.id = id
        self.name = name
        self.glyphWidth = glyphWidth
        self.glyphHeight = glyphHeight
        self.glyphs = glyphs
        self.baseline = max(0, min(glyphHeight - 1, baseline))
    }

    static func sample() -> FontDocument {
        var glyphs: [Glyph] = []
        glyphs.append(Glyph(character: "0", width: 14, height: 22))
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
            self.baseline = max(0, min(glyphHeight - 1, decodedBaseline))
        } else {
            self.baseline = max(0, glyphHeight - 2)
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
    func exportC(options: ExportOptions) -> String {
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

        let tab = String(repeating: " ", count: options.tabSize)
        let nameC = cIdentifier(from: name)
        let dateString: String = {
            let f = DateFormatter()
            f.dateFormat = "dd-MM-yyyy HH:mm:ss"
            return f.string(from: Date())
        }()

        // Collect only drawn glyphs (with a character)
        let presentGlyphs = glyphs.compactMap { g -> (UInt32, Glyph)? in
            guard let scalar = g.character?.unicodeScalars.first else { return nil }
            return (scalar.value, g)
        }.sorted { $0.0 < $1.0 }

        // Precompute bytes per glyph using current options
        func bytes(for glyph: Glyph) -> [UInt8] {
            glyph.toBytes(msbFirst: options.msbFirst, invert: options.invertBits)
        }

        // Build arrays
        var dataBytes: [UInt8] = []
        var offsets: [UInt16] = []
        var chars: [UInt8] = []
        var advances: [UInt8] = []

        for (code, g) in presentGlyphs {
            let offset = UInt16(dataBytes.count & 0xFFFF)
            offsets.append(offset)
            chars.append(UInt8(code & 0xFF))
            let adv = max(0, min(255, glyphWidth + g.advanceWidthOffset))
            advances.append(UInt8(adv))
            let b = bytes(for: g)
            dataBytes.append(contentsOf: b)
        }

        // Header
        var out: [String] = []
        out.append("// \(nameC)")
        out.append("// Font Size: \(glyphWidth)x\(glyphHeight)px")
        out.append("// Created: \(dateString)")
        out.append("//")
        out.append("")
        out.append("#include <Arduino.h>")
        out.append("")

        // Metadata constants
        out.append("const uint8_t \(nameC)_width = \(glyphWidth);")
        out.append("const uint8_t \(nameC)_height = \(glyphHeight);")
        out.append("const uint8_t \(nameC)_count = \(chars.count);")
        out.append("const uint8_t \(nameC)_baseline = \(max(0, min(255, baseline)));")
        out.append("")

        // Data array
        let progmem = options.usePROGMEM ? " PROGMEM" : ""
        out.append("const uint8_t \(nameC)[]\(progmem) = {")

        // Emit bytes in lines of 16
        let bytesPerLine = 16
        var line: [String] = []
        for (i, byte) in dataBytes.enumerated() {
            line.append(String(format: "0x%02X", byte))
            if line.count == bytesPerLine || i == dataBytes.count - 1 {
                out.append("\(tab)" + line.joined(separator: "," ) + ",")
                line.removeAll()
            }
        }
        out.append("};")
        out.append("")

        // Offsets
        out.append("const uint16_t \(nameC)_offsets[]\(progmem) = {")
        for (i, off) in offsets.enumerated() {
            let code = presentGlyphs[i].0
            let ch: String = {
                if let s = UnicodeScalar(code) { return String(Character(s)) } else { return "?" }
            }()
            out.append("\(tab)\(off), // Character 0x\(String(format: "%02X", code)) (\(code): '\(ch)')")
        }
        out.append("};")
        out.append("")

        // Chars
        out.append("const uint8_t \(nameC)_chars[]\(progmem) = {")
        var charLine: [String] = []
        for (i, c) in chars.enumerated() {
            charLine.append(String(format: "0x%02X", c))
            if charLine.count == bytesPerLine || i == chars.count - 1 {
                out.append("\(tab)" + charLine.joined(separator: "," ) + ",")
                charLine.removeAll()
            }
        }
        out.append("};")

        out.append("")
        out.append("const uint8_t \(nameC)_advances[]\(progmem) = {")
        var advLine: [String] = []
        for (i, a) in advances.enumerated() {
            advLine.append(String(format: "0x%02X", a))
            if advLine.count == bytesPerLine || i == advances.count - 1 {
                out.append("\(tab)" + advLine.joined(separator: "," ) + ",")
                advLine.removeAll()
            }
        }
        out.append("};")

        out.append("")
        out.append("// Helper usage (example):")
        out.append("//")
        out.append("// - Find glyph index by ASCII code")
        out.append("// - Read offset from \(nameC)_offsets")
        out.append("// - Read \(nameC)_width and \(nameC)_height")
        out.append("// - Iterate bits from \(nameC) + offset")
        out.append("//")
        out.append("/*")
        out.append("static int16_t \(nameC)_findIndex(uint8_t ascii) {")
        out.append("    for (uint8_t i = 0; i < \(nameC)_count; i++) {")
        out.append("        if (pgm_read_byte(&\(nameC)_chars[i]) == ascii) {")
        out.append("            return (int16_t)i;")
        out.append("        }")
        out.append("    }")
        out.append("    return -1;")
        out.append("}")
        out.append("")
        out.append("static uint8_t \(nameC)_advance(uint8_t ascii) {")
        out.append("    int16_t idx = \(nameC)_findIndex(ascii);")
        out.append("    if (idx < 0) return \(nameC)_width;")
        out.append("    return pgm_read_byte(&\(nameC)_advances[idx]);")
        out.append("}")
        out.append("")
        out.append("static uint16_t \(nameC)_bytesPerGlyph() {")
        out.append("    uint16_t bits = (uint16_t)\(nameC)_width * (uint16_t)\(nameC)_height;")
        out.append("    return (bits + 7) / 8;")
        out.append("}")
        out.append("")
        out.append("static bool \(nameC)_bitAt(const uint8_t* data, uint16_t bitIndex) {")
        out.append("    uint16_t byteIndex = bitIndex >> 3;")
        out.append("    uint8_t bitPos = bitIndex & 7;")
        out.append("    uint8_t b = pgm_read_byte(&data[byteIndex]);")
        out.append("    return (b >> (7 - bitPos)) & 0x01;")
        out.append("}")
        out.append("")
        out.append("static void \(nameC)_drawGlyph(uint8_t ascii, int16_t x, int16_t y, void (*putPixel)(int16_t, int16_t, bool)) {")
        out.append("    int16_t idx = \(nameC)_findIndex(ascii);")
        out.append("    if (idx < 0) return;")
        out.append("")
        out.append("    uint16_t offset = pgm_read_word(&\(nameC)_offsets[idx]);")
        out.append("    const uint8_t* data = \(nameC) + offset;")
        out.append("")
        out.append("    uint8_t W = \(nameC)_width;")
        out.append("    uint8_t H = \(nameC)_height;")
        out.append("    uint16_t totalBits = (uint16_t)W * (uint16_t)H;")
        out.append("")
        out.append("    for (uint16_t bit = 0; bit < totalBits; ++bit) {")
        out.append("        uint8_t row = bit / W;")
        out.append("        uint8_t col = bit % W;")
        out.append("        bool on = \(nameC)_bitAt(data, bit);")
        out.append("        putPixel(x + col, y + row, on);")
        out.append("    }")
        out.append("}")

        out.append("static void \(nameC)_drawText(const char* text, int16_t x, int16_t y, void (*putPixel)(int16_t, int16_t, bool)) {")
        out.append("    if (!text) return;")
        out.append("    int16_t cx = x;")
        out.append("    for (const char* p = text; *p; ++p) {")
        out.append("        uint8_t ascii = (uint8_t)*p;")
        out.append("        \(nameC)_drawGlyph(ascii, cx, y, putPixel);")
        out.append("        uint8_t adv = \(nameC)_advance(ascii);")
        out.append("        cx += adv;")
        out.append("    }")
        out.append("}")
        out.append("*/")

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


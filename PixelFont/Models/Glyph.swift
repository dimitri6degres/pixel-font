import Foundation

struct Glyph: Identifiable, Hashable, Equatable {
    let id: UUID
    var character: Character?
    var pixels: [[Bool]]
    var advanceWidthOffset: Int = 0

    init(id: UUID = UUID(), character: Character? = nil, pixels: [[Bool]], advanceWidthOffset: Int = 0) {
        self.id = id
        self.character = character
        self.pixels = pixels
        self.advanceWidthOffset = advanceWidthOffset
    }

    init(id: UUID = UUID(), character: Character? = nil, width: Int, height: Int, advanceWidthOffset: Int = 0) {
        self.id = id
        self.character = character
        self.pixels = Array(
            repeating: Array(repeating: false, count: width),
            count: height
        )
        self.advanceWidthOffset = advanceWidthOffset
    }

    static func empty(width: Int, height: Int, character: Character? = nil) -> Glyph {
        let pixels = Array(
            repeating: Array(repeating: false, count: width),
            count: height
        )
        return Glyph(character: character, pixels: pixels)
    }

    var width: Int { pixels.first?.count ?? 0 }
    var height: Int { pixels.count }
    var effectiveWidth: Int { pixels.first?.count ?? 0 }
}

extension Glyph: Codable {
    private enum CodingKeys: String, CodingKey {
        case id, character, pixels, advanceWidthOffset
    }
    init(from decoder: Decoder) throws {
        let container = try decoder.container(keyedBy: CodingKeys.self)
        self.id = try container.decode(UUID.self, forKey: .id)
        if let stringValue = try container.decodeIfPresent(String.self, forKey: .character) {
            self.character = stringValue.first
        } else {
            self.character = nil
        }
        self.pixels = try container.decode([[Bool]].self, forKey: .pixels)
        self.advanceWidthOffset = try container.decodeIfPresent(Int.self, forKey: .advanceWidthOffset) ?? 0
    }

    func encode(to encoder: Encoder) throws {
        var container = encoder.container(keyedBy: CodingKeys.self)
        try container.encode(id, forKey: .id)
        let stringValue = character.map { String($0) }
        try container.encodeIfPresent(stringValue, forKey: .character)
        try container.encode(pixels, forKey: .pixels)
        try container.encode(advanceWidthOffset, forKey: .advanceWidthOffset)
    }
}

extension Glyph {
    func resized(toWidth newWidth: Int, height newHeight: Int) -> Glyph {
        var newPixels: [[Bool]] = Array(
            repeating: Array(repeating: false, count: newWidth),
            count: newHeight
        )
        let copyHeight = max(0, min(newHeight, self.height))
        let copyWidth = max(0, min(newWidth, self.width))

        if copyHeight > 0 && copyWidth > 0 {
            for row in 0..<copyHeight {
                for col in 0..<copyWidth {
                    newPixels[row][col] = self.pixels[row][col]
                }
            }
        }

        return Glyph(id: id, character: character, pixels: newPixels)
    }
}


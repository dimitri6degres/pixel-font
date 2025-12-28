import SwiftUI
import UniformTypeIdentifiers
import Combine

extension UTType {
    static var pixelFontDocument: UTType {
        UTType(exportedAs: "gi.dimitrifontaine.pixelfont.pixf")
    }
}


final class FontFileDocument: ReferenceFileDocument, ObservableObject {
    typealias Snapshot = FontDocument

    static var readableContentTypes: [UTType] { [.pixelFontDocument] }

    @Published var model: FontDocument

    init(model: FontDocument) {
        self.model = model
    }

    convenience init() {
        self.init(model: .sample())
    }

    convenience init(configuration: ReadConfiguration) throws {
        guard let data = configuration.file.regularFileContents else {
            throw CocoaError(.fileReadCorruptFile)
        }
        let decoder = JSONDecoder()
        let decoded = try decoder.decode(FontDocument.self, from: data)
        self.init(model: decoded)
    }

    func snapshot(contentType: UTType) throws -> Snapshot {
        model
    }

    func fileWrapper(snapshot: Snapshot, configuration: WriteConfiguration) throws -> FileWrapper {
        let encoder = JSONEncoder()
        encoder.outputFormatting = [.prettyPrinted, .sortedKeys]
        let data = try encoder.encode(snapshot)
        return .init(regularFileWithContents: data)
    }
}


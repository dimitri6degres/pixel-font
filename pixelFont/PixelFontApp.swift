import SwiftUI
// Note: The document file extension and UTI are defined in FontFileDocument (UTType extension)
// and in Info.plist (Document types + Exported/Imported UTIs). Update both when changing extension.

@main
struct PixelFontApp: App {
    var body: some Scene {
        DocumentGroup(newDocument: { FontFileDocument() }) { file in
            DocumentContainer(file: file.document)
        }
    }
}
private struct DocumentContainer: View {
    @ObservedObject var file: FontFileDocument
    @StateObject private var viewModel: FontDocumentViewModel

    init(file: FontFileDocument) {
        self.file = file
        let initialVM = FontDocumentViewModel(document: file.model)
        initialVM.exportBaseName = file.model.name
        _viewModel = StateObject(wrappedValue: initialVM)
    }

    var body: some View {
        ContentView()
            .environmentObject(viewModel)
            .onChange(of: viewModel.document) { _, newValue in
                file.model = newValue
            }
            .onChange(of: viewModel.document.name) { _, newName in
                viewModel.exportBaseName = newName
            }
    }
}


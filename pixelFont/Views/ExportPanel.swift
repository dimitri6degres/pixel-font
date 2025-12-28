import SwiftUI
import AppKit

struct ExportPanel: View {
    @EnvironmentObject private var document: FontDocumentViewModel
    @State private var copiedFeedback: Bool = false
    @State private var includeGenericHelper: Bool = true
    
    var close: () -> Void
    
    
    var body: some View {
        VStack(alignment: .leading, spacing: 10) {
            HStack {
                
                Button("close", systemImage: "xmark", action: close)
               
                Spacer()
                
                Text("Export")
                    .font(.headline)
                Spacer()
                
                Button {
                    copyToPasteboard()
                } label: {
                    Label(copiedFeedback ? "Copied!" : "Copy", systemImage: "doc.on.doc")
                        // .labelStyle(.iconOnly)
                }
                .keyboardShortcut("c", modifiers: [.command, .shift])
                .help("Copy exported code")
            }
            
            VStack(alignment: .leading, spacing: 8) {
                Text("Adafruit GFX export (MSB-first)")
                    .font(.subheadline)
                    .foregroundStyle(.secondary)
                Text("Font name: \(document.document.name)")
                Text("Glyph size: \(document.document.glyphWidth)x\(document.document.glyphHeight)")
            }
            
            TextEditor(text: .constant(exportedText))
                .font(.system(.body, design: .monospaced))
                .frame(minHeight: 220)
                .overlay(
                    RoundedRectangle(cornerRadius: 10)
                        .stroke(Color.secondary.opacity(0.2), lineWidth: 1)
                )
        }
        .padding(20)
    }
    
    private var exportedText: String {
        // Use the document's font name to build the Adafruit GFX header
        let fontName = document.document.name
        return document.exportAdafruitGFX(fontName: fontName)
    }
    
    
    private func copyToPasteboard() {
        
        let pasteboard = NSPasteboard.general
        pasteboard.clearContents()
        pasteboard.setString(exportedText, forType: .string)
        withAnimation(.easeInOut) {
            copiedFeedback = true
        }
        DispatchQueue.main.asyncAfter(deadline: .now() + 1.4) {
            withAnimation(.easeInOut) {
                copiedFeedback = false
            }
        }
        
    }
}


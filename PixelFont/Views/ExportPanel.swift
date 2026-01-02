import SwiftUI
import AppKit
import UniformTypeIdentifiers

struct ExportPanel: View {
    @EnvironmentObject private var document: FontDocumentViewModel
    @State private var copiedFeedback: Bool = false
    @State private var includeGenericHelper: Bool = true
    @State private var savedFeedback: Bool = false
    
    var close: () -> Void
    
    
    var body: some View {
        VStack(alignment: .leading, spacing: 10) {
            HStack {
                
                Button("Close", systemImage: "xmark", action: close)
               
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
                
                Button {
                    saveToFile()
                } label: {
                    Label(savedFeedback ? "Saved!" : "Save", systemImage: "externaldrive")
                }
                .keyboardShortcut("s", modifiers: [.command, .shift])
                .help("Save exported header (.h)")
   
            }
            
            VStack(alignment: .leading, spacing: 8) {
                Text("Adafruit GFX export (MSB-first)")
                    .font(.subheadline)
                    .foregroundStyle(.secondary)
                Text("Font name: \(document.document.name)")
                Text("Glyph size: \(document.document.glyphWidth)x\(document.document.glyphHeight)")
                
                HStack(spacing: 8) {
                    Image(systemName: "doc.badge.ellipsis")
                    Text("Export size: \(exportedSizeReadable) (\(exportedSizeBytes) bytes)")
                        .font(.footnote)
                        .foregroundStyle(.secondary)
                }
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
        let fontName = document.document.name
        var opts = document.exportOptions
        opts.msbFirst = true
        opts.invertBits = false
        opts.includeLineSpacing = true
        opts.usePROGMEM = true
        let final = ExportOptions(msbFirst: opts.msbFirst, invertBits: opts.invertBits, includeLineSpacing: opts.includeLineSpacing, tabSize: opts.tabSize, usePROGMEM: opts.usePROGMEM, cropGlyphs: true)
        return document.exportAdafruitGFX(fontName: fontName, options: final)
    }
    
    private var exportedSizeBytes: Int {
        exportedText.data(using: .utf8)?.count ?? 0
    }

    private var exportedSizeReadable: String {
        let bytes = Double(exportedSizeBytes)
        if bytes < 1024 { return "\(Int(bytes)) B" }
        let kb = bytes / 1024
        if kb < 1024 { return String(format: "%.1f KB", kb) }
        let mb = kb / 1024
        return String(format: "%.2f MB", mb)
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
    
    private func saveToFile() {
        let panel = NSSavePanel()
        panel.allowedContentTypes = [.cHeader]
        panel.allowsOtherFileTypes = false
        panel.canCreateDirectories = true
        let defaultName = document.exportBaseName?.isEmpty == false ? document.exportBaseName! : document.document.name
        panel.nameFieldStringValue = defaultName.replacingOccurrences(of: " ", with: "_") + ".h"
        panel.title = "Save Header"
        panel.message = "Choose a location to save the exported header (.h)"
        panel.prompt = "Save"
        if panel.runModal() == .OK, let url = panel.url {
            do {
                let data = exportedText.data(using: .utf8) ?? Data()
                try data.write(to: url, options: .atomic)
                withAnimation(.easeInOut) { savedFeedback = true }
                DispatchQueue.main.asyncAfter(deadline: .now() + 1.4) {
                    withAnimation(.easeInOut) { savedFeedback = false }
                }
            } catch {
                NSAlert(error: error).runModal()
            }
        }
    }
}


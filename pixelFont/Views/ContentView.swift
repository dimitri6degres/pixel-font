import SwiftUI
import UniformTypeIdentifiers
import Combine

struct ContentView: View {
    @EnvironmentObject private var document: FontDocumentViewModel
    @State private var newGlyphCharacter: String = ""
    @Environment(\.undoManager) private var undoManager

    @State private var showExport = false
    @State private var showImport = false
    @AppStorage("showBaseline") private var showBaseline: Bool = true
    
    var body: some View {
        NavigationSplitView {
            VStack(alignment: .leading, spacing: 12) {
                VStack(alignment: .leading, spacing: 6) {
                    Text("Font name")
                        .font(.subheadline)
                        .foregroundStyle(.secondary)
                    TextField("Font name", text: $document.document.name)
                        .textFieldStyle(.roundedBorder)
                        .padding(.bottom, 4)
                }
                VStack(alignment: .leading, spacing: 6) {
                    Text("Glyphs size")
                        .font(.subheadline)
                        .foregroundStyle(.secondary)

                    HStack(spacing: 12) {
                        HStack(spacing: 6) {
                            Stepper(
                                "W",
                                value: Binding(
                                    get: { document.document.glyphWidth },
                                    set: { document.resizeGlyphs(width: $0, height: document.document.glyphHeight, undoManager: undoManager) }
                                ),
                                in: 1...100
                            )
                            TextField(
                                "W",
                                value: Binding(
                                    get: { document.document.glyphWidth },
                                    set: { newValue in
                                        let clamped = min(max(newValue, 1), 100)
                                        if clamped != document.document.glyphWidth {
                                            document.resizeGlyphs(width: clamped, height: document.document.glyphHeight, undoManager: undoManager)
                                        }
                                    }
                                ),
                                format: .number
                            )
                            .frame(width: 48)
                            .textFieldStyle(.roundedBorder)
                            .multilineTextAlignment(.trailing)
                        }
                        HStack(spacing: 6) {
                            Stepper(
                                "H",
                                value: Binding(
                                    get: { document.document.glyphHeight },
                                    set: { document.resizeGlyphs(width: document.document.glyphWidth, height: $0, undoManager: undoManager) }
                                ),
                                in: 1...100
                            )
                            TextField(
                                "H",
                                value: Binding(
                                    get: { document.document.glyphHeight },
                                    set: { newValue in
                                        let clamped = min(max(newValue, 1), 100)
                                        if clamped != document.document.glyphHeight {
                                            document.resizeGlyphs(width: document.document.glyphWidth, height: clamped, undoManager: undoManager)
                                        }
                                    }
                                ),
                                format: .number
                            )
                            .frame(width: 48)
                            .textFieldStyle(.roundedBorder)
                            .multilineTextAlignment(.trailing)
                        }
                    }
                    .help("Changer la taille redimensionne tous les glyphes (remplit de faux si on agrandit, tronque si on réduit).")
                }
                
                Divider()
                
          
                List(selection: $document.selectedGlyphID) {
                    ForEach(document.document.glyphs) { glyph in
                        GlyphRow(glyph: glyph)
                            .tag(glyph.id)
                            .onTapGesture { document.select(glyph) }
                        
                        
                            .swipeActions(edge: .trailing, allowsFullSwipe: true) {
                                Button {
                                    document.duplicateSelectedGlyph(selectedID: glyph.id, undoManager: undoManager)
                                } label: {
                                    Image(systemName: "document.on.document")
                                }
                            }
                            .swipeActions(edge: .trailing, allowsFullSwipe: true) {
                                Button {
                                    document.resetGlyph(selectedID: glyph.id, undoManager: undoManager)
                                } label: {
                                    Image(systemName: "eraser")
                                }
                                
                             

                            }
                            .swipeActions(edge: .trailing, allowsFullSwipe: true) {
                                Button(role: .destructive) {
                                    document.removeGlyph(selectedID: glyph.id, undoManager: undoManager)
                                } label: {
                                    Image(systemName: "trash")
                                }
                                
                            }
                        
                    }
                    .onMove(perform: document.moveGlyphs)
                    
                   
                    
          
                }
                .listStyle(.sidebar)

                HStack {
                    TextField("Add glyph (character)", text: $newGlyphCharacter)
                        .textFieldStyle(.roundedBorder)
                        .frame(minWidth: 120)
                        .onSubmit(addGlyphIfNeeded)
                    Button("Add", action: addGlyphIfNeeded)
                        .buttonStyle(.borderedProminent)
                        .disabled(newGlyphCharacter.count != 1)
                }

               
            }
            .padding()
            .frame(minWidth: 280)
        } detail: {
        
                VStack(spacing: 16) {

                    Spacer()
                    
                    GlyphCanvasView(
                        glyph: document.selectedGlyph,
                        baseWidth: document.document.glyphWidth,
                        baseHeight: document.document.glyphHeight,
                        baseline: showBaseline ? document.document.baseline : nil,
                        pixelSize: (30.0 / (  max( CGFloat(document.selectedGlyph?.height ?? 20), CGFloat(document.selectedGlyph?.width ?? 20) ))) * 22,
                        onSet: { r, c, v in document.setPixel(row: r, column: c, to: v, undoManager: undoManager) },
                        beginStroke: { undoManager?.beginUndoGrouping() },
                        endStroke: { undoManager?.endUndoGrouping() }
                    )
                    .padding(.bottom, 8)

                    
                    Spacer()
                    
                    HStack(spacing: 8) {
                        
                        Text("Char")
                        TextField(
                            "Char",
                            text: Binding(
                                get: { document.selectedGlyph?.character.map(String.init) ?? "" },
                                set: { input in
                                    let single = input.first.map(String.init) ?? ""
                                    document.renameSelectedGlyph(to: single)
                                }
                            )
                        )
                        .frame(maxWidth: 20)
                        .textFieldStyle(.roundedBorder)
                        
                        Divider()
                            .frame(height: 18)
                        
                        Button {
                            document.negativeSelectedGlyph(undoManager: undoManager)
                        } label: {
                            Image(systemName: "circle.bottomrighthalf.pattern.checkered")
                        }
                        
                        Button {
                            document.flipSelectedGlyphHorizontally(undoManager: undoManager)
                        } label: {
                            Image(systemName: "arrow.left.and.right.righttriangle.left.righttriangle.right")
                        }
                        
                        Button {
                            document.flipSelectedGlyphVertically(undoManager: undoManager)
                        } label: {
                            Image(systemName: "arrow.up.and.down.righttriangle.up.righttriangle.down")
                        }
                        
                        Button {
                            document.rotateSelectedGlyphCounterClockwise(undoManager: undoManager)
                        } label: {
                            Image(systemName: "rotate.left")
                        }
                        
                        Button {
                            document.rotateSelectedGlyphClockwise(undoManager: undoManager)
                        } label: {
                            Image(systemName: "rotate.right")
                        }
                        
                        Divider()
                            .frame(height: 18)
                        
                        HStack{
                            
                            
                            Button {
                                document.nudgeSelectedGlyphLeft(undoManager: undoManager)
                            } label: {
                                Image(systemName: "arrow.left")
                            }
                            
                            
                            VStack{
                                Button {
                                    document.nudgeSelectedGlyphUp(undoManager: undoManager)
                                } label: {
                                    Image(systemName: "arrow.up")
                                }
                              
                                
                                Button {
                                    document.nudgeSelectedGlyphDown(undoManager: undoManager)
                                } label: {
                                    Image(systemName: "arrow.down")
                                }
                            }
                            
                            Button {
                                document.nudgeSelectedGlyphRight(undoManager: undoManager)
                            } label: {
                                Image(systemName: "arrow.right")
                            }
                        }
                        
                        Divider()
                            .frame(height: 18)

                        HStack(spacing: 6) {
                            Text("Width")
                           
                            TextField(
                                "",
                                value: Binding(
                                    get: { document.selectedGlyphEffectiveWidth },
                                    set: { document.setSelectedGlyphEffectiveWidth($0, undoManager: undoManager) }
                                ),
                                format: .number
                            )
                            .frame(width: 48)
                            .textFieldStyle(.roundedBorder)
                            .multilineTextAlignment(.trailing)
                            Stepper(
                                value: Binding(
                                    get: { document.selectedGlyphEffectiveWidth },
                                    set: { document.setSelectedGlyphEffectiveWidth($0, undoManager: undoManager) }
                                ),
                                in: 1...100
                            ) { EmptyView() }
                        }
                        .help("Largeur du glyphe sélectionné par rapport à la largeur standard")
                        
                        

                        Divider()
                            .frame(height: 18)
                        
                        HStack(spacing: 6) {
                            Text("Baseline")
                            Toggle("", isOn: $showBaseline)
                                .toggleStyle(.switch)
                                .help("Afficher/Cacher la ligne de base")
                            TextField(
                                "",
                                value: Binding(
                                    get: { document.document.baseline },
                                    set: { newVal in
                                        let clamped = max(0, min(document.document.glyphHeight - 1, newVal))
                                        document.document.baseline = clamped
                                        document.objectWillChange.send()
                                    }
                                ),
                                format: .number
                            )
                            .frame(width: 48)
                            .textFieldStyle(.roundedBorder)
                            .multilineTextAlignment(.trailing)
                            Stepper(
                                value: Binding(
                                    get: { document.document.baseline },
                                    set: { newVal in
                                        let clamped = max(0, min(document.document.glyphHeight - 1, newVal))
                                        document.document.baseline = clamped
                                        document.objectWillChange.send()
                                    }
                                ),
                                in: 0...(max(0, document.document.glyphHeight - 1))
                            ) { EmptyView() }
                            
                        }
                        .help("Ligne de base (y) de la fonte")

                       
                        
                    }
                    .disabled(document.selectedGlyph == nil)
                    .help("Symétries et déplacement d’un pixel du glyphe sélectionné")
                }
                .padding()
             
                .frame(minWidth: 600, minHeight: 520)
        }
        .toolbar {
//            Button("Diagnostiquer le presse-papiers", systemImage: "doc.text.magnifyingglass") {
//                document.logPasteboardContents()
//            }
            Button("Coller et importer", systemImage: "doc.on.clipboard") {
                document.importFromPasteboard(undoManager: undoManager)
            }
            .keyboardShortcut("v", modifiers: [.command])
           
            Button("Import Image", systemImage: "photo.on.rectangle") {
                showImport.toggle()
            }
            Button("Export", systemImage: "arrow.up.doc") {
                showExport.toggle()
            }
        }
        
        .sheet(isPresented: $showExport) {
            ExportPanel { showExport.toggle() }
                .frame(minWidth: 700, minHeight: 520)
        }
        
        .sheet(isPresented: $showImport) {
            ImageImportPanel { url in
                if let url, let img = NSImage(contentsOf: url) {
                    document.importImageToSelectedGlyph(platformImage: img, undoManager: undoManager)
                }
                showImport = false
            }
            .frame(width: 420, height: 200)
        }
        
     
        .onChange(of: document.document.glyphs) {
            guard let char = document.document.glyphs.last?.character else { return }
            newGlyphCharacter = String(char.incrementedCharacter())
        }
        
        .onAppear() {
            guard let char = document.document.glyphs.last?.character else { return }
            newGlyphCharacter = String(char.incrementedCharacter())
        }
        
    }
    
    private func addGlyphIfNeeded() {
        guard let character = newGlyphCharacter.first else { return }
        document.addGlyph(from: character)
        newGlyphCharacter.removeAll()
    }
}

private struct GlyphRow: View {
    @EnvironmentObject private var document: FontDocumentViewModel
    let glyph: Glyph

    var body: some View {
        HStack {
            
            VStack(alignment: .leading) {
                Text(glyph.character.map(String.init) ?? "Custom").fontDesign(.monospaced)
//                Text("\(glyph.width)x\(glyph.height)")
                    .foregroundStyle(.secondary)
//                    .font(.footnote)
            }
            
            GlyphCanvasView(
                glyph: glyph,
                baseWidth: document.document.glyphWidth,
                baseHeight: document.document.glyphHeight,
                pixelSize: 2,
                preview: true,
                alignLeft: true,
                onSet: { _, _, _ in },
                beginStroke: { },
                endStroke: { }
            )
            .frame(width: CGFloat((glyph.width * 2 ) + 10), height: CGFloat((glyph.height * 2 ) + 10))

        }
    }
}

import AppKit
private struct ImageImportPanel: View {
    @EnvironmentObject private var document: FontDocumentViewModel
    
    var onComplete: (_ url: URL?) -> Void
    @State private var threshold: Double = 0.5
    @State private var margin: Double = 0.0

    var body: some View {
        VStack(spacing: 16) {
            Text("Importer une image en glyph")
                .font(.headline)
            Text("Choisissez une image; elle sera redimensionnée à la taille du glyphe et seuillée.")
                .font(.subheadline)
                .foregroundStyle(.secondary)
            HStack {
                Text("Seuil")
                Slider(value: $threshold, in: 0...1)
                Text(String(format: "%.2f", threshold))
                    .monospacedDigit()
            }
            .onChange(of: threshold) { document.importThreshold = threshold }
            HStack {
                Text("Margin")
                Slider(value: $margin, in: 0...0.45)
                Text(String(format: "%.2f", margin))
                    .monospacedDigit()
            }
            .onChange(of: margin) { document.importMargin = margin }
            HStack {
                Button("Choisir une image…") {
                    let panel = NSOpenPanel()
                    panel.allowedContentTypes = [.png, .jpeg, .tiff]
                    panel.allowsMultipleSelection = false
                    panel.begin { resp in
                        if resp == .OK { onComplete(panel.url) }
                    }
                }
                Button("Importer") {
                    // No-op: Import is triggered by choosing image. Keep for UX.
                }
                Button("Fermer") {
                    onComplete(nil)
                }
            }
        }
        .padding()
        .onAppear {
            threshold = document.importThreshold
            margin = document.importMargin
        }
    }
}


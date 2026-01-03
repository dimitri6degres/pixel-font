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
    @AppStorage("brushSize") private var brushSize: Int = 1
    
    @State private var widthString: String = ""
    @State private var heightString: String = ""
    
    @AppStorage("previewSample") private var previewSample: String = "0123 AaBbCc"
    @AppStorage("previewPixelSize") private var previewPixelSize: Double = 0.5
    @StateObject private var flags = ModifierFlagsMonitor()
    @AppStorage("previewTabSelection") private var previewTabSelection: Int = 0
    
    // All Adafruit printable characters (ASCII 0x20..0x7E)
    private let adafruitChars: [Character] = FontDocument.adafruitPrintableChars
    
    
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
                                text: $widthString,
                                onCommit: {
                                    if let val = Int(widthString) {
                                        let clamped = min(max(val, 1), 100)
                                        if clamped != document.document.glyphWidth {
                                            document.resizeGlyphs(width: clamped, height: document.document.glyphHeight, undoManager: undoManager)
                                        }
                                        widthString = String(clamped)
                                    } else {
                                        widthString = String(document.document.glyphWidth)
                                    }
                                }
                            )
                            .frame(width: 48)
                            .textFieldStyle(.roundedBorder)
                            .multilineTextAlignment(.trailing)
                            .onChange(of: document.document.glyphWidth) { _, newVal in
                                // Keep string in sync when width changes externally (e.g., stepper)
                                widthString = String(newVal)
                            }
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
                                text: $heightString,
                                onCommit: {
                                    if let val = Int(heightString) {
                                        let clamped = min(max(val, 1), 100)
                                        if clamped != document.document.glyphHeight {
                                            document.resizeGlyphs(width: document.document.glyphWidth, height: clamped, undoManager: undoManager)
                                        }
                                        heightString = String(clamped)
                                    } else {
                                        heightString = String(document.document.glyphHeight)
                                    }
                                }
                            )
                            .frame(width: 48)
                            .textFieldStyle(.roundedBorder)
                            .multilineTextAlignment(.trailing)
                            .onChange(of: document.document.glyphHeight) { _, newVal in
                                // Keep string in sync when height changes externally (e.g., stepper)
                                heightString = String(newVal)
                            }
                        }
                    }
                    .help("Changing the size resizes all glyphs (fills with false when enlarging, truncates when reducing).")
                    
                    // Typography preview under Glyphs size
                    VStack(alignment: .leading, spacing: 6) {
                        
                        
                        Text("Preview text")
                            .font(.subheadline)
                            .foregroundStyle(.secondary)
                        
                        
                        // Editable sample text
                        HStack {
                            HStack(spacing: 8) {
                                TextField("AaBbCc 0123", text: $previewSample)
                                    .textFieldStyle(.roundedBorder)
                            }
                            
                            
                            
                            
                            Stepper("", value: Binding(
                                get: { previewPixelSize },
                                set: { previewPixelSize = $0 }
                            ), in: 0.5...5, step: 0.5)
                        }
                        
                        ScrollView(.horizontal, showsIndicators: true) {
                            TextGlyphPreview(
                                sample: previewSample,
                                glyphs: document.document.glyphs,
                                baseWidth: document.document.glyphWidth,
                                baseHeight: document.document.glyphHeight,
                                baseline: document.document.baseline,
                                pixelSize: previewPixelSize
                            )
                            
                        }
                    }
                    .padding(.top, 6)
                }
                
                Divider()

                TabView(selection: $previewTabSelection) {
                    // Onglet 1: Liste des glyphes existants
                    VStack {
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
                            Button("Add a glyph", action: addGlyphIfNeeded)
                                .buttonStyle(.borderedProminent)
                                .disabled(newGlyphCharacter.count != 1)
                        }
                    }
                    .tabItem { Label("List", systemImage: "list.number") }
                    .tag(0)

                    // Onglet 2: Grille des caractères Adafruit (prévisualisation/creation)
                    ScrollView {
                        let cols = [GridItem(.adaptive(minimum: 44), spacing: 8, alignment: .topLeading)]
                        LazyVGrid(columns: cols, spacing: 8) {
                            ForEach(adafruitChars, id: \.self) { ch in
                                let glyph = document.document.glyphs.first(where: { $0.character == ch })
                                Button {
                                    if let g = glyph {
                                        document.select(g)
                                    } else {
                                        document.addGlyph(from: ch)
                                        if let newly = document.document.glyphs.first(where: { $0.character == ch }) {
                                            document.select(newly)
                                        }
                                    }
                                } label: {
                                    ZStack(alignment: .center) {
                                        RoundedRectangle(cornerRadius: 6)
                                            .fill(Color.secondary.opacity(0.08))
                                        RoundedRectangle(cornerRadius: 6)
                                            .stroke(document.selectedGlyph?.character == ch ? Color.accentColor : Color.secondary.opacity(0.3), lineWidth: document.selectedGlyph?.character == ch ? 2 : 1)

                                        if let g = glyph {
                                            GlyphCanvasView(
                                                glyph: g,
                                                baseWidth: document.document.glyphWidth,
                                                baseHeight: document.document.glyphHeight,
                                                pixelSize: 2,
                                                brushSize: 1,
                                                preview: true,
                                                alignLeft: true,
                                                onSet: { _, _, _ in },
                                                beginStroke: { },
                                                endStroke: { }
                                            )
                                            .allowsHitTesting(false)
                                            .padding(4)
                                        } else {
                                            Text(String(ch))
                                                .font(.system(size: 14, weight: .regular, design: .monospaced))
                                                .foregroundStyle(.secondary)
                                        }
                                    }
                                    .overlay(alignment: .topTrailing) {
                                        ZStack {
                                            RoundedRectangle(cornerRadius: 3)
                                                .fill(Color.secondary.opacity(0.25))
                                            Text(String(ch))
                                                .font(.system(size: 9, weight: .semibold, design: .monospaced))
                                                .foregroundStyle(.black)
                                        }
                                        .frame(width: 13, height: 13)
                                        .padding(1)
                                    }
                                    .frame(minHeight: 44)
                                }
                                .contentShape(Rectangle())
                                .buttonStyle(.plain)
                                .help(glyph != nil ? "Edit glyph \(ch)" : "Create glyph \(ch)")
                            }
                        }
                        .padding(.vertical, 4)
                    }
                    .tabItem {
                                       Label("Grid", systemImage: "rectangle.grid.2x2")
                                   }
                    
//
                    .tag(1)
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
                    brushSize: brushSize,
                    onSet: { r, c, v in document.setPixel(row: r, column: c, to: v, undoManager: undoManager) },
                    beginStroke: { undoManager?.beginUndoGrouping() },
                    endStroke: { undoManager?.endUndoGrouping() }
                )
                .padding(.bottom, 8)
                
                
                Spacer()
                
                HStack(spacing: 20) {
                    
                    // Tiny placeholder of selected character in the top-right corner
                    ZStack {
                        Color.clear
                    }
                    .frame(height: 0)
                    .overlay(alignment: .trailing) {
                        if let currentChar = document.selectedGlyph?.character {
                            ZStack {
                                RoundedRectangle(cornerRadius: 6)
                                    .fill(Color.secondary.opacity(0.8))
                                if previewTabSelection == 0 {
                                    // Editable in List mode
                                    TextField(
                                        String(currentChar),
                                        text: Binding(
                                            get: { document.selectedGlyph?.character.map(String.init) ?? "" },
                                            set: { input in
                                                let single = input.first.map(String.init) ?? "~"
                                                document.renameSelectedGlyph(to: single)
                                            }
                                        )
                                    )
                                    .textFieldStyle(.plain)
                                    .multilineTextAlignment(.center)
                                    .font(.system(size: 18, weight: .semibold, design: .monospaced))
                                    .foregroundStyle(.white)
                                } else {
                                    // Read-only in Grid mode
                                    Text(String(currentChar))
                                        .font(.system(size: 30, weight: .semibold, design: .monospaced))
                                        .foregroundStyle(.white)
                                }
                            }
                            .frame(width: 40, height: 40)
                            .padding(2)
                        }
                    }
                    
                    
                    HStack {
                        
                        VStack{
                            Text(document.selectedGlyphEffectiveWidth,  format: .number)
                                .font(.caption)
                            
                            Image(systemName: "arrow.left.and.line.vertical.and.arrow.right")
                        }
                        Stepper(
                            value: Binding(
                                get: { document.selectedGlyphEffectiveWidth },
                                set: { document.setSelectedGlyphEffectiveWidth($0, undoManager: undoManager) }
                            ),
                            in: 1...100
                        ) { EmptyView() }
                            .rotationEffect(Angle(degrees: 90))
                        
                    }
                    .help("Largeur du glyphe sélectionné par rapport à la largeur standard")
                    
                    
                    
                    Divider()
                        .frame(height: 38)
                    
                    HStack {
                        
                        Image(systemName: "arrow.up.and.line.horizontal.and.arrow.down")
                        
                        Toggle("", isOn: $showBaseline)
                            .toggleStyle(.switch)
                            .help("Show/Hide the baseline")
                        
                        Stepper(
                            value: Binding(
                                get: { document.document.baseline },
                                set: { newVal in
                                    let clamped = max(0, min(document.document.glyphHeight, newVal))
                                    document.document.baseline = clamped
                                    document.objectWillChange.send()
                                }
                            ),
                            in: 0...(document.document.glyphHeight > 0 ? document.document.glyphHeight : 0)
                        )
                        { EmptyView() }
                            .rotationEffect(Angle(degrees: 180))
                        
                        
                        
                        
                    }
                    .help("Font baseline (y)")
                    
                    Divider()
                        .frame(height: 38)
                    
                    HStack {
                        VStack{
                            Text(brushSize,  format: .number)
                                .font(.caption)
                            Image(systemName: "paintbrush.pointed")
                        }
                        Stepper(
                            value: $brushSize,
                            in: 1...9
                        ) { EmptyView() }
                        
                        
                    }
                    .help("Brush size in pixels (odd values recommended: 1, 3, 5…)")
                    
                    Divider()
                        .frame(height: 38)
                    
                    
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
                    .help("Move the glyph by one pixel")
                    
                    
                    
                    Divider()
                        .frame(height: 38)
                    
                    VStack{
                        
                        Button {
                            document.cropSelectedGlyphToVisibleWindow(undoManager: undoManager)
                        } label: {
                            Image(systemName: "circle.dashed.rectangle")
                        }
                        .help("Remove extra pixels outside the visible frame (crop)")
                        
                        Button {
                            document.cropSelectedGlyphToContent(undoManager: undoManager)
                        } label: {
                            Image(systemName: "circle.rectangle.dashed")
                        }
                        .help("Crop tightly by removing only empty outer rows/columns")
                        
                    }
                    Divider()
                        .frame(height: 38)
                    
                    
                    VStack{
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
                    }
                    
                    Button {
                        document.negativeSelectedGlyph(undoManager: undoManager)
                    } label: {
                        Image(systemName: "circle.bottomrighthalf.pattern.checkered")
                    }
                    
                    
                    VStack{
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
                    }
                    
                    
                    Divider()
                        .frame(height: 38)
                    
                    HStack {
                        // Add the hover modifiers here
                        Button {
                            document.expandOrShrinkSelectedGlyphLeft(shrink: flags.isCommandPressed, undoManager: undoManager)
                        } label: {
                            Image(systemName: flags.isCommandPressed ? "arrow.right.to.line" : "arrow.left.to.line")
                        }
                        VStack{
                            Button {
                                document.expandOrShrinkSelectedGlyphUp(shrink: flags.isCommandPressed, undoManager: undoManager)
                            } label: {
                                Image(systemName: flags.isCommandPressed ? "arrow.down.to.line" : "arrow.up.to.line")
                            }
                            Button {
                                document.expandOrShrinkSelectedGlyphDown(shrink: flags.isCommandPressed, undoManager: undoManager)
                            } label: {
                                Image(systemName: flags.isCommandPressed ? "arrow.up.to.line" : "arrow.down.to.line")
                            }
                        }
                        Button {
                            document.expandOrShrinkSelectedGlyphRight(shrink: flags.isCommandPressed, undoManager: undoManager)
                        } label: {
                            Image(systemName: flags.isCommandPressed ? "arrow.left.to.line" : "arrow.right.to.line")
                        }
                    }
                    .help("Expand (click) / Shrink (cmd+click) the glyph canvas outside the visible frame")
                    
                    
                    
                    
                }
                .disabled(document.selectedGlyph == nil)
                .help("Symmetries and one-pixel moves for the selected glyph")
            }
            .padding()
            
            .frame(minWidth: 600, minHeight: 520)
            
            
        }
        .toolbar {
            //            Button("Diagnostiquer le presse-papiers", systemImage: "doc.text.magnifyingglass") {
            //                document.logPasteboardContents()
            //            }
            
            Button {
                document.openHeaderAndImport(undoManager: NSApp.keyWindow?.undoManager)
            } label: {
                Label("Import .h", systemImage: "tray.and.arrow.down")
            }
            .keyboardShortcut("i", modifiers: [.command, .shift])
            .help("Import Adafruit GFX header (.h)")
            
            Button("Copy Glyph", systemImage: "doc.on.doc") {
                copySelectedGlyphToPasteboard()
            }
            .disabled(document.selectedGlyph == nil)
            .keyboardShortcut("c", modifiers: [.command])
            .help("Copy the selected glyph to the pasteboard")
            
            Button("Paste and Import", systemImage: "doc.on.clipboard") {
                document.importFromPasteboard(undoManager: undoManager)
            }
            .keyboardShortcut("v", modifiers: [.command])
            
//            Button("Paste as New Glyph", systemImage: "plus.rectangle.on.rectangle") {
//                document.pasteGlyphAsNew(undoManager: undoManager)
//            }
//            .keyboardShortcut("v", modifiers: [.command, .shift])
//            .help("Paste clipboard content as a new glyph (JSON glyph preferred, otherwise import image)")
            
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
            if let next = FontDocument.adafruitNextChar(after: char) {
                newGlyphCharacter = String(next)
            } else {
                // Wrap to first if we reached the end of the printable range
                newGlyphCharacter = String(FontDocument.adafruitFirstChar)
            }
        }
        
        .onAppear() {
            if let char = document.document.glyphs.last?.character {
                if let next = FontDocument.adafruitNextChar(after: char) {
                    newGlyphCharacter = String(next)
                } else {
                    newGlyphCharacter = String(FontDocument.adafruitFirstChar)
                }
            } else {
                newGlyphCharacter = String(FontDocument.adafruitFirstChar)
            }
            widthString = String(document.document.glyphWidth)
            heightString = String(document.document.glyphHeight)
        }
        
    }
    
    private func addGlyphIfNeeded() {
        guard let character = newGlyphCharacter.first else { return }
        document.addGlyph(from: character)
        newGlyphCharacter.removeAll()
    }
    
    private func copySelectedGlyphToPasteboard() {
        guard let g = document.selectedGlyph else { return }
        let payload: [String: Any] = [
            "type": "pixelfont.glyph",
            "character": g.character.map(String.init) ?? "",
            "width": g.width,
            "height": g.height,
            "viewOffsetX": g.viewOffsetX,
            "viewOffsetY": g.viewOffsetY,
            "advanceWidthOffset": g.advanceWidthOffset,
            "pixels": g.pixels.map { row in row.map { $0 ? 1 : 0 } }
        ]
        guard let data = try? JSONSerialization.data(withJSONObject: payload, options: []),
              let jsonString = String(data: data, encoding: .utf8) else { return }
        let pb = NSPasteboard.general
        pb.clearContents()
        pb.setString(jsonString, forType: .string)
    }
}

private struct GlyphRow: View {
    @EnvironmentObject private var document: FontDocumentViewModel
    let glyph: Glyph
    
    var body: some View {
        HStack {
            
            VStack(alignment: .leading) {
                Text(glyph.character.map(String.init) ?? "_").fontDesign(.monospaced)
                //                Text("\(glyph.width)x\(glyph.height)")
                    .foregroundStyle(.secondary)
                //                    .font(.footnote)
            }
            
            GlyphCanvasView(
                glyph: glyph,
                baseWidth: document.document.glyphWidth,
                baseHeight: document.document.glyphHeight,
                pixelSize: 2,
                brushSize: 1,
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
            Text("Import an image into glyph")
                .font(.headline)
            Text("Choose an image; it will be resized to the glyph size and thresholded.")
                .font(.subheadline)
                .foregroundStyle(.secondary)
            HStack {
                Text("Threshold")
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
                Button("Choose an image…") {
                    let panel = NSOpenPanel()
                    panel.allowedContentTypes = [.png, .jpeg, .tiff]
                    panel.allowsMultipleSelection = false
                    panel.begin { resp in
                        if resp == .OK { onComplete(panel.url) }
                    }
                }
                Button("Import") {
                    // No-op: Import is triggered by choosing image. Keep for UX.
                }
                Button("Close") {
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


final class ModifierFlagsMonitor: ObservableObject {
    @Published var isCommandPressed: Bool = false
    private var monitor: Any?
    
    init() {
        monitor = NSEvent.addLocalMonitorForEvents(matching: .flagsChanged) { [weak self] event in
            self?.isCommandPressed = event.modifierFlags.contains(.command)
            return event
        }
    }
    
    deinit {
        if let monitor { NSEvent.removeMonitor(monitor) }
    }
}

struct TextGlyphPreview: View {
    let sample: String
    let glyphs: [Glyph]
    let baseWidth: Int
    let baseHeight: Int
    let baseline: Int
    let pixelSize: CGFloat
    var body: some View {
        // Compute advances per character
        let advances: [Int] = sample.map { ch in
            if let g = glyphs.first(where: { $0.character == ch }) {
                return max(1, baseWidth + g.advanceWidthOffset)
            } else {
                return baseWidth
            }
        }
        let totalAdvance = max(1, advances.reduce(0, +))
        let canvasWidth = totalAdvance
        let canvasHeight = baseHeight
        
        Canvas { context, _ in
            var penX = 20
            for ch in sample {
                if let g = glyphs.first(where: { $0.character == ch }) {
                    // Updated pixel rendering logic using vertical and horizontal framing from GlyphCanvasView
                    
                    let startRow = g.viewOffsetY
                    let startCol = g.viewOffsetX
                    for row in 0..<g.height {
                        let targetRow = row - startRow
                        let rowPixels = g.pixels[row]
                        for col in 0..<rowPixels.count where rowPixels[col] {
                            let targetCol = col - startCol
                            let x = CGFloat(penX + targetCol) * pixelSize
                            let y = CGFloat(targetRow) * pixelSize + 15
                            let rect = CGRect(x: x, y: y, width: pixelSize, height: pixelSize)
                            context.fill(Path(rect), with: .color(.primary))
                        }
                    }
                    
                    // Advance pen by effective width
                    let xAdv = max(1, baseWidth + g.advanceWidthOffset)
                    penX += xAdv
                } else {
                    // Missing glyph: just advance by base width
                    penX += baseWidth
                }
            }
            
            //            // Draw baseline across the whole preview
            //            let baselineY = CGFloat(baseline + 1) * pixelSize - 0.5
            //            let basePath = Path(CGRect(x: 0, y: baselineY, width: CGFloat(canvasWidth) * pixelSize, height: 1))
            //            context.fill(basePath, with: .color(.red.opacity(0.8)))
        }
        .frame(
            width: CGFloat(canvasWidth) * pixelSize + 40,
            height: CGFloat(canvasHeight) * pixelSize + 30,
            alignment: .topTrailing
        )
        //        .background(
        //            RoundedRectangle(cornerRadius: 4).stroke(Color.secondary.opacity(0.2))
        //        )
    }
}


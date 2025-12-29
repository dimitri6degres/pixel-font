# PixelFont (SwiftUI)

A SwiftUI bitmap font editor for macOS. Create, modify, and export glyphs (Adafruit GFX, raw C, etc.).

- 100% SwiftUI
- Image import (PNG/JPEG/TIFF/PDF) into a glyph
- Drawing tools (paint, erase with ⌘ while dragging, flips, rotations, nudges)
- Per-glyph effective width control (advance width offset)
- Adafruit GFX and raw C export
- Full Undo/Redo support

## Screenshots

<img src="../screenshot_01.png" alt="Screenshot 1" width="700">

## Requirements

- macOS with Xcode 15 or later (tested on recent Xcode versions)

## Installation

1. Open `PixelFont.xcodeproj` in Xcode.
2. Build and run the macOS app.

## Usage

- Create or open a document.
- Adjust global glyph size from the sidebar.
- Draw with click/drag; hold ⌘ while dragging to erase.
- Use the toolbar buttons for inversion, horizontal/vertical flips, 90° rotations, and pixel nudges.
- Import images via the “Import Image” button or “Paste and import”. Images are resized to the current glyph size with thresholding and optional margins.
- Export using the “Export” button (Adafruit GFX / C helpers).

## File Format

Documents are serialized as JSON using `ReferenceFileDocument` with UTI `gi.dimitrifontaine.pixelfont.pixf`.

## Export

- Adafruit GFX (`GFXfont`) via the Export panel.
- Raw C export via `FontDocument.exportC(options:)` if you need a byte/offset/advance table.

## Architecture Notes

- The model is centered around `FontDocument` and `Glyph`.
- `FontDocumentViewModel` coordinates editing operations with undo support.
- `GlyphCanvasView` renders and edits pixels with SwiftUI’s `Canvas`.
- Adafruit GFX export is generated from the current glyph set and dimensions.

## Credits & Inspiration

This project was inspired by https://github.com/ayoy/fontedit, but has been fully reworked and implemented in SwiftUI.
## Roadmap (Ideas)

- More import controls (auto-trim, auto-baseline)
- Additional export targets
- Sample fonts and templates

## Contributing

Issues and pull requests are welcome. Please include screenshots and steps to reproduce for UI issues.

## License

MIT — see `LICENSE` for details.

## Badges

![Swift](https://img.shields.io/badge/Swift-6.x-orange)
![Platform](https://img.shields.io/badge/platform-macOS-blue)
![License](https://img.shields.io/badge/license-MIT-green)


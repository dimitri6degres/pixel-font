# PixelFont (SwiftUI)

Un éditeur de polices bitmap en SwiftUI pour macOS. Permet de créer, modifier et exporter des glyphes (Adafruit GFX, C, etc.).

- 100% SwiftUI
- Import d’images (PNG/JPEG/TIFF/PDF) vers un glyphe
- Outils de dessin (peinture, gomme via ⌘, flip, rotation, nudges)
- Gestion de la largeur effective par glyphe
- Export Adafruit GFX et C
- Undo/Redo supporté

## Captures d’écran

(ajoute ici des images GIF/PNG du fonctionnement)

## Installation

- Ouvrir `PixelFont.xcodeproj` dans Xcode 15+ (ou 16/17/26 selon ta version)
- Compiler et lancer sur macOS

## Utilisation

- Crée/importe un document
- Ajuste la taille des glyphes
- Dessine via clic/drag, ⌘ pour effacer
- Outils: inversion, symétries, rotations, nudges
- Import d’images: menu “Import Image” ou “Coller et importer”
- Export: bouton “Export” (Adafruit GFX / C)

## Format de fichier

Le document est sérialisé en JSON via `ReferenceFileDocument` (UTType: `gi.dimitrifontaine.pixelfont.pixf`).

## Export

- Adafruit GFX (`GFXfont`) via `ExportPanel`
- Export C brut via `FontDocument.exportC(options:)`

## Crédits et inspiration

- Inspiré de https://github.com/ayoy/fontedit, mais entièrement réécrit en SwiftUI et remanié.
- Merci aux contributeurs open source.

## Licence

MIT — voir le fichier `LICENSE`.

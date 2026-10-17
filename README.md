# DocMind

An offline document scanner and PDF toolkit for personal use: Adobe Scan–style
features in a clean glass UI, with no accounts, no ads and no cloud.
Nothing leaves the phone unless you share it.

## Features

**Scan**
- One full-screen camera for every mode, with live page-edge detection,
  auto-capture when the page is steady, flash and torch, tap to focus,
  pinch to zoom, a grid, and gallery import
- Modes: Document, Book (two-page spreads split into single pages), ID Card
  (guided front then back, both on one A4 page at large or actual size),
  Business Card (saved as a contact), Whiteboard, Receipt and QR Code
- Four-corner crop with perspective correction, a magnifier loupe, and
  auto-detect
- Multi-page scans, adding pages later, retaking a page, importing photos
  (edges found automatically) and PDFs

**Edit**
- Six filters (Original, Auto Color, Light Text, Grayscale, B&W, Whiteboard)
  with shadow removal and live previews, plus "apply to all pages"
- Crop, rotate, brightness/contrast, reorder by drag, duplicate and delete pages
- Fill & Sign: saved signature, pen, highlighter, text, date, tick and cross

**Text (OCR, on-device)**
- English text recognition
- Searchable PDFs with an invisible text layer
- Full-text search across every scan, with matches highlighted on the page
- Copy or share the text, and smart file names taken from the first line

**Organize and share**
- Folders, favourites, sorting, and grid or list view
- Multi-select to ZIP, merge, move or delete
- Share or save as PDF, JPG, TXT or ZIP; compressed PDF; print

**Tools**
- Merge PDFs, split or extract pages, compress PDF
- **Protect PDF with a password (AES-256)** and **remove a PDF password**
- PDF to JPG, images to PDF, import a PDF to edit and sign it
- **Create a ZIP (optionally password-protected)** and extract a ZIP
- QR and barcode scanning in the same camera, and text from an image

**Privacy**
- App Lock with fingerprint, face or screen lock
- Light, dark and auto themes, five premium accents (Sapphire, Emerald,
  Champagne, Ruby, Graphite), Manrope type, and haptics

## Build

Requires Flutter 3.47 or newer and the Android SDK.

```bash
flutter pub get
flutter test                      # core logic tests
flutter build apk --release --split-per-abi
# install build/app/outputs/flutter-apk/app-arm64-v8a-release.apk on the phone
```

The release build is signed with the debug key, which is fine for sideloading
onto your own phone.

## Project layout

```
lib/
  app/       theme (glass tokens, transitions), icon glyphs
  core/      models, settings, library storage, image filters, OCR,
             PDF engine, export/ZIP, scanner, business-card parser
  screens/   home, search, tools, settings, editor, crop, fill & sign,
             document viewer, OCR text, merge, QR, business card, lock
  widgets/   glass components, document tiles, dialogs
```

## Libraries

- Google ML Kit: document scanner and text recognition
- Syncfusion Flutter PDF: PDF writing, merging and encryption (Community
  License, free for individuals)
- pdfrx: PDF rendering
- `camera` (CameraX), and our own edge detection and perspective warp in Dart
- `image` (filters), `archive` (ZIP with AES), ML Kit barcode scanning (QR)
- Phosphor Icons (MIT) and Manrope (OFL): fonts bundled in `assets/fonts`

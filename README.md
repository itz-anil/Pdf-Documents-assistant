# DocMind

An offline document scanner and PDF toolkit for personal use: Adobe Scan–style
features in a clean glass UI, with no accounts, no ads and no cloud.
Nothing leaves the phone unless you share it.

## Features

**Scan**
- Camera scanning with automatic edge detection, auto-capture, crop and a
  cleanup brush (Google's on-device document scanner)
- Modes: Document, Book (two-page spreads split into single pages), ID Card
  (front and back on one A4 page), Business Card (saved as a contact),
  Whiteboard, Receipt
- Multi-page scans, adding pages later, importing photos and PDFs

**Edit**
- Six filters (Original, Auto Color, Light Text, Grayscale, B&W, Whiteboard)
  with shadow removal and live previews, plus "apply to all pages"
- Crop, rotate, brightness/contrast, reorder by drag, duplicate and delete pages
- Fill & Sign: saved signature, pen, highlighter, text, date, tick and cross

**Text (OCR, on-device)**
- English and Hindi (Devanagari) recognition
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
- QR and barcode scanner, text from image

**Privacy**
- App Lock with fingerprint, face or screen lock
- Light, dark and auto themes, five accent colours, and haptics

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
- `image` (filters), `archive` (ZIP with AES), `mobile_scanner` (QR)
- Phosphor Icons (MIT): fonts bundled in `assets/fonts`

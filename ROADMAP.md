# 📄 PDF Documents Assistant — Roadmap

> **Goal:** Adobe Scan जैसा एक personal scanner app — सारे main features के साथ, clean और simple UI, पूरी तरह **offline** और **free** (कोई account, ads या cloud ज़रूरी नहीं)।
>
> **Scope:** सिर्फ़ personal use के लिए — Play Store पर publish नहीं करना है। इसलिए Adobe का नाम, logo या design assets use नहीं करेंगे; सिर्फ़ features का अपना version बनाएँगे।

---

## 1. Tech Stack (Recommended)

| Layer | Choice | क्यों |
|---|---|---|
| Framework | **Flutter (Dart)** | एक ही code से Android (+ बाद में iOS/desktop), fast UI बनाना आसान |
| Camera + Edge detection | `google_mlkit_document_scanner` (Android) / `cunning_document_scanner` | Google का ready-made scanner — auto edge detection, auto-capture, crop, filters free में |
| Custom image processing | `opencv_dart` + `image` package | अपने filters, perspective correction, book-page split |
| OCR (text recognition) | `google_mlkit_text_recognition` | On-device, offline; **Latin + Devanagari (Hindi)** दोनों support |
| PDF बनाना | `pdf` package (+ `syncfusion_flutter_pdf` advanced काम के लिए) | Searchable PDF (invisible OCR text layer), merge, password |
| PDF देखना | `pdfrx` | Fast viewer, text search, zoom |
| Database | `drift` (SQLite) | Documents, pages, tags, OCR text का index (full-text search) |
| State management | `riverpod` | Clean, testable |
| Navigation | `go_router` | |
| Share / Print | `share_plus`, `printing` | |
| Security | `local_auth` | Fingerprint / PIN app lock |
| QR / Barcode | `mobile_scanner` | |

> **Alternative:** अगर सिर्फ़ Android चाहिए और native performance चाहिए → **Kotlin + Jetpack Compose + ML Kit Document Scanner API + PdfRenderer**। बाकी roadmap वैसा ही रहेगा।

---

## 2. Feature List (Adobe Scan के equivalent)

### 📷 Capture
- [ ] Auto edge detection + **auto-capture** (document steady होते ही photo)
- [ ] Capture modes: **Document, Whiteboard, Book, ID Card, Business Card, Receipt/Form**
- [ ] Multi-page batch scanning (एक session में कई pages)
- [ ] Gallery से images import करना
- [ ] Flash toggle, grid lines, manual/auto shutter

### ✂️ Edit / Enhance
- [ ] Crop + 4-corner perspective adjust (magnifier के साथ)
- [ ] Rotate, re-take, delete page
- [ ] Pages **reorder** (drag & drop)
- [ ] Filters: **Original, Auto Color, Light Text, Grayscale, B&W, Whiteboard**
- [ ] Brightness / contrast slider
- [ ] **Cleanup tool** — दाग, उँगली, shadow को eraser से साफ़ करना
- [ ] Book mode: दो pages को auto-split + page curve हल्का सा flat करना
- [ ] ID Card mode: front + back एक ही page पर

### 🔤 OCR (Text Recognition)
- [ ] हर page पर automatic OCR (background में)
- [ ] **Searchable PDF** — image के ऊपर invisible text layer
- [ ] Text select/copy, पूरा text `.txt` में export
- [ ] Hindi + English दोनों
- [ ] Business card → name/phone/email निकालकर **contact save**

### 📁 Document Management
- [ ] Home screen: recent scans (grid / list view)
- [ ] Smart auto-naming (OCR से title या date: `Scan 16 Oct 2026`)
- [ ] Rename, delete, duplicate, **folders/tags**, favorites
- [ ] **Search** — file name ही नहीं, document के अंदर के text से भी
- [ ] Sort: date, name, size

### 📤 Export / Share
- [ ] Save as **PDF / JPEG / PNG / TXT**
- [ ] PDF **compress** (Low / Medium / High quality)
- [ ] Share (WhatsApp, Email, Drive — system share sheet से)
- [ ] Print
- [ ] Phone storage (Downloads) में save

### 🛠️ PDF Tools
- [ ] Multiple PDFs **merge**, PDF **split**/pages extract
- [ ] Existing PDF import करके pages add/delete
- [ ] **Fill & Sign** — signature draw/save करके PDF पर लगाना, text/date/checkmark लगाना
- [ ] Annotations: highlight, underline, pen, sticky note
- [ ] **Password protect** / unlock PDF
- [ ] Watermark (optional)

### 🔒 Privacy & Settings
- [ ] App lock (fingerprint / PIN)
- [ ] Default filter, default quality, file name format, OCR language
- [ ] Dark / Light / System theme
- [ ] Local backup/restore (ZIP export) — optional

### ✨ Extra (Adobe से बेहतर बनाने के लिए — optional)
- [ ] QR / Barcode scanner
- [ ] Receipt से amount/date निकालना
- [ ] Home screen widget — "Quick Scan"
- [ ] AI summary / Q&A on document (Claude API से, optional, internet चाहिए)

---

## 3. UI / UX Plan (Clean Design)

**Design principles:** Material 3, कम buttons, बड़ा touch area, एक primary action (Scan), dark mode।

```
┌───────── Home ─────────┐     ┌──── Camera ────┐     ┌──── Review ────┐
│ 🔍 Search              │     │  [mode tabs]   │     │ page thumbnails│
│ Recent ▸ grid/list     │ ──▶ │  live edges ▢  │ ──▶ │ crop · filter  │
│ Folders · Tools        │     │  ◉ auto/manual │     │ rotate · clean │
│            [ 📷 Scan ] │     │  thumbs ▸ Done │     │   [ Save PDF ] │
└────────────────────────┘     └────────────────┘     └────────────────┘
                                                              │
                         ┌──── Document View ────┐ ◀──────────┘
                         │ PDF viewer + search   │
                         │ Share · Edit · Sign · │
                         │ OCR text · Compress   │
                         └───────────────────────┘
```

**Screens:** Home · Camera · Review/Edit · Document Viewer · Tools (merge/split/compress/protect) · Fill & Sign · Settings

**Bottom navigation:** Home | Files | Tools | Settings + बीच में floating **Scan** button।

---

## 4. Project Structure

```
lib/
├── main.dart
├── app/            # theme, router, constants
├── core/           # db (drift), storage, utils, permissions
├── features/
│   ├── home/
│   ├── scanner/    # camera, edge detection, capture modes
│   ├── editor/     # crop, filters, cleanup, reorder
│   ├── ocr/
│   ├── documents/  # viewer, rename, folders, search
│   ├── pdf_tools/  # merge, split, compress, protect
│   ├── sign/       # signature + annotations
│   └── settings/
└── shared/         # common widgets
```

**Storage layout (app private folder):**
```
documents/<doc_id>/
├── original/page_001.jpg   # raw capture (re-edit के लिए)
├── processed/page_001.jpg  # filter/crop के बाद
├── ocr/page_001.json       # OCR text + bounding boxes
└── output.pdf
```

**DB tables:** `documents` (id, title, folder_id, created_at, page_count, size) · `pages` (id, doc_id, order, paths, filter, crop_points) · `folders` · `ocr_fts` (FTS5 full-text search)

---

## 5. Phase-wise Roadmap

> Timeline अंदाज़न है — रोज़ 2–3 घंटे काम मानकर।

### Phase 0 — Setup (2–3 दिन)
- Flutter install, project बनाना, folder structure, theme (light/dark), router, Riverpod, drift DB
- Git + basic CI (`flutter analyze`, `flutter test`)
- ✅ **Done जब:** खाली Home screen dark/light दोनों में चले

### Phase 1 — MVP: Scan → PDF (1–2 हफ़्ते)
- ML Kit Document Scanner integrate (auto-edge, auto-capture, crop, basic filters)
- Multi-page scan → PDF बनाना → app में save
- Home screen पर list, PDF open (viewer), share, rename, delete
- ✅ **Done जब:** 5 pages scan करके WhatsApp पर PDF भेज सकें

### Phase 2 — Editor (1–2 हफ़्ते)
- अपनी Review screen: reorder, rotate, re-take, delete, add page
- Custom filters (OpenCV): Auto Color, Light Text, Grayscale, B&W, Whiteboard
- Manual crop/perspective with magnifier
- Gallery import
- ✅ **Done जब:** saved document दोबारा खोलकर edit कर सकें (original images से)

### Phase 3 — OCR + Search (1–2 हफ़्ते)
- Background OCR (Hindi + English), progress indicator
- Searchable PDF (invisible text layer)
- Copy text / export TXT
- FTS search: document के अंदर का text search
- Smart auto-naming
- ✅ **Done जब:** "invoice" search करने पर वो scan मिल जाए जिसके अंदर ये शब्द है

### Phase 4 — Organize + Export (1 हफ़्ता)
- Folders, tags, favorites, sort, grid/list toggle
- Export JPEG/PNG, PDF compress (quality options), print, Downloads में save
- ✅ **Done जब:** 20 MB PDF को 2 MB तक compress कर सकें, readable रहे

### Phase 5 — Capture Modes (1–2 हफ़्ते)
- Book mode (page split), ID Card (front+back एक page), Business Card (→ contact), Whiteboard, Receipt
- Cleanup/eraser tool
- ✅ **Done जब:** Aadhaar front+back एक A4 page पर आ जाए

### Phase 6 — PDF Tools + Fill & Sign (2 हफ़्ते)
- Merge, split, existing PDF import, page delete
- Signature pad (save करके reuse), text/date/tick लगाना
- Annotations: highlight, pen, notes
- Password protect / remove
- ✅ **Done जब:** form PDF पर sign करके, password लगाकर share कर सकें

### Phase 7 — Polish + Privacy (1 हफ़्ता)
- App lock (biometric), settings screen, onboarding (2–3 slides)
- Animations, haptics, empty states, error handling
- Performance: thumbnails cache, large docs (100+ pages) test
- Local backup/restore (ZIP)
- ✅ **Done जब:** daily use में कोई crash/lag न हो

### Phase 8 — Extras (optional, जब मन हो)
- QR/Barcode scanner, Quick Scan widget, receipt data extraction
- AI summary / document Q&A (Claude API)
- iOS / Desktop build

**कुल अंदाज़न समय:** ~10–14 हफ़्ते (MVP सिर्फ़ ~2 हफ़्ते में तैयार)

---

## 6. Install करना (बिना Play Store)

```bash
flutter build apk --release --split-per-abi
# build/app/outputs/flutter-apk/app-arm64-v8a-release.apk → phone में copy करके install
```
या USB debugging on करके `flutter install`।

---

## 7. Testing Checklist

- [ ] कम रोशनी, टेढ़ा document, सफ़ेद टेबल पर सफ़ेद page
- [ ] Hindi printed text, handwritten notes का OCR
- [ ] 100+ page document — memory/speed
- [ ] Phone rotate, app background में जाना, scan के बीच call आना
- [ ] Storage full होने पर error message
- [ ] Unit tests: PDF बनाना, DB, filters · Widget tests: main screens

---

## 8. Risks / ध्यान रखने वाली बातें

| Risk | Solution |
|---|---|
| ML Kit Document Scanner सिर्फ़ Android पर | iOS के लिए `cunning_document_scanner` (VisionKit) |
| Handwriting OCR कमज़ोर | Printed text पर focus; बाद में optional cloud OCR |
| बड़ी images से memory issue | Pages को disk पर रखें, thumbnails cache करें, isolates में processing |
| Brand/copyright | Adobe का नाम/logo/assets कहीं use न करें — अपना नाम और icon रखें |

---

## 9. अगला कदम

1. Flutter install करें (`flutter doctor`)
2. **Phase 0** शुरू करें — project skeleton
3. Phase 1 का MVP बनाकर phone पर test करें, फिर आगे बढ़ें

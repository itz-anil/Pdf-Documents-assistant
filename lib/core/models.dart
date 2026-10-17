import '../app/icons.dart';
import 'package:flutter/widgets.dart';

enum PageFilter { original, autoColor, lightText, grayscale, blackWhite, whiteboard }

extension PageFilterInfo on PageFilter {
  String get label => switch (this) {
        PageFilter.original => 'Original',
        PageFilter.autoColor => 'Auto Color',
        PageFilter.lightText => 'Light Text',
        PageFilter.grayscale => 'Grayscale',
        PageFilter.blackWhite => 'B&W',
        PageFilter.whiteboard => 'Whiteboard',
      };
}

enum ScanMode { document, book, idCard, businessCard, whiteboard, receipt }

extension ScanModeInfo on ScanMode {
  String get label => switch (this) {
        ScanMode.document => 'Document',
        ScanMode.book => 'Book',
        ScanMode.idCard => 'ID Card',
        ScanMode.businessCard => 'Business Card',
        ScanMode.whiteboard => 'Whiteboard',
        ScanMode.receipt => 'Receipt',
      };

  String get hint => switch (this) {
        ScanMode.document => 'Letters, forms, bills and notes',
        ScanMode.book => 'Two-page spreads split into single pages',
        ScanMode.idCard => 'Front and back on one A4 page',
        ScanMode.businessCard => 'Reads name, phone and email into a contact',
        ScanMode.whiteboard => 'Boosts marker contrast, removes glare',
        ScanMode.receipt => 'Long receipts with crisp light text',
      };

  IconData get icon => switch (this) {
        ScanMode.document => PhosphorIconsRegular.fileText,
        ScanMode.book => PhosphorIconsRegular.bookOpen,
        ScanMode.idCard => PhosphorIconsRegular.identificationCard,
        ScanMode.businessCard => PhosphorIconsRegular.addressBook,
        ScanMode.whiteboard => PhosphorIconsRegular.chalkboard,
        ScanMode.receipt => PhosphorIconsRegular.receipt,
      };

  PageFilter? get preferredFilter => switch (this) {
        ScanMode.whiteboard => PageFilter.whiteboard,
        ScanMode.receipt => PageFilter.lightText,
        _ => null,
      };
}

/// One OCR line, with its box normalised to the processed image (0..1).
class OcrLine {
  final String text;
  final double l, t, w, h;
  const OcrLine(this.text, this.l, this.t, this.w, this.h);

  Map<String, dynamic> toJson() => {'x': text, 'l': l, 't': t, 'w': w, 'h': h};
  factory OcrLine.fromJson(Map<String, dynamic> j) => OcrLine(
        j['x'] as String,
        (j['l'] as num).toDouble(),
        (j['t'] as num).toDouble(),
        (j['w'] as num).toDouble(),
        (j['h'] as num).toDouble(),
      );
}

class PageItem {
  final String id;

  /// File names inside the document folder.
  String original; // as captured
  String base; // flattened by [quad], cached
  String processed; // base + rotation + filter
  String thumb;

  PageFilter filter;
  int quarterTurns;

  /// Document outline on the original: 4 corners (TL, TR, BR, BL) as
  /// normalised [x0, y0, … x3, y3]. Null means the whole image.
  List<double>? quad;
  double brightness; // -0.5 .. 0.5
  double contrast; // 0.5 .. 1.8
  String ocrText;
  List<OcrLine> ocrLines;
  bool ocrDone;
  int width;
  int height;

  PageItem({
    required this.id,
    required this.original,
    this.base = '',
    required this.processed,
    required this.thumb,
    this.filter = PageFilter.autoColor,
    this.quarterTurns = 0,
    this.quad,
    this.brightness = 0,
    this.contrast = 1,
    this.ocrText = '',
    List<OcrLine>? ocrLines,
    this.ocrDone = false,
    this.width = 0,
    this.height = 0,
  }) : ocrLines = ocrLines ?? [];

  Map<String, dynamic> toJson() => {
        'id': id,
        'o': original,
        'bs': base,
        'p': processed,
        'th': thumb,
        'f': filter.name,
        'q': quarterTurns,
        'qd': quad,
        'b': brightness,
        'k': contrast,
        'ot': ocrText,
        'ol': ocrLines.map((e) => e.toJson()).toList(),
        'od': ocrDone,
        'w': width,
        'h': height,
      };

  factory PageItem.fromJson(Map<String, dynamic> j) => PageItem(
        id: j['id'] as String,
        original: j['o'] as String,
        base: j['bs'] as String? ?? '',
        processed: j['p'] as String,
        thumb: j['th'] as String,
        filter: PageFilter.values.firstWhere((f) => f.name == j['f'], orElse: () => PageFilter.original),
        quarterTurns: (j['q'] as num?)?.toInt() ?? 0,
        quad: _quadFromJson(j),
        brightness: (j['b'] as num?)?.toDouble() ?? 0,
        contrast: (j['k'] as num?)?.toDouble() ?? 1,
        ocrText: j['ot'] as String? ?? '',
        ocrLines: (j['ol'] as List?)?.map((e) => OcrLine.fromJson(Map<String, dynamic>.from(e))).toList(),
        ocrDone: j['od'] as bool? ?? false,
        width: (j['w'] as num?)?.toInt() ?? 0,
        height: (j['h'] as num?)?.toInt() ?? 0,
      );
}

List<double>? _quadFromJson(Map<String, dynamic> j) {
  final q = (j['qd'] as List?)?.map((e) => (e as num).toDouble()).toList();
  if (q != null && q.length == 8) return q;
  // Version 1 stored a rectangle crop [l, t, r, b].
  final c = (j['c'] as List?)?.map((e) => (e as num).toDouble()).toList();
  if (c != null && c.length == 4) return [c[0], c[1], c[2], c[1], c[2], c[3], c[0], c[3]];
  return null;
}

class DocItem {
  final String id;
  String name;
  final DateTime createdAt;
  DateTime updatedAt;
  String? folderId;
  bool favorite;
  ScanMode mode;
  List<PageItem> pages;

  DocItem({
    required this.id,
    required this.name,
    required this.createdAt,
    required this.updatedAt,
    this.folderId,
    this.favorite = false,
    this.mode = ScanMode.document,
    required this.pages,
  });

  String get fullText => pages.map((p) => p.ocrText).where((t) => t.isNotEmpty).join('\n\n');
  bool get ocrPending => pages.any((p) => !p.ocrDone);

  Map<String, dynamic> toJson() => {
        'id': id,
        'name': name,
        'created': createdAt.toIso8601String(),
        'updated': updatedAt.toIso8601String(),
        'folder': folderId,
        'fav': favorite,
        'mode': mode.name,
        'pages': pages.map((p) => p.toJson()).toList(),
      };

  factory DocItem.fromJson(Map<String, dynamic> j) => DocItem(
        id: j['id'] as String,
        name: j['name'] as String,
        createdAt: DateTime.parse(j['created'] as String),
        updatedAt: DateTime.parse(j['updated'] as String),
        folderId: j['folder'] as String?,
        favorite: j['fav'] as bool? ?? false,
        mode: ScanMode.values.firstWhere((m) => m.name == j['mode'], orElse: () => ScanMode.document),
        pages: (j['pages'] as List).map((e) => PageItem.fromJson(Map<String, dynamic>.from(e))).toList(),
      );
}

class Folder {
  final String id;
  String name;
  int colorIndex;
  Folder({required this.id, required this.name, this.colorIndex = 0});

  Map<String, dynamic> toJson() => {'id': id, 'name': name, 'c': colorIndex};
  factory Folder.fromJson(Map<String, dynamic> j) =>
      Folder(id: j['id'] as String, name: j['name'] as String, colorIndex: (j['c'] as num?)?.toInt() ?? 0);
}

enum SortOrder { newest, oldest, nameAZ, nameZA, largest }

extension SortOrderInfo on SortOrder {
  String get label => switch (this) {
        SortOrder.newest => 'Newest first',
        SortOrder.oldest => 'Oldest first',
        SortOrder.nameAZ => 'Name A–Z',
        SortOrder.nameZA => 'Name Z–A',
        SortOrder.largest => 'Most pages',
      };
}

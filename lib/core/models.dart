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
        ScanMode.document => PhosphorIconsDuotone.fileText,
        ScanMode.book => PhosphorIconsDuotone.bookOpen,
        ScanMode.idCard => PhosphorIconsDuotone.identificationCard,
        ScanMode.businessCard => PhosphorIconsDuotone.addressBook,
        ScanMode.whiteboard => PhosphorIconsDuotone.chalkboard,
        ScanMode.receipt => PhosphorIconsDuotone.receipt,
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
  String original;
  String processed;
  String thumb;

  PageFilter filter;
  int quarterTurns;

  /// Normalised crop rect [left, top, right, bottom] on the original, or null.
  List<double>? crop;
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
    required this.processed,
    required this.thumb,
    this.filter = PageFilter.autoColor,
    this.quarterTurns = 0,
    this.crop,
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
        'p': processed,
        'th': thumb,
        'f': filter.name,
        'q': quarterTurns,
        'c': crop,
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
        processed: j['p'] as String,
        thumb: j['th'] as String,
        filter: PageFilter.values.firstWhere((f) => f.name == j['f'], orElse: () => PageFilter.original),
        quarterTurns: (j['q'] as num?)?.toInt() ?? 0,
        crop: (j['c'] as List?)?.map((e) => (e as num).toDouble()).toList(),
        brightness: (j['b'] as num?)?.toDouble() ?? 0,
        contrast: (j['k'] as num?)?.toDouble() ?? 1,
        ocrText: j['ot'] as String? ?? '',
        ocrLines: (j['ol'] as List?)?.map((e) => OcrLine.fromJson(Map<String, dynamic>.from(e))).toList(),
        ocrDone: j['od'] as bool? ?? false,
        width: (j['w'] as num?)?.toInt() ?? 0,
        height: (j['h'] as num?)?.toInt() ?? 0,
      );
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

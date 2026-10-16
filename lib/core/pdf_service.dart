import 'dart:io';
import 'dart:isolate';
import 'dart:math' as math;
import 'dart:typed_data';
import 'dart:ui' show Offset, Rect, Size;

import 'package:image/image.dart' as img;
import 'package:path/path.dart' as p;
import 'package:pdfrx/pdfrx.dart' as rx;
import 'package:syncfusion_flutter_pdf/pdf.dart';

import 'image_processing.dart';
import 'library_store.dart';
import 'models.dart';
import 'settings.dart';

class PasswordRequiredException implements Exception {
  const PasswordRequiredException();
  @override
  String toString() => 'This PDF is password protected.';
}

class WrongPasswordException implements Exception {
  const WrongPasswordException();
  @override
  String toString() => 'The password is incorrect.';
}

class PdfPageSource {
  final String path;
  final int width;
  final int height;
  final List<OcrLine> lines;
  const PdfPageSource(this.path, this.width, this.height, this.lines);
}

class PdfOptions {
  final PageSizeOption pageSize;
  final bool textLayer;
  final int? maxSide; // recompress pages when set
  final int? jpegQuality;
  final String? password;
  const PdfOptions({
    this.pageSize = PageSizeOption.fit,
    this.textLayer = true,
    this.maxSide,
    this.jpegQuality,
    this.password,
  });
}

/// Every PDF operation lives here. Heavy work runs in background isolates.
class PdfService {
  PdfService._();

  // ------------------------------------------------------------- building

  /// Builds a searchable PDF (image + invisible OCR text) for [doc].
  static Future<Uint8List> buildDocument(LibraryStore store, DocItem doc, PdfOptions o) {
    final pages = doc.pages
        .map((pg) => PdfPageSource(store.processedFile(doc, pg).path, pg.width, pg.height, pg.ocrLines))
        .toList();
    return Isolate.run(() => _build(pages, o));
  }

  /// Builds a PDF from explicit page sources (image + optional OCR lines).
  static Future<Uint8List> buildPages(List<PdfPageSource> pages, PdfOptions o) => Isolate.run(() => _build(pages, o));

  /// Builds a plain PDF from arbitrary image files (Images → PDF tool).
  static Future<Uint8List> buildFromImages(List<String> paths, PdfOptions o) {
    final pages = paths.map((x) => PdfPageSource(x, 0, 0, const [])).toList();
    return Isolate.run(() => _build(pages, o));
  }

  static Uint8List _build(List<PdfPageSource> pages, PdfOptions o) {
    final doc = PdfDocument();
    for (final input in pages) {
      List<int> bytes = File(input.path).readAsBytesSync();
      var w = input.width, h = input.height;
      if (o.maxSide != null || w == 0 || h == 0) {
        var im = img.decodeImage(Uint8List.fromList(bytes))!;
        im = img.bakeOrientation(im);
        final longest = math.max(im.width, im.height);
        if (o.maxSide != null && longest > o.maxSide!) {
          im = im.width >= im.height
              ? img.copyResize(im, width: o.maxSide, interpolation: img.Interpolation.average)
              : img.copyResize(im, height: o.maxSide, interpolation: img.Interpolation.average);
        }
        if (im.numChannels == 4) {
          final flat = img.Image(width: im.width, height: im.height, numChannels: 3);
          img.fill(flat, color: img.ColorRgb8(255, 255, 255));
          img.compositeImage(flat, im);
          im = flat;
        }
        bytes = img.encodeJpg(im, quality: o.jpegQuality ?? 85);
        w = im.width;
        h = im.height;
      }
      final Size pageSize = switch (o.pageSize) {
        PageSizeOption.a4 => const Size(595, 842),
        PageSizeOption.letter => const Size(612, 792),
        PageSizeOption.fit => Size(595, 595 * h / w),
      };
      final landscape = w > h && o.pageSize != PageSizeOption.fit;
      final size = landscape ? Size(pageSize.height, pageSize.width) : pageSize;
      final section = doc.sections!.add();
      section.pageSettings.margins.all = 0;
      section.pageSettings.size = size;
      final page = section.pages.add();
      final g = page.graphics;
      final scale = math.min(size.width / w, size.height / h);
      final rect = Rect.fromLTWH(
        (size.width - w * scale) / 2,
        (size.height - h * scale) / 2,
        w * scale,
        h * scale,
      );
      g.drawImage(PdfBitmap(bytes), rect);

      if (o.textLayer && input.lines.isNotEmpty) {
        g.save();
        g.setTransparency(0);
        for (final line in input.lines) {
          final text = String.fromCharCodes(line.text.runes.where((c) => c >= 32 && c < 256));
          if (text.trim().isEmpty) continue;
          final box = Rect.fromLTWH(
            rect.left + line.l * rect.width,
            rect.top + line.t * rect.height,
            math.max(4, line.w * rect.width),
            math.max(4, line.h * rect.height),
          );
          final font = PdfStandardFont(PdfFontFamily.helvetica, math.max(3, box.height * 0.8));
          g.drawString(text, font, bounds: box, brush: PdfBrushes.black);
        }
        g.restore();
      }
    }
    if (o.password != null && o.password!.isNotEmpty) {
      doc.security.algorithm = PdfEncryptionAlgorithm.aesx256Bit;
      doc.security.userPassword = o.password!;
      doc.security.ownerPassword = o.password!;
    }
    final out = Uint8List.fromList(doc.saveSync());
    doc.dispose();
    return out;
  }

  // ------------------------------------------------------------ inspection

  static PdfDocument _open(Uint8List bytes, String? password) {
    try {
      return PdfDocument(inputBytes: bytes, password: password);
    } catch (e) {
      final msg = e.toString().toLowerCase();
      if (msg.contains('password')) {
        throw (password == null || password.isEmpty)
            ? const PasswordRequiredException()
            : const WrongPasswordException();
      }
      rethrow;
    }
  }

  /// Returns page count, throwing [PasswordRequiredException] when locked.
  static Future<int> pageCount(Uint8List bytes, {String? password}) => Isolate.run(() {
        final d = _open(bytes, password);
        final n = d.pages.count;
        d.dispose();
        return n;
      });

  static Future<bool> isEncrypted(Uint8List bytes) async {
    try {
      await pageCount(bytes);
      return false;
    } on PasswordRequiredException {
      return true;
    } on WrongPasswordException {
      return true;
    }
  }

  // ------------------------------------------------------------- security

  static Future<Uint8List> protect(Uint8List bytes, String newPassword, {String? currentPassword}) =>
      Isolate.run(() {
        final d = _open(bytes, currentPassword);
        d.security.algorithm = PdfEncryptionAlgorithm.aesx256Bit;
        d.security.userPassword = newPassword;
        d.security.ownerPassword = newPassword;
        final out = Uint8List.fromList(d.saveSync());
        d.dispose();
        return out;
      });

  static Future<Uint8List> removePassword(Uint8List bytes, String password) => Isolate.run(() {
        final d = _open(bytes, password);
        d.security.userPassword = '';
        d.security.ownerPassword = '';
        final out = Uint8List.fromList(d.saveSync());
        d.dispose();
        return out;
      });

  // ------------------------------------------------------ merge and split

  static void _copyPages(PdfDocument from, PdfDocument to, Iterable<int> indexes) {
    for (final i in indexes) {
      final page = from.pages[i];
      final size = page.size;
      final tpl = page.createTemplate();
      final section = to.sections!.add();
      section.pageSettings.margins.all = 0;
      section.pageSettings.size = size;
      final np = section.pages.add();
      np.graphics.drawPdfTemplate(tpl, Offset.zero, size);
    }
  }

  static Future<Uint8List> merge(List<Uint8List> files, List<String?> passwords) => Isolate.run(() {
        final out = PdfDocument();
        for (var i = 0; i < files.length; i++) {
          final src = _open(files[i], passwords[i]);
          _copyPages(src, out, List.generate(src.pages.count, (k) => k));
          src.dispose();
        }
        final bytes = Uint8List.fromList(out.saveSync());
        out.dispose();
        return bytes;
      });

  /// Keeps only [indexes] (0-based, in the given order).
  static Future<Uint8List> extractPages(Uint8List bytes, List<int> indexes, {String? password}) =>
      Isolate.run(() {
        final src = _open(bytes, password);
        final out = PdfDocument();
        _copyPages(src, out, indexes.where((i) => i >= 0 && i < src.pages.count));
        final res = Uint8List.fromList(out.saveSync());
        out.dispose();
        src.dispose();
        return res;
      });

  /// One PDF per page.
  static Future<List<Uint8List>> splitEach(Uint8List bytes, {String? password}) => Isolate.run(() {
        final src = _open(bytes, password);
        final list = <Uint8List>[];
        for (var i = 0; i < src.pages.count; i++) {
          final out = PdfDocument();
          _copyPages(src, out, [i]);
          list.add(Uint8List.fromList(out.saveSync()));
          out.dispose();
        }
        src.dispose();
        return list;
      });

  /// Parses "1-3, 5, 8-6" into 0-based indexes. Throws [FormatException].
  static List<int> parseRanges(String input, int pageCount) {
    final out = <int>[];
    for (final part in input.split(',')) {
      final t = part.trim();
      if (t.isEmpty) continue;
      final m = RegExp(r'^(\d+)\s*(?:-\s*(\d+))?$').firstMatch(t);
      if (m == null) throw FormatException('“$t” is not a page or range');
      final a = int.parse(m.group(1)!);
      final b = m.group(2) == null ? a : int.parse(m.group(2)!);
      if (a < 1 || b < 1 || a > pageCount || b > pageCount) {
        throw FormatException('Pages must be between 1 and $pageCount');
      }
      final step = a <= b ? 1 : -1;
      for (var i = a; step > 0 ? i <= b : i >= b; i += step) {
        out.add(i - 1);
      }
    }
    if (out.isEmpty) throw const FormatException('Enter at least one page');
    return out;
  }

  // ------------------------------------------------------------- rendering

  /// Renders every page of a PDF to JPEG files in [outDir].
  static Future<List<String>> renderToImages(
    Uint8List bytes,
    Directory outDir, {
    String? password,
    double dpi = 200,
    int maxSide = 3000,
    int quality = 88,
    void Function(int done, int total)? onProgress,
  }) async {
    var asked = false;
    final rx.PdfDocument doc;
    try {
      doc = await rx.PdfDocument.openData(
        bytes,
        passwordProvider: () {
          if (asked) return null;
          asked = true;
          return password;
        },
      );
    } catch (e) {
      if (password == null) throw const PasswordRequiredException();
      throw const WrongPasswordException();
    }
    final paths = <String>[];
    try {
      final total = doc.pages.length;
      for (var i = 0; i < total; i++) {
        final page = doc.pages[i];
        var scale = dpi / 72;
        final longest = math.max(page.width, page.height) * scale;
        if (longest > maxSide) scale *= maxSide / longest;
        final w = (page.width * scale).round();
        final h = (page.height * scale).round();
        final image = await page.render(
          width: w,
          height: h,
          fullWidth: w.toDouble(),
          fullHeight: h.toDouble(),
          backgroundColor: 0xFFFFFFFF,
        );
        if (image == null) continue;
        final out = p.join(outDir.path, 'page_${(i + 1).toString().padLeft(3, '0')}.jpg');
        await writeBgraAsJpeg(image.pixels, image.width, image.height, out, quality: quality);
        image.dispose();
        paths.add(out);
        onProgress?.call(i + 1, total);
      }
    } finally {
      await doc.dispose();
    }
    return paths;
  }

  /// Shrinks any PDF by re-rendering its pages as optimised images.
  static Future<Uint8List> compressExternal(
    Uint8List bytes,
    Directory work,
    ImageQuality level, {
    String? password,
    void Function(int done, int total)? onProgress,
  }) async {
    final dpi = switch (level) {
      ImageQuality.high => 170.0,
      ImageQuality.balanced => 130.0,
      ImageQuality.small => 96.0,
    };
    final pages = await renderToImages(bytes, work,
        password: password, dpi: dpi, quality: level.jpegQuality, onProgress: onProgress);
    return buildFromImages(pages, const PdfOptions(textLayer: false));
  }
}

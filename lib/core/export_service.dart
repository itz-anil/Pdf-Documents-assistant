import 'dart:io';
import 'dart:isolate';

import 'package:archive/archive.dart';
import 'package:flutter/services.dart';
import 'package:open_filex/open_filex.dart';
import 'package:path/path.dart' as p;
import 'package:printing/printing.dart';
import 'package:share_plus/share_plus.dart';

import 'library_store.dart';
import 'models.dart';
import 'pdf_service.dart';
import 'settings.dart';

enum ZipContent { pdf, images, text }

class ZipEntrySource {
  final String name;
  final String path;
  const ZipEntrySource(this.name, this.path);
}

/// Sharing, saving, printing and archive helpers.
class ExportService {
  ExportService._();

  static String mimeFor(String path) => switch (p.extension(path).toLowerCase()) {
        '.pdf' => 'application/pdf',
        '.jpg' || '.jpeg' => 'image/jpeg',
        '.png' => 'image/png',
        '.zip' => 'application/zip',
        '.txt' => 'text/plain',
        '.vcf' => 'text/x-vcard',
        _ => 'application/octet-stream',
      };

  static Future<void> share(List<String> paths, {String? subject}) async {
    await SharePlus.instance.share(ShareParams(
      files: paths.map((x) => XFile(x, mimeType: mimeFor(x))).toList(),
      subject: subject,
    ));
  }

  static Future<void> shareText(String text, {String? subject}) async {
    await SharePlus.instance.share(ShareParams(text: text, subject: subject));
  }

  static const _storage = MethodChannel('docmind/storage');

  /// Saves a copy into the phone's public storage: PDFs, ZIPs and text go to
  /// Downloads/DocMind, images to Pictures/DocMind (visible in Gallery).
  /// Returns where the file was saved.
  static Future<String> saveToDevice(String path, {String? fileName}) async {
    final name = fileName ?? p.basename(path);
    if (!Platform.isAndroid) {
      await share([path]);
      return name;
    }
    try {
      final where = await _storage.invokeMethod<String>('saveToPublic', {
        'path': path,
        'name': name,
        'mime': mimeFor(path),
      });
      return where ?? name;
    } on PlatformException catch (e) {
      throw Exception(e.code == 'permission'
          ? 'Allow storage access to save files to Downloads'
          : (e.message ?? 'Could not save the file'));
    }
  }

  /// Saves several files; returns the folder they went to.
  static Future<String> saveAllToDevice(List<String> paths) async {
    var where = '';
    for (final x in paths) {
      where = await saveToDevice(x);
    }
    return p.dirname(where);
  }

  static Future<void> printPdf(Uint8List bytes, String name) =>
      Printing.layoutPdf(onLayout: (_) async => bytes, name: name);

  static Future<void> open(String path) => OpenFilex.open(path);

  /// Writes a ZIP archive in a background isolate. Optional AES password.
  static Future<File> zip(List<ZipEntrySource> entries, String outPath, {String? password}) async {
    await Isolate.run(() {
      final archive = Archive();
      final used = <String>{};
      for (final e in entries) {
        var name = e.name;
        var n = 2;
        while (!used.add(name)) {
          name = '${p.basenameWithoutExtension(e.name)} ($n)${p.extension(e.name)}';
          n++;
        }
        archive.addFile(ArchiveFile.bytes(name, File(e.path).readAsBytesSync()));
      }
      final encoder = ZipEncoder(password: (password == null || password.isEmpty) ? null : password);
      File(outPath).writeAsBytesSync(encoder.encodeBytes(archive, level: DeflateLevel.defaultCompression));
    });
    return File(outPath);
  }

  /// Extracts a ZIP into [outDir]. Returns extracted file paths.
  static Future<List<String>> unzip(String zipPath, String outDir, {String? password}) => Isolate.run(() {
        final archive = ZipDecoder().decodeBytes(
          File(zipPath).readAsBytesSync(),
          password: (password == null || password.isEmpty) ? null : password,
        );
        final out = <String>[];
        for (final f in archive) {
          if (!f.isFile) continue;
          final safe = p.normalize(f.name).replaceAll('..', '_');
          final target = File(p.join(outDir, safe));
          target.parent.createSync(recursive: true);
          target.writeAsBytesSync(f.content as List<int>);
          out.add(target.path);
        }
        return out;
      });

  // -------------------------------------------------------- document export

  static Future<File> docPdf(
    LibraryStore store,
    DocItem doc, {
    String? password,
    ImageQuality? compress,
  }) async {
    final bytes = await PdfService.buildDocument(
      store,
      doc,
      PdfOptions(
        pageSize: store.settings.pageSize,
        password: password,
        maxSide: compress?.maxSide,
        jpegQuality: compress?.jpegQuality,
      ),
    );
    final dir = await store.scratch('pdf');
    final file = File(p.join(dir.path, '${safeFileName(doc.name)}.pdf'));
    await file.writeAsBytes(bytes, flush: true);
    return file;
  }

  static Future<List<String>> docImages(LibraryStore store, DocItem doc) async {
    final dir = await store.scratch('jpg');
    final out = <String>[];
    final base = safeFileName(doc.name);
    for (var i = 0; i < doc.pages.length; i++) {
      final name = doc.pages.length == 1 ? '$base.jpg' : '$base - ${i + 1}.jpg';
      final f = await store.processedFile(doc, doc.pages[i]).copy(p.join(dir.path, name));
      out.add(f.path);
    }
    return out;
  }

  static Future<File> docText(LibraryStore store, DocItem doc) async {
    final dir = await store.scratch('txt');
    final buf = StringBuffer();
    for (var i = 0; i < doc.pages.length; i++) {
      if (doc.pages.length > 1) buf.writeln('--- Page ${i + 1} ---');
      buf.writeln(doc.pages[i].ocrText);
      buf.writeln();
    }
    final f = File(p.join(dir.path, '${safeFileName(doc.name)}.txt'));
    await f.writeAsString(buf.toString().trim(), flush: true);
    return f;
  }

  /// ZIP of one or more documents with the chosen contents.
  static Future<File> docsZip(
    LibraryStore store,
    List<DocItem> docs,
    Set<ZipContent> content, {
    String? password,
  }) async {
    final entries = <ZipEntrySource>[];
    for (final d in docs) {
      final folder = docs.length > 1 ? '${safeFileName(d.name)}/' : '';
      if (content.contains(ZipContent.pdf)) {
        final pdf = await docPdf(store, d);
        entries.add(ZipEntrySource('$folder${p.basename(pdf.path)}', pdf.path));
      }
      if (content.contains(ZipContent.images)) {
        for (final img in await docImages(store, d)) {
          entries.add(ZipEntrySource('${folder}images/${p.basename(img)}', img));
        }
      }
      if (content.contains(ZipContent.text)) {
        final t = await docText(store, d);
        entries.add(ZipEntrySource('$folder${p.basename(t.path)}', t.path));
      }
    }
    final dir = await store.scratch('zip');
    final name = docs.length == 1 ? safeFileName(docs.first.name) : 'DocMind ${docs.length} documents';
    return zip(entries, p.join(dir.path, '$name.zip'), password: password);
  }
}

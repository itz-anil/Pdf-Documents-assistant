import 'dart:io';
import 'dart:typed_data';

import 'package:file_picker/file_picker.dart';
import 'package:flutter/material.dart';
import 'package:path/path.dart' as p;
import 'package:provider/provider.dart';

import '../core/library_store.dart';
import '../core/models.dart';
import '../core/pdf_service.dart';
import '../core/scan_service.dart';
import '../widgets/common.dart';
import 'business_card_screen.dart';
import 'camera_screen.dart';
import 'id_card_screen.dart';
import 'editor_screen.dart';
import 'lock_gate.dart';

/// Entry points for creating documents. Every capture goes through the one
/// shared [CameraScreen] and the one shared [_pageSources] pipeline.
class ScanFlow {
  ScanFlow._();

  /// The big Scan button: straight into the camera, like Adobe Scan.
  static Future<void> chooseAndScan(BuildContext context, {String? folderId}) {
    haptic(context);
    return scan(context, ScanMode.document, folderId: folderId);
  }

  static Future<void> scan(BuildContext context, ScanMode mode, {String? folderId}) async {
    final r = await CameraScreen.open(context, mode: CameraModeInfo.fromScan(mode));
    if (r == null || r.shots.isEmpty || !context.mounted) return;
    await createFromCapture(context, r, folderId: folderId);
  }

  static Future<void> openQr(BuildContext context) =>
      CameraScreen.open(context, mode: CameraMode.qr, lockMode: true);

  /// Shared: shots → page sources for any mode (book split, ID card layout).
  /// Returns null if the user backed out (e.g. from the ID card review).
  static Future<List<PageSource>?> _pageSources(BuildContext context, CaptureResult r) async {
    final store = context.read<LibraryStore>();
    final shots = [for (final s in r.shots) (s.path, s.quad)];
    switch (r.mode) {
      case CameraMode.book:
        return runBusy(context, 'Splitting pages…', (_) async => ScanService.bookPages(shots, await store.scratch('book')));
      case CameraMode.idCard:
        final page = await Navigator.of(context).push<String>(MaterialPageRoute(
          builder: (_) => IdCardScreen(front: r.shots.first, back: r.shots.length > 1 ? r.shots[1] : null),
        ));
        return page == null ? null : [PageSource(page)];
      default:
        return ScanService.pages(shots);
    }
  }

  /// Shared: builds a new document from a capture and opens the next screen.
  static Future<void> createFromCapture(BuildContext context, CaptureResult r, {String? folderId}) async {
    final store = context.read<LibraryStore>();
    final sources = await _pageSources(context, r);
    if (sources == null || sources.isEmpty || !context.mounted) return;
    final mode = r.mode.scanMode;
    final doc = await runBusy(context, 'Enhancing pages…', (progress) {
      return store.createDocument(
        pages: sources,
        mode: mode,
        folderId: folderId,
        onProgress: (d, t) => progress.value = t == 1 ? 'Enhancing page…' : 'Enhancing page $d of $t…',
      );
    });
    if (doc == null || !context.mounted) return;
    if (mode == ScanMode.businessCard) {
      await runBusy(context, 'Reading card…', (_) => store.runOcrNow(doc));
      if (!context.mounted) return;
      await Navigator.of(context).push(MaterialPageRoute(builder: (_) => BusinessCardScreen(doc: doc)));
      return;
    }
    await Navigator.of(context).push(MaterialPageRoute(builder: (_) => EditorScreen(doc: doc, isNew: true)));
  }

  static Future<void> importPhotos(BuildContext context, {String? folderId}) async {
    final store = context.read<LibraryStore>();
    LockGate.externalActivity = true;
    final List<String> paths;
    try {
      paths = await ScanService.pickPhotos();
    } finally {
      LockGate.externalActivity = false;
    }
    if (paths.isEmpty || !context.mounted) return;
    final doc = await runBusy(
      context,
      'Importing ${paths.length} photo${paths.length == 1 ? '' : 's'}…',
      (progress) => store.createDocument(
        pages: [for (final x in paths) PageSource(x, detect: true)],
        folderId: folderId,
        onProgress: (d, t) => progress.value = 'Finding edges · $d of $t…',
      ),
    );
    if (doc == null || !context.mounted) return;
    await Navigator.of(context).push(MaterialPageRoute(builder: (_) => EditorScreen(doc: doc, isNew: true)));
  }

  /// Adds pages to an existing document with the same camera and mode.
  static Future<void> addPages(BuildContext context, DocItem doc) async {
    final store = context.read<LibraryStore>();
    final r = await CameraScreen.open(context, mode: CameraModeInfo.fromScan(doc.mode), lockMode: true, purpose: 'Add pages');
    if (r == null || r.shots.isEmpty || !context.mounted) return;
    final sources = await _pageSources(context, r);
    if (sources == null || !context.mounted) return;
    await runBusy(context, 'Adding pages…', (_) => store.addPages(doc, sources));
  }

  /// Replaces one page with a new photo, keeping its filter.
  static Future<void> retakePage(BuildContext context, DocItem doc, PageItem page) async {
    final store = context.read<LibraryStore>();
    final mode = doc.mode == ScanMode.idCard ? CameraMode.document : CameraModeInfo.fromScan(doc.mode);
    final r = await CameraScreen.open(context, mode: mode, lockMode: true, maxShots: 1, purpose: 'Retake page');
    if (r == null || r.shots.isEmpty || !context.mounted) return;
    final shot = r.shots.first;
    await runBusy(context, 'Updating page…',
        (_) => store.replacePageImage(doc, page, shot.path, quad: shot.quad, keepFilter: true));
  }

  /// Picks one PDF. Returns its bytes and name, asking for a password when needed.
  static Future<PickedPdf?> pickPdf(BuildContext context, {String title = 'Choose a PDF'}) async {
    LockGate.externalActivity = true;
    final PlatformFile? f;
    try {
      f = await FilePicker.pickFile(type: FileType.custom, allowedExtensions: ['pdf'], dialogTitle: title);
    } finally {
      LockGate.externalActivity = false;
    }
    if (f == null) return null;
    final bytes = await f.xFile.readAsBytes();
    if (!context.mounted) return null;
    return unlockIfNeeded(context, PickedPdf(f.name, bytes));
  }

  /// Asks for the password of an encrypted PDF until it opens or the user gives up.
  static Future<PickedPdf?> unlockIfNeeded(BuildContext context, PickedPdf pdf) async {
    if (!await PdfService.isEncrypted(pdf.bytes)) return pdf;
    if (!context.mounted) return null;
    var message = '“${pdf.name}” is password protected.';
    while (context.mounted) {
      final pw = await promptPassword(context, title: 'Enter password', message: message, action: 'Unlock');
      if (pw == null) return null;
      try {
        await PdfService.pageCount(pdf.bytes, password: pw);
        return PickedPdf(pdf.name, pdf.bytes, password: pw);
      } catch (_) {
        message = 'That password did not work. Try again.';
      }
    }
    return null;
  }

  static Future<void> importPdf(BuildContext context, {String? folderId}) async {
    final store = context.read<LibraryStore>();
    final pdf = await pickPdf(context, title: 'Import PDF');
    if (pdf == null || !context.mounted) return;
    final doc = await runBusy(context, 'Importing PDF…', (progress) async {
      final work = await store.scratch('import');
      final pages = await PdfService.renderToImages(
        pdf.bytes,
        work,
        password: pdf.password,
        onProgress: (d, t) => progress.value = 'Reading page $d of $t…',
      );
      progress.value = 'Building document…';
      return store.createDocument(
        pages: [for (final x in pages) PageSource(x)],
        name: p.basenameWithoutExtension(pdf.name),
        folderId: folderId,
        filter: PageFilter.original,
      );
    });
    if (doc == null || !context.mounted) return;
    toast(context, 'Imported ${doc.pages.length} pages');
    await Navigator.of(context).push(MaterialPageRoute(builder: (_) => EditorScreen(doc: doc, isNew: true)));
  }

}

class PickedPdf {
  final String name;
  final Uint8List bytes;
  final String? password;
  PickedPdf(this.name, this.bytes, {this.password});
}

extension PickedPdfFile on PickedPdf {
  Future<File> writeTo(Directory dir) async {
    final f = File(p.join(dir.path, name));
    await f.writeAsBytes(bytes, flush: true);
    return f;
  }
}

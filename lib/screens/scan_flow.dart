import 'dart:io';
import 'dart:typed_data';

import 'package:file_picker/file_picker.dart';
import 'package:flutter/material.dart';
import 'package:path/path.dart' as p;
import '../app/icons.dart';
import 'package:provider/provider.dart';

import '../app/theme.dart';
import '../core/library_store.dart';
import '../core/models.dart';
import '../core/pdf_service.dart';
import '../core/scan_service.dart';
import '../widgets/common.dart';
import '../widgets/glass.dart';
import 'business_card_screen.dart';
import 'editor_screen.dart';
import 'lock_gate.dart';

/// Entry points for creating documents: camera modes and imports.
class ScanFlow {
  ScanFlow._();

  static Future<void> chooseAndScan(BuildContext context, {String? folderId}) async {
    haptic(context);
    final choice = await showGlassSheet<Object>(
      context,
      builder: (ctx) {
        final g = Glass.of(ctx);
        return SingleChildScrollView(
          padding: const EdgeInsets.fromLTRB(16, 14, 16, 12),
          child: Column(
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              Padding(
                padding: const EdgeInsets.symmetric(horizontal: 6),
                child: Text('New scan', style: TextStyle(fontSize: 20, fontWeight: FontWeight.w800, color: g.text)),
              ),
              Padding(
                padding: const EdgeInsets.fromLTRB(6, 4, 6, 14),
                child: Text('Pick what you are capturing — edges are found automatically.',
                    style: TextStyle(color: g.muted)),
              ),
              GridView.count(
                crossAxisCount: 3,
                shrinkWrap: true,
                physics: const NeverScrollableScrollPhysics(),
                mainAxisSpacing: 10,
                crossAxisSpacing: 10,
                childAspectRatio: 0.92,
                children: [
                  for (final m in ScanMode.values)
                    GlassPanel(
                      radius: 20,
                      onTap: () => Navigator.pop(ctx, m),
                      padding: const EdgeInsets.all(10),
                      child: Column(
                        mainAxisAlignment: MainAxisAlignment.center,
                        children: [
                          IconBadge(m.icon, size: 48, filled: m == ScanMode.document),
                          const SizedBox(height: 10),
                          Text(m.label,
                              textAlign: TextAlign.center,
                              style: TextStyle(fontWeight: FontWeight.w700, fontSize: 13, color: g.text)),
                        ],
                      ),
                    ),
                ],
              ),
              const SizedBox(height: 14),
              GlassTile(
                icon: PhosphorIconsDuotone.images,
                title: 'Import photos',
                subtitle: 'Turn gallery images into a document',
                onTap: () => Navigator.pop(ctx, 'photos'),
              ),
              GlassTile(
                icon: PhosphorIconsDuotone.filePdf,
                title: 'Import PDF',
                subtitle: 'Bring an existing PDF into DocMind',
                onTap: () => Navigator.pop(ctx, 'pdf'),
              ),
            ],
          ),
        );
      },
    );
    if (!context.mounted || choice == null) return;
    if (choice is ScanMode) {
      await scan(context, choice, folderId: folderId);
    } else if (choice == 'photos') {
      await importPhotos(context, folderId: folderId);
    } else if (choice == 'pdf') {
      await importPdf(context, folderId: folderId);
    }
  }

  static Future<void> scan(BuildContext context, ScanMode mode, {String? folderId}) async {
    final store = context.read<LibraryStore>();
    List<String> shots;
    LockGate.externalActivity = true;
    try {
      shots = await ScanService.capture(mode: mode);
    } catch (e) {
      if (context.mounted) toast(context, 'Camera scanner unavailable: ${friendlyError(e)}', error: true);
      return;
    } finally {
      LockGate.externalActivity = false;
    }
    if (shots.isEmpty || !context.mounted) return;
    if (mode == ScanMode.idCard && shots.length == 1 && context.mounted) {
      toast(context, 'Only the front side was captured');
    }
    final doc = await runBusy(context, 'Enhancing pages…', (progress) async {
      final work = await store.scratch('scan');
      final pages = await ScanService.prepare(mode, shots, work);
      progress.value = 'Enhancing ${pages.length} page${pages.length == 1 ? '' : 's'}…';
      return store.createDocument(imagePaths: pages, mode: mode, folderId: folderId);
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
      (_) => store.createDocument(imagePaths: paths, folderId: folderId),
    );
    if (doc == null || !context.mounted) return;
    await Navigator.of(context).push(MaterialPageRoute(builder: (_) => EditorScreen(doc: doc, isNew: true)));
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
        imagePaths: pages,
        name: p.basenameWithoutExtension(pdf.name),
        folderId: folderId,
        filter: PageFilter.original,
      );
    });
    if (doc == null || !context.mounted) return;
    toast(context, 'Imported ${doc.pages.length} pages');
    await Navigator.of(context).push(MaterialPageRoute(builder: (_) => EditorScreen(doc: doc, isNew: true)));
  }

  /// Adds more pages to an existing document from camera or gallery.
  static Future<void> addPages(BuildContext context, DocItem doc) async {
    final store = context.read<LibraryStore>();
    final src = await pickOption<String>(
      context,
      title: 'Add pages',
      options: const ['camera', 'photos'],
      label: (o) => o == 'camera' ? 'Scan with camera' : 'Choose photos',
      icon: (o) => o == 'camera' ? PhosphorIconsDuotone.camera : PhosphorIconsDuotone.images,
    );
    if (src == null || !context.mounted) return;
    LockGate.externalActivity = true;
    List<String> paths;
    try {
      paths = src == 'camera' ? await ScanService.capture(mode: doc.mode) : await ScanService.pickPhotos();
    } catch (e) {
      if (context.mounted) toast(context, friendlyError(e), error: true);
      return;
    } finally {
      LockGate.externalActivity = false;
    }
    if (paths.isEmpty || !context.mounted) return;
    await runBusy(context, 'Adding pages…', (_) async {
      final work = await store.scratch('add');
      final pages = src == 'camera' ? await ScanService.prepare(doc.mode, paths, work) : paths;
      await store.addPages(doc, pages);
    });
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

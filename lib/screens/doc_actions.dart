import 'dart:io';

import 'package:flutter/material.dart';
import '../app/icons.dart';
import 'package:provider/provider.dart';

import '../app/theme.dart';
import '../core/export_service.dart';
import '../core/library_store.dart';
import '../core/models.dart';
import '../core/settings.dart';
import '../widgets/common.dart';
import '../widgets/doc_tile.dart';
import '../widgets/glass.dart';
import 'business_card_screen.dart';
import 'document_screen.dart';
import 'ocr_text_screen.dart';

/// Actions shared by the home list, selection bar and document viewer.
class DocActions {
  DocActions._();

  static Future<void> open(BuildContext context, DocItem doc, {int page = 0, String? highlight}) =>
      Navigator.of(context).push(MaterialPageRoute(
        builder: (_) => DocumentScreen(doc: doc, initialPage: page, highlight: highlight),
      ));

  static Future<void> rename(BuildContext context, DocItem doc) async {
    final name = await promptText(context, title: 'Rename document', initial: doc.name, hint: 'Document name');
    if (name != null && name.trim().isNotEmpty && context.mounted) {
      context.read<LibraryStore>().rename(doc, name);
    }
  }

  static Future<bool> delete(BuildContext context, List<DocItem> docs) async {
    final many = docs.length > 1;
    final ok = await confirm(
      context,
      title: many ? 'Delete ${docs.length} documents?' : 'Delete document?',
      message: many ? 'These documents will be removed from this device.' : '“${docs.first.name}” will be removed from this device.',
    );
    if (!ok || !context.mounted) return false;
    await context.read<LibraryStore>().deleteDocs(docs);
    if (context.mounted) toast(context, many ? 'Documents deleted' : 'Document deleted');
    return true;
  }

  static Future<void> moveToFolder(BuildContext context, List<DocItem> docs) async {
    final store = context.read<LibraryStore>();
    const none = '__none__';
    const create = '__new__';
    final options = [none, ...store.folders.map((f) => f.id), create];
    final choice = await pickOption<String>(
      context,
      title: 'Move to folder',
      options: options,
      label: (o) => o == none
          ? 'No folder'
          : o == create
              ? 'New folder…'
              : store.folders.firstWhere((f) => f.id == o).name,
      icon: (o) => o == create
          ? PhosphorIconsRegular.folderPlus
          : o == none
              ? PhosphorIconsRegular.folderDashed
              : PhosphorIconsRegular.folder,
      selected: docs.length == 1 ? (docs.first.folderId ?? none) : null,
    );
    if (choice == null || !context.mounted) return;
    String? target;
    if (choice == create) {
      final f = await createFolder(context);
      if (f == null) return;
      target = f.id;
    } else if (choice != none) {
      target = choice;
    }
    store.moveToFolder(docs, target);
    if (context.mounted) toast(context, target == null ? 'Removed from folder' : 'Moved');
  }

  static Future<Folder?> createFolder(BuildContext context) async {
    final name = await promptText(context, title: 'New folder', hint: 'Folder name', action: 'Create');
    if (name == null || name.trim().isEmpty || !context.mounted) return null;
    final store = context.read<LibraryStore>();
    return store.createFolder(name, store.folders.length % folderColors.length);
  }

  // ---------------------------------------------------------------- sharing

  static Future<void> shareSheet(BuildContext context, DocItem doc) {
    return showGlassSheet<void>(
      context,
      builder: (ctx) => ListView(
        shrinkWrap: true,
        padding: const EdgeInsets.fromLTRB(10, 14, 10, 12),
        children: [
          _sheetTitle(ctx, 'Share', doc.name),
          GlassTile(
            icon: PhosphorIconsRegular.filePdf,
            title: 'PDF',
            subtitle: 'Searchable PDF with selectable text',
            onTap: () {
              Navigator.pop(ctx);
              sharePdf(context, doc);
            },
          ),
          GlassTile(
            icon: PhosphorIconsRegular.images,
            title: 'Images (JPG)',
            subtitle: '${doc.pages.length} image${doc.pages.length == 1 ? '' : 's'}',
            onTap: () async {
              Navigator.pop(ctx);
              final files = await runBusy(context, 'Preparing images…', (_) => ExportService.docImages(context.read(), doc));
              if (files != null) await ExportService.share(files);
            },
          ),
          GlassTile(
            icon: PhosphorIconsRegular.fileZip,
            title: 'ZIP archive',
            subtitle: 'PDF, images and text in one file',
            onTap: () {
              Navigator.pop(ctx);
              zip(context, [doc]);
            },
          ),
          GlassTile(
            icon: PhosphorIconsRegular.lockKey,
            title: 'Password-protected PDF',
            subtitle: 'Only people with the password can open it',
            onTap: () {
              Navigator.pop(ctx);
              protectedPdf(context, doc);
            },
          ),
          GlassTile(
            icon: PhosphorIconsRegular.arrowsInSimple,
            title: 'Compressed PDF',
            subtitle: 'Smaller file for email and chat',
            onTap: () {
              Navigator.pop(ctx);
              compress(context, doc);
            },
          ),
          GlassTile(
            icon: PhosphorIconsRegular.textAa,
            title: 'Text only',
            subtitle: 'Recognised text as a .txt file',
            onTap: () async {
              Navigator.pop(ctx);
              if (doc.fullText.isEmpty) {
                toast(context, 'No text recognised yet', error: true);
                return;
              }
              final f = await ExportService.docText(context.read(), doc);
              await ExportService.share([f.path]);
            },
          ),
        ],
      ),
    );
  }

  static Widget _sheetTitle(BuildContext ctx, String title, String subtitle) {
    final g = Glass.of(ctx);
    return Padding(
      padding: const EdgeInsets.fromLTRB(14, 0, 14, 8),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Text(title, style: TextStyle(fontSize: 19, fontWeight: FontWeight.w800, color: g.text)),
          Text(subtitle, maxLines: 1, overflow: TextOverflow.ellipsis, style: TextStyle(color: g.muted)),
        ],
      ),
    );
  }

  static Future<void> sharePdf(BuildContext context, DocItem doc) async {
    final f = await runBusy(context, 'Creating PDF…', (_) => ExportService.docPdf(context.read(), doc));
    if (f != null) await ExportService.share([f.path], subject: doc.name);
  }

  /// Creates the files and copies them into Downloads (or Gallery for JPG).
  static Future<void> _save(BuildContext context, String busy, Future<List<String>> Function() make) async {
    final where = await runBusy(context, busy, (progress) async {
      final files = await make();
      progress.value = 'Saving…';
      return (await ExportService.saveAllToDevice(files), files.length);
    });
    if (where != null && context.mounted) {
      toast(context, where.$2 == 1 ? 'Saved to ${where.$1}' : '${where.$2} files saved to ${where.$1}');
    }
  }

  static Future<void> savePdf(BuildContext context, DocItem doc) => _save(
      context, 'Creating PDF…', () async => [(await ExportService.docPdf(context.read(), doc)).path]);

  /// "Save as…" — PDF, JPG pages, ZIP, protected or compressed PDF.
  static Future<void> saveSheet(BuildContext context, DocItem doc) {
    final store = context.read<LibraryStore>();
    return showGlassSheet<void>(
      context,
      builder: (ctx) {
        void go(Future<void> Function() a) {
          Navigator.pop(ctx);
          a();
        }

        return ListView(
          shrinkWrap: true,
          padding: const EdgeInsets.fromLTRB(10, 14, 10, 12),
          children: [
            _sheetTitle(ctx, 'Save to phone', 'PDF & ZIP → Downloads/DocMind · JPG → Gallery'),
            GlassTile(
              icon: PhosphorIconsRegular.filePdf,
              title: 'Save as PDF',
              subtitle: 'Searchable PDF, ${doc.pages.length} page${doc.pages.length == 1 ? '' : 's'}',
              onTap: () => go(() => savePdf(context, doc)),
            ),
            GlassTile(
              icon: PhosphorIconsRegular.image,
              title: 'Save as JPG',
              subtitle: doc.pages.length == 1 ? 'One image in your Gallery' : '${doc.pages.length} images in your Gallery',
              onTap: () => go(() => _save(context, 'Preparing images…', () => ExportService.docImages(store, doc))),
            ),
            GlassTile(
              icon: PhosphorIconsRegular.fileZip,
              title: 'Save as ZIP',
              subtitle: 'PDF, images and text together',
              onTap: () => go(() => zip(context, [doc], save: true)),
            ),
            GlassTile(
              icon: PhosphorIconsRegular.lockKey,
              title: 'Save password-protected PDF',
              subtitle: 'AES-256 encrypted',
              onTap: () => go(() async {
                final pw = await promptPassword(context,
                    title: 'Protect PDF', message: 'This password will be needed to open the PDF.', confirmField: true, action: 'Save');
                if (pw == null || !context.mounted) return;
                await _save(context, 'Encrypting PDF…', () async => [(await ExportService.docPdf(store, doc, password: pw)).path]);
              }),
            ),
            GlassTile(
              icon: PhosphorIconsRegular.arrowsInSimple,
              title: 'Save compressed PDF',
              subtitle: 'Smaller file, good for sharing',
              onTap: () => go(() => _save(context, 'Compressing…',
                  () async => [(await ExportService.docPdf(store, doc, compress: ImageQuality.small)).path])),
            ),
            if (doc.fullText.isNotEmpty)
              GlassTile(
                icon: PhosphorIconsRegular.textAa,
                title: 'Save text (.txt)',
                onTap: () => go(() => _save(context, 'Saving text…', () async => [(await ExportService.docText(store, doc)).path])),
              ),
          ],
        );
      },
    );
  }

  static Future<void> print(BuildContext context, DocItem doc) async {
    final f = await runBusy(context, 'Preparing to print…', (_) => ExportService.docPdf(context.read(), doc));
    if (f != null) await ExportService.printPdf(await f.readAsBytes(), doc.name);
  }

  static Future<void> protectedPdf(BuildContext context, DocItem doc) async {
    final pw = await promptPassword(
      context,
      title: 'Protect PDF',
      message: 'Anyone opening this PDF will need this password. Keep it safe — it cannot be recovered.',
      confirmField: true,
      action: 'Protect',
    );
    if (pw == null || !context.mounted) return;
    final f = await runBusy(context, 'Encrypting PDF…', (_) => ExportService.docPdf(context.read(), doc, password: pw));
    if (f != null && context.mounted) {
      await showResultSheet(context, title: 'Protected PDF ready', files: [f.path], note: 'AES-256 encrypted');
    }
  }

  static Future<void> compress(BuildContext context, DocItem doc) async {
    final level = await pickOption<ImageQuality>(
      context,
      title: 'Compress PDF',
      options: ImageQuality.values,
      label: (q) => q.label,
      subtitle: (q) => q.hint,
      icon: (q) => switch (q) {
        ImageQuality.high => PhosphorIconsRegular.sparkle,
        ImageQuality.balanced => PhosphorIconsRegular.scales,
        ImageQuality.small => PhosphorIconsRegular.arrowsInSimple,
      },
    );
    if (level == null || !context.mounted) return;
    final f = await runBusy(context, 'Compressing…', (_) => ExportService.docPdf(context.read(), doc, compress: level));
    if (f != null && context.mounted) {
      await showResultSheet(context, title: 'Compressed PDF ready', files: [f.path]);
    }
  }

  static Future<void> zip(BuildContext context, List<DocItem> docs, {bool save = false}) async {
    final result = await showGlassSheet<(Set<ZipContent>, String?)>(
      context,
      builder: (_) => _ZipOptions(count: docs.length),
    );
    if (result == null || !context.mounted) return;
    final f = await runBusy(
      context,
      'Creating ZIP…',
      (_) => ExportService.docsZip(context.read(), docs, result.$1, password: result.$2),
    );
    if (f == null || !context.mounted) return;
    if (save) {
      try {
        final where = await ExportService.saveToDevice(f.path);
        if (context.mounted) toast(context, 'Saved to $where');
      } catch (e) {
        if (context.mounted) toast(context, friendlyError(e), error: true);
      }
      return;
    }
    await showResultSheet(
      context,
      title: 'ZIP ready',
      files: [f.path],
      note: result.$2 != null ? 'Password protected (AES)' : null,
    );
  }

  // ---------------------------------------------------------------- menu

  static Future<void> moreSheet(BuildContext context, DocItem doc, {VoidCallback? onDeleted}) {
    final store = context.read<LibraryStore>();
    return showGlassSheet<void>(
      context,
      builder: (ctx) {
        void go(Future<void> Function() action) {
          Navigator.pop(ctx);
          action();
        }

        return ListView(
          shrinkWrap: true,
          padding: const EdgeInsets.fromLTRB(10, 14, 10, 12),
          children: [
            _sheetTitle(ctx, doc.name, docMeta(doc)),
            GlassTile(
              icon: PhosphorIconsRegular.shareNetwork,
              title: 'Share',
              onTap: () => go(() => shareSheet(context, doc)),
            ),
            GlassTile(
              icon: PhosphorIconsRegular.pencilSimpleLine,
              title: 'Rename',
              onTap: () => go(() => rename(context, doc)),
            ),
            GlassTile(
              icon: doc.favorite ? PhosphorIconsRegular.starHalf : PhosphorIconsRegular.star,
              title: doc.favorite ? 'Remove from favourites' : 'Add to favourites',
              onTap: () => go(() async => store.toggleFavorite(doc)),
            ),
            GlassTile(
              icon: PhosphorIconsRegular.folderSimple,
              title: 'Move to folder',
              onTap: () => go(() => moveToFolder(context, [doc])),
            ),
            GlassTile(
              icon: PhosphorIconsRegular.downloadSimple,
              title: 'Save to phone',
              onTap: () => go(() => saveSheet(context, doc)),
            ),
            GlassTile(
              icon: PhosphorIconsRegular.fileZip,
              title: 'Export as ZIP',
              onTap: () => go(() => zip(context, [doc])),
            ),
            GlassTile(
              icon: PhosphorIconsRegular.lockKey,
              title: 'Password-protect PDF',
              onTap: () => go(() => protectedPdf(context, doc)),
            ),
            GlassTile(
              icon: PhosphorIconsRegular.arrowsInSimple,
              title: 'Compress PDF',
              onTap: () => go(() => compress(context, doc)),
            ),
            GlassTile(
              icon: PhosphorIconsRegular.textT,
              title: 'View text (OCR)',
              onTap: () => go(() => Navigator.of(context)
                  .push(MaterialPageRoute(builder: (_) => OcrTextScreen(doc: doc)))),
            ),
            if (doc.mode == ScanMode.businessCard)
              GlassTile(
                icon: PhosphorIconsRegular.addressBook,
                title: 'Save as contact',
                onTap: () => go(() => Navigator.of(context)
                    .push(MaterialPageRoute(builder: (_) => BusinessCardScreen(doc: doc)))),
              ),
            GlassTile(
              icon: PhosphorIconsRegular.printer,
              title: 'Print',
              onTap: () => go(() => print(context, doc)),
            ),
            GlassTile(
              icon: PhosphorIconsRegular.copy,
              title: 'Duplicate',
              onTap: () => go(() async {
                await runBusy(context, 'Duplicating…', (_) => store.duplicateDoc(doc));
              }),
            ),
            GlassTile(
              icon: PhosphorIconsRegular.trash,
              title: 'Delete',
              danger: true,
              onTap: () => go(() async {
                if (await delete(context, [doc])) onDeleted?.call();
              }),
            ),
          ],
        );
      },
    );
  }
}

class _ZipOptions extends StatefulWidget {
  final int count;
  const _ZipOptions({required this.count});

  @override
  State<_ZipOptions> createState() => _ZipOptionsState();
}

class _ZipOptionsState extends State<_ZipOptions> {
  final Set<ZipContent> _content = {ZipContent.pdf};
  bool _protect = false;
  final _pw = TextEditingController();
  bool _hidden = true;

  @override
  Widget build(BuildContext context) {
    final g = Glass.of(context);
    Widget option(ZipContent c, IconData icon, String title, String sub) {
      final on = _content.contains(c);
      return GlassTile(
        icon: icon,
        title: title,
        subtitle: sub,
        trailing: Checkbox(
          value: on,
          onChanged: (_) => setState(() => on ? _content.remove(c) : _content.add(c)),
        ),
        onTap: () => setState(() => on ? _content.remove(c) : _content.add(c)),
      );
    }

    return SingleChildScrollView(
      padding: const EdgeInsets.fromLTRB(10, 14, 10, 14),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Padding(
            padding: const EdgeInsets.fromLTRB(14, 0, 14, 4),
            child: Text('Create ZIP', style: TextStyle(fontSize: 19, fontWeight: FontWeight.w800, color: g.text)),
          ),
          Padding(
            padding: const EdgeInsets.fromLTRB(14, 0, 14, 8),
            child: Text(
              widget.count == 1 ? 'Choose what goes inside' : '${widget.count} documents · choose what goes inside',
              style: TextStyle(color: g.muted),
            ),
          ),
          option(ZipContent.pdf, PhosphorIconsRegular.filePdf, 'PDF', 'Searchable PDF per document'),
          option(ZipContent.images, PhosphorIconsRegular.images, 'Images', 'Every page as JPG'),
          option(ZipContent.text, PhosphorIconsRegular.textAa, 'Text', 'Recognised text (.txt)'),
          GlassTile(
            icon: PhosphorIconsRegular.password,
            title: 'Protect with password',
            subtitle: 'AES-encrypted ZIP',
            trailing: Switch(value: _protect, onChanged: (v) => setState(() => _protect = v)),
            onTap: () => setState(() => _protect = !_protect),
          ),
          AnimatedSize(
            duration: const Duration(milliseconds: 200),
            curve: Curves.easeOut,
            child: _protect
                ? Padding(
                    padding: const EdgeInsets.fromLTRB(14, 4, 14, 4),
                    child: TextField(
                      controller: _pw,
                      obscureText: _hidden,
                      onChanged: (_) => setState(() {}),
                      decoration: InputDecoration(
                        labelText: 'ZIP password',
                        suffixIcon: IconButton(
                          tooltip: _hidden ? 'Show password' : 'Hide password',
                          icon: PhosphorIcon(_hidden ? PhosphorIconsRegular.eye : PhosphorIconsRegular.eyeSlash),
                          onPressed: () => setState(() => _hidden = !_hidden),
                        ),
                      ),
                    ),
                  )
                : const SizedBox(width: double.infinity),
          ),
          const SizedBox(height: 14),
          Padding(
            padding: const EdgeInsets.symmetric(horizontal: 14),
            child: GradientButton(
              label: 'Create ZIP',
              icon: PhosphorIconsRegular.fileZip,
              expand: true,
              onTap: _content.isEmpty || (_protect && _pw.text.isEmpty)
                  ? null
                  : () => Navigator.pop(context, (_content, _protect ? _pw.text : null)),
            ),
          ),
        ],
      ),
    );
  }
}

/// Shared helper so the result sheet's file list type stays simple.
List<String> pathsOf(List<File> files) => files.map((f) => f.path).toList();

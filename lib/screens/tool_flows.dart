import 'dart:io';

import 'package:file_picker/file_picker.dart';
import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:path/path.dart' as p;
import '../app/icons.dart';
import 'package:provider/provider.dart';

import '../app/theme.dart';
import '../core/export_service.dart';
import '../core/image_processing.dart';
import '../core/library_store.dart';
import '../core/ocr_service.dart';
import '../core/pdf_service.dart';
import '../core/scan_service.dart';
import '../core/settings.dart';
import '../widgets/common.dart';
import '../widgets/glass.dart';
import 'lock_gate.dart';
import 'scan_flow.dart';

String _base(String name) => p.basenameWithoutExtension(name);

Future<File> _write(LibraryStore store, String label, String fileName, List<int> bytes) async {
  final dir = await store.scratch(label);
  final f = File(p.join(dir.path, fileName));
  await f.writeAsBytes(bytes, flush: true);
  return f;
}

/// Standalone tools that work on any file, not just library documents.
class ToolFlows {
  ToolFlows._();

  static Future<void> merge(BuildContext context) =>
      Navigator.of(context).push(MaterialPageRoute(builder: (_) => const MergeScreen()));

  static Future<void> split(BuildContext context) async {
    final store = context.read<LibraryStore>();
    final pdf = await ScanFlow.pickPdf(context, title: 'Split PDF');
    if (pdf == null || !context.mounted) return;
    final count = await PdfService.pageCount(pdf.bytes, password: pdf.password);
    if (!context.mounted) return;
    final mode = await pickOption<String>(
      context,
      title: 'Split “${pdf.name}” · $count pages',
      options: const ['range', 'each'],
      label: (o) => o == 'range' ? 'Extract pages' : 'Split into single pages',
      subtitle: (o) => o == 'range' ? 'Pick pages like 1-3, 5' : '$count separate PDFs in a ZIP',
      icon: (o) => o == 'range' ? PhosphorIconsDuotone.selection : PhosphorIconsDuotone.squareSplitHorizontal,
    );
    if (mode == null || !context.mounted) return;
    if (mode == 'range') {
      final input = await promptText(
        context,
        title: 'Pages to extract',
        hint: 'e.g. 1-3, 5, 8',
        action: 'Extract',
        keyboard: TextInputType.text,
      );
      if (input == null || !context.mounted) return;
      final List<int> pages;
      try {
        pages = PdfService.parseRanges(input, count);
      } on FormatException catch (e) {
        toast(context, e.message, error: true);
        return;
      }
      final f = await runBusy(context, 'Extracting pages…', (_) async {
        final bytes = await PdfService.extractPages(pdf.bytes, pages, password: pdf.password);
        return _write(store, 'split', '${_base(pdf.name)} (pages ${input.replaceAll(' ', '')}).pdf', bytes);
      });
      if (f != null && context.mounted) {
        await showResultSheet(context, title: '${pages.length} pages extracted', files: [f.path]);
      }
    } else {
      final f = await runBusy(context, 'Splitting…', (progress) async {
        final parts = await PdfService.splitEach(pdf.bytes, password: pdf.password);
        final dir = await store.scratch('split');
        final entries = <ZipEntrySource>[];
        for (var i = 0; i < parts.length; i++) {
          final name = '${_base(pdf.name)} - page ${i + 1}.pdf';
          final file = File(p.join(dir.path, name));
          await file.writeAsBytes(parts[i]);
          entries.add(ZipEntrySource(name, file.path));
        }
        progress.value = 'Packing ZIP…';
        return ExportService.zip(entries, p.join(dir.path, '${_base(pdf.name)} pages.zip'));
      });
      if (f != null && context.mounted) {
        await showResultSheet(context, title: 'Split into $count PDFs', files: [f.path]);
      }
    }
  }

  static Future<void> compress(BuildContext context) async {
    final store = context.read<LibraryStore>();
    final pdf = await ScanFlow.pickPdf(context, title: 'Compress PDF');
    if (pdf == null || !context.mounted) return;
    final level = await pickOption<ImageQuality>(
      context,
      title: 'Compression level',
      options: ImageQuality.values,
      label: (q) => q.label,
      subtitle: (q) => q.hint,
      icon: (q) => switch (q) {
        ImageQuality.high => PhosphorIconsDuotone.sparkle,
        ImageQuality.balanced => PhosphorIconsDuotone.scales,
        ImageQuality.small => PhosphorIconsDuotone.arrowsInSimple,
      },
    );
    if (level == null || !context.mounted) return;
    final f = await runBusy(context, 'Compressing…', (progress) async {
      final work = await store.scratch('compress_work');
      final bytes = await PdfService.compressExternal(
        pdf.bytes,
        work,
        level,
        password: pdf.password,
        onProgress: (d, t) => progress.value = 'Optimising page $d of $t…',
      );
      return _write(store, 'compress', '${_base(pdf.name)} (compressed).pdf', bytes);
    });
    if (f != null && context.mounted) {
      final before = pdf.bytes.length;
      final after = await f.length();
      if (!context.mounted) return;
      final saved = before > 0 ? ((1 - after / before) * 100).round() : 0;
      await showResultSheet(
        context,
        title: 'Compressed PDF ready',
        files: [f.path],
        note: saved > 0
            ? '${formatBytes(before)} → ${formatBytes(after)} ($saved% smaller). Pages were re-rendered as images.'
            : 'This PDF was already well optimised (${formatBytes(before)} → ${formatBytes(after)}).',
      );
    }
  }

  static Future<void> protect(BuildContext context) async {
    final store = context.read<LibraryStore>();
    final pdf = await ScanFlow.pickPdf(context, title: 'Protect PDF');
    if (pdf == null || !context.mounted) return;
    final pw = await promptPassword(
      context,
      title: pdf.password == null ? 'Set a password' : 'Set a new password',
      message: 'Anyone opening “${pdf.name}” will need this password. It cannot be recovered if forgotten.',
      confirmField: true,
      action: 'Protect',
    );
    if (pw == null || !context.mounted) return;
    final f = await runBusy(context, 'Encrypting…', (_) async {
      final bytes = await PdfService.protect(pdf.bytes, pw, currentPassword: pdf.password);
      return _write(store, 'protect', '${_base(pdf.name)} (protected).pdf', bytes);
    });
    if (f != null && context.mounted) {
      await showResultSheet(context, title: 'PDF protected', files: [f.path], note: 'AES-256 encryption');
    }
  }

  static Future<void> removePassword(BuildContext context) async {
    final store = context.read<LibraryStore>();
    LockGate.externalActivity = true;
    final PlatformFile? picked;
    try {
      picked = await FilePicker.pickFile(type: FileType.custom, allowedExtensions: ['pdf'], dialogTitle: 'Remove password');
    } finally {
      LockGate.externalActivity = false;
    }
    if (picked == null || !context.mounted) return;
    final raw = PickedPdf(picked.name, await picked.xFile.readAsBytes());
    if (!context.mounted) return;
    if (!await PdfService.isEncrypted(raw.bytes)) {
      if (context.mounted) toast(context, 'This PDF is not password protected');
      return;
    }
    if (!context.mounted) return;
    final pdf = await ScanFlow.unlockIfNeeded(context, raw);
    if (pdf == null || pdf.password == null || !context.mounted) return;
    final f = await runBusy(context, 'Removing password…', (_) async {
      final bytes = await PdfService.removePassword(pdf.bytes, pdf.password!);
      return _write(store, 'unlock', '${_base(pdf.name)} (unlocked).pdf', bytes);
    });
    if (f != null && context.mounted) {
      await showResultSheet(context, title: 'Password removed', files: [f.path], note: 'This copy opens without a password.');
    }
  }

  static Future<void> pdfToImages(BuildContext context) async {
    final store = context.read<LibraryStore>();
    final pdf = await ScanFlow.pickPdf(context, title: 'PDF to JPG');
    if (pdf == null || !context.mounted) return;
    final files = await runBusy(context, 'Converting…', (progress) async {
      final dir = await store.scratch('pdf2jpg');
      final pages = await PdfService.renderToImages(
        pdf.bytes,
        dir,
        password: pdf.password,
        onProgress: (d, t) => progress.value = 'Page $d of $t…',
      );
      final out = <String>[];
      for (var i = 0; i < pages.length; i++) {
        final name = pages.length == 1 ? '${_base(pdf.name)}.jpg' : '${_base(pdf.name)} - ${i + 1}.jpg';
        out.add((await File(pages[i]).rename(p.join(dir.path, name))).path);
      }
      return out;
    });
    if (files != null && files.isNotEmpty && context.mounted) {
      await showResultSheet(context, title: '${files.length} image${files.length == 1 ? '' : 's'} ready', files: files);
    }
  }

  static Future<void> imagesToPdf(BuildContext context) async {
    final store = context.read<LibraryStore>();
    LockGate.externalActivity = true;
    final List<String> paths;
    try {
      paths = await ScanService.pickPhotos();
    } finally {
      LockGate.externalActivity = false;
    }
    if (paths.isEmpty || !context.mounted) return;
    final f = await runBusy(context, 'Creating PDF…', (_) async {
      final q = store.settings.quality;
      final bytes = await PdfService.buildFromImages(
        paths,
        PdfOptions(pageSize: store.settings.pageSize, textLayer: false, maxSide: q.maxSide, jpegQuality: q.jpegQuality),
      );
      return _write(store, 'img2pdf', '${store.defaultName()}.pdf', bytes);
    });
    if (f != null && context.mounted) {
      await showResultSheet(context, title: 'PDF ready', files: [f.path], note: '${paths.length} images');
    }
  }

  static Future<void> createZip(BuildContext context) async {
    final store = context.read<LibraryStore>();
    LockGate.externalActivity = true;
    final List<PlatformFile> files;
    try {
      files = await FilePicker.pickFiles(dialogTitle: 'Files to compress');
    } finally {
      LockGate.externalActivity = false;
    }
    if (files.isEmpty || !context.mounted) return;
    final protect = await pickOption<bool>(
      context,
      title: '${files.length} file${files.length == 1 ? '' : 's'} selected',
      options: const [false, true],
      label: (b) => b ? 'Password-protected ZIP' : 'Regular ZIP',
      subtitle: (b) => b ? 'AES encrypted, needs a password to open' : 'Opens anywhere',
      icon: (b) => b ? PhosphorIconsDuotone.lockKey : PhosphorIconsDuotone.fileZip,
    );
    if (protect == null || !context.mounted) return;
    String? pw;
    if (protect) {
      pw = await promptPassword(context, title: 'ZIP password', confirmField: true, action: 'Create');
      if (pw == null || !context.mounted) return;
    }
    final f = await runBusy(context, 'Creating ZIP…', (_) async {
      final dir = await store.scratch('zip_in');
      final entries = <ZipEntrySource>[];
      for (final pf in files) {
        final target = File(p.join(dir.path, pf.name));
        await target.writeAsBytes(await pf.xFile.readAsBytes());
        entries.add(ZipEntrySource(pf.name, target.path));
      }
      final out = await store.scratch('zip');
      final name = files.length == 1 ? _base(files.first.name) : 'DocMind archive';
      return ExportService.zip(entries, p.join(out.path, '$name.zip'), password: pw);
    });
    if (f != null && context.mounted) {
      await showResultSheet(context, title: 'ZIP ready', files: [f.path], note: pw != null ? 'Password protected' : null);
    }
  }

  static Future<void> extractZip(BuildContext context) async {
    final store = context.read<LibraryStore>();
    LockGate.externalActivity = true;
    final PlatformFile? picked;
    try {
      picked = await FilePicker.pickFile(type: FileType.custom, allowedExtensions: ['zip'], dialogTitle: 'Extract ZIP');
    } finally {
      LockGate.externalActivity = false;
    }
    if (picked == null || !context.mounted) return;
    final dir = await store.scratch('unzip_src');
    final src = File(p.join(dir.path, picked.name));
    await src.writeAsBytes(await picked.xFile.readAsBytes());
    String? pw;
    while (context.mounted) {
      final out = await store.scratch('unzip');
      try {
        final files = await ExportService.unzip(src.path, out.path, password: pw);
        if (!context.mounted) return;
        if (files.isEmpty) {
          toast(context, 'The ZIP is empty');
          return;
        }
        await showResultSheet(context, title: '${files.length} file${files.length == 1 ? '' : 's'} extracted', files: files);
        return;
      } catch (e) {
        if (!context.mounted) return;
        pw = await promptPassword(
          context,
          title: 'ZIP password',
          message: pw == null ? 'This archive needs a password.' : 'Wrong password, or the archive is damaged.',
          action: 'Extract',
        );
        if (pw == null) return;
      }
    }
  }

  static Future<void> textFromImage(BuildContext context) async {
    final store = context.read<LibraryStore>();
    LockGate.externalActivity = true;
    final List<String> paths;
    try {
      paths = await ScanService.pickPhotos();
    } finally {
      LockGate.externalActivity = false;
    }
    if (paths.isEmpty || !context.mounted) return;
    final text = await runBusy(context, 'Reading text…', (progress) async {
      final dir = await store.scratch('ocr');
      final parts = <String>[];
      for (var i = 0; i < paths.length; i++) {
        progress.value = 'Reading image ${i + 1} of ${paths.length}…';
        final norm = p.join(dir.path, 'img_$i.jpg');
        await normaliseImage(paths[i], norm);
        final r = await OcrService.instance.recognise(norm, 0, 0, store.settings.ocrLanguage);
        parts.add(r.text);
      }
      return parts.where((t) => t.isNotEmpty).join('\n\n');
    });
    if (text == null || !context.mounted) return;
    await showGlassSheet<void>(
      context,
      builder: (ctx) {
        final g = Glass.of(ctx);
        return Padding(
          padding: const EdgeInsets.fromLTRB(20, 14, 20, 16),
          child: Column(
            mainAxisSize: MainAxisSize.min,
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              Text('Recognised text', style: TextStyle(fontSize: 19, fontWeight: FontWeight.w800, color: g.text)),
              const SizedBox(height: 12),
              ConstrainedBox(
                constraints: BoxConstraints(maxHeight: MediaQuery.of(ctx).size.height * 0.5),
                child: GlassPanel(
                  padding: const EdgeInsets.all(14),
                  child: SingleChildScrollView(
                    child: text.isEmpty
                        ? Text('No text found.', style: TextStyle(color: g.muted))
                        : SelectableText(text, style: TextStyle(color: g.text, height: 1.5)),
                  ),
                ),
              ),
              const SizedBox(height: 14),
              Row(
                children: [
                  Expanded(
                    child: GlassButton(
                      label: 'Copy',
                      icon: PhosphorIconsDuotone.copy,
                      onTap: text.isEmpty
                          ? null
                          : () {
                              Clipboard.setData(ClipboardData(text: text));
                              toast(ctx, 'Copied');
                            },
                    ),
                  ),
                  const SizedBox(width: 10),
                  Expanded(
                    child: GradientButton(
                      label: 'Share',
                      icon: PhosphorIconsDuotone.shareNetwork,
                      onTap: text.isEmpty ? null : () => ExportService.shareText(text),
                    ),
                  ),
                ],
              ),
            ],
          ),
        );
      },
    );
  }
}

/// Pick, order and merge several PDFs.
class MergeScreen extends StatefulWidget {
  const MergeScreen({super.key});

  @override
  State<MergeScreen> createState() => _MergeScreenState();
}

class _MergeScreenState extends State<MergeScreen> {
  final List<PickedPdf> _files = [];
  final Map<PickedPdf, int> _pages = {};

  @override
  void initState() {
    super.initState();
    WidgetsBinding.instance.addPostFrameCallback((_) => _add());
  }

  Future<void> _add() async {
    LockGate.externalActivity = true;
    final List<PlatformFile> picked;
    try {
      picked = await FilePicker.pickFiles(type: FileType.custom, allowedExtensions: ['pdf'], dialogTitle: 'Add PDFs');
    } finally {
      LockGate.externalActivity = false;
    }
    for (final f in picked) {
      if (!mounted) return;
      final raw = PickedPdf(f.name, await f.xFile.readAsBytes());
      if (!mounted) return;
      final ready = await ScanFlow.unlockIfNeeded(context, raw);
      if (ready == null) continue;
      try {
        final n = await PdfService.pageCount(ready.bytes, password: ready.password);
        setState(() {
          _files.add(ready);
          _pages[ready] = n;
        });
      } catch (e) {
        if (mounted) toast(context, '${f.name}: ${friendlyError(e)}', error: true);
      }
    }
  }

  Future<void> _merge() async {
    final store = context.read<LibraryStore>();
    final f = await runBusy(context, 'Merging ${_files.length} PDFs…', (_) async {
      final bytes = await PdfService.merge(
        _files.map((e) => e.bytes).toList(),
        _files.map((e) => e.password).toList(),
      );
      return _write(store, 'merge', 'Merged ${store.defaultName().replaceFirst('${store.settings.namePrefix} ', '')}.pdf', bytes);
    });
    if (f != null && mounted) {
      await showResultSheet(context, title: 'PDFs merged', files: [f.path], note: '${_pages.values.fold<int>(0, (a, b) => a + b)} pages in total');
    }
  }

  @override
  Widget build(BuildContext context) {
    final g = Glass.of(context);
    return Scaffold(
      body: GlassBackground(
        child: SafeArea(
          child: Column(
            children: [
              GlassTopBar(
                title: 'Merge PDFs',
                subtitle: 'Drag to change the order',
                actions: [GlassIconButton(icon: PhosphorIconsBold.plus, tooltip: 'Add PDFs', onTap: _add)],
              ),
              Expanded(
                child: _files.isEmpty
                    ? Center(
                        child: EmptyState(
                          icon: PhosphorIconsDuotone.unite,
                          title: 'Add PDFs to merge',
                          message: 'Choose two or more PDFs. Password-protected files will ask for their password.',
                          action: GradientButton(label: 'Choose PDFs', icon: PhosphorIconsDuotone.filePlus, onTap: _add),
                        ),
                      )
                    : ReorderableListView.builder(
                        padding: const EdgeInsets.fromLTRB(16, 8, 16, 16),
                        itemCount: _files.length,
                        proxyDecorator: (child, _, _) => Material(color: Colors.transparent, child: child),
                        onReorderItem: (a, b) => setState(() => _files.insert(b, _files.removeAt(a))),
                        itemBuilder: (_, i) {
                          final f = _files[i];
                          return Padding(
                            key: ObjectKey(f),
                            padding: const EdgeInsets.only(bottom: 10),
                            child: GlassPanel(
                              radius: 18,
                              padding: const EdgeInsets.fromLTRB(12, 10, 4, 10),
                              child: Row(
                                children: [
                                  IconBadge(PhosphorIconsDuotone.filePdf, size: 44, tint: const Color(0xFFE5484D)),
                                  const SizedBox(width: 12),
                                  Expanded(
                                    child: Column(
                                      crossAxisAlignment: CrossAxisAlignment.start,
                                      children: [
                                        Text(f.name,
                                            maxLines: 1,
                                            overflow: TextOverflow.ellipsis,
                                            style: TextStyle(fontWeight: FontWeight.w700, color: g.text)),
                                        Text(
                                          '${_pages[f]} pages · ${formatBytes(f.bytes.length)}${f.password != null ? ' · unlocked' : ''}',
                                          style: TextStyle(fontSize: 12, color: g.muted),
                                        ),
                                      ],
                                    ),
                                  ),
                                  IconButton(
                                    tooltip: 'Remove',
                                    onPressed: () => setState(() {
                                      _files.remove(f);
                                      _pages.remove(f);
                                    }),
                                    icon: PhosphorIcon(PhosphorIconsDuotone.xCircle, color: g.muted),
                                  ),
                                  ReorderableDragStartListener(
                                    index: i,
                                    child: Padding(
                                      padding: const EdgeInsets.all(8),
                                      child: PhosphorIcon(PhosphorIconsBold.dotsSixVertical, color: g.muted),
                                    ),
                                  ),
                                ],
                              ),
                            ),
                          );
                        },
                      ),
              ),
              Padding(
                padding: const EdgeInsets.fromLTRB(16, 4, 16, 16),
                child: GradientButton(
                  label: _files.length < 2 ? 'Add at least 2 PDFs' : 'Merge ${_files.length} PDFs',
                  icon: PhosphorIconsDuotone.unite,
                  expand: true,
                  onTap: _files.length < 2 ? null : _merge,
                ),
              ),
            ],
          ),
        ),
      ),
    );
  }
}

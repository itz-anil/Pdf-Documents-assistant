import 'dart:async';
import 'dart:convert';
import 'dart:io';

import 'package:flutter/foundation.dart';
import 'package:flutter/painting.dart';
import 'package:intl/intl.dart';
import 'package:path/path.dart' as p;
import 'package:path_provider/path_provider.dart';
import 'package:uuid/uuid.dart';

import 'edge_detect.dart';
import 'image_processing.dart';
import 'models.dart';
import 'ocr_service.dart';
import 'settings.dart';

const _uuid = Uuid();

String newId() => _uuid.v4().replaceAll('-', '').substring(0, 16);

/// One image to turn into a page. [quad] is its document outline; with
/// [detect] the outline is found automatically (gallery imports).
class PageSource {
  final String path;
  final Quad? quad;
  final bool detect;
  const PageSource(this.path, {this.quad, this.detect = false});
}

/// Makes a string safe to use as a file name on every platform.
String safeFileName(String name) {
  final cleaned = name.replaceAll(RegExp(r'[\\/:*?"<>|\n\r\t]'), ' ').replaceAll(RegExp(r'\s+'), ' ').trim();
  return cleaned.isEmpty ? 'DocMind' : (cleaned.length > 80 ? cleaned.substring(0, 80) : cleaned);
}

/// Owns every scanned document: files on disk plus a JSON index.
class LibraryStore extends ChangeNotifier {
  final SettingsStore settings;
  LibraryStore(this.settings);

  late Directory root;
  late Directory tempRoot;
  final List<DocItem> docs = [];
  final List<Folder> folders = [];
  bool loaded = false;

  final Set<String> _autoNamed = {};
  final Set<String> busyPages = {};
  Future<void> _writeChain = Future.value();
  Future<void> _ocrChain = Future.value();

  File get _indexFile => File(p.join(root.path, 'library.json'));

  Future<void> init() async {
    final base = await getApplicationDocumentsDirectory();
    root = Directory(p.join(base.path, 'library'));
    await root.create(recursive: true);
    final tmp = await getTemporaryDirectory();
    tempRoot = Directory(p.join(tmp.path, 'docmind'));
    await tempRoot.create(recursive: true);
    if (await _indexFile.exists()) {
      try {
        final j = jsonDecode(await _indexFile.readAsString()) as Map<String, dynamic>;
        docs.addAll((j['docs'] as List).map((e) => DocItem.fromJson(Map<String, dynamic>.from(e))));
        folders.addAll((j['folders'] as List? ?? []).map((e) => Folder.fromJson(Map<String, dynamic>.from(e))));
      } catch (e) {
        debugPrint('Library index unreadable: $e');
      }
    }
    loaded = true;
    notifyListeners();
    // Finish OCR that was interrupted last session.
    for (final d in docs.where((d) => d.ocrPending)) {
      if (settings.autoOcr) queueOcr(d);
    }
  }

  void _persist() {
    final snapshot = jsonEncode({
      'docs': docs.map((d) => d.toJson()).toList(),
      'folders': folders.map((f) => f.toJson()).toList(),
    });
    _writeChain = _writeChain.then((_) async {
      final tmp = File('${_indexFile.path}.tmp');
      await tmp.writeAsString(snapshot, flush: true);
      await tmp.rename(_indexFile.path);
    }).catchError((e) => debugPrint('Save failed: $e'));
  }

  void touch(DocItem doc) {
    doc.updatedAt = DateTime.now();
    _persist();
    notifyListeners();
  }

  Directory docDir(DocItem d) => Directory(p.join(root.path, d.id));
  File fileOf(DocItem d, String name) => File(p.join(root.path, d.id, name));
  File processedFile(DocItem d, PageItem pg) => fileOf(d, pg.processed);
  File thumbFile(DocItem d, PageItem pg) => fileOf(d, pg.thumb);
  File originalFile(DocItem d, PageItem pg) => fileOf(d, pg.original);
  File baseFile(DocItem d, PageItem pg) => fileOf(d, pg.base);

  DocItem? byId(String id) {
    for (final d in docs) {
      if (d.id == id) return d;
    }
    return null;
  }

  /// A fresh, empty scratch folder for exports and tool results.
  Future<Directory> scratch(String label) async {
    final dir = Directory(p.join(tempRoot.path, '${label}_${DateTime.now().millisecondsSinceEpoch}'));
    await dir.create(recursive: true);
    return dir;
  }

  String defaultName([ScanMode mode = ScanMode.document]) {
    final stamp = DateFormat('d MMM yyyy, HH.mm').format(DateTime.now());
    final prefix = mode == ScanMode.document ? settings.namePrefix : mode.label;
    return '$prefix $stamp';
  }

  // ---------------------------------------------------------------- creation

  Future<DocItem> createDocument({
    required List<PageSource> pages,
    ScanMode mode = ScanMode.document,
    String? name,
    String? folderId,
    PageFilter? filter,
    void Function(int done, int total)? onProgress,
  }) async {
    final now = DateTime.now();
    final doc = DocItem(
      id: newId(),
      name: name ?? defaultName(mode),
      createdAt: now,
      updatedAt: now,
      folderId: folderId,
      mode: mode,
      pages: [],
    );
    if (name == null) _autoNamed.add(doc.id);
    await docDir(doc).create(recursive: true);
    final f = filter ?? mode.preferredFilter ?? settings.defaultFilter;
    try {
      for (var i = 0; i < pages.length; i++) {
        doc.pages.add(await _importPage(doc, pages[i], f));
        onProgress?.call(i + 1, pages.length);
      }
    } catch (_) {
      final dir = docDir(doc);
      if (await dir.exists()) await dir.delete(recursive: true);
      rethrow;
    }
    docs.insert(0, doc);
    _persist();
    notifyListeners();
    if (settings.autoOcr) queueOcr(doc);
    return doc;
  }

  Future<void> addPages(DocItem doc, List<PageSource> pages, {PageFilter? filter}) async {
    final f = filter ?? doc.mode.preferredFilter ?? settings.defaultFilter;
    for (final src in pages) {
      doc.pages.add(await _importPage(doc, src, f));
      notifyListeners();
    }
    touch(doc);
    if (settings.autoOcr) queueOcr(doc);
  }

  Future<PageItem> _importPage(DocItem doc, PageSource src, PageFilter filter) async {
    final pid = newId();
    final original = 'o_$pid.jpg';
    await normaliseImage(src.path, fileOf(doc, original).path);
    final quad = src.detect ? await detectQuadInFile(fileOf(doc, original).path) : src.quad;
    final page = PageItem(id: pid, original: original, processed: '', thumb: '', filter: filter, quad: quad);
    await _renderBase(doc, page);
    await _render(doc, page);
    return page;
  }

  Future<void> _deleteFile(DocItem doc, String name) async {
    if (name.isEmpty) return;
    final f = fileOf(doc, name);
    FileImage(f).evict();
    if (await f.exists()) await f.delete();
  }

  /// Rebuilds the flattened base image from the original and its outline.
  Future<void> _renderBase(DocItem doc, PageItem page) async {
    final base = 'b_${page.id}_${DateTime.now().microsecondsSinceEpoch}.jpg';
    await buildBase(fileOf(doc, page.original).path, page.quad, fileOf(doc, base).path, 4000);
    final old = page.base;
    page.base = base;
    await _deleteFile(doc, old);
  }

  Future<void> _render(DocItem doc, PageItem page) async {
    if (page.base.isEmpty || !await fileOf(doc, page.base).exists()) await _renderBase(doc, page);
    final rev = DateTime.now().microsecondsSinceEpoch;
    final processed = 'p_${page.id}_$rev.jpg';
    final thumb = 't_${page.id}_$rev.jpg';
    final q = settings.quality;
    final size = await processPage(ProcessParams(
      src: fileOf(doc, page.base).path,
      out: fileOf(doc, processed).path,
      thumb: fileOf(doc, thumb).path,
      filter: page.filter,
      quarterTurns: page.quarterTurns,
      brightness: page.brightness,
      contrast: page.contrast,
      maxSide: q.maxSide,
      jpegQuality: q.jpegQuality,
    ));
    final oldP = page.processed, oldT = page.thumb;
    page
      ..processed = processed
      ..thumb = thumb
      ..width = size[0]
      ..height = size[1];
    await _deleteFile(doc, oldP);
    await _deleteFile(doc, oldT);
  }

  // ----------------------------------------------------------------- editing

  /// Applies edits to a page and re-renders it off the UI thread.
  Future<void> editPage(
    DocItem doc,
    PageItem page, {
    PageFilter? filter,
    int? quarterTurns,
    List<double>? quad,
    bool clearQuad = false,
    double? brightness,
    double? contrast,
  }) async {
    final outlineChanged = quad != null || clearQuad;
    final geometryChanged = quarterTurns != null || outlineChanged;
    if (filter != null) page.filter = filter;
    if (quarterTurns != null) page.quarterTurns = quarterTurns % 4;
    if (quad != null) page.quad = quad;
    if (clearQuad) page.quad = null;
    if (brightness != null) page.brightness = brightness;
    if (contrast != null) page.contrast = contrast;
    busyPages.add(page.id);
    notifyListeners();
    try {
      if (outlineChanged) await _renderBase(doc, page);
      await _render(doc, page);
    } finally {
      busyPages.remove(page.id);
    }
    if (geometryChanged) {
      page.ocrDone = false;
      if (settings.autoOcr) queueOcr(doc);
    }
    touch(doc);
  }

  Future<void> applyFilterToAll(DocItem doc, PageFilter filter) async {
    for (final pg in doc.pages) {
      if (pg.filter != filter) await editPage(doc, pg, filter: filter);
    }
  }

  /// Replaces a page's source image (after Fill & Sign, or a retake).
  /// [keepFilter] keeps the page's look; markup passes false so ink colours stay true.
  Future<void> replacePageImage(DocItem doc, PageItem page, String newImagePath, {Quad? quad, bool keepFilter = false}) async {
    final original = 'o_${page.id}_${DateTime.now().millisecondsSinceEpoch}.jpg';
    await normaliseImage(newImagePath, fileOf(doc, original).path);
    await _deleteFile(doc, page.original);
    page
      ..original = original
      ..quad = quad
      ..quarterTurns = 0
      ..brightness = 0
      ..contrast = 1
      ..ocrDone = false;
    if (!keepFilter) page.filter = PageFilter.original;
    busyPages.add(page.id);
    notifyListeners();
    try {
      await _renderBase(doc, page);
      await _render(doc, page);
    } finally {
      busyPages.remove(page.id);
    }
    touch(doc);
    if (settings.autoOcr) queueOcr(doc);
  }

  /// [to] is the final index (already adjusted for the removed item).
  void reorderPage(DocItem doc, int from, int to) {
    final pg = doc.pages.removeAt(from);
    doc.pages.insert(to, pg);
    touch(doc);
  }

  Future<void> deletePage(DocItem doc, PageItem page) async {
    doc.pages.remove(page);
    for (final f in [page.original, page.base, page.processed, page.thumb]) {
      await _deleteFile(doc, f);
    }
    if (doc.pages.isEmpty) {
      await deleteDocs([doc]);
    } else {
      touch(doc);
    }
  }

  Future<void> duplicatePage(DocItem doc, PageItem page) async {
    final pid = newId();
    final copy = PageItem.fromJson(page.toJson()..['id'] = pid);
    copy
      ..original = 'o_$pid.jpg'
      ..base = 'b_${pid}_0.jpg'
      ..processed = 'p_${pid}_0.jpg'
      ..thumb = 't_${pid}_0.jpg';
    await _copyPageFiles(doc, page, doc, copy);
    doc.pages.insert(doc.pages.indexOf(page) + 1, copy);
    touch(doc);
  }

  Future<void> _copyPageFiles(DocItem fromDoc, PageItem from, DocItem toDoc, PageItem to) async {
    if (from.base.isEmpty) await _renderBase(fromDoc, from);
    await fileOf(fromDoc, from.original).copy(fileOf(toDoc, to.original).path);
    await fileOf(fromDoc, from.base).copy(fileOf(toDoc, to.base).path);
    await fileOf(fromDoc, from.processed).copy(fileOf(toDoc, to.processed).path);
    await fileOf(fromDoc, from.thumb).copy(fileOf(toDoc, to.thumb).path);
  }

  // ------------------------------------------------------------ doc actions

  void rename(DocItem doc, String name) {
    doc.name = name.trim().isEmpty ? doc.name : name.trim();
    _autoNamed.remove(doc.id);
    touch(doc);
  }

  void toggleFavorite(DocItem doc) {
    doc.favorite = !doc.favorite;
    _persist();
    notifyListeners();
  }

  void moveToFolder(Iterable<DocItem> items, String? folderId) {
    for (final d in items) {
      d.folderId = folderId;
    }
    _persist();
    notifyListeners();
  }

  Future<void> deleteDocs(Iterable<DocItem> items) async {
    final list = items.toList();
    for (final d in list) {
      docs.remove(d);
      final dir = docDir(d);
      if (await dir.exists()) await dir.delete(recursive: true);
    }
    _persist();
    notifyListeners();
  }

  Future<DocItem> duplicateDoc(DocItem src) async {
    final copy = await mergeDocs([src], name: '${src.name} (copy)');
    return copy;
  }

  /// Combines documents (in order) into a new document; originals are kept.
  Future<DocItem> mergeDocs(List<DocItem> items, {String? name}) async {
    final now = DateTime.now();
    final doc = DocItem(
      id: newId(),
      name: name ?? 'Merged ${DateFormat('d MMM yyyy, HH.mm').format(now)}',
      createdAt: now,
      updatedAt: now,
      folderId: items.first.folderId,
      mode: items.first.mode,
      pages: [],
    );
    await docDir(doc).create(recursive: true);
    for (final src in items) {
      for (final pg in src.pages) {
        final pid = newId();
        final copy = PageItem.fromJson(pg.toJson()..['id'] = pid);
        copy
          ..original = 'o_$pid.jpg'
          ..base = 'b_${pid}_0.jpg'
          ..processed = 'p_${pid}_0.jpg'
          ..thumb = 't_${pid}_0.jpg';
        await _copyPageFiles(src, pg, doc, copy);
        doc.pages.add(copy);
      }
    }
    docs.insert(0, doc);
    _persist();
    notifyListeners();
    return doc;
  }

  // ---------------------------------------------------------------- folders

  Folder createFolder(String name, int colorIndex) {
    final f = Folder(id: newId(), name: name.trim(), colorIndex: colorIndex);
    folders.add(f);
    _persist();
    notifyListeners();
    return f;
  }

  void renameFolder(Folder f, String name) {
    f.name = name.trim();
    _persist();
    notifyListeners();
  }

  void deleteFolder(Folder f) {
    for (final d in docs.where((d) => d.folderId == f.id)) {
      d.folderId = null;
    }
    folders.remove(f);
    _persist();
    notifyListeners();
  }

  Folder? folderOf(DocItem d) {
    for (final f in folders) {
      if (f.id == d.folderId) return f;
    }
    return null;
  }

  // -------------------------------------------------------------------- OCR

  /// Runs OCR for every pending page of [doc]. Jobs run one at a time.
  void queueOcr(DocItem doc, {bool force = false}) {
    _ocrChain = _ocrChain.then((_) => _runOcr(doc, force)).catchError((e) => debugPrint('OCR failed: $e'));
  }

  Future<void> runOcrNow(DocItem doc, {bool force = false}) {
    queueOcr(doc, force: force);
    return _ocrChain;
  }

  Future<void> _runOcr(DocItem doc, bool force) async {
    if (!docs.contains(doc)) return;
    for (final pg in List.of(doc.pages)) {
      if (pg.ocrDone && !force) continue;
      final file = processedFile(doc, pg);
      if (!await file.exists()) continue;
      try {
        final r = await OcrService.instance.recognise(file.path, pg.width, pg.height);
        pg
          ..ocrText = r.text
          ..ocrLines = r.lines
          ..ocrDone = true;
      } catch (e) {
        debugPrint('OCR page failed: $e');
        pg.ocrDone = true;
      }
      _persist();
      notifyListeners();
    }
    if (_autoNamed.remove(doc.id) && settings.smartNames) {
      final suggestion = _smartName(doc);
      if (suggestion != null) {
        doc.name = suggestion;
        touch(doc);
      }
    }
  }

  String? _smartName(DocItem doc) {
    if (doc.pages.isEmpty) return null;
    for (final line in doc.pages.first.ocrText.split('\n')) {
      final t = line.trim();
      final letters = t.replaceAll(RegExp(r'[^A-Za-zऀ-ॿ]'), '');
      if (t.length >= 4 && t.length <= 48 && letters.length >= 3) {
        return '${_title(t)} · ${DateFormat('d MMM').format(doc.createdAt)}';
      }
    }
    return null;
  }

  String _title(String s) {
    if (s != s.toUpperCase()) return s;
    return s
        .toLowerCase()
        .split(' ')
        .map((w) => w.isEmpty ? w : w[0].toUpperCase() + w.substring(1))
        .join(' ');
  }

  // ------------------------------------------------------------------ query

  List<DocItem> query({String text = '', String? folderId, bool favoritesOnly = false, required SortOrder sort}) {
    final q = text.trim().toLowerCase();
    final out = docs.where((d) {
      if (favoritesOnly && !d.favorite) return false;
      if (folderId != null && d.folderId != folderId) return false;
      if (q.isEmpty) return true;
      return d.name.toLowerCase().contains(q) || d.fullText.toLowerCase().contains(q);
    }).toList();
    switch (sort) {
      case SortOrder.newest:
        out.sort((a, b) => b.updatedAt.compareTo(a.updatedAt));
      case SortOrder.oldest:
        out.sort((a, b) => a.createdAt.compareTo(b.createdAt));
      case SortOrder.nameAZ:
        out.sort((a, b) => a.name.toLowerCase().compareTo(b.name.toLowerCase()));
      case SortOrder.nameZA:
        out.sort((a, b) => b.name.toLowerCase().compareTo(a.name.toLowerCase()));
      case SortOrder.largest:
        out.sort((a, b) => b.pages.length.compareTo(a.pages.length));
    }
    return out;
  }

  /// True when [d] matched only by text inside its pages.
  bool matchedInText(DocItem d, String text) {
    final q = text.trim().toLowerCase();
    return q.isNotEmpty && !d.name.toLowerCase().contains(q) && d.fullText.toLowerCase().contains(q);
  }

  Future<int> docBytes(DocItem d) async {
    var total = 0;
    final dir = docDir(d);
    if (!await dir.exists()) return 0;
    await for (final e in dir.list()) {
      if (e is File && p.basename(e.path).startsWith('p_')) total += await e.length();
    }
    return total;
  }

  Future<(int library, int cache)> storageUsage() async {
    Future<int> size(Directory d) async {
      var t = 0;
      if (!await d.exists()) return 0;
      await for (final e in d.list(recursive: true)) {
        if (e is File) t += await e.length();
      }
      return t;
    }

    return (await size(root), await size(tempRoot));
  }

  Future<void> clearCache() async {
    if (await tempRoot.exists()) {
      await tempRoot.delete(recursive: true);
    }
    await tempRoot.create(recursive: true);
  }
}

String formatBytes(int bytes) {
  if (bytes < 1024) return '$bytes B';
  if (bytes < 1024 * 1024) return '${(bytes / 1024).toStringAsFixed(0)} KB';
  if (bytes < 1024 * 1024 * 1024) return '${(bytes / (1024 * 1024)).toStringAsFixed(1)} MB';
  return '${(bytes / (1024 * 1024 * 1024)).toStringAsFixed(2)} GB';
}

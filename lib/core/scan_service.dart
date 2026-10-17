import 'dart:io';

import 'package:image_picker/image_picker.dart';
import 'package:path/path.dart' as p;

import 'edge_detect.dart';
import 'image_processing.dart';
import 'library_store.dart';

/// Turns camera/gallery shots into page sources for the library.
class ScanService {
  ScanService._();

  static Future<List<String>> pickPhotos() async {
    final files = await ImagePicker().pickMultiImage(imageQuality: 100);
    return files.map((f) => f.path).toList();
  }

  /// Regular pages: each shot keeps its detected outline.
  static List<PageSource> pages(List<(String, Quad?)> shots) =>
      [for (final (path, quad) in shots) PageSource(path, quad: quad)];

  /// Book spreads: flatten each spread, then split it at the spine.
  static Future<List<PageSource>> bookPages(List<(String, Quad?)> shots, Directory work) async {
    final out = <PageSource>[];
    for (var i = 0; i < shots.length; i++) {
      final (path, quad) = shots[i];
      final l = p.join(work.path, 'book_${i}_l.jpg');
      final r = p.join(work.path, 'book_${i}_r.jpg');
      await splitSpread(path, quad, l, r);
      out
        ..add(PageSource(l))
        ..add(PageSource(r));
    }
    return out;
  }
}

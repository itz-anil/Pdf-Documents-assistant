import 'dart:io';

import 'package:flutter/services.dart';
import 'package:google_mlkit_document_scanner/google_mlkit_document_scanner.dart';
import 'package:image_picker/image_picker.dart';
import 'package:path/path.dart' as p;

import 'image_processing.dart';
import 'models.dart';

/// Camera capture (Google's on-device document scanner: auto edge detection,
/// auto capture, crop, cleanup brush) plus mode-specific post processing.
class ScanService {
  ScanService._();

  static Future<List<String>> capture({required ScanMode mode, bool allowGallery = true}) async {
    final limit = switch (mode) {
      ScanMode.idCard => 2,
      ScanMode.businessCard => 1,
      _ => 100,
    };
    final scanner = DocumentScanner(
      options: DocumentScannerOptions(
        documentFormats: const {DocumentFormat.jpeg},
        pageLimit: limit,
        mode: ScannerMode.full,
        isGalleryImport: allowGallery,
      ),
    );
    try {
      final result = await scanner.scanDocument();
      return (result.images ?? []).map((x) => x.startsWith('file://') ? Uri.parse(x).toFilePath() : x).toList();
    } on PlatformException catch (e) {
      if ((e.message ?? '').toLowerCase().contains('cancel')) return [];
      rethrow;
    } finally {
      await scanner.close();
    }
  }

  static Future<List<String>> pickPhotos() async {
    final files = await ImagePicker().pickMultiImage(imageQuality: 100);
    return files.map((f) => f.path).toList();
  }

  /// Turns captured shots into final page images for [mode].
  static Future<List<String>> prepare(ScanMode mode, List<String> shots, Directory work) async {
    switch (mode) {
      case ScanMode.book:
        final pages = <String>[];
        for (var i = 0; i < shots.length; i++) {
          final l = p.join(work.path, 'book_${i}_l.jpg');
          final r = p.join(work.path, 'book_${i}_r.jpg');
          await splitSpread(shots[i], l, r);
          pages.addAll([l, r]);
        }
        return pages;
      case ScanMode.idCard:
        final pages = <String>[];
        for (var i = 0; i < shots.length; i += 2) {
          final out = p.join(work.path, 'id_$i.jpg');
          await composeIdCard(shots[i], i + 1 < shots.length ? shots[i + 1] : null, out);
          pages.add(out);
        }
        return pages;
      default:
        return shots;
    }
  }
}

import 'dart:io';
import 'dart:typed_data';

import 'package:docmind/core/business_card.dart';
import 'package:docmind/core/export_service.dart';
import 'package:docmind/core/image_processing.dart';
import 'package:docmind/core/library_store.dart';
import 'package:docmind/core/models.dart';
import 'package:docmind/core/pdf_service.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:image/image.dart' as img;
import 'package:path/path.dart' as p;
import 'package:syncfusion_flutter_pdf/pdf.dart' as sf;

void main() {
  late Directory tmp;
  late String jpg;

  setUpAll(() async {
    tmp = await Directory.systemTemp.createTemp('docmind_test');
    final im = img.Image(width: 400, height: 560, numChannels: 3);
    img.fill(im, color: img.ColorRgb8(235, 228, 210));
    img.fillRect(im, x1: 40, y1: 60, x2: 360, y2: 80, color: img.ColorRgb8(30, 30, 30));
    img.fillRect(im, x1: 0, y1: 300, x2: 400, y2: 560, color: img.ColorRgb8(170, 165, 150)); // shadow
    jpg = p.join(tmp.path, 'page.jpg');
    File(jpg).writeAsBytesSync(img.encodeJpg(im));
  });

  tearDownAll(() => tmp.delete(recursive: true));

  group('page ranges', () {
    test('parses single pages, ranges and reverse ranges', () {
      expect(PdfService.parseRanges('1-3, 5', 6), [0, 1, 2, 4]);
      expect(PdfService.parseRanges('4-2', 6), [3, 2, 1]);
    });
    test('rejects out-of-range and junk input', () {
      expect(() => PdfService.parseRanges('0', 3), throwsFormatException);
      expect(() => PdfService.parseRanges('2-9', 3), throwsFormatException);
      expect(() => PdfService.parseRanges('abc', 3), throwsFormatException);
      expect(() => PdfService.parseRanges(' , ', 3), throwsFormatException);
    });
  });

  group('image processing', () {
    test('every filter renders and removes the shadow', () async {
      for (final f in PageFilter.values) {
        final out = p.join(tmp.path, 'p_${f.name}.jpg');
        final th = p.join(tmp.path, 't_${f.name}.jpg');
        final size = await processPage(ProcessParams(
          src: jpg,
          out: out,
          thumb: th,
          filter: f,
          quarterTurns: 1,
          crop: const [0, 0, 1, 1],
          brightness: 0,
          contrast: 1,
          maxSide: 2000,
          jpegQuality: 85,
        ));
        expect(size, [560, 400], reason: 'rotated 90°');
        expect(File(th).existsSync(), isTrue);
        if (f == PageFilter.autoColor || f == PageFilter.blackWhite) {
          final res = img.decodeJpg(File(out).readAsBytesSync())!;
          // Shadowed paper (originally 170) should be lifted close to white.
          expect(res.getPixel(100, 200).luminance, greaterThan(200), reason: f.label);
        }
      }
    });

    test('book spreads split into two pages', () async {
      final l = p.join(tmp.path, 'l.jpg'), r = p.join(tmp.path, 'r.jpg');
      await splitSpread(jpg, l, r);
      final li = img.decodeJpg(File(l).readAsBytesSync())!;
      expect(li.width, lessThan(200));
      expect(File(r).existsSync(), isTrue);
    });

    test('ID card front and back land on one A4 page', () async {
      final out = p.join(tmp.path, 'id.jpg');
      await composeIdCard(jpg, jpg, out);
      final im = img.decodeJpg(File(out).readAsBytesSync())!;
      expect([im.width, im.height], [2480, 3508]);
    });
  });

  group('pdf', () {
    late Uint8List pdf;
    setUpAll(() async {
      pdf = await PdfService.buildFromImages([jpg, jpg, jpg], const PdfOptions(textLayer: false));
    });

    test('builds a 3-page PDF', () async {
      expect(await PdfService.pageCount(pdf), 3);
      expect(await PdfService.isEncrypted(pdf), isFalse);
    });

    test('password protect and remove round-trip', () async {
      final locked = await PdfService.protect(pdf, 'secret123');
      expect(await PdfService.isEncrypted(locked), isTrue);
      expect(() => PdfService.pageCount(locked, password: 'wrong'), throwsA(isA<WrongPasswordException>()));
      expect(await PdfService.pageCount(locked, password: 'secret123'), 3);
      final open = await PdfService.removePassword(locked, 'secret123');
      expect(await PdfService.isEncrypted(open), isFalse);
      expect(await PdfService.pageCount(open), 3);
    });

    test('merge, extract and split', () async {
      final locked = await PdfService.protect(pdf, 'pw');
      final merged = await PdfService.merge([pdf, locked], [null, 'pw']);
      expect(await PdfService.pageCount(merged), 6);
      final some = await PdfService.extractPages(merged, [5, 0]);
      expect(await PdfService.pageCount(some), 2);
      final parts = await PdfService.splitEach(pdf);
      expect(parts.length, 3);
    });

    test('searchable text layer is written and extractable', () async {
      final bytes = await PdfService.buildPages(
        [PdfPageSource(jpg, 400, 560, const [OcrLine('Electricity Invoice 2026', 0.1, 0.1, 0.8, 0.04)])],
        const PdfOptions(),
      );
      final doc = sf.PdfDocument(inputBytes: bytes);
      final text = sf.PdfTextExtractor(doc).extractText();
      doc.dispose();
      expect(text, contains('Electricity Invoice'));
    });
  });

  group('zip', () {
    test('plain and password ZIP round-trip', () async {
      final a = File(p.join(tmp.path, 'a.txt'))..writeAsStringSync('hello');
      final entries = [ZipEntrySource('a.txt', a.path), ZipEntrySource('a.txt', jpg)];
      final plain = await ExportService.zip(entries, p.join(tmp.path, 'plain.zip'));
      final outA = await Directory(p.join(tmp.path, 'outA')).create();
      final files = await ExportService.unzip(plain.path, outA.path);
      expect(files.map(p.basename).toSet(), {'a.txt', 'a (2).txt'});

      final secure = await ExportService.zip(entries, p.join(tmp.path, 'secure.zip'), password: 'zip-pw');
      final outB = await Directory(p.join(tmp.path, 'outB')).create();
      final opened = await ExportService.unzip(secure.path, outB.path, password: 'zip-pw');
      expect(File(opened.firstWhere((f) => f.endsWith('a.txt'))).readAsStringSync(), 'hello');
    });
  });

  group('business card', () {
    test('extracts contact fields', () {
      final c = ContactCard.parse('Priya Sharma\nSenior Product Manager\nNimbus Technologies Pvt Ltd\n'
          '+91 98765 43210\npriya.sharma@nimbus.in\nwww.nimbus.in\n4th Floor, MG Road, Bengaluru 560001');
      expect(c.name, 'Priya Sharma');
      expect(c.title, contains('Manager'));
      expect(c.company, contains('Nimbus'));
      expect(c.phones.single, contains('98765'));
      expect(c.emails.single, 'priya.sharma@nimbus.in');
      expect(c.website, 'www.nimbus.in');
      expect(c.address, contains('MG Road'));
      final v = c.toVCard();
      expect(v, contains('FN:Priya Sharma'));
      expect(v, contains('TEL;TYPE=CELL:+919876543210'));
    });
  });

  test('file names are sanitised', () {
    expect(safeFileName('Bill: Sep/Oct?'), 'Bill Sep Oct');
    expect(safeFileName('   '), 'DocMind');
  });

  test('document JSON round-trip keeps OCR boxes', () {
    final d = DocItem(
      id: 'x',
      name: 'Doc',
      createdAt: DateTime(2026),
      updatedAt: DateTime(2026),
      pages: [
        PageItem(id: 'p', original: 'o', processed: 'pp', thumb: 't', ocrLines: [const OcrLine('hi', .1, .2, .3, .4)]),
      ],
    );
    final back = DocItem.fromJson(d.toJson());
    expect(back.pages.single.ocrLines.single.text, 'hi');
    expect(back.pages.single.filter, PageFilter.autoColor);
  });
}

import 'dart:io';
import 'dart:typed_data';

import 'package:docmind/core/business_card.dart';
import 'package:docmind/core/edge_detect.dart';
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
      await splitSpread(jpg, null, l, r);
      final li = img.decodeJpg(File(l).readAsBytesSync())!;
      expect(li.width, lessThan(200));
      expect(File(r).existsSync(), isTrue);
    });

    test('ID card: front on top, back below, on one A4 page', () async {
      String card(String name, img.Color c) {
        final im = img.Image(width: 856, height: 540, numChannels: 3);
        img.fill(im, color: c);
        final path = p.join(tmp.path, name);
        File(path).writeAsBytesSync(img.encodeJpg(im));
        return path;
      }

      final front = card('front.jpg', img.ColorRgb8(220, 40, 40));
      final back = card('back.jpg', img.ColorRgb8(40, 60, 220));
      final out = p.join(tmp.path, 'id.jpg');
      await composeIdCard(IdSide(front, null), IdSide(back, null), out);
      final im = img.decodeJpg(File(out).readAsBytesSync())!;
      expect([im.width, im.height], [2480, 3508]);
      final top = im.getPixel(1240, 1100), bottom = im.getPixel(1240, 2450);
      expect(top.r, greaterThan(180), reason: 'front (red) sits in the upper half');
      expect(bottom.b, greaterThan(180), reason: 'back (blue) sits in the lower half');
      // Large mode: the card spans most of the page width.
      var left = 0;
      while (im.getPixel(left, 1100).r > 200 && im.getPixel(left, 1100).g > 200) {
        left++;
      }
      expect(2480 - 2 * left, greaterThan(1700));

      final actual = p.join(tmp.path, 'id_actual.jpg');
      await composeIdCard(IdSide(front, null), IdSide(back, null), actual, size: IdCardSize.actual);
      final a = img.decodeJpg(File(actual).readAsBytesSync())!;
      var x = 0;
      while (a.getPixel(x, 400).r > 200 && a.getPixel(x, 400).g > 200) {
        x++;
      }
      expect((2480 - 2 * x - 1011).abs(), lessThan(12), reason: '85.6 mm at 300 dpi');
    });

    test('a portrait-held card side can be rotated', () async {
      final out = p.join(tmp.path, 'side.jpg');
      await renderIdSide(IdSide(jpg, null, 1), out);
      final im = img.decodeJpg(File(out).readAsBytesSync())!;
      expect(im.width, greaterThan(im.height));
    });
  });

  group('edge detection & perspective', () {
    // A bright page photographed at an angle on a dark desk.
    const corners = [130.0, 70.0, 540.0, 100.0, 575.0, 430.0, 95.0, 405.0];
    late String photo;
    setUpAll(() {
      final im = img.Image(width: 640, height: 480, numChannels: 3);
      img.fill(im, color: img.ColorRgb8(58, 52, 48));
      img.fillPolygon(im,
          vertices: [for (var i = 0; i < 4; i++) img.Point(corners[i * 2], corners[i * 2 + 1])],
          color: img.ColorRgb8(232, 228, 218));
      for (var y = 150; y < 360; y += 22) {
        img.fillRect(im, x1: 190, y1: y, x2: 470, y2: y + 6, color: img.ColorRgb8(50, 50, 55));
      }
      photo = p.join(tmp.path, 'desk.jpg');
      File(photo).writeAsBytesSync(img.encodeJpg(im, quality: 92));
    });

    test('finds the four page corners', () async {
      final q = await detectQuadInFile(photo);
      expect(q, isNotNull);
      for (var i = 0; i < 4; i++) {
        expect(q![i * 2], closeTo(corners[i * 2] / 640, 0.03), reason: 'corner $i x');
        expect(q[i * 2 + 1], closeTo(corners[i * 2 + 1] / 480, 0.03), reason: 'corner $i y');
      }
    });

    test('returns null when there is no page', () {
      final flat = Uint8List(200 * 150)..fillRange(0, 200 * 150, 120);
      expect(detectQuad(flat, 200, 150), isNull);
      final paper = Uint8List(200 * 150)..fillRange(0, 200 * 150, 235);
      expect(detectQuad(paper, 200, 150), isNull, reason: 'page fills the frame → keep whole image');
    });

    test('flattens the page and drops the desk', () async {
      final q = (await detectQuadInFile(photo))!;
      final out = p.join(tmp.path, 'flat.jpg');
      final size = await buildBase(photo, q, out, 3000);
      final im = img.decodeJpg(File(out).readAsBytesSync())!;
      expect(size, [im.width, im.height]);
      expect(im.width / im.height, closeTo(480 / 335, 0.06), reason: 'page proportions kept');
      for (final (x, y) in [(4, 4), (im.width - 5, 4), (4, im.height - 5), (im.width - 5, im.height - 5)]) {
        expect(im.getPixel(x, y).luminance, greaterThan(170), reason: 'corner ($x,$y) is paper, not desk');
      }
    });

    test('quad rotation round-trips', () {
      const q = [0.1, 0.2, 0.8, 0.15, 0.9, 0.85, 0.05, 0.9];
      final back = rotateQuad(rotateQuad(q, 90), 270);
      for (var i = 0; i < 8; i++) {
        expect(back[i], closeTo(q[i], 1e-9));
      }
      expect(isFullQuad(fullQuad), isTrue);
      expect(isFullQuad(q), isFalse);
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
    // Version 1 rectangle crops become four-corner outlines.
    final v1 = PageItem.fromJson({'id': 'a', 'o': 'o', 'p': 'p', 'th': 't', 'c': [0.1, 0.2, 0.9, 0.8]});
    expect(v1.quad, [0.1, 0.2, 0.9, 0.2, 0.9, 0.8, 0.1, 0.8]);
    expect(v1.base, '');
  });
}

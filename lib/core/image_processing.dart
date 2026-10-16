import 'dart:io';
import 'dart:isolate';
import 'dart:math' as math;
import 'dart:typed_data';

import 'package:image/image.dart' as img;

import 'models.dart';

/// Everything a worker isolate needs to (re)render one page.
class ProcessParams {
  final String src;
  final String out;
  final String thumb;
  final PageFilter filter;
  final int quarterTurns;
  final List<double>? crop;
  final double brightness;
  final double contrast;
  final int maxSide;
  final int jpegQuality;

  const ProcessParams({
    required this.src,
    required this.out,
    required this.thumb,
    required this.filter,
    required this.quarterTurns,
    required this.crop,
    required this.brightness,
    required this.contrast,
    required this.maxSide,
    required this.jpegQuality,
  });
}

/// Renders a page in a background isolate. Returns [width, height].
Future<List<int>> processPage(ProcessParams p) => Isolate.run(() => _process(p));

List<int> _process(ProcessParams p) {
  var im = _load(p.src);
  final crop = p.crop;
  if (crop != null) {
    final x = (crop[0] * im.width).round().clamp(0, im.width - 1);
    final y = (crop[1] * im.height).round().clamp(0, im.height - 1);
    final w = ((crop[2] - crop[0]) * im.width).round().clamp(1, im.width - x);
    final h = ((crop[3] - crop[1]) * im.height).round().clamp(1, im.height - y);
    im = img.copyCrop(im, x: x, y: y, width: w, height: h);
  }
  final turns = p.quarterTurns % 4;
  if (turns != 0) im = img.copyRotate(im, angle: 90 * turns);
  im = _limit(im, p.maxSide);
  im = applyFilter(im, p.filter, brightness: p.brightness, contrast: p.contrast);
  File(p.out).writeAsBytesSync(img.encodeJpg(im, quality: p.jpegQuality));
  _writeThumb(im, p.thumb);
  return [im.width, im.height];
}

img.Image _load(String path) {
  final decoded = img.decodeImage(File(path).readAsBytesSync());
  if (decoded == null) throw const FormatException('Unsupported image');
  var im = img.bakeOrientation(decoded);
  if (im.numChannels != 3 || im.format != img.Format.uint8) {
    im = im.convert(format: img.Format.uint8, numChannels: 3);
  }
  return im;
}

img.Image _limit(img.Image im, int maxSide) {
  final longest = math.max(im.width, im.height);
  if (longest <= maxSide) return im;
  return im.width >= im.height
      ? img.copyResize(im, width: maxSide, interpolation: img.Interpolation.average)
      : img.copyResize(im, height: maxSide, interpolation: img.Interpolation.average);
}

void _writeThumb(img.Image im, String path) {
  final th = im.width >= im.height
      ? img.copyResize(im, width: 420, interpolation: img.Interpolation.average)
      : img.copyResize(im, height: 520, interpolation: img.Interpolation.average);
  File(path).writeAsBytesSync(img.encodeJpg(th, quality: 78));
}

Uint8List _lut(double gamma) {
  final t = Uint8List(256);
  for (var i = 0; i < 256; i++) {
    t[i] = (math.pow(i / 255, gamma) * 255).round().clamp(0, 255);
  }
  return t;
}

/// Estimates the paper's lighting (bright background) so shadows can be
/// divided out. Max-filter removes dark text before blurring.
Uint8List _background(img.Image im) {
  final sw = math.max(8, im.width ~/ 24);
  var small = img.copyResize(im, width: sw, interpolation: img.Interpolation.average);
  final w = small.width, h = small.height;
  final src = small.getBytes(order: img.ChannelOrder.rgb);
  final dst = Uint8List(src.length);
  for (var y = 0; y < h; y++) {
    for (var x = 0; x < w; x++) {
      for (var c = 0; c < 3; c++) {
        var m = 0;
        for (var dy = -2; dy <= 2; dy++) {
          final yy = (y + dy).clamp(0, h - 1);
          for (var dx = -2; dx <= 2; dx++) {
            final xx = (x + dx).clamp(0, w - 1);
            final v = src[(yy * w + xx) * 3 + c];
            if (v > m) m = v;
          }
        }
        dst[(y * w + x) * 3 + c] = m;
      }
    }
  }
  small = img.Image.fromBytes(width: w, height: h, bytes: dst.buffer, numChannels: 3);
  small = img.gaussianBlur(small, radius: 2);
  final full = img.copyResize(small, width: im.width, height: im.height, interpolation: img.Interpolation.linear);
  return full.getBytes(order: img.ChannelOrder.rgb);
}

img.Image applyFilter(img.Image im, PageFilter filter, {double brightness = 0, double contrast = 1}) {
  final px = Uint8List.fromList(im.getBytes(order: img.ChannelOrder.rgb));
  final n = px.length;

  if (filter != PageFilter.original) {
    final bg = _background(im);
    final curve = _lut(switch (filter) {
      PageFilter.autoColor => 1.15,
      PageFilter.lightText => 1.7,
      PageFilter.grayscale => 1.4,
      PageFilter.whiteboard => 1.5,
      _ => 1.0,
    });
    final sat = switch (filter) {
      PageFilter.autoColor => 1.2,
      PageFilter.whiteboard => 1.7,
      PageFilter.lightText => 1.05,
      _ => 1.0,
    };
    for (var i = 0; i < n; i += 3) {
      var r = px[i].toDouble(), g = px[i + 1].toDouble(), b = px[i + 2].toDouble();
      final nr = math.min(255.0, r * 255 / math.max(bg[i], 24));
      final ng = math.min(255.0, g * 255 / math.max(bg[i + 1], 24));
      final nb = math.min(255.0, b * 255 / math.max(bg[i + 2], 24));
      if (filter == PageFilter.autoColor) {
        r = nr * 0.82 + r * 0.18;
        g = ng * 0.82 + g * 0.18;
        b = nb * 0.82 + b * 0.18;
      } else {
        r = nr;
        g = ng;
        b = nb;
      }
      final l = 0.299 * r + 0.587 * g + 0.114 * b;
      if (filter == PageFilter.grayscale) {
        r = g = b = l;
      } else if (filter == PageFilter.blackWhite) {
        final v = l >= 205 ? 255.0 : (l <= 150 ? 0.0 : (l - 150) * 255 / 55);
        r = g = b = v;
      } else if (sat != 1.0) {
        r = l + (r - l) * sat;
        g = l + (g - l) * sat;
        b = l + (b - l) * sat;
      }
      px[i] = curve[r.round().clamp(0, 255)];
      px[i + 1] = curve[g.round().clamp(0, 255)];
      px[i + 2] = curve[b.round().clamp(0, 255)];
    }
  }

  if (brightness != 0 || contrast != 1) {
    final t = Uint8List(256);
    for (var v = 0; v < 256; v++) {
      t[v] = ((v - 128) * contrast + 128 + brightness * 255).round().clamp(0, 255);
    }
    for (var i = 0; i < n; i++) {
      px[i] = t[px[i]];
    }
  }
  return img.Image.fromBytes(width: im.width, height: im.height, bytes: px.buffer, numChannels: 3);
}

/// Book mode: splits a two-page spread into left and right pages.
Future<void> splitSpread(String src, String left, String right) => Isolate.run(() {
      final im = _load(src);
      final half = im.width ~/ 2;
      final gutter = (im.width * 0.01).round();
      File(left).writeAsBytesSync(
          img.encodeJpg(img.copyCrop(im, x: 0, y: 0, width: half - gutter, height: im.height), quality: 92));
      File(right).writeAsBytesSync(img.encodeJpg(
          img.copyCrop(im, x: half + gutter, y: 0, width: im.width - half - gutter, height: im.height),
          quality: 92));
    });

/// ID card mode: front (and optional back) laid out on one A4 page.
Future<void> composeIdCard(String front, String? back, String out) => Isolate.run(() {
      const pw = 2480, ph = 3508; // A4 @ 300 dpi
      final page = img.Image(width: pw, height: ph, numChannels: 3);
      img.fill(page, color: img.ColorRgb8(255, 255, 255));
      void place(String path, int top) {
        var card = _load(path);
        if (card.height > card.width) card = img.copyRotate(card, angle: 90);
        card = img.copyResize(card, width: 1500, interpolation: img.Interpolation.average);
        if (card.height > 1300) {
          card = img.copyResize(card, height: 1300, interpolation: img.Interpolation.average);
        }
        img.compositeImage(page, card, dstX: (pw - card.width) ~/ 2, dstY: top);
      }

      place(front, 260);
      if (back != null) place(back, 1860);
      File(out).writeAsBytesSync(img.encodeJpg(page, quality: 92));
    });

/// Converts raw BGRA pixels (e.g. a rendered PDF page) into a JPEG file.
Future<void> writeBgraAsJpeg(Uint8List bgra, int width, int height, String out, {int quality = 88}) =>
    Isolate.run(() {
      final im = img.Image.fromBytes(
        width: width,
        height: height,
        bytes: bgra.buffer,
        numChannels: 4,
        order: img.ChannelOrder.bgra,
      );
      final flat = img.Image(width: width, height: height, numChannels: 3);
      img.fill(flat, color: img.ColorRgb8(255, 255, 255));
      img.compositeImage(flat, im);
      File(out).writeAsBytesSync(img.encodeJpg(flat, quality: quality));
    });

/// Re-encodes an image file with a size/quality budget. Returns new bytes.
Future<Uint8List> recompress(String path, int maxSide, int quality) => Isolate.run(() {
      final im = _limit(_load(path), maxSide);
      return img.encodeJpg(im, quality: quality);
    });

/// Normalises an arbitrary picked image into a JPEG at [out].
Future<void> normaliseImage(String src, String out) => Isolate.run(() {
      final im = _limit(_load(src), 4000);
      File(out).writeAsBytesSync(img.encodeJpg(im, quality: 93));
    });

/// Reads image dimensions without full processing.
Future<List<int>> imageSize(String path) => Isolate.run(() {
      final im = _load(path);
      return [im.width, im.height];
    });

/// Small previews of every filter for the editor's filter strip.
Future<List<Uint8List>> filterPreviews(String original, List<double>? crop, int quarterTurns) => Isolate.run(() {
      var im = _load(original);
      if (crop != null) {
        final x = (crop[0] * im.width).round().clamp(0, im.width - 1);
        final y = (crop[1] * im.height).round().clamp(0, im.height - 1);
        final w = ((crop[2] - crop[0]) * im.width).round().clamp(1, im.width - x);
        final h = ((crop[3] - crop[1]) * im.height).round().clamp(1, im.height - y);
        im = img.copyCrop(im, x: x, y: y, width: w, height: h);
      }
      if (quarterTurns % 4 != 0) im = img.copyRotate(im, angle: 90 * (quarterTurns % 4));
      im = im.width >= im.height
          ? img.copyResize(im, width: 220, interpolation: img.Interpolation.average)
          : img.copyResize(im, height: 260, interpolation: img.Interpolation.average);
      return [for (final f in PageFilter.values) img.encodeJpg(applyFilter(im, f), quality: 80)];
    });

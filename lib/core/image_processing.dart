import 'dart:io';
import 'dart:isolate';
import 'dart:math' as math;
import 'dart:typed_data';

import 'package:image/image.dart' as img;

import 'edge_detect.dart';
import 'models.dart';

// Page pipeline:
//   original (as captured) --warp by quad--> base (flat page, cached)
//   base --rotate, filter, adjust--> processed + thumbnail
// Filter / rotation edits only redo the second step, so they stay fast.

/// Flattens [original] by [quad] into the cached base image. Returns [w, h].
Future<List<int>> buildBase(String original, Quad? quad, String out, int maxSide) => Isolate.run(() {
      var im = loadImage(original);
      im = isFullQuad(quad) ? limitSize(im, maxSide) : warpQuad(im, quad!, maxSide: maxSide);
      File(out).writeAsBytesSync(img.encodeJpg(im, quality: 93));
      return [im.width, im.height];
    });

/// Everything a worker isolate needs to render a page from its base.
class ProcessParams {
  final String src;
  final String out;
  final String thumb;
  final PageFilter filter;
  final int quarterTurns;
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
    required this.brightness,
    required this.contrast,
    required this.maxSide,
    required this.jpegQuality,
  });
}

/// Renders a page in a background isolate. Returns [width, height].
Future<List<int>> processPage(ProcessParams p) => Isolate.run(() => _process(p));

List<int> _process(ProcessParams p) {
  var im = loadImage(p.src);
  final turns = p.quarterTurns % 4;
  if (turns != 0) im = img.copyRotate(im, angle: 90 * turns);
  im = limitSize(im, p.maxSide);
  im = applyFilter(im, p.filter, brightness: p.brightness, contrast: p.contrast);
  File(p.out).writeAsBytesSync(img.encodeJpg(im, quality: p.jpegQuality));
  _writeThumb(im, p.thumb);
  return [im.width, im.height];
}

img.Image loadImage(String path) {
  final decoded = img.decodeImage(File(path).readAsBytesSync());
  if (decoded == null) throw const FormatException('This image format is not supported');
  var im = img.bakeOrientation(decoded);
  if (im.numChannels != 3 || im.format != img.Format.uint8) {
    final flat = img.Image(width: im.width, height: im.height, numChannels: 3);
    img.fill(flat, color: img.ColorRgb8(255, 255, 255));
    img.compositeImage(flat, im.convert(format: img.Format.uint8, numChannels: 4));
    im = flat;
  }
  return im;
}

img.Image limitSize(img.Image im, int maxSide) {
  final longest = math.max(im.width, im.height);
  if (longest <= maxSide) return im;
  return im.width >= im.height
      ? img.copyResize(im, width: maxSide, interpolation: img.Interpolation.average)
      : img.copyResize(im, height: maxSide, interpolation: img.Interpolation.average);
}

void _writeThumb(img.Image im, String path) {
  final th = im.width >= im.height
      ? img.copyResize(im, width: 420, interpolation: img.Interpolation.average)
      : img.copyResize(im, height: 560, interpolation: img.Interpolation.average);
  File(path).writeAsBytesSync(img.encodeJpg(th, quality: 80));
}

/// Finds the document outline in an image file (null = use the whole image).
Future<Quad?> detectQuadInFile(String path) => Isolate.run(() {
      final (g, w, h) = grayForDetection(loadImage(path));
      return detectQuad(g, w, h);
    });

/// Normalises an arbitrary picked or captured image into a JPEG at [out].
Future<List<int>> normaliseImage(String src, String out) => Isolate.run(() {
      final im = limitSize(loadImage(src), 4000);
      File(out).writeAsBytesSync(img.encodeJpg(im, quality: 94));
      return [im.width, im.height];
    });

/// Reads image dimensions (after EXIF rotation).
Future<List<int>> imageSize(String path) => Isolate.run(() {
      final im = loadImage(path);
      return [im.width, im.height];
    });

// ------------------------------------------------------------------ filters

Uint8List _lut(double gamma) {
  final t = Uint8List(256);
  for (var i = 0; i < 256; i++) {
    t[i] = (math.pow(i / 255, gamma) * 255).round().clamp(0, 255);
  }
  return t;
}

/// Estimates the paper's lighting so shadows can be divided out.
/// A max-filter removes dark text before blurring.
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
            final v = src[(yy * w + (x + dx).clamp(0, w - 1)) * 3 + c];
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

/// Small previews of every filter for the editor's filter strip.
Future<List<Uint8List>> filterPreviews(String base, int quarterTurns) => Isolate.run(() {
      var im = loadImage(base);
      if (quarterTurns % 4 != 0) im = img.copyRotate(im, angle: 90 * (quarterTurns % 4));
      im = im.width >= im.height
          ? img.copyResize(im, width: 220, interpolation: img.Interpolation.average)
          : img.copyResize(im, height: 260, interpolation: img.Interpolation.average);
      return [for (final f in PageFilter.values) img.encodeJpg(applyFilter(im, f), quality: 82)];
    });

// ------------------------------------------------------------ scan modes

/// Book mode: flattens a two-page spread and splits it at the spine.
Future<void> splitSpread(String src, Quad? quad, String left, String right) => Isolate.run(() {
      var im = loadImage(src);
      if (!isFullQuad(quad)) im = warpQuad(im, quad!, maxSide: 4200);
      final half = im.width ~/ 2;
      final gutter = (im.width * 0.008).round();
      File(left).writeAsBytesSync(
          img.encodeJpg(img.copyCrop(im, x: 0, y: 0, width: half - gutter, height: im.height), quality: 93));
      File(right).writeAsBytesSync(img.encodeJpg(
          img.copyCrop(im, x: half + gutter, y: 0, width: im.width - half - gutter, height: im.height),
          quality: 93));
    });

enum IdCardSize { large, actual }

/// One side of an ID card: source image, outline and extra rotation.
class IdSide {
  final String path;
  final Quad? quad;
  final int quarterTurns;
  const IdSide(this.path, this.quad, [this.quarterTurns = 0]);
}

/// Flattens one ID card side (cropped, rotated, landscape) into [out].
Future<void> renderIdSide(IdSide side, String out) => Isolate.run(() {
      File(out).writeAsBytesSync(img.encodeJpg(_idSide(side), quality: 92));
    });

img.Image _idSide(IdSide side) {
  var card = loadImage(side.path);
  if (!isFullQuad(side.quad)) card = warpQuad(card, side.quad!, maxSide: 2400);
  if (side.quarterTurns % 4 != 0) card = img.copyRotate(card, angle: 90 * (side.quarterTurns % 4));
  return card;
}

/// ID card mode: front and back laid out on one A4 page (300 dpi).
/// [IdCardSize.actual] prints the card at its real size (85.6 × 54 mm).
Future<void> composeIdCard(IdSide front, IdSide? back, String out, {IdCardSize size = IdCardSize.large}) =>
    Isolate.run(() {
      const pw = 2480, ph = 3508;
      final page = img.Image(width: pw, height: ph, numChannels: 3);
      img.fill(page, color: img.ColorRgb8(255, 255, 255));
      final sides = [_idSide(front), if (back != null) _idSide(back)];
      // Fit every side into the same box so both sides line up.
      final boxW = size == IdCardSize.actual ? 1011 : 1820;
      final boxH = size == IdCardSize.actual ? 638 : (back == null ? 2400 : 1500);
      final placed = <img.Image>[];
      for (final s in sides) {
        final scale = math.min(boxW / s.width, boxH / s.height);
        placed.add(img.copyResize(s,
            width: math.max(1, (s.width * scale).round()),
            height: math.max(1, (s.height * scale).round()),
            interpolation: img.Interpolation.cubic));
      }
      final gap = size == IdCardSize.actual ? 160 : 180;
      final totalH = placed.fold<int>(0, (a, b) => a + b.height) + gap * (placed.length - 1);
      var y = size == IdCardSize.actual ? 300 : (ph - totalH) ~/ 2;
      for (final p in placed) {
        final x = (pw - p.width) ~/ 2;
        // hairline frame so the card edge stays visible on white paper
        img.drawRect(page,
            x1: x - 2, y1: y - 2, x2: x + p.width + 1, y2: y + p.height + 1, color: img.ColorRgb8(214, 218, 225), thickness: 2);
        img.compositeImage(page, p, dstX: x, dstY: y);
        y += p.height + gap;
      }
      File(out).writeAsBytesSync(img.encodeJpg(page, quality: 93));
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
      final im = limitSize(loadImage(path), maxSide);
      return img.encodeJpg(im, quality: quality);
    });

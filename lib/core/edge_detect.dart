import 'dart:math' as math;
import 'dart:typed_data';

import 'package:image/image.dart' as img;

/// A document outline: four corners normalised to 0..1, ordered
/// top-left, top-right, bottom-right, bottom-left, as [x0, y0, ... x3, y3].
typedef Quad = List<double>;

const Quad fullQuad = [0, 0, 1, 0, 1, 1, 0, 1];

bool isFullQuad(Quad? q) {
  if (q == null) return true;
  for (var i = 0; i < 8; i++) {
    if ((q[i] - fullQuad[i]).abs() > 0.004) return false;
  }
  return true;
}

class _P {
  final double x, y;
  const _P(this.x, this.y);
}

double _cross(_P o, _P a, _P b) => (a.x - o.x) * (b.y - o.y) - (a.y - o.y) * (b.x - o.x);

double _polyArea(List<_P> p) {
  var s = 0.0;
  for (var i = 0; i < p.length; i++) {
    final a = p[i], b = p[(i + 1) % p.length];
    s += a.x * b.y - b.x * a.y;
  }
  return s.abs() / 2;
}

List<_P> _hull(List<_P> pts) {
  pts.sort((a, b) => a.x != b.x ? a.x.compareTo(b.x) : a.y.compareTo(b.y));
  final lower = <_P>[], upper = <_P>[];
  for (final p in pts) {
    while (lower.length >= 2 && _cross(lower[lower.length - 2], lower.last, p) <= 0) {
      lower.removeLast();
    }
    lower.add(p);
  }
  for (final p in pts.reversed) {
    while (upper.length >= 2 && _cross(upper[upper.length - 2], upper.last, p) <= 0) {
      upper.removeLast();
    }
    upper.add(p);
  }
  lower.removeLast();
  upper.removeLast();
  return [...lower, ...upper];
}

/// Picks the four hull vertices that enclose the largest area — the page
/// corners. Long hulls are first thinned by dropping low-impact vertices.
List<_P> _toQuad(List<_P> hull) {
  final p = _thin(hull, 36);
  final n = p.length;
  if (n <= 4) return p;
  var best = -1.0;
  var pick = const [0, 1, 2, 3];
  for (var a = 0; a < n - 3; a++) {
    for (var b = a + 1; b < n - 2; b++) {
      for (var c = b + 1; c < n - 1; c++) {
        for (var d = c + 1; d < n; d++) {
          final area = _polyArea([p[a], p[b], p[c], p[d]]);
          if (area > best) {
            best = area;
            pick = [a, b, c, d];
          }
        }
      }
    }
  }
  return [for (final i in pick) p[i]];
}

/// Repeatedly drops the hull vertex whose removal loses the least area.
List<_P> _thin(List<_P> hull, int keep) {
  final p = List.of(hull);
  while (p.length > keep) {
    var best = 0;
    var bestLoss = double.infinity;
    for (var i = 0; i < p.length; i++) {
      final a = p[(i - 1 + p.length) % p.length], b = p[i], c = p[(i + 1) % p.length];
      final loss = _cross(a, b, c).abs() / 2;
      if (loss < bestLoss) {
        bestLoss = loss;
        best = i;
      }
    }
    p.removeAt(best);
  }
  return p;
}

/// Orders four points as TL, TR, BR, BL (screen coordinates, y down).
List<_P> _order(List<_P> q) {
  final cx = q.fold<double>(0, (s, p) => s + p.x) / 4;
  final cy = q.fold<double>(0, (s, p) => s + p.y) / 4;
  final sorted = List.of(q)..sort((a, b) => math.atan2(a.y - cy, a.x - cx).compareTo(math.atan2(b.y - cy, b.x - cx)));
  // atan2 order (y down) goes TL → TR → BR → BL clockwise; start at min(x+y).
  var start = 0;
  for (var i = 1; i < 4; i++) {
    if (sorted[i].x + sorted[i].y < sorted[start].x + sorted[start].y) start = i;
  }
  return [for (var i = 0; i < 4; i++) sorted[(start + i) % 4]];
}

/// Snaps each corner to the intersection of straight lines fitted to the
/// page edges (the blur and the hull simplification round corners off).
List<_P> _refine(List<_P> q, List<_P> boundary) {
  final lines = <(double, double, double)>[]; // a*x + b*y = c, with (a, b) unit normal
  for (var i = 0; i < 4; i++) {
    final a = q[i], b = q[(i + 1) % 4];
    final dx = b.x - a.x, dy = b.y - a.y;
    final len = math.sqrt(dx * dx + dy * dy);
    if (len < 4) return q;
    final nx = -dy / len, ny = dx / len;
    final c0 = nx * a.x + ny * a.y;
    var sx = 0.0, sy = 0.0, sxx = 0.0, syy = 0.0, sxy = 0.0, n = 0;
    for (final p in boundary) {
      if ((nx * p.x + ny * p.y - c0).abs() > 4) continue;
      final t = ((p.x - a.x) * dx + (p.y - a.y) * dy) / (len * len);
      if (t < 0.15 || t > 0.85) continue;
      sx += p.x;
      sy += p.y;
      sxx += p.x * p.x;
      syy += p.y * p.y;
      sxy += p.x * p.y;
      n++;
    }
    if (n < 6) return q;
    final mx = sx / n, my = sy / n;
    final cxx = sxx / n - mx * mx, cyy = syy / n - my * my, cxy = sxy / n - mx * my;
    // Direction of the edge = principal eigenvector of the covariance.
    final theta = 0.5 * math.atan2(2 * cxy, cxx - cyy);
    final ux = math.cos(theta), uy = math.sin(theta);
    final la = -uy, lb = ux;
    lines.add((la, lb, la * mx + lb * my));
  }
  final out = <_P>[];
  for (var i = 0; i < 4; i++) {
    final (a1, b1, c1) = lines[(i + 3) % 4];
    final (a2, b2, c2) = lines[i];
    final det = a1 * b2 - a2 * b1;
    if (det.abs() < 1e-6) return q;
    final p = _P((c1 * b2 - c2 * b1) / det, (a1 * c2 - a2 * c1) / det);
    final moved = math.sqrt(math.pow(p.x - q[i].x, 2) + math.pow(p.y - q[i].y, 2));
    if (moved > 12) return q; // a wild fit — keep the hull corner
    out.add(p);
  }
  return out;
}

double _angleAt(_P a, _P b, _P c) {
  final v1x = a.x - b.x, v1y = a.y - b.y, v2x = c.x - b.x, v2y = c.y - b.y;
  final d = math.sqrt(v1x * v1x + v1y * v1y) * math.sqrt(v2x * v2x + v2y * v2y);
  if (d == 0) return 0;
  return math.acos(((v1x * v2x + v1y * v2y) / d).clamp(-1.0, 1.0)) * 180 / math.pi;
}

void _boxBlur(Uint8List src, Uint8List tmp, int w, int h, int r) {
  for (var y = 0; y < h; y++) {
    var sum = 0;
    final row = y * w;
    for (var x = -r; x <= r; x++) {
      sum += src[row + x.clamp(0, w - 1)];
    }
    for (var x = 0; x < w; x++) {
      tmp[row + x] = sum ~/ (2 * r + 1);
      sum += src[row + (x + r + 1).clamp(0, w - 1)] - src[row + (x - r).clamp(0, w - 1)];
    }
  }
  for (var x = 0; x < w; x++) {
    var sum = 0;
    for (var y = -r; y <= r; y++) {
      sum += tmp[y.clamp(0, h - 1) * w + x];
    }
    for (var y = 0; y < h; y++) {
      src[y * w + x] = sum ~/ (2 * r + 1);
      sum += tmp[(y + r + 1).clamp(0, h - 1) * w + x] - tmp[(y - r).clamp(0, h - 1) * w + x];
    }
  }
}

int _otsu(Uint8List g) {
  final hist = List<int>.filled(256, 0);
  for (final v in g) {
    hist[v]++;
  }
  final total = g.length;
  var sum = 0.0;
  for (var i = 0; i < 256; i++) {
    sum += i * hist[i];
  }
  var sumB = 0.0, wB = 0, best = 0.0, t = 128;
  for (var i = 0; i < 256; i++) {
    wB += hist[i];
    if (wB == 0) continue;
    final wF = total - wB;
    if (wF == 0) break;
    sumB += i * hist[i];
    final mB = sumB / wB, mF = (sum - sumB) / wF;
    final between = wB * wF * (mB - mF) * (mB - mF);
    if (between > best) {
      best = between;
      t = i;
    }
  }
  return t;
}

/// Finds the document outline in a small grayscale frame (~150–320 px).
/// Returns null when no confident, document-like shape is found.
Quad? detectQuad(Uint8List gray, int w, int h) {
  if (w < 16 || h < 16) return null;
  final g = Uint8List.fromList(gray);
  _boxBlur(g, Uint8List(w * h), w, h, 2);
  final t = _otsu(g);
  final n = w * h;
  final label = Int32List(n);
  final stack = Int32List(n);
  var bestArea = 0, bestLabel = 0, next = 0;
  final borderTouch = <int, int>{};
  for (var i = 0; i < n; i++) {
    if (label[i] != 0 || g[i] <= t) continue;
    next++;
    var area = 0, sp = 0, touches = 0;
    stack[sp++] = i;
    label[i] = next;
    while (sp > 0) {
      final p = stack[--sp];
      area++;
      final x = p % w, y = p ~/ w;
      if (x == 0 || y == 0 || x == w - 1 || y == h - 1) touches++;
      if (x > 0 && label[p - 1] == 0 && g[p - 1] > t) {
        label[p - 1] = next;
        stack[sp++] = p - 1;
      }
      if (x < w - 1 && label[p + 1] == 0 && g[p + 1] > t) {
        label[p + 1] = next;
        stack[sp++] = p + 1;
      }
      if (y > 0 && label[p - w] == 0 && g[p - w] > t) {
        label[p - w] = next;
        stack[sp++] = p - w;
      }
      if (y < h - 1 && label[p + w] == 0 && g[p + w] > t) {
        label[p + w] = next;
        stack[sp++] = p + w;
      }
    }
    borderTouch[next] = touches;
    if (area > bestArea) {
      bestArea = area;
      bestLabel = next;
    }
  }
  if (bestLabel == 0 || bestArea < n * 0.08) return null;
  // A blob hugging most of the frame border is background, not a page.
  if (borderTouch[bestLabel]! > (w + h) * 2 * 0.55) return null;

  final boundary = <_P>[];
  for (var y = 0; y < h; y++) {
    for (var x = 0; x < w; x++) {
      final i = y * w + x;
      if (label[i] != bestLabel) continue;
      if (x == 0 ||
          y == 0 ||
          x == w - 1 ||
          y == h - 1 ||
          label[i - 1] != bestLabel ||
          label[i + 1] != bestLabel ||
          label[i - w] != bestLabel ||
          label[i + w] != bestLabel) {
        boundary.add(_P(x + 0.5, y + 0.5));
      }
    }
  }
  if (boundary.length < 8) return null;
  final hull = _hull(boundary);
  if (hull.length < 4) return null;
  final quad = _refine(_order(_toQuad(hull)), boundary);
  final qa = _polyArea(quad);
  if (qa < n * 0.08) return null;
  // The blob should fill its quad (a page, not a blobby object).
  if (bestArea / qa < 0.82) return null;
  for (var i = 0; i < 4; i++) {
    final ang = _angleAt(quad[(i + 3) % 4], quad[i], quad[(i + 1) % 4]);
    if (ang < 40 || ang > 140) return null;
  }
  return [for (final p in quad) ...[(p.x / w).clamp(0.0, 1.0), (p.y / h).clamp(0.0, 1.0)]];
}

/// Downscaled grayscale copy of an image for detection.
(Uint8List, int, int) grayForDetection(img.Image im, {int longSide = 256}) {
  final small = im.width >= im.height
      ? img.copyResize(im, width: longSide, interpolation: img.Interpolation.average)
      : img.copyResize(im, height: longSide, interpolation: img.Interpolation.average);
  final rgb = small.getBytes(order: img.ChannelOrder.rgb);
  final out = Uint8List(small.width * small.height);
  for (var i = 0, j = 0; i < out.length; i++, j += 3) {
    out[i] = (rgb[j] * 77 + rgb[j + 1] * 150 + rgb[j + 2] * 29) >> 8;
  }
  return (out, small.width, small.height);
}

/// Samples the luma plane of an NV21 / YUV frame down to roughly [target] px wide.
(Uint8List, int, int) subsampleLuma(Uint8List y, int width, int height, int rowStride, {int target = 200}) {
  final step = math.max(1, width ~/ target);
  final w = width ~/ step, h = height ~/ step;
  final out = Uint8List(w * h);
  for (var r = 0; r < h; r++) {
    final src = r * step * rowStride;
    for (var c = 0; c < w; c++) {
      out[r * w + c] = y[src + c * step];
    }
  }
  return (out, w, h);
}

/// Rotates a quad by the camera sensor orientation (0/90/180/270 clockwise).
Quad rotateQuad(Quad q, int degrees) {
  final out = List<double>.filled(8, 0);
  for (var i = 0; i < 4; i++) {
    final x = q[i * 2], y = q[i * 2 + 1];
    final (nx, ny) = switch (degrees % 360) {
      90 => (1 - y, x),
      180 => (1 - x, 1 - y),
      270 => (y, 1 - x),
      _ => (x, y),
    };
    out[i * 2] = nx;
    out[i * 2 + 1] = ny;
  }
  final pts = _order([for (var i = 0; i < 4; i++) _P(out[i * 2], out[i * 2 + 1])]);
  return [for (final p in pts) ...[p.x, p.y]];
}

/// Largest corner movement between two quads (normalised units).
double quadDistance(Quad a, Quad b) {
  var m = 0.0;
  for (var i = 0; i < 8; i++) {
    m = math.max(m, (a[i] - b[i]).abs());
  }
  return m;
}

// ------------------------------------------------------------ perspective

List<double> _solve(List<List<double>> a, List<double> b) {
  final n = b.length;
  for (var c = 0; c < n; c++) {
    var piv = c;
    for (var r = c + 1; r < n; r++) {
      if (a[r][c].abs() > a[piv][c].abs()) piv = r;
    }
    final tr = a[c];
    a[c] = a[piv];
    a[piv] = tr;
    final tb = b[c];
    b[c] = b[piv];
    b[piv] = tb;
    for (var r = c + 1; r < n; r++) {
      final f = a[r][c] / a[c][c];
      for (var k = c; k < n; k++) {
        a[r][k] -= f * a[c][k];
      }
      b[r] -= f * b[c];
    }
  }
  final x = List<double>.filled(n, 0);
  for (var r = n - 1; r >= 0; r--) {
    var s = b[r];
    for (var k = r + 1; k < n; k++) {
      s -= a[r][k] * x[k];
    }
    x[r] = s / a[r][r];
  }
  return x;
}

/// Homography mapping (u, v) in the output rectangle to source pixels.
List<double> _homography(List<double> dst, List<double> src) {
  final a = <List<double>>[];
  final b = <double>[];
  for (var i = 0; i < 4; i++) {
    final u = dst[i * 2], v = dst[i * 2 + 1], x = src[i * 2], y = src[i * 2 + 1];
    a.add([u, v, 1, 0, 0, 0, -u * x, -v * x]);
    b.add(x);
    a.add([0, 0, 0, u, v, 1, -u * y, -v * y]);
    b.add(y);
  }
  return _solve(a, b);
}

/// Flattens the area inside [quad] into a rectangle (perspective correction).
img.Image warpQuad(img.Image src, Quad quad, {int maxSide = 3200}) {
  if (isFullQuad(quad)) return src;
  final sw = src.width, sh = src.height;
  final px = [for (var i = 0; i < 4; i++) quad[i * 2] * (sw - 1)];
  final py = [for (var i = 0; i < 4; i++) quad[i * 2 + 1] * (sh - 1)];
  double d(int a, int b) => math.sqrt(math.pow(px[a] - px[b], 2) + math.pow(py[a] - py[b], 2));
  var outW = math.max(d(0, 1), d(3, 2));
  var outH = math.max(d(0, 3), d(1, 2));
  final scale = math.min(1.0, maxSide / math.max(outW, outH));
  final w = math.max(1, (outW * scale).round()), h = math.max(1, (outH * scale).round());
  final hm = _homography(
    [0, 0, w - 1.0, 0, w - 1.0, h - 1.0, 0, h - 1.0],
    [px[0], py[0], px[1], py[1], px[2], py[2], px[3], py[3]],
  );
  final s = src.getBytes(order: img.ChannelOrder.rgb);
  final out = Uint8List(w * h * 3);
  var o = 0;
  for (var v = 0; v < h; v++) {
    for (var u = 0; u < w; u++) {
      final den = hm[6] * u + hm[7] * v + 1;
      var x = (hm[0] * u + hm[1] * v + hm[2]) / den;
      var y = (hm[3] * u + hm[4] * v + hm[5]) / den;
      if (x < 0) x = 0;
      if (y < 0) y = 0;
      if (x > sw - 1.001) x = sw - 1.001;
      if (y > sh - 1.001) y = sh - 1.001;
      final x0 = x.toInt(), y0 = y.toInt();
      final fx = x - x0, fy = y - y0;
      final i00 = (y0 * sw + x0) * 3, i10 = i00 + 3, i01 = i00 + sw * 3, i11 = i01 + 3;
      for (var c = 0; c < 3; c++) {
        final top = s[i00 + c] + (s[i10 + c] - s[i00 + c]) * fx;
        final bot = s[i01 + c] + (s[i11 + c] - s[i01 + c]) * fx;
        out[o++] = (top + (bot - top) * fy).round();
      }
    }
  }
  return img.Image.fromBytes(width: w, height: h, bytes: out.buffer, numChannels: 3);
}

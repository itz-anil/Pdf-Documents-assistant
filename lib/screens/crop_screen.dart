import 'dart:io';
import 'dart:math' as math;

import 'package:flutter/material.dart';

import '../app/icons.dart';
import '../app/theme.dart';
import '../core/edge_detect.dart';
import '../core/image_processing.dart';
import '../widgets/common.dart';
import '../widgets/glass.dart';

class CropResult {
  /// Outline on the original image (null = whole image).
  final Quad? quad;
  final int quarterTurns;
  const CropResult(this.quad, this.quarterTurns);
}

/// Drag the four corners onto the page's edges; the page is flattened
/// (perspective-corrected) when applied. A loupe magnifies the corner.
class CropScreen extends StatefulWidget {
  final String imagePath;
  final Quad? quad;
  final int quarterTurns;
  final String title;
  const CropScreen({
    super.key,
    required this.imagePath,
    this.quad,
    this.quarterTurns = 0,
    this.title = 'Adjust corners',
  });

  static Future<CropResult?> open(BuildContext context, String path, Quad? quad, int turns, {String? title}) =>
      Navigator.of(context).push<CropResult>(MaterialPageRoute(
        builder: (_) => CropScreen(imagePath: path, quad: quad, quarterTurns: turns, title: title ?? 'Adjust corners'),
      ));

  @override
  State<CropScreen> createState() => _CropScreenState();
}

class _CropScreenState extends State<CropScreen> {
  Size? _imageSize;
  late int _turns = widget.quarterTurns % 4;
  late List<Offset> _pts; // display-normalised TL, TR, BR, BL
  int? _drag; // 0-3 corners, 4-7 edges (top, right, bottom, left)
  Offset? _finger;
  bool _detecting = false;

  @override
  void initState() {
    super.initState();
    _setFromOriginal(widget.quad ?? fullQuad);
    imageSize(widget.imagePath).then((s) {
      if (mounted) setState(() => _imageSize = Size(s[0].toDouble(), s[1].toDouble()));
    });
  }

  void _setFromOriginal(Quad q) {
    final d = rotateQuad(q, 90 * _turns);
    _pts = [for (var i = 0; i < 4; i++) Offset(d[i * 2], d[i * 2 + 1])];
  }

  Quad _toOriginal() {
    final d = [for (final p in _pts) ...[p.dx, p.dy]];
    return rotateQuad(d, (360 - 90 * _turns) % 360);
  }

  void _rotate(int delta) {
    final q = _toOriginal();
    setState(() {
      _turns = (_turns + delta) % 4;
      _setFromOriginal(q);
    });
  }

  Future<void> _auto() async {
    setState(() => _detecting = true);
    final q = await detectQuadInFile(widget.imagePath);
    if (!mounted) return;
    setState(() {
      _detecting = false;
      if (q != null) _setFromOriginal(q);
    });
    if (q == null) toast(context, 'No page edges found — drag the corners yourself', error: true);
  }

  bool _isConvex() {
    double cross(Offset o, Offset a, Offset b) => (a.dx - o.dx) * (b.dy - o.dy) - (a.dy - o.dy) * (b.dx - o.dx);
    var sign = 0;
    for (var i = 0; i < 4; i++) {
      final c = cross(_pts[i], _pts[(i + 1) % 4], _pts[(i + 2) % 4]);
      if (c.abs() < 1e-6) return false;
      final s = c > 0 ? 1 : -1;
      if (sign == 0) sign = s;
      if (s != sign) return false;
    }
    return true;
  }

  void _apply() {
    if (!_isConvex()) {
      toast(context, 'The corners cross over — drag them to the page corners', error: true);
      return;
    }
    final q = _toOriginal();
    Navigator.pop(context, CropResult(isFullQuad(q) ? null : q, _turns));
  }

  int? _hit(Offset local, Size box) {
    Offset px(Offset n) => Offset(n.dx * box.width, n.dy * box.height);
    var best = -1;
    var bestD = 44.0;
    for (var i = 0; i < 4; i++) {
      final d = (px(_pts[i]) - local).distance;
      if (d < bestD) {
        bestD = d;
        best = i;
      }
    }
    if (best >= 0) return best;
    for (var e = 0; e < 4; e++) {
      final mid = (px(_pts[e]) + px(_pts[(e + 1) % 4])) / 2;
      if ((mid - local).distance < 36) return 4 + e;
    }
    return null;
  }

  void _move(Offset delta, Size box) {
    final d = Offset(delta.dx / box.width, delta.dy / box.height);
    Offset clamp(Offset o) => Offset(o.dx.clamp(0.0, 1.0), o.dy.clamp(0.0, 1.0));
    final i = _drag;
    if (i == null) return;
    setState(() {
      if (i < 4) {
        _pts[i] = clamp(_pts[i] + d);
      } else {
        final a = i - 4, b = (i - 3) % 4;
        _pts[a] = clamp(_pts[a] + d);
        _pts[b] = clamp(_pts[b] + d);
      }
    });
  }

  @override
  Widget build(BuildContext context) {
    final g = Glass.of(context);
    final dark = Theme.of(context).copyWith(extensions: [Glass.dark(g.accent)]);
    return Theme(
      data: dark,
      child: Scaffold(
        backgroundColor: const Color(0xFF0A0B0E),
        body: SafeArea(
          child: Column(
            children: [
              GlassTopBar(
                title: widget.title,
                subtitle: 'Drag corners or edges onto the page',
                actions: [
                  GlassIconButton(icon: PhosphorIconsRegular.arrowCounterClockwise, tooltip: 'Rotate left', onTap: () => _rotate(3)),
                  GlassIconButton(icon: PhosphorIconsRegular.arrowClockwise, tooltip: 'Rotate right', onTap: () => _rotate(1)),
                ],
              ),
              Expanded(
                child: _imageSize == null
                    ? const Center(child: CircularProgressIndicator(color: Colors.white))
                    : LayoutBuilder(builder: (_, c) {
                        final src = _turns.isOdd ? Size(_imageSize!.height, _imageSize!.width) : _imageSize!;
                        final avail = Size(c.maxWidth - 56, c.maxHeight - 56);
                        final scale = math.min(avail.width / src.width, avail.height / src.height);
                        final box = Size(src.width * scale, src.height * scale);
                        return Center(
                          child: SizedBox(
                            width: box.width,
                            height: box.height,
                            child: GestureDetector(
                              onPanStart: (d) => setState(() {
                                _drag = _hit(d.localPosition, box);
                                _finger = _drag == null ? null : d.localPosition;
                              }),
                              onPanUpdate: (d) {
                                _move(d.delta, box);
                                if (_drag != null) setState(() => _finger = d.localPosition);
                              },
                              onPanEnd: (_) => setState(() {
                                _drag = null;
                                _finger = null;
                              }),
                              child: Stack(
                                clipBehavior: Clip.none,
                                children: [
                                  Positioned.fill(
                                    child: RotatedBox(
                                      quarterTurns: _turns,
                                      child: Image.file(File(widget.imagePath), fit: BoxFit.fill, cacheWidth: 1800),
                                    ),
                                  ),
                                  Positioned.fill(
                                    child: CustomPaint(painter: _QuadPainter(_pts, g.accent.primary, _drag)),
                                  ),
                                  if (_finger != null)
                                    Positioned(
                                      left: _finger!.dx - 58,
                                      top: _finger!.dy - 58 - 96,
                                      child: const RawMagnifier(
                                        size: Size(116, 116),
                                        magnificationScale: 2.4,
                                        focalPointOffset: Offset(0, 96),
                                        decoration: MagnifierDecoration(
                                          shape: CircleBorder(side: BorderSide(color: Colors.white, width: 3)),
                                          shadows: [BoxShadow(color: Colors.black54, blurRadius: 16)],
                                        ),
                                      ),
                                    ),
                                ],
                              ),
                            ),
                          ),
                        );
                      }),
              ),
              Padding(
                padding: const EdgeInsets.fromLTRB(16, 6, 16, 6),
                child: Row(
                  mainAxisAlignment: MainAxisAlignment.center,
                  children: [
                    _ChipButton(
                      icon: PhosphorIconsRegular.magicWand,
                      label: _detecting ? 'Detecting…' : 'Auto detect',
                      onTap: _detecting ? null : _auto,
                    ),
                    const SizedBox(width: 10),
                    _ChipButton(
                      icon: PhosphorIconsRegular.cornersOut,
                      label: 'Whole image',
                      onTap: () => setState(() => _setFromOriginal(fullQuad)),
                    ),
                  ],
                ),
              ),
              Padding(
                padding: const EdgeInsets.fromLTRB(20, 10, 20, 16),
                child: Row(
                  children: [
                    Expanded(child: GlassButton(label: 'Cancel', expand: true, onTap: () => Navigator.pop(context))),
                    const SizedBox(width: 12),
                    Expanded(
                      child: GradientButton(label: 'Apply', icon: PhosphorIconsBold.check, expand: true, onTap: _apply),
                    ),
                  ],
                ),
              ),
            ],
          ),
        ),
      ),
    );
  }
}

class _ChipButton extends StatelessWidget {
  final IconData icon;
  final String label;
  final VoidCallback? onTap;
  const _ChipButton({required this.icon, required this.label, this.onTap});

  @override
  Widget build(BuildContext context) {
    return Semantics(
      button: true,
      label: label,
      child: Pressable(
        onTap: onTap,
        child: Container(
          height: 40,
          padding: const EdgeInsets.symmetric(horizontal: 14),
          decoration: BoxDecoration(
            color: Colors.white.withValues(alpha: 0.08),
            borderRadius: BorderRadius.circular(20),
            border: Border.all(color: Colors.white.withValues(alpha: 0.1)),
          ),
          child: Row(
            mainAxisSize: MainAxisSize.min,
            children: [
              PhosphorIcon(icon, size: 18, color: Colors.white),
              const SizedBox(width: 8),
              Text(label, style: const TextStyle(color: Colors.white, fontWeight: FontWeight.w600, fontSize: 13)),
            ],
          ),
        ),
      ),
    );
  }
}

class _QuadPainter extends CustomPainter {
  final List<Offset> pts;
  final Color accent;
  final int? active;
  _QuadPainter(this.pts, this.accent, this.active);

  @override
  void paint(Canvas canvas, Size size) {
    final p = [for (final o in pts) Offset(o.dx * size.width, o.dy * size.height)];
    final quad = Path()..addPolygon(p, true);
    canvas.drawPath(
      Path()
        ..fillType = PathFillType.evenOdd
        ..addRect(Offset.zero & size)
        ..addPath(quad, Offset.zero),
      Paint()..color = Colors.black.withValues(alpha: 0.5),
    );
    canvas.drawPath(quad, Paint()..color = accent.withValues(alpha: 0.10));
    canvas.drawPath(
      quad,
      Paint()
        ..color = accent
        ..style = PaintingStyle.stroke
        ..strokeWidth = 2.5,
    );
    // edge handles
    for (var e = 0; e < 4; e++) {
      final a = p[e], b = p[(e + 1) % 4];
      final mid = (a + b) / 2;
      final dir = (b - a) / (b - a).distance;
      final on = active == 4 + e;
      canvas.drawLine(
        mid - dir * 14,
        mid + dir * 14,
        Paint()
          ..color = on ? accent : Colors.white
          ..strokeWidth = 7
          ..strokeCap = StrokeCap.round,
      );
    }
    for (var i = 0; i < 4; i++) {
      final on = active == i;
      canvas.drawCircle(p[i], on ? 15 : 12, Paint()..color = Colors.white);
      canvas.drawCircle(
        p[i],
        on ? 15 : 12,
        Paint()
          ..color = accent
          ..style = PaintingStyle.stroke
          ..strokeWidth = 3.5,
      );
    }
  }

  @override
  bool shouldRepaint(_QuadPainter old) => true;
}

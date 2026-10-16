import 'dart:io';
import 'dart:math' as math;

import 'package:flutter/material.dart';
import '../app/icons.dart';
import 'package:provider/provider.dart';

import '../app/theme.dart';
import '../core/image_processing.dart';
import '../core/library_store.dart';
import '../core/models.dart';
import '../widgets/glass.dart';

/// Fine crop on the original capture. Returns [l, t, r, b] in the original
/// (unrotated) image's normalised coordinates.
class CropScreen extends StatefulWidget {
  final DocItem doc;
  final PageItem page;
  const CropScreen({super.key, required this.doc, required this.page});

  @override
  State<CropScreen> createState() => _CropScreenState();
}

enum _Handle { tl, tr, bl, br, move }

class _CropScreenState extends State<CropScreen> {
  Size? _imageSize; // original pixel size
  late Rect _rect; // display-normalised crop
  _Handle? _active;
  int get _q => widget.page.quarterTurns % 4;

  static Offset _toDisplay(Offset o, int q) => switch (q) {
        1 => Offset(1 - o.dy, o.dx),
        2 => Offset(1 - o.dx, 1 - o.dy),
        3 => Offset(o.dy, 1 - o.dx),
        _ => o,
      };

  static Offset _toOriginal(Offset o, int q) => switch (q) {
        1 => Offset(o.dy, 1 - o.dx),
        2 => Offset(1 - o.dx, 1 - o.dy),
        3 => Offset(1 - o.dy, o.dx),
        _ => o,
      };

  @override
  void initState() {
    super.initState();
    final c = widget.page.crop;
    if (c == null) {
      _rect = const Rect.fromLTRB(0, 0, 1, 1);
    } else {
      final a = _toDisplay(Offset(c[0], c[1]), _q);
      final b = _toDisplay(Offset(c[2], c[3]), _q);
      _rect = Rect.fromPoints(a, b);
    }
    final store = context.read<LibraryStore>();
    imageSize(store.originalFile(widget.doc, widget.page).path).then((s) {
      if (mounted) setState(() => _imageSize = Size(s[0].toDouble(), s[1].toDouble()));
    });
  }

  List<double> _result() {
    final a = _toOriginal(_rect.topLeft, _q);
    final b = _toOriginal(_rect.bottomRight, _q);
    final r = Rect.fromPoints(a, b);
    return [r.left, r.top, r.right, r.bottom].map((v) => v.clamp(0.0, 1.0)).toList();
  }

  _Handle _hit(Offset local, Size box) {
    final r = Rect.fromLTRB(_rect.left * box.width, _rect.top * box.height, _rect.right * box.width,
        _rect.bottom * box.height);
    const reach = 36.0;
    final corners = {
      _Handle.tl: r.topLeft,
      _Handle.tr: r.topRight,
      _Handle.bl: r.bottomLeft,
      _Handle.br: r.bottomRight,
    };
    _Handle best = _Handle.move;
    var bestD = reach;
    corners.forEach((h, c) {
      final d = (c - local).distance;
      if (d < bestD) {
        bestD = d;
        best = h;
      }
    });
    return best;
  }

  void _drag(Offset delta, Size box) {
    final dx = delta.dx / box.width, dy = delta.dy / box.height;
    const minSize = 0.08;
    var l = _rect.left, t = _rect.top, r = _rect.right, b = _rect.bottom;
    switch (_active) {
      case _Handle.tl:
        l = (l + dx).clamp(0.0, r - minSize);
        t = (t + dy).clamp(0.0, b - minSize);
      case _Handle.tr:
        r = (r + dx).clamp(l + minSize, 1.0);
        t = (t + dy).clamp(0.0, b - minSize);
      case _Handle.bl:
        l = (l + dx).clamp(0.0, r - minSize);
        b = (b + dy).clamp(t + minSize, 1.0);
      case _Handle.br:
        r = (r + dx).clamp(l + minSize, 1.0);
        b = (b + dy).clamp(t + minSize, 1.0);
      case _Handle.move:
        final w = r - l, h = b - t;
        l = (l + dx).clamp(0.0, 1.0 - w);
        t = (t + dy).clamp(0.0, 1.0 - h);
        r = l + w;
        b = t + h;
      case null:
        return;
    }
    setState(() => _rect = Rect.fromLTRB(l, t, r, b));
  }

  @override
  Widget build(BuildContext context) {
    final g = Glass.of(context);
    final store = context.read<LibraryStore>();
    return Scaffold(
      backgroundColor: Colors.black,
      body: SafeArea(
        child: Column(
          children: [
            Theme(
              data: Theme.of(context).copyWith(extensions: [Glass.dark(g.accent)]),
              child: Builder(
                builder: (ctx) => GlassTopBar(
                  title: 'Crop',
                  subtitle: 'Drag the corners or move the frame',
                  actions: [
                    GlassIconButton(
                      icon: PhosphorIconsDuotone.arrowsOut,
                      tooltip: 'Full page',
                      onTap: () => setState(() => _rect = const Rect.fromLTRB(0, 0, 1, 1)),
                    ),
                  ],
                ),
              ),
            ),
            Expanded(
              child: _imageSize == null
                  ? const Center(child: CircularProgressIndicator())
                  : LayoutBuilder(builder: (_, c) {
                      final src = _q.isOdd ? Size(_imageSize!.height, _imageSize!.width) : _imageSize!;
                      final avail = Size(c.maxWidth - 48, c.maxHeight - 48);
                      final scale = math.min(avail.width / src.width, avail.height / src.height);
                      final box = Size(src.width * scale, src.height * scale);
                      return Center(
                        child: SizedBox(
                          width: box.width,
                          height: box.height,
                          child: GestureDetector(
                            onPanStart: (d) => _active = _hit(d.localPosition, box),
                            onPanUpdate: (d) => _drag(d.delta, box),
                            onPanEnd: (_) => setState(() => _active = null),
                            child: Stack(
                              fit: StackFit.expand,
                              children: [
                                RotatedBox(
                                  quarterTurns: _q,
                                  child: Image.file(
                                    File(store.originalFile(widget.doc, widget.page).path),
                                    fit: BoxFit.fill,
                                    cacheWidth: 1600,
                                  ),
                                ),
                                CustomPaint(painter: _CropPainter(_rect, g.accent.primary, _active != null)),
                              ],
                            ),
                          ),
                        ),
                      );
                    }),
            ),
            Padding(
              padding: const EdgeInsets.fromLTRB(20, 8, 20, 16),
              child: Row(
                children: [
                  Expanded(
                    child: Theme(
                      data: Theme.of(context).copyWith(extensions: [Glass.dark(g.accent)]),
                      child: GlassButton(label: 'Cancel', onTap: () => Navigator.pop(context)),
                    ),
                  ),
                  const SizedBox(width: 12),
                  Expanded(
                    child: GradientButton(
                      label: 'Apply',
                      icon: PhosphorIconsBold.check,
                      expand: true,
                      onTap: () => Navigator.pop(context, _result()),
                    ),
                  ),
                ],
              ),
            ),
          ],
        ),
      ),
    );
  }
}

class _CropPainter extends CustomPainter {
  final Rect n;
  final Color accent;
  final bool dragging;
  _CropPainter(this.n, this.accent, this.dragging);

  @override
  void paint(Canvas canvas, Size size) {
    final r = Rect.fromLTRB(n.left * size.width, n.top * size.height, n.right * size.width, n.bottom * size.height);
    final shade = Path()
      ..fillType = PathFillType.evenOdd
      ..addRect(Offset.zero & size)
      ..addRect(r);
    canvas.drawPath(shade, Paint()..color = Colors.black.withValues(alpha: 0.55));
    canvas.drawRect(r, Paint()
      ..style = PaintingStyle.stroke
      ..strokeWidth = 2
      ..color = accent);
    if (dragging) {
      final grid = Paint()
        ..color = Colors.white.withValues(alpha: 0.45)
        ..strokeWidth = 1;
      for (var i = 1; i < 3; i++) {
        final x = r.left + r.width * i / 3;
        final y = r.top + r.height * i / 3;
        canvas.drawLine(Offset(x, r.top), Offset(x, r.bottom), grid);
        canvas.drawLine(Offset(r.left, y), Offset(r.right, y), grid);
      }
    }
    final fill = Paint()..color = Colors.white;
    final ring = Paint()
      ..color = accent
      ..style = PaintingStyle.stroke
      ..strokeWidth = 3;
    for (final c in [r.topLeft, r.topRight, r.bottomLeft, r.bottomRight]) {
      canvas.drawCircle(c, 11, fill);
      canvas.drawCircle(c, 11, ring);
    }
  }

  @override
  bool shouldRepaint(_CropPainter old) => old.n != n || old.dragging != dragging || old.accent != accent;
}

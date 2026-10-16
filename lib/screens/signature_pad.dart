import 'dart:io';
import 'dart:math' as math;
import 'dart:ui' as ui;

import 'package:flutter/material.dart';
import 'package:path/path.dart' as p;
import '../app/icons.dart';
import 'package:provider/provider.dart';

import '../app/theme.dart';
import '../core/library_store.dart';
import '../core/settings.dart';
import '../widgets/common.dart';
import '../widgets/glass.dart';

/// Draw a signature. Returns the path of a transparent, trimmed PNG.
class SignaturePadScreen extends StatefulWidget {
  const SignaturePadScreen({super.key});

  @override
  State<SignaturePadScreen> createState() => _SignaturePadScreenState();
}

class _SignaturePadScreenState extends State<SignaturePadScreen> {
  final List<List<Offset>> _strokes = [];
  Color _ink = const Color(0xFF0F172A);
  bool _remember = true;

  static const _inks = [Color(0xFF0F172A), Color(0xFF1D4ED8), Color(0xFFB91C1C)];

  Future<void> _save() async {
    final pts = _strokes.expand((s) => s).toList();
    if (pts.length < 2) {
      toast(context, 'Draw your signature first', error: true);
      return;
    }
    final store = context.read<LibraryStore>();
    final settings = context.read<SettingsStore>();
    var minX = pts.first.dx, maxX = minX, minY = pts.first.dy, maxY = minY;
    for (final o in pts) {
      minX = math.min(minX, o.dx);
      maxX = math.max(maxX, o.dx);
      minY = math.min(minY, o.dy);
      maxY = math.max(maxY, o.dy);
    }
    const pad = 10.0, scale = 3.0;
    final w = (maxX - minX + pad * 2), h = (maxY - minY + pad * 2);
    final rec = ui.PictureRecorder();
    final canvas = Canvas(rec);
    canvas.scale(scale);
    canvas.translate(pad - minX, pad - minY);
    final paint = Paint()
      ..color = _ink
      ..strokeWidth = 3.2
      ..strokeCap = StrokeCap.round
      ..strokeJoin = StrokeJoin.round
      ..style = PaintingStyle.stroke;
    for (final s in _strokes) {
      canvas.drawPath(_smooth(s), paint);
    }
    final image = await rec.endRecording().toImage((w * scale).ceil(), (h * scale).ceil());
    final data = await image.toByteData(format: ui.ImageByteFormat.png);
    final name = 'signature_${DateTime.now().millisecondsSinceEpoch}.png';
    final file = File(p.join(store.root.path, name));
    await file.writeAsBytes(data!.buffer.asUint8List(), flush: true);
    if (_remember) {
      final old = settings.savedSignature;
      if (old != null) {
        final f = File(p.join(store.root.path, old));
        if (await f.exists()) await f.delete();
      }
      settings.setSavedSignature = name;
    }
    if (mounted) Navigator.pop(context, file.path);
  }

  @override
  Widget build(BuildContext context) {
    final g = Glass.of(context);
    return Scaffold(
      body: GlassBackground(
        child: SafeArea(
          child: Column(
            children: [
              GlassTopBar(
                title: 'Your signature',
                subtitle: 'Sign inside the box',
                actions: [
                  GlassIconButton(
                    icon: PhosphorIconsDuotone.arrowCounterClockwise,
                    tooltip: 'Undo',
                    onTap: _strokes.isEmpty ? null : () => setState(_strokes.removeLast),
                  ),
                  GlassIconButton(
                    icon: PhosphorIconsDuotone.eraser,
                    tooltip: 'Clear',
                    onTap: () => setState(_strokes.clear),
                  ),
                ],
              ),
              Expanded(
                child: Padding(
                  padding: const EdgeInsets.all(20),
                  child: Container(
                    decoration: BoxDecoration(
                      color: Colors.white,
                      borderRadius: BorderRadius.circular(24),
                      boxShadow: [BoxShadow(color: Colors.black.withValues(alpha: 0.15), blurRadius: 20)],
                    ),
                    clipBehavior: Clip.antiAlias,
                    child: Stack(
                      children: [
                        Positioned(
                          left: 28,
                          right: 28,
                          bottom: 70,
                          child: Container(height: 1.5, color: const Color(0xFFCBD5E1)),
                        ),
                        Positioned(
                          left: 28,
                          bottom: 78,
                          child: Text('×', style: TextStyle(fontSize: 26, color: Colors.grey.shade500)),
                        ),
                        Positioned.fill(
                          child: GestureDetector(
                            onPanStart: (d) => setState(() => _strokes.add([d.localPosition])),
                            onPanUpdate: (d) => setState(() => _strokes.last.add(d.localPosition)),
                            child: CustomPaint(painter: _PadPainter(_strokes, _ink)),
                          ),
                        ),
                      ],
                    ),
                  ),
                ),
              ),
              Padding(
                padding: const EdgeInsets.symmetric(horizontal: 20),
                child: Row(
                  children: [
                    for (final c in _inks)
                      Padding(
                        padding: const EdgeInsets.only(right: 10),
                        child: Semantics(
                          button: true,
                          label: 'Ink colour',
                          selected: c == _ink,
                          child: Pressable(
                            onTap: () => setState(() => _ink = c),
                            child: AnimatedContainer(
                              duration: const Duration(milliseconds: 160),
                              width: 34,
                              height: 34,
                              decoration: BoxDecoration(
                                color: c,
                                shape: BoxShape.circle,
                                border: Border.all(color: c == _ink ? g.accent.primary : g.border, width: c == _ink ? 3 : 1),
                              ),
                            ),
                          ),
                        ),
                      ),
                    const Spacer(),
                    Text('Remember', style: TextStyle(color: g.text, fontWeight: FontWeight.w600)),
                    Switch(value: _remember, onChanged: (v) => setState(() => _remember = v)),
                  ],
                ),
              ),
              Padding(
                padding: const EdgeInsets.fromLTRB(20, 12, 20, 16),
                child: GradientButton(label: 'Use signature', icon: PhosphorIconsBold.check, expand: true, onTap: _save),
              ),
            ],
          ),
        ),
      ),
    );
  }
}

Path _smooth(List<Offset> pts) {
  final path = Path();
  if (pts.isEmpty) return path;
  path.moveTo(pts.first.dx, pts.first.dy);
  if (pts.length == 1) {
    path.lineTo(pts.first.dx + 0.1, pts.first.dy + 0.1);
    return path;
  }
  for (var i = 1; i < pts.length - 1; i++) {
    final mid = Offset((pts[i].dx + pts[i + 1].dx) / 2, (pts[i].dy + pts[i + 1].dy) / 2);
    path.quadraticBezierTo(pts[i].dx, pts[i].dy, mid.dx, mid.dy);
  }
  path.lineTo(pts.last.dx, pts.last.dy);
  return path;
}

Path smoothPath(List<Offset> pts) => _smooth(pts);

class _PadPainter extends CustomPainter {
  final List<List<Offset>> strokes;
  final Color ink;
  _PadPainter(this.strokes, this.ink);

  @override
  void paint(Canvas canvas, Size size) {
    final paint = Paint()
      ..color = ink
      ..strokeWidth = 3.2
      ..strokeCap = StrokeCap.round
      ..strokeJoin = StrokeJoin.round
      ..style = PaintingStyle.stroke;
    for (final s in strokes) {
      canvas.drawPath(_smooth(s), paint);
    }
  }

  @override
  bool shouldRepaint(_PadPainter old) => true;
}

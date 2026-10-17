import 'dart:io';
import 'dart:math' as math;
import 'dart:ui' as ui;

import 'package:flutter/material.dart';
import 'package:intl/intl.dart';
import 'package:path/path.dart' as p;
import '../app/icons.dart';
import 'package:provider/provider.dart';

import '../app/theme.dart';
import '../core/library_store.dart';
import '../core/models.dart';
import '../core/settings.dart';
import '../widgets/common.dart';
import '../widgets/glass.dart';
import 'signature_pad.dart';

enum _Tool { move, pen, highlighter }

enum _StampKind { text, signature, check, cross }

class _Stroke {
  final List<Offset> pts; // normalised to image
  final Color color;
  final double width; // fraction of image width
  final bool highlight;
  _Stroke(this.pts, this.color, this.width, this.highlight);
}

class _Stamp {
  final _StampKind kind;
  String text;
  Offset center; // normalised
  double scale;
  Color color;
  final ui.Image? image;
  _Stamp(this.kind, {this.text = '', required this.center, required this.color, this.image}) : scale = 1;


  /// Base size as a fraction of the image width.
  double get baseWidth => switch (kind) {
        _StampKind.signature => 0.32,
        _StampKind.check || _StampKind.cross => 0.06,
        _StampKind.text => 0.0,
      };
}

const _fontFraction = 0.035;

/// Fill & Sign / markup. Everything is merged into the page on save.
class AnnotateScreen extends StatefulWidget {
  final DocItem doc;
  final PageItem page;
  const AnnotateScreen({super.key, required this.doc, required this.page});

  @override
  State<AnnotateScreen> createState() => _AnnotateScreenState();
}

class _AnnotateScreenState extends State<AnnotateScreen> {
  ui.Image? _image;
  _Tool _tool = _Tool.move;
  Color _color = const Color(0xFF1D4ED8);
  double _penWidth = 0.006;
  final List<_Stroke> _strokes = [];
  final List<_Stamp> _stamps = [];
  final List<Object> _history = [];
  _Stroke? _live;
  _Stamp? _selected;

  static const _colors = [
    Color(0xFF0F172A),
    Color(0xFF1D4ED8),
    Color(0xFFDC2626),
    Color(0xFF059669),
    Color(0xFFF59E0B),
  ];

  @override
  void initState() {
    super.initState();
    _load();
  }

  Future<void> _load() async {
    final store = context.read<LibraryStore>();
    final bytes = await store.processedFile(widget.doc, widget.page).readAsBytes();
    final frame = await (await ui.instantiateImageCodec(bytes)).getNextFrame();
    if (mounted) setState(() => _image = frame.image);
  }

  Future<ui.Image> _decode(String path) async {
    final frame = await (await ui.instantiateImageCodec(await File(path).readAsBytes())).getNextFrame();
    return frame.image;
  }

  bool get _dirty => _strokes.isNotEmpty || _stamps.isNotEmpty;

  void _addStamp(_Stamp s) {
    setState(() {
      _stamps.add(s);
      _history.add(s);
      _selected = s;
      _tool = _Tool.move;
    });
  }

  Future<void> _addText({String? preset}) async {
    final text = preset ?? await promptText(context, title: 'Add text', hint: 'Type text', action: 'Add');
    if (text == null || text.trim().isEmpty) return;
    _addStamp(_Stamp(_StampKind.text, text: text.trim(), center: const Offset(0.5, 0.45), color: _color));
  }

  Future<void> _addSignature() async {
    final store = context.read<LibraryStore>();
    final settings = context.read<SettingsStore>();
    String? path;
    final saved = settings.savedSignature == null ? null : File(p.join(store.root.path, settings.savedSignature!));
    if (saved != null && await saved.exists() && mounted) {
      final choice = await showGlassSheet<String>(
        context,
        builder: (ctx) {
          final g = Glass.of(ctx);
          return Padding(
            padding: const EdgeInsets.fromLTRB(16, 14, 16, 16),
            child: Column(
              mainAxisSize: MainAxisSize.min,
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Text('Signature', style: TextStyle(fontSize: 19, fontWeight: FontWeight.w800, color: g.text)),
                const SizedBox(height: 12),
                GlassPanel(
                  onTap: () => Navigator.pop(ctx, 'saved'),
                  color: Colors.white,
                  padding: const EdgeInsets.all(16),
                  child: SizedBox(height: 80, child: Center(child: Image.file(saved))),
                ),
                const SizedBox(height: 8),
                GlassTile(
                  icon: PhosphorIconsRegular.signature,
                  title: 'Use saved signature',
                  onTap: () => Navigator.pop(ctx, 'saved'),
                ),
                GlassTile(
                  icon: PhosphorIconsRegular.pencilLine,
                  title: 'Draw a new signature',
                  onTap: () => Navigator.pop(ctx, 'new'),
                ),
              ],
            ),
          );
        },
      );
      if (choice == null) return;
      if (choice == 'saved') path = saved.path;
    }
    if (path == null && mounted) {
      path = await Navigator.of(context).push<String>(MaterialPageRoute(builder: (_) => const SignaturePadScreen()));
    }
    if (path == null) return;
    final img = await _decode(path);
    _addStamp(_Stamp(_StampKind.signature, center: const Offset(0.7, 0.85), color: _color, image: img));
  }

  void _undo() {
    if (_history.isEmpty) return;
    setState(() {
      final last = _history.removeLast();
      _strokes.remove(last);
      _stamps.remove(last);
      if (_selected == last) _selected = null;
    });
  }

  Future<void> _save() async {
    final image = _image;
    if (image == null) return;
    if (!_dirty) {
      Navigator.pop(context);
      return;
    }
    final store = context.read<LibraryStore>();
    final ok = await runBusy(context, 'Saving markup…', (_) async {
      final w = image.width.toDouble(), h = image.height.toDouble();
      final rec = ui.PictureRecorder();
      final canvas = Canvas(rec);
      canvas.drawImage(image, Offset.zero, Paint());
      _paintStrokes(canvas, Size(w, h), _strokes);
      for (final s in _stamps) {
        _paintStamp(canvas, Size(w, h), s);
      }
      final out = await rec.endRecording().toImage(image.width, image.height);
      final data = await out.toByteData(format: ui.ImageByteFormat.png);
      final dir = await store.scratch('markup');
      final file = File(p.join(dir.path, 'page.png'));
      await file.writeAsBytes(data!.buffer.asUint8List(), flush: true);
      await store.replacePageImage(widget.doc, widget.page, file.path);
      return true;
    });
    if (ok == true && mounted) {
      toast(context, 'Markup saved');
      Navigator.pop(context);
    }
  }

  Future<bool> _confirmLeave() async {
    if (!_dirty) return true;
    return confirm(context, title: 'Discard markup?', message: 'Your changes on this page will be lost.', action: 'Discard');
  }

  @override
  Widget build(BuildContext context) {
    final g = Glass.of(context);
    return PopScope(
      canPop: !_dirty,
      onPopInvokedWithResult: (didPop, _) async {
        if (didPop) return;
        if (await _confirmLeave() && context.mounted) Navigator.of(context).pop();
      },
      child: Scaffold(
        body: GlassBackground(
          child: SafeArea(
            bottom: false,
            child: Column(
              children: [
                GlassTopBar(
                  title: 'Fill & Sign',
                  subtitle: 'Markup is merged into the page',
                  actions: [
                    GlassIconButton(
                      icon: PhosphorIconsRegular.arrowCounterClockwise,
                      tooltip: 'Undo',
                      onTap: _history.isEmpty ? null : _undo,
                    ),
                    GradientButton(label: 'Save', onTap: _image == null ? null : _save, height: 44),
                  ],
                ),
                Expanded(
                  child: _image == null
                      ? const Center(child: CircularProgressIndicator())
                      : LayoutBuilder(builder: (_, c) => _canvas(c)),
                ),
                AnimatedSize(
                  duration: const Duration(milliseconds: 200),
                  curve: Curves.easeOut,
                  child: _selected != null ? _stampBar(g) : _styleBar(g),
                ),
                _toolBar(g),
              ],
            ),
          ),
        ),
      ),
    );
  }

  Widget _canvas(BoxConstraints c) {
    final image = _image!;
    final avail = Size(c.maxWidth - 32, c.maxHeight - 24);
    final scale = math.min(avail.width / image.width, avail.height / image.height);
    final size = Size(image.width * scale, image.height * scale);
    final drawing = _tool != _Tool.move;

    Offset norm(Offset local) => Offset(local.dx / size.width, local.dy / size.height);

    return Center(
      child: SizedBox(
        width: size.width,
        height: size.height,
        child: GestureDetector(
          onTap: () => setState(() => _selected = null),
          onPanStart: drawing
              ? (d) => setState(() {
                    _selected = null;
                    _live = _Stroke(
                      [norm(d.localPosition)],
                      _tool == _Tool.highlighter ? const Color(0xFFFDE047) : _color,
                      _tool == _Tool.highlighter ? 0.028 : _penWidth,
                      _tool == _Tool.highlighter,
                    );
                  })
              : null,
          onPanUpdate: drawing ? (d) => setState(() => _live?.pts.add(norm(d.localPosition))) : null,
          onPanEnd: drawing
              ? (_) => setState(() {
                    if (_live != null) {
                      _strokes.add(_live!);
                      _history.add(_live!);
                    }
                    _live = null;
                  })
              : null,
          child: Stack(
            clipBehavior: Clip.none,
            children: [
              Positioned.fill(
                child: DecoratedBox(
                  decoration: BoxDecoration(
                    boxShadow: [BoxShadow(color: Colors.black.withValues(alpha: 0.25), blurRadius: 20)],
                  ),
                  child: RawImage(image: image, fit: BoxFit.fill),
                ),
              ),
              Positioned.fill(
                child: RepaintBoundary(
                  child: CustomPaint(painter: _StrokePainter([..._strokes, ?_live])),
                ),
              ),
              for (final s in _stamps) _stampWidget(s, size),
            ],
          ),
        ),
      ),
    );
  }

  Widget _stampWidget(_Stamp s, Size size) {
    final g = Glass.of(context);
    final selected = s == _selected;
    Widget child;
    switch (s.kind) {
      case _StampKind.text:
        child = Text(s.text,
            style: TextStyle(
              color: s.color,
              fontSize: size.width * _fontFraction * s.scale,
              fontWeight: FontWeight.w600,
              height: 1.15,
            ));
      case _StampKind.signature:
        final w = size.width * s.baseWidth * s.scale;
        child = SizedBox(
          width: w,
          height: w * s.image!.height / s.image!.width,
          child: RawImage(image: s.image, fit: BoxFit.contain),
        );
      case _StampKind.check:
      case _StampKind.cross:
        final w = size.width * s.baseWidth * s.scale;
        child = SizedBox(
          width: w,
          height: w,
          child: CustomPaint(painter: _MarkPainter(s.kind == _StampKind.check, s.color)),
        );
    }
    return Positioned(
      left: s.center.dx * size.width,
      top: s.center.dy * size.height,
      child: FractionalTranslation(
        translation: const Offset(-0.5, -0.5),
        child: GestureDetector(
          onTap: () => setState(() => _selected = s),
          onPanStart: (_) => setState(() => _selected = s),
          onPanUpdate: (d) => setState(() {
            s.center = Offset(
              (s.center.dx + d.delta.dx / size.width).clamp(0.0, 1.0),
              (s.center.dy + d.delta.dy / size.height).clamp(0.0, 1.0),
            );
          }),
          onDoubleTap: s.kind == _StampKind.text
              ? () async {
                  final t = await promptText(context, title: 'Edit text', initial: s.text);
                  if (t != null && t.trim().isNotEmpty) setState(() => s.text = t.trim());
                }
              : null,
          child: Container(
            padding: const EdgeInsets.all(4),
            decoration: BoxDecoration(
              border: Border.all(color: selected ? g.accent.primary : Colors.transparent, width: 1.5),
              borderRadius: BorderRadius.circular(6),
              color: selected ? g.accent.primary.withValues(alpha: 0.06) : null,
            ),
            child: child,
          ),
        ),
      ),
    );
  }

  Widget _styleBar(Glass g) {
    return Padding(
      key: const ValueKey('style'),
      padding: const EdgeInsets.fromLTRB(16, 6, 16, 6),
      child: Row(
        children: [
          for (final c in _colors)
            Padding(
              padding: const EdgeInsets.only(right: 10),
              child: Semantics(
                button: true,
                label: 'Colour',
                selected: c == _color,
                child: Pressable(
                  onTap: () => setState(() => _color = c),
                  child: AnimatedContainer(
                    duration: const Duration(milliseconds: 150),
                    width: 30,
                    height: 30,
                    decoration: BoxDecoration(
                      color: c,
                      shape: BoxShape.circle,
                      border: Border.all(color: c == _color ? g.text : g.border, width: c == _color ? 3 : 1),
                    ),
                  ),
                ),
              ),
            ),
          const Spacer(),
          if (_tool == _Tool.pen)
            SizedBox(
              width: 120,
              child: Slider(
                value: _penWidth,
                min: 0.002,
                max: 0.016,
                onChanged: (v) => setState(() => _penWidth = v),
              ),
            ),
        ],
      ),
    );
  }

  Widget _stampBar(Glass g) {
    final s = _selected!;
    return Padding(
      key: const ValueKey('stamp'),
      padding: const EdgeInsets.fromLTRB(16, 4, 16, 4),
      child: Row(
        children: [
          Text('Selected', style: TextStyle(color: g.muted, fontWeight: FontWeight.w600)),
          const Spacer(),
          IconButton(
            tooltip: 'Smaller',
            onPressed: () => setState(() => s.scale = (s.scale / 1.15).clamp(0.3, 6.0)),
            icon: PhosphorIcon(PhosphorIconsRegular.minusCircle, color: g.text),
          ),
          IconButton(
            tooltip: 'Bigger',
            onPressed: () => setState(() => s.scale = (s.scale * 1.15).clamp(0.3, 6.0)),
            icon: PhosphorIcon(PhosphorIconsRegular.plusCircle, color: g.text),
          ),
          if (s.kind != _StampKind.signature)
            IconButton(
              tooltip: 'Use current colour',
              onPressed: () => setState(() => s.color = _color),
              icon: PhosphorIcon(PhosphorIconsRegular.paintBucket, color: _color),
            ),
          if (s.kind == _StampKind.text)
            IconButton(
              tooltip: 'Edit text',
              onPressed: () async {
                final t = await promptText(context, title: 'Edit text', initial: s.text);
                if (t != null && t.trim().isNotEmpty) setState(() => s.text = t.trim());
              },
              icon: PhosphorIcon(PhosphorIconsRegular.pencilSimpleLine, color: g.text),
            ),
          IconButton(
            tooltip: 'Remove',
            onPressed: () => setState(() {
              _stamps.remove(s);
              _history.remove(s);
              _selected = null;
            }),
            icon: PhosphorIcon(PhosphorIconsRegular.trash, color: g.danger),
          ),
        ],
      ),
    );
  }

  Widget _toolBar(Glass g) {
    final bottom = MediaQuery.of(context).padding.bottom;
    Widget tool(IconData icon, String label, VoidCallback onTap, {bool active = false}) {
      final c = active ? g.accent.primary : g.text;
      return Semantics(
        button: true,
        label: label,
        selected: active,
        child: Pressable(
          onTap: onTap,
          scale: 0.9,
          child: SizedBox(
            width: 64,
            child: Column(
              mainAxisSize: MainAxisSize.min,
              children: [
                AnimatedContainer(
                  duration: const Duration(milliseconds: 160),
                  padding: const EdgeInsets.all(8),
                  decoration: BoxDecoration(
                    color: active ? g.accent.primary.withValues(alpha: 0.16) : Colors.transparent,
                    borderRadius: BorderRadius.circular(12),
                  ),
                  child: AppIcon(icon, size: 23, color: c),
                ),
                const SizedBox(height: 2),
                Text(label, style: TextStyle(fontSize: 11, fontWeight: FontWeight.w600, color: c)),
              ],
            ),
          ),
        ),
      );
    }

    return GlassPanel(
      blur: true,
      radius: 0,
      borderOverride: Border(top: BorderSide(color: g.border)),
      padding: EdgeInsets.fromLTRB(0, 10, 0, bottom + 10),
      child: SingleChildScrollView(
        scrollDirection: Axis.horizontal,
        padding: const EdgeInsets.symmetric(horizontal: 8),
        child: Row(
          children: [
            tool(PhosphorIconsRegular.handGrabbing, 'Move', () => setState(() => _tool = _Tool.move),
                active: _tool == _Tool.move),
            tool(PhosphorIconsRegular.pen, 'Pen', () => setState(() => _tool = _Tool.pen), active: _tool == _Tool.pen),
            tool(PhosphorIconsRegular.highlighter, 'Highlight', () => setState(() => _tool = _Tool.highlighter),
                active: _tool == _Tool.highlighter),
            tool(PhosphorIconsRegular.signature, 'Sign', _addSignature),
            tool(PhosphorIconsRegular.textT, 'Text', _addText),
            tool(PhosphorIconsRegular.calendarCheck, 'Date',
                () => _addText(preset: DateFormat('d MMM yyyy').format(DateTime.now()))),
            tool(PhosphorIconsRegular.checkSquare, 'Tick',
                () => _addStamp(_Stamp(_StampKind.check, center: const Offset(0.5, 0.5), color: _color))),
            tool(PhosphorIconsRegular.xSquare, 'Cross',
                () => _addStamp(_Stamp(_StampKind.cross, center: const Offset(0.5, 0.5), color: _color))),
          ],
        ),
      ),
    );
  }

  // ---------------------------------------------------------------- export

  void _paintStrokes(Canvas canvas, Size size, List<_Stroke> strokes) {
    for (final s in strokes) {
      final paint = Paint()
        ..color = s.highlight ? s.color.withValues(alpha: 0.38) : s.color
        ..strokeWidth = s.width * size.width
        ..strokeCap = s.highlight ? StrokeCap.square : StrokeCap.round
        ..strokeJoin = StrokeJoin.round
        ..style = PaintingStyle.stroke;
      canvas.drawPath(smoothPath(s.pts.map((o) => Offset(o.dx * size.width, o.dy * size.height)).toList()), paint);
    }
  }

  void _paintStamp(Canvas canvas, Size size, _Stamp s) {
    final c = Offset(s.center.dx * size.width, s.center.dy * size.height);
    switch (s.kind) {
      case _StampKind.text:
        final tp = TextPainter(
          text: TextSpan(
            text: s.text,
            style: TextStyle(
              color: s.color,
              fontSize: size.width * _fontFraction * s.scale,
              fontWeight: FontWeight.w600,
              height: 1.15,
            ),
          ),
          textDirection: ui.TextDirection.ltr,
        )..layout();
        tp.paint(canvas, c - Offset(tp.width / 2, tp.height / 2));
      case _StampKind.signature:
        final w = size.width * s.baseWidth * s.scale;
        final h = w * s.image!.height / s.image!.width;
        canvas.drawImageRect(
          s.image!,
          Rect.fromLTWH(0, 0, s.image!.width.toDouble(), s.image!.height.toDouble()),
          Rect.fromCenter(center: c, width: w, height: h),
          Paint()..filterQuality = FilterQuality.high,
        );
      case _StampKind.check:
      case _StampKind.cross:
        final w = size.width * s.baseWidth * s.scale;
        canvas.save();
        canvas.translate(c.dx - w / 2, c.dy - w / 2);
        _MarkPainter(s.kind == _StampKind.check, s.color).paint(canvas, Size(w, w));
        canvas.restore();
    }
  }
}

class _StrokePainter extends CustomPainter {
  final List<_Stroke> strokes;
  _StrokePainter(this.strokes);

  @override
  void paint(Canvas canvas, Size size) {
    for (final s in strokes) {
      final paint = Paint()
        ..color = s.highlight ? s.color.withValues(alpha: 0.38) : s.color
        ..strokeWidth = s.width * size.width
        ..strokeCap = s.highlight ? StrokeCap.square : StrokeCap.round
        ..strokeJoin = StrokeJoin.round
        ..style = PaintingStyle.stroke;
      canvas.drawPath(smoothPath(s.pts.map((o) => Offset(o.dx * size.width, o.dy * size.height)).toList()), paint);
    }
  }

  @override
  bool shouldRepaint(_StrokePainter old) => true;
}

class _MarkPainter extends CustomPainter {
  final bool check;
  final Color color;
  _MarkPainter(this.check, this.color);

  @override
  void paint(Canvas canvas, Size size) {
    final paint = Paint()
      ..color = color
      ..strokeWidth = size.width * 0.13
      ..strokeCap = StrokeCap.round
      ..strokeJoin = StrokeJoin.round
      ..style = PaintingStyle.stroke;
    final w = size.width, h = size.height;
    if (check) {
      canvas.drawPath(
        Path()
          ..moveTo(w * 0.15, h * 0.55)
          ..lineTo(w * 0.42, h * 0.8)
          ..lineTo(w * 0.88, h * 0.22),
        paint,
      );
    } else {
      canvas.drawLine(Offset(w * 0.2, h * 0.2), Offset(w * 0.8, h * 0.8), paint);
      canvas.drawLine(Offset(w * 0.8, h * 0.2), Offset(w * 0.2, h * 0.8), paint);
    }
  }

  @override
  bool shouldRepaint(_MarkPainter old) => old.check != check || old.color != color;
}

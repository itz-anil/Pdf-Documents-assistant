import 'dart:io';

import 'package:flutter/material.dart';
import 'package:path/path.dart' as p;
import 'package:provider/provider.dart';

import '../app/icons.dart';
import '../app/theme.dart';
import '../core/image_processing.dart';
import '../core/library_store.dart';
import '../core/settings.dart';
import '../widgets/glass.dart';
import 'camera_screen.dart';
import 'crop_screen.dart';

/// Review both sides of an ID card, fix each one, and lay them out on a
/// single A4 page. Returns the path of the composed page image.
class IdCardScreen extends StatefulWidget {
  final Shot front;
  final Shot? back;
  const IdCardScreen({super.key, required this.front, this.back});

  @override
  State<IdCardScreen> createState() => _IdCardScreenState();
}

class _IdCardScreenState extends State<IdCardScreen> {
  late Shot _front = widget.front;
  late Shot? _back = widget.back;
  late IdCardSize _size = context.read<SettingsStore>().idCardSize;
  Directory? _work;
  String? _page;
  final Map<Shot, String> _sidePreview = {};
  int _rev = 0;
  bool _rendering = false;

  @override
  void initState() {
    super.initState();
    _render();
  }

  IdSide _side(Shot s) => IdSide(s.path, s.quad, s.quarterTurns);

  Future<void> _render() async {
    final rev = ++_rev;
    setState(() => _rendering = true);
    _work ??= await context.read<LibraryStore>().scratch('idcard');
    final dir = _work!;
    for (final s in [_front, ?_back]) {
      final out = p.join(dir.path, 'side_${s.hashCode}_${s.quad.hashCode}_${s.quarterTurns}.jpg');
      if (!File(out).existsSync()) await renderIdSide(_side(s), out);
      _sidePreview[s] = out;
    }
    final out = p.join(dir.path, 'page_$rev.jpg');
    await composeIdCard(_side(_front), _back == null ? null : _side(_back!), out, size: _size);
    if (!mounted || rev != _rev) return;
    setState(() {
      _page = out;
      _rendering = false;
    });
  }

  Future<void> _adjust(Shot s) async {
    final r = await CropScreen.open(context, s.path, s.quad, s.quarterTurns,
        title: s == _front ? 'Front side' : 'Back side');
    if (r == null) return;
    s
      ..quad = r.quad
      ..quarterTurns = r.quarterTurns;
    _render();
  }

  void _rotate(Shot s) {
    s.quarterTurns = (s.quarterTurns + 1) % 4;
    _render();
  }

  Future<void> _retake(bool front) async {
    final r = await CameraScreen.open(
      context,
      mode: CameraMode.idCard,
      lockMode: true,
      maxShots: 1,
      purpose: front ? 'Front side' : 'Back side',
    );
    if (r == null || r.shots.isEmpty) return;
    setState(() => front ? _front = r.shots.first : _back = r.shots.first);
    _render();
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
                title: 'ID card',
                subtitle: _back == null ? 'Front side on one page' : 'Front and back on one page',
              ),
              Expanded(
                child: ListView(
                  padding: const EdgeInsets.fromLTRB(16, 4, 16, 16),
                  children: [
                    Center(
                      child: SizedBox(
                        height: 420,
                        child: AspectRatio(
                        aspectRatio: 2480 / 3508,
                        child: Container(
                          decoration: BoxDecoration(
                            color: Colors.white,
                            borderRadius: BorderRadius.circular(6),
                            boxShadow: [BoxShadow(color: Colors.black.withValues(alpha: 0.3), blurRadius: 24, offset: const Offset(0, 10))],
                          ),
                          clipBehavior: Clip.antiAlias,
                          child: Stack(
                            fit: StackFit.expand,
                            children: [
                              if (_page != null)
                                Image.file(File(_page!), key: ValueKey(_page), fit: BoxFit.contain, gaplessPlayback: true),
                              if (_rendering)
                                Center(child: CircularProgressIndicator(color: g.accent.primary, strokeWidth: 3)),
                            ],
                          ),
                        ),
                      ),
                      ),
                    ),
                    const SizedBox(height: 18),
                    _SegmentRow(
                      value: _size,
                      onChanged: (v) {
                        setState(() => _size = v);
                        context.read<SettingsStore>().setIdCardSize = v;
                        _render();
                      },
                    ),
                    const SizedBox(height: 8),
                    Text(_size.hint, textAlign: TextAlign.center, style: TextStyle(color: g.muted, fontSize: 12.5)),
                    const SectionLabel('Sides'),
                    _SideTile(
                      label: 'Front',
                      preview: _sidePreview[_front],
                      onAdjust: () => _adjust(_front),
                      onRotate: () => _rotate(_front),
                      onRetake: () => _retake(true),
                    ),
                    const SizedBox(height: 10),
                    if (_back != null)
                      _SideTile(
                        label: 'Back',
                        preview: _sidePreview[_back],
                        onAdjust: () => _adjust(_back!),
                        onRotate: () => _rotate(_back!),
                        onRetake: () => _retake(false),
                        onRemove: () {
                          setState(() => _back = null);
                          _render();
                        },
                      )
                    else
                      GlassPanel(
                        radius: 18,
                        padding: const EdgeInsets.all(14),
                        onTap: () => _retake(false),
                        child: Row(
                          children: [
                            IconBadge(PhosphorIconsDuotone.plusCircle, size: 44),
                            const SizedBox(width: 14),
                            Expanded(
                              child: Text('Add back side',
                                  style: TextStyle(fontWeight: FontWeight.w700, color: g.text, fontSize: 15)),
                            ),
                          ],
                        ),
                      ),
                  ],
                ),
              ),
              Padding(
                padding: const EdgeInsets.fromLTRB(16, 4, 16, 16),
                child: GradientButton(
                  label: 'Save ID card',
                  icon: PhosphorIconsBold.check,
                  expand: true,
                  onTap: _page == null || _rendering ? null : () => Navigator.pop(context, _page),
                ),
              ),
            ],
          ),
        ),
      ),
    );
  }
}

class _SegmentRow extends StatelessWidget {
  final IdCardSize value;
  final ValueChanged<IdCardSize> onChanged;
  const _SegmentRow({required this.value, required this.onChanged});

  @override
  Widget build(BuildContext context) {
    final g = Glass.of(context);
    return Container(
      padding: const EdgeInsets.all(4),
      decoration: BoxDecoration(color: g.faint, borderRadius: BorderRadius.circular(14)),
      child: Row(
        children: [
          for (final s in IdCardSize.values)
            Expanded(
              child: Semantics(
                button: true,
                selected: s == value,
                child: Pressable(
                  onTap: () => onChanged(s),
                  child: AnimatedContainer(
                    duration: const Duration(milliseconds: 180),
                    height: 40,
                    alignment: Alignment.center,
                    decoration: BoxDecoration(
                      color: s == value ? g.fillStrong : Colors.transparent,
                      borderRadius: BorderRadius.circular(11),
                      border: Border.all(color: s == value ? g.border : Colors.transparent),
                    ),
                    child: Text(s.label,
                        style: TextStyle(
                          fontWeight: FontWeight.w700,
                          color: s == value ? g.text : g.muted,
                        )),
                  ),
                ),
              ),
            ),
        ],
      ),
    );
  }
}

class _SideTile extends StatelessWidget {
  final String label;
  final String? preview;
  final VoidCallback onAdjust;
  final VoidCallback onRotate;
  final VoidCallback onRetake;
  final VoidCallback? onRemove;
  const _SideTile({
    required this.label,
    required this.preview,
    required this.onAdjust,
    required this.onRotate,
    required this.onRetake,
    this.onRemove,
  });

  @override
  Widget build(BuildContext context) {
    final g = Glass.of(context);
    Widget action(IconData icon, String tip, VoidCallback onTap) => IconButton(
          tooltip: tip,
          onPressed: onTap,
          icon: PhosphorIcon(icon, color: g.text, size: 22),
        );
    return GlassPanel(
      radius: 18,
      padding: const EdgeInsets.fromLTRB(10, 10, 4, 10),
      child: Row(
        children: [
          Container(
            width: 92,
            height: 58,
            decoration: BoxDecoration(color: g.faint, borderRadius: BorderRadius.circular(8)),
            clipBehavior: Clip.antiAlias,
            child: preview == null
                ? null
                : Image.file(File(preview!), key: ValueKey(preview), fit: BoxFit.cover, cacheWidth: 300, gaplessPlayback: true),
          ),
          const SizedBox(width: 12),
          Expanded(child: Text(label, style: TextStyle(fontWeight: FontWeight.w700, color: g.text, fontSize: 15))),
          action(PhosphorIconsRegular.crop, 'Adjust corners', onAdjust),
          action(PhosphorIconsRegular.arrowClockwise, 'Rotate', onRotate),
          action(PhosphorIconsRegular.camera, 'Retake', onRetake),
          if (onRemove != null) action(PhosphorIconsRegular.trash, 'Remove back side', onRemove!),
        ],
      ),
    );
  }
}

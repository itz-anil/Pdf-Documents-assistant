import 'dart:io';
import 'dart:typed_data';

import 'package:flutter/material.dart';
import '../app/icons.dart';
import 'package:provider/provider.dart';

import '../app/theme.dart';
import '../core/image_processing.dart';
import '../core/library_store.dart';
import '../core/models.dart';
import '../widgets/common.dart';
import '../widgets/glass.dart';
import 'annotate_screen.dart';
import 'crop_screen.dart';
import 'document_screen.dart';
import 'scan_flow.dart';

enum _Panel { none, filters, adjust }

/// Review & edit pages: filters, crop, rotate, adjust, markup, reorder.
class EditorScreen extends StatefulWidget {
  final DocItem doc;
  final bool isNew;
  final int initialPage;
  const EditorScreen({super.key, required this.doc, this.isNew = false, this.initialPage = 0});

  @override
  State<EditorScreen> createState() => _EditorScreenState();
}

class _EditorScreenState extends State<EditorScreen> {
  late final PageController _pager;
  late int _current;
  _Panel _panel = _Panel.filters;
  final Map<String, List<Uint8List>> _previews = {};
  final Set<String> _loadingPreviews = {};
  double? _brightness;
  double? _contrast;

  DocItem get doc => widget.doc;
  PageItem get page => doc.pages[_current.clamp(0, doc.pages.length - 1)];

  @override
  void initState() {
    super.initState();
    _current = widget.initialPage.clamp(0, doc.pages.length - 1);
    _pager = PageController(initialPage: _current);
  }

  @override
  void dispose() {
    _pager.dispose();
    super.dispose();
  }

  String _previewKey(PageItem p) => '${p.id}|${p.base}|${p.quarterTurns}';

  void _ensurePreviews(LibraryStore store) {
    if (doc.pages.isEmpty) return;
    final p = page;
    final key = _previewKey(p);
    if (_previews.containsKey(key) || _loadingPreviews.contains(key)) return;
    _loadingPreviews.add(key);
    filterPreviews(store.baseFile(doc, p).path, p.quarterTurns).then((list) {
      if (!mounted) return;
      setState(() {
        _previews[key] = list;
        _loadingPreviews.remove(key);
      });
    }).catchError((Object _) {
      _loadingPreviews.remove(key);
    });
  }

  void _goTo(int i) {
    _pager.animateToPage(i, duration: const Duration(milliseconds: 280), curve: Curves.easeOutCubic);
  }

  Future<void> _done() async {
    if (widget.isNew) {
      await Navigator.of(context).pushReplacement(MaterialPageRoute(builder: (_) => DocumentScreen(doc: doc)));
    } else {
      Navigator.of(context).pop();
    }
  }

  Future<void> _edit(Future<void> Function(LibraryStore store) action) async {
    final store = context.read<LibraryStore>();
    try {
      await action(store);
    } catch (e) {
      if (mounted) toast(context, friendlyError(e), error: true);
    }
  }

  @override
  Widget build(BuildContext context) {
    final store = context.watch<LibraryStore>();
    final g = Glass.of(context);
    if (!store.docs.contains(doc) || doc.pages.isEmpty) {
      WidgetsBinding.instance.addPostFrameCallback((_) {
        if (mounted) Navigator.of(context).maybePop();
      });
      return const Scaffold();
    }
    if (_current >= doc.pages.length) _current = doc.pages.length - 1;
    if (_panel == _Panel.filters) _ensurePreviews(store);
    final busy = store.busyPages.contains(page.id);

    return Scaffold(
      body: GlassBackground(
        child: SafeArea(
          bottom: false,
          child: Column(
            children: [
              GlassTopBar(
                title: doc.name,
                subtitle: 'Page ${_current + 1} of ${doc.pages.length}',
                onBack: _done,
                actions: [
                  GlassIconButton(
                    icon: PhosphorIconsRegular.pencilSimpleLine,
                    tooltip: 'Rename',
                    onTap: () async {
                      final n = await promptText(context, title: 'Rename document', initial: doc.name);
                      if (n != null && n.trim().isNotEmpty) store.rename(doc, n);
                    },
                  ),
                  GradientButton(label: 'Done', onTap: _done, height: 44),
                ],
              ),
              Expanded(
                child: PageView.builder(
                  controller: _pager,
                  itemCount: doc.pages.length,
                  onPageChanged: (i) => setState(() {
                    _current = i;
                    _brightness = null;
                    _contrast = null;
                  }),
                  itemBuilder: (_, i) {
                    final pg = doc.pages[i];
                    final pageBusy = store.busyPages.contains(pg.id);
                    return Padding(
                      padding: const EdgeInsets.fromLTRB(24, 8, 24, 12),
                      child: Center(
                        child: Stack(
                          alignment: Alignment.center,
                          children: [
                            Container(
                              decoration: BoxDecoration(
                                boxShadow: [
                                  BoxShadow(
                                    color: Colors.black.withValues(alpha: 0.25),
                                    blurRadius: 24,
                                    offset: const Offset(0, 10),
                                  ),
                                ],
                              ),
                              child: Image.file(
                                File(store.processedFile(doc, pg).path),
                                key: ValueKey(pg.processed),
                                fit: BoxFit.contain,
                                gaplessPlayback: true,
                                cacheWidth: 1400,
                                errorBuilder: (_, _, _) => const SizedBox(width: 200, height: 280),
                              ),
                            ),
                            AnimatedOpacity(
                              opacity: pageBusy ? 1 : 0,
                              duration: const Duration(milliseconds: 160),
                              child: IgnorePointer(
                                child: GlassPanel(
                                  blur: true,
                                  radius: 18,
                                  padding: const EdgeInsets.all(16),
                                  child: SizedBox(
                                    width: 28,
                                    height: 28,
                                    child: CircularProgressIndicator(strokeWidth: 3, color: g.accent.primary),
                                  ),
                                ),
                              ),
                            ),
                          ],
                        ),
                      ),
                    );
                  },
                ),
              ),
              _ThumbStrip(
                store: store,
                doc: doc,
                current: _current,
                onTap: _goTo,
                onAdd: () => ScanFlow.addPages(context, doc),
                onReorder: (a, b) {
                  final currentId = page.id;
                  store.reorderPage(doc, a, b);
                  final ni = doc.pages.indexWhere((p) => p.id == currentId);
                  setState(() => _current = ni);
                  _pager.jumpToPage(ni);
                },
              ),
              AnimatedSize(
                duration: const Duration(milliseconds: 220),
                curve: Curves.easeOutCubic,
                child: AnimatedSwitcher(
                  duration: const Duration(milliseconds: 180),
                  child: switch (_panel) {
                    _Panel.filters => _FilterStrip(
                        key: const ValueKey('filters'),
                        current: page.filter,
                        previews: _previews[_previewKey(page)],
                        enabled: !busy,
                        onPick: (f) => _edit((s) => s.editPage(doc, page, filter: f)),
                        onApplyAll: () => _edit((s) async {
                          await runBusy(context, 'Applying to all pages…', (_) => s.applyFilterToAll(doc, page.filter));
                        }),
                      ),
                    _Panel.adjust => _AdjustPanel(
                        key: ValueKey('adjust${page.id}'),
                        brightness: _brightness ?? page.brightness,
                        contrast: _contrast ?? page.contrast,
                        onBrightness: (v) => setState(() => _brightness = v),
                        onContrast: (v) => setState(() => _contrast = v),
                        onCommit: () => _edit((s) => s.editPage(doc, page,
                            brightness: _brightness ?? page.brightness, contrast: _contrast ?? page.contrast)),
                        onReset: () {
                          setState(() {
                            _brightness = 0;
                            _contrast = 1;
                          });
                          _edit((s) => s.editPage(doc, page, brightness: 0, contrast: 1));
                        },
                      ),
                    _Panel.none => const SizedBox(key: ValueKey('none'), width: double.infinity),
                  },
                ),
              ),
              _ToolBar(
                panel: _panel,
                busy: busy,
                onFilters: () => setState(() => _panel = _panel == _Panel.filters ? _Panel.none : _Panel.filters),
                onAdjust: () => setState(() => _panel = _panel == _Panel.adjust ? _Panel.none : _Panel.adjust),
                onCrop: () async {
                  final pg = page;
                  final r = await CropScreen.open(context, store.originalFile(doc, pg).path, pg.quad, pg.quarterTurns);
                  if (r == null) return;
                  await _edit((s) => r.quad == null
                      ? s.editPage(doc, pg, clearQuad: true, quarterTurns: r.quarterTurns)
                      : s.editPage(doc, pg, quad: r.quad, quarterTurns: r.quarterTurns));
                },
                onRetake: () => ScanFlow.retakePage(context, doc, page),
                onRotate: () => _edit((s) => s.editPage(doc, page, quarterTurns: page.quarterTurns + 1)),
                onMarkup: () => Navigator.of(context)
                    .push(MaterialPageRoute(builder: (_) => AnnotateScreen(doc: doc, page: page))),
                onDuplicate: () => _edit((s) async {
                  await runBusy(context, 'Duplicating page…', (_) => s.duplicatePage(doc, page));
                }),
                onDelete: () async {
                  final ok = await confirm(
                    context,
                    title: 'Delete page?',
                    message: doc.pages.length == 1
                        ? 'This is the only page — the whole document will be deleted.'
                        : 'Page ${_current + 1} will be removed.',
                  );
                  if (ok) await _edit((s) => s.deletePage(doc, page));
                },
              ),
            ],
          ),
        ),
      ),
    );
  }
}

class _ThumbStrip extends StatelessWidget {
  final LibraryStore store;
  final DocItem doc;
  final int current;
  final ValueChanged<int> onTap;
  final VoidCallback onAdd;
  final void Function(int, int) onReorder;
  const _ThumbStrip({
    required this.store,
    required this.doc,
    required this.current,
    required this.onTap,
    required this.onAdd,
    required this.onReorder,
  });

  @override
  Widget build(BuildContext context) {
    final g = Glass.of(context);
    return SizedBox(
      height: 92,
      child: Row(
        children: [
          Expanded(
            child: ReorderableListView.builder(
              scrollDirection: Axis.horizontal,
              padding: const EdgeInsets.fromLTRB(16, 6, 6, 10),
              itemCount: doc.pages.length,
              onReorderItem: onReorder,
              proxyDecorator: (child, _, _) => Material(color: Colors.transparent, child: child),
              itemBuilder: (_, i) {
                final pg = doc.pages[i];
                final sel = i == current;
                return Padding(
                  key: ValueKey(pg.id),
                  padding: const EdgeInsets.only(right: 10),
                  child: Semantics(
                    button: true,
                    label: 'Page ${i + 1}',
                    selected: sel,
                    child: GestureDetector(
                      onTap: () => onTap(i),
                      child: AnimatedContainer(
                        duration: const Duration(milliseconds: 180),
                        width: 56,
                        decoration: BoxDecoration(
                          borderRadius: BorderRadius.circular(10),
                          border: Border.all(color: sel ? g.accent.primary : g.border, width: sel ? 2.5 : 1),
                        ),
                        clipBehavior: Clip.antiAlias,
                        child: Stack(
                          fit: StackFit.expand,
                          children: [
                            Image.file(
                              File(store.thumbFile(doc, pg).path),
                              key: ValueKey(pg.thumb),
                              fit: BoxFit.cover,
                              cacheWidth: 160,
                              gaplessPlayback: true,
                              errorBuilder: (_, _, _) => const SizedBox(),
                            ),
                            Positioned(
                              right: 3,
                              bottom: 3,
                              child: Container(
                                padding: const EdgeInsets.symmetric(horizontal: 5, vertical: 1),
                                decoration: BoxDecoration(
                                  color: Colors.black.withValues(alpha: 0.6),
                                  borderRadius: BorderRadius.circular(6),
                                ),
                                child: Text('${i + 1}',
                                    style: const TextStyle(color: Colors.white, fontSize: 10, fontWeight: FontWeight.w700)),
                              ),
                            ),
                          ],
                        ),
                      ),
                    ),
                  ),
                );
              },
            ),
          ),
          Padding(
            padding: const EdgeInsets.fromLTRB(0, 6, 16, 10),
            child: Semantics(
              button: true,
              label: 'Add pages',
              child: Pressable(
                onTap: onAdd,
                child: Container(
                  width: 56,
                  decoration: BoxDecoration(
                    color: g.fill,
                    borderRadius: BorderRadius.circular(10),
                    border: Border.all(color: g.accent.primary.withValues(alpha: 0.5), width: 1.5),
                  ),
                  alignment: Alignment.center,
                  child: PhosphorIcon(PhosphorIconsBold.plus, color: g.accent.primary),
                ),
              ),
            ),
          ),
        ],
      ),
    );
  }
}

class _FilterStrip extends StatelessWidget {
  final PageFilter current;
  final List<Uint8List>? previews;
  final bool enabled;
  final ValueChanged<PageFilter> onPick;
  final VoidCallback onApplyAll;
  const _FilterStrip({
    super.key,
    required this.current,
    required this.previews,
    required this.enabled,
    required this.onPick,
    required this.onApplyAll,
  });

  @override
  Widget build(BuildContext context) {
    final g = Glass.of(context);
    return Column(
      mainAxisSize: MainAxisSize.min,
      children: [
        SizedBox(
          height: 112,
          child: ListView.separated(
            scrollDirection: Axis.horizontal,
            padding: const EdgeInsets.symmetric(horizontal: 16),
            physics: const BouncingScrollPhysics(),
            itemCount: PageFilter.values.length,
            separatorBuilder: (_, _) => const SizedBox(width: 10),
            itemBuilder: (_, i) {
              final f = PageFilter.values[i];
              final sel = f == current;
              return Semantics(
                button: true,
                selected: sel,
                label: f.label,
                child: Pressable(
                  onTap: enabled && !sel ? () => onPick(f) : null,
                  child: Column(
                    children: [
                      AnimatedContainer(
                        duration: const Duration(milliseconds: 180),
                        width: 68,
                        height: 82,
                        padding: const EdgeInsets.all(3),
                        decoration: BoxDecoration(
                          borderRadius: BorderRadius.circular(14),
                          color: sel ? g.accent.primary : g.fill,
                        ),
                        child: ClipRRect(
                          borderRadius: BorderRadius.circular(11),
                          child: previews == null
                              ? Container(color: g.faint)
                              : Image.memory(previews![i], fit: BoxFit.cover, gaplessPlayback: true),
                        ),
                      ),
                      const SizedBox(height: 6),
                      Text(f.label,
                          style: TextStyle(
                            fontSize: 11.5,
                            fontWeight: sel ? FontWeight.w800 : FontWeight.w600,
                            color: sel ? g.accent.primary : g.muted,
                          )),
                    ],
                  ),
                ),
              );
            },
          ),
        ),
        Align(
          alignment: Alignment.centerRight,
          child: Padding(
            padding: const EdgeInsets.only(right: 12),
            child: TextButton.icon(
              onPressed: enabled ? onApplyAll : null,
              icon: const PhosphorIcon(PhosphorIconsRegular.copySimple, size: 18),
              label: Text('Apply “${current.label}” to all pages'),
            ),
          ),
        ),
      ],
    );
  }
}

class _AdjustPanel extends StatelessWidget {
  final double brightness;
  final double contrast;
  final ValueChanged<double> onBrightness;
  final ValueChanged<double> onContrast;
  final VoidCallback onCommit;
  final VoidCallback onReset;
  const _AdjustPanel({
    super.key,
    required this.brightness,
    required this.contrast,
    required this.onBrightness,
    required this.onContrast,
    required this.onCommit,
    required this.onReset,
  });

  @override
  Widget build(BuildContext context) {
    final g = Glass.of(context);
    Widget row(IconData icon, String label, double value, double min, double max, ValueChanged<double> onChanged) {
      return Row(
        children: [
          AppIcon(icon, size: 20, color: g.muted),
          const SizedBox(width: 10),
          SizedBox(width: 74, child: Text(label, style: TextStyle(color: g.text, fontWeight: FontWeight.w600))),
          Expanded(
            child: Slider(
              value: value.clamp(min, max),
              min: min,
              max: max,
              onChanged: onChanged,
              onChangeEnd: (_) => onCommit(),
            ),
          ),
        ],
      );
    }

    return Padding(
      padding: const EdgeInsets.fromLTRB(20, 4, 12, 4),
      child: Column(
        mainAxisSize: MainAxisSize.min,
        children: [
          row(PhosphorIconsRegular.sun, 'Brightness', brightness, -0.4, 0.4, onBrightness),
          row(PhosphorIconsRegular.circleHalf, 'Contrast', contrast, 0.6, 1.8, onContrast),
          Align(
            alignment: Alignment.centerRight,
            child: TextButton(onPressed: onReset, child: const Text('Reset')),
          ),
        ],
      ),
    );
  }
}

class _ToolBar extends StatelessWidget {
  final _Panel panel;
  final bool busy;
  final VoidCallback onFilters;
  final VoidCallback onCrop;
  final VoidCallback onRotate;
  final VoidCallback onAdjust;
  final VoidCallback onMarkup;
  final VoidCallback onDuplicate;
  final VoidCallback onRetake;
  final VoidCallback onDelete;
  const _ToolBar({
    required this.panel,
    required this.busy,
    required this.onFilters,
    required this.onCrop,
    required this.onRotate,
    required this.onAdjust,
    required this.onMarkup,
    required this.onDuplicate,
    required this.onRetake,
    required this.onDelete,
  });

  @override
  Widget build(BuildContext context) {
    final g = Glass.of(context);
    final bottom = MediaQuery.of(context).padding.bottom;
    Widget tool(IconData icon, String label, VoidCallback onTap, {bool active = false, bool danger = false}) {
      final c = danger ? g.danger : (active ? g.accent.primary : g.text);
      return Semantics(
        button: true,
        label: label,
        selected: active,
        child: Pressable(
          onTap: busy ? null : onTap,
          scale: 0.9,
          child: SizedBox(
            width: 66,
            child: Column(
              mainAxisSize: MainAxisSize.min,
              children: [
                AnimatedContainer(
                  duration: const Duration(milliseconds: 180),
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
        physics: const BouncingScrollPhysics(),
        child: Opacity(
          opacity: busy ? 0.5 : 1,
          child: Row(
            children: [
              tool(PhosphorIconsRegular.magicWand, 'Filters', onFilters, active: panel == _Panel.filters),
              tool(PhosphorIconsRegular.crop, 'Crop', onCrop),
              tool(PhosphorIconsRegular.arrowClockwise, 'Rotate', onRotate),
              tool(PhosphorIconsRegular.slidersHorizontal, 'Adjust', onAdjust, active: panel == _Panel.adjust),
              tool(PhosphorIconsRegular.signature, 'Sign', onMarkup),
              tool(PhosphorIconsRegular.camera, 'Retake', onRetake),
              tool(PhosphorIconsRegular.copy, 'Duplicate', onDuplicate),
              tool(PhosphorIconsRegular.trash, 'Delete', onDelete, danger: true),
            ],
          ),
        ),
      ),
    );
  }
}

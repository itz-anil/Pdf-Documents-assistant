import 'dart:io';

import 'package:flutter/material.dart';
import '../app/icons.dart';
import 'package:provider/provider.dart';

import '../app/theme.dart';
import '../core/library_store.dart';
import '../core/models.dart';
import '../widgets/common.dart';
import '../widgets/doc_tile.dart';
import '../widgets/glass.dart';
import 'annotate_screen.dart';
import 'doc_actions.dart';
import 'editor_screen.dart';
import 'ocr_text_screen.dart';

/// Page viewer with zoom, search highlights and the main document actions.
class DocumentScreen extends StatefulWidget {
  final DocItem doc;
  final int initialPage;
  final String? highlight;
  const DocumentScreen({super.key, required this.doc, this.initialPage = 0, this.highlight});

  @override
  State<DocumentScreen> createState() => _DocumentScreenState();
}

class _DocumentScreenState extends State<DocumentScreen> {
  late final PageController _pager;
  late int _current;
  bool _zoomed = false;

  DocItem get doc => widget.doc;

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
    final page = doc.pages[_current];

    return Scaffold(
      body: GlassBackground(
        child: SafeArea(
          bottom: false,
          child: Column(
            children: [
              GlassTopBar(
                title: doc.name,
                subtitle: docMeta(doc),
                actions: [
                  GlassIconButton(
                    icon: doc.favorite ? PhosphorIconsFill.star : PhosphorIconsDuotone.star,
                    color: doc.favorite ? const Color(0xFFF5B301) : null,
                    tooltip: doc.favorite ? 'Remove from favourites' : 'Add to favourites',
                    onTap: () {
                      haptic(context);
                      store.toggleFavorite(doc);
                    },
                  ),
                  GlassIconButton(
                    icon: PhosphorIconsBold.dotsThreeVertical,
                    tooltip: 'More options',
                    onTap: () => DocActions.moreSheet(context, doc),
                  ),
                ],
              ),
              Expanded(
                child: Stack(
                  children: [
                    PageView.builder(
                      controller: _pager,
                      physics: _zoomed ? const NeverScrollableScrollPhysics() : const PageScrollPhysics(),
                      itemCount: doc.pages.length,
                      onPageChanged: (i) => setState(() => _current = i),
                      itemBuilder: (_, i) => _ZoomPage(
                        store: store,
                        doc: doc,
                        page: doc.pages[i],
                        highlight: widget.highlight,
                        onZoomChanged: (z) {
                          if (z != _zoomed) setState(() => _zoomed = z);
                        },
                      ),
                    ),
                    Positioned(
                      left: 0,
                      right: 0,
                      bottom: 14,
                      child: Center(
                        child: GlassPanel(
                          blur: true,
                          radius: 20,
                          padding: const EdgeInsets.symmetric(horizontal: 14, vertical: 7),
                          child: Row(
                            mainAxisSize: MainAxisSize.min,
                            children: [
                              Text('${_current + 1} / ${doc.pages.length}',
                                  style: TextStyle(fontWeight: FontWeight.w700, color: g.text)),
                              if (!page.ocrDone) ...[
                                const SizedBox(width: 10),
                                SizedBox(
                                  width: 12,
                                  height: 12,
                                  child: CircularProgressIndicator(strokeWidth: 2, color: g.accent.primary),
                                ),
                                const SizedBox(width: 6),
                                Text('Reading text', style: TextStyle(fontSize: 12, color: g.muted)),
                              ],
                            ],
                          ),
                        ),
                      ),
                    ),
                  ],
                ),
              ),
              _ActionBar(
                onShare: () => DocActions.shareSheet(context, doc),
                onEdit: () => Navigator.of(context).push(MaterialPageRoute(
                  builder: (_) => EditorScreen(doc: doc, initialPage: _current),
                )),
                onSign: () => Navigator.of(context).push(MaterialPageRoute(
                  builder: (_) => AnnotateScreen(doc: doc, page: page),
                )),
                onText: () => Navigator.of(context).push(MaterialPageRoute(
                  builder: (_) => OcrTextScreen(doc: doc, initialPage: _current),
                )),
                onSave: () => DocActions.savePdf(context, doc),
              ),
            ],
          ),
        ),
      ),
    );
  }
}

class _ZoomPage extends StatefulWidget {
  final LibraryStore store;
  final DocItem doc;
  final PageItem page;
  final String? highlight;
  final ValueChanged<bool> onZoomChanged;
  const _ZoomPage({
    required this.store,
    required this.doc,
    required this.page,
    required this.highlight,
    required this.onZoomChanged,
  });

  @override
  State<_ZoomPage> createState() => _ZoomPageState();
}

class _ZoomPageState extends State<_ZoomPage> {
  final _controller = TransformationController();
  TapDownDetails? _tap;

  @override
  void initState() {
    super.initState();
    _controller.addListener(() {
      widget.onZoomChanged(_controller.value.getMaxScaleOnAxis() > 1.02);
    });
  }

  @override
  void dispose() {
    _controller.dispose();
    super.dispose();
  }

  void _toggleZoom() {
    if (_controller.value.getMaxScaleOnAxis() > 1.02) {
      _controller.value = Matrix4.identity();
    } else if (_tap != null) {
      final pos = _tap!.localPosition;
      _controller.value = Matrix4.identity()
        ..translateByDouble(-pos.dx * 1.5, -pos.dy * 1.5, 0, 1)
        ..scaleByDouble(2.5, 2.5, 1, 1);
    }
  }

  @override
  Widget build(BuildContext context) {
    final pg = widget.page;
    final q = widget.highlight?.trim().toLowerCase() ?? '';
    final hits = q.isEmpty ? <OcrLine>[] : pg.ocrLines.where((l) => l.text.toLowerCase().contains(q)).toList();
    return GestureDetector(
      onDoubleTapDown: (d) => _tap = d,
      onDoubleTap: _toggleZoom,
      child: InteractiveViewer(
        transformationController: _controller,
        minScale: 1,
        maxScale: 5,
        child: Padding(
          padding: const EdgeInsets.fromLTRB(20, 8, 20, 60),
          child: Center(
            child: AspectRatio(
              aspectRatio: pg.width > 0 && pg.height > 0 ? pg.width / pg.height : 0.707,
              child: Container(
                decoration: BoxDecoration(
                  color: Colors.white,
                  boxShadow: [
                    BoxShadow(color: Colors.black.withValues(alpha: 0.25), blurRadius: 24, offset: const Offset(0, 10)),
                  ],
                ),
                child: LayoutBuilder(
                  builder: (_, c) => Stack(
                    fit: StackFit.expand,
                    children: [
                      Image.file(
                        File(widget.store.processedFile(widget.doc, pg).path),
                        key: ValueKey(pg.processed),
                        fit: BoxFit.fill,
                        gaplessPlayback: true,
                        filterQuality: FilterQuality.medium,
                        errorBuilder: (_, _, _) => const SizedBox(),
                      ),
                      for (final h in hits)
                        Positioned(
                          left: h.l * c.maxWidth - 2,
                          top: h.t * c.maxHeight - 2,
                          width: h.w * c.maxWidth + 4,
                          height: h.h * c.maxHeight + 4,
                          child: IgnorePointer(
                            child: DecoratedBox(
                              decoration: BoxDecoration(
                                color: const Color(0xFFFDE047).withValues(alpha: 0.38),
                                borderRadius: BorderRadius.circular(3),
                              ),
                            ),
                          ),
                        ),
                    ],
                  ),
                ),
              ),
            ),
          ),
        ),
      ),
    );
  }
}

class _ActionBar extends StatelessWidget {
  final VoidCallback onShare;
  final VoidCallback onEdit;
  final VoidCallback onSign;
  final VoidCallback onText;
  final VoidCallback onSave;
  const _ActionBar({
    required this.onShare,
    required this.onEdit,
    required this.onSign,
    required this.onText,
    required this.onSave,
  });

  @override
  Widget build(BuildContext context) {
    final g = Glass.of(context);
    final bottom = MediaQuery.of(context).padding.bottom;
    Widget item(IconData icon, String label, VoidCallback onTap, {bool primary = false}) {
      return Expanded(
        child: Semantics(
          button: true,
          label: label,
          child: Pressable(
            onTap: onTap,
            scale: 0.9,
            child: Column(
              mainAxisSize: MainAxisSize.min,
              children: [
                primary
                    ? IconBadge(icon, size: 42, filled: true)
                    : SizedBox(height: 42, child: Center(child: AppIcon(icon, size: 24, color: g.text))),
                const SizedBox(height: 4),
                Text(label, style: TextStyle(fontSize: 11.5, fontWeight: FontWeight.w600, color: g.text)),
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
      padding: EdgeInsets.fromLTRB(8, 10, 8, bottom + 10),
      child: Row(
        children: [
          item(PhosphorIconsDuotone.pencilSimple, 'Edit', onEdit),
          item(PhosphorIconsDuotone.signature, 'Sign', onSign),
          item(PhosphorIconsDuotone.shareNetwork, 'Share', onShare, primary: true),
          item(PhosphorIconsDuotone.textT, 'Text', onText),
          item(PhosphorIconsDuotone.downloadSimple, 'Save', onSave),
        ],
      ),
    );
  }
}

import 'dart:io';

import 'package:flutter/material.dart';
import 'package:intl/intl.dart';
import '../app/icons.dart';

import '../app/theme.dart';
import '../core/library_store.dart';
import '../core/models.dart';
import 'glass.dart';

const folderColors = <Color>[
  Color(0xFF6366F1),
  Color(0xFF0EA5E9),
  Color(0xFF10B981),
  Color(0xFFF59E0B),
  Color(0xFFEF4444),
  Color(0xFFEC4899),
  Color(0xFF8B5CF6),
];

String docMeta(DocItem d) {
  final n = d.pages.length;
  final date = DateFormat('d MMM yyyy').format(d.updatedAt);
  return '$n page${n == 1 ? '' : 's'} · $date';
}

class PageThumb extends StatelessWidget {
  final LibraryStore store;
  final DocItem doc;
  final PageItem? page;
  final double width;
  final double height;
  final double radius;
  const PageThumb({
    super.key,
    required this.store,
    required this.doc,
    this.page,
    required this.width,
    required this.height,
    this.radius = 10,
  });

  @override
  Widget build(BuildContext context) {
    final g = Glass.of(context);
    final pg = page ?? (doc.pages.isNotEmpty ? doc.pages.first : null);
    final dpr = MediaQuery.of(context).devicePixelRatio;
    return Container(
      width: width,
      height: height,
      decoration: BoxDecoration(
        color: Colors.white,
        borderRadius: BorderRadius.circular(radius),
        border: Border.all(color: g.border),
        boxShadow: [BoxShadow(color: Colors.black.withValues(alpha: 0.12), blurRadius: 10, offset: const Offset(0, 4))],
      ),
      clipBehavior: Clip.antiAlias,
      child: pg == null
          ? null
          : Image.file(
              File(store.thumbFile(doc, pg).path),
              fit: BoxFit.cover,
              cacheWidth: (width * dpr).round(),
              gaplessPlayback: true,
              errorBuilder: (_, _, _) => const SizedBox(),
            ),
    );
  }
}

class _Badges extends StatelessWidget {
  final LibraryStore store;
  final DocItem doc;
  const _Badges({required this.store, required this.doc});

  @override
  Widget build(BuildContext context) {
    final g = Glass.of(context);
    final folder = store.folderOf(doc);
    return Wrap(
      spacing: 6,
      runSpacing: 4,
      children: [
        if (folder != null)
          _Pill(label: folder.name, color: folderColors[folder.colorIndex % folderColors.length]),
        if (doc.ocrPending)
          _Pill(label: 'Reading text…', color: g.muted)
        else if (doc.fullText.isNotEmpty)
          _Pill(label: 'Searchable', color: g.success),
      ],
    );
  }
}

class _Pill extends StatelessWidget {
  final String label;
  final Color color;
  const _Pill({required this.label, required this.color});

  @override
  Widget build(BuildContext context) {
    return Container(
      padding: const EdgeInsets.symmetric(horizontal: 8, vertical: 3),
      decoration: BoxDecoration(
        color: color.withValues(alpha: 0.14),
        borderRadius: BorderRadius.circular(20),
      ),
      child: Text(label, style: TextStyle(fontSize: 11, fontWeight: FontWeight.w700, color: color)),
    );
  }
}

class _SelectMark extends StatelessWidget {
  final bool selected;
  const _SelectMark({required this.selected});

  @override
  Widget build(BuildContext context) {
    final g = Glass.of(context);
    return AnimatedContainer(
      duration: const Duration(milliseconds: 160),
      width: 26,
      height: 26,
      decoration: BoxDecoration(
        shape: BoxShape.circle,
        color: selected ? g.accent.primary : g.fill,
                border: Border.all(color: selected ? Colors.transparent : g.muted.withValues(alpha: 0.6), width: 1.5),
      ),
      child: selected ? Icon(Icons.check_rounded, size: 17, color: g.onAccent) : null,
    );
  }
}

class DocListTile extends StatelessWidget {
  final LibraryStore store;
  final DocItem doc;
  final bool selecting;
  final bool selected;
  final VoidCallback onTap;
  final VoidCallback onLongPress;
  final VoidCallback onMore;
  const DocListTile({
    super.key,
    required this.store,
    required this.doc,
    required this.selecting,
    required this.selected,
    required this.onTap,
    required this.onLongPress,
    required this.onMore,
  });

  @override
  Widget build(BuildContext context) {
    final g = Glass.of(context);
    return GlassPanel(
      radius: 20,
      onTap: onTap,
      onLongPress: onLongPress,
      color: selected ? g.accent.primary.withValues(alpha: g.dark ? 0.18 : 0.12) : null,
      padding: const EdgeInsets.all(10),
      child: Row(
        children: [
          PageThumb(store: store, doc: doc, width: 58, height: 74),
          const SizedBox(width: 14),
          Expanded(
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Row(
                  children: [
                    Expanded(
                      child: Text(doc.name,
                          maxLines: 1,
                          overflow: TextOverflow.ellipsis,
                          style: TextStyle(fontSize: 15.5, fontWeight: FontWeight.w700, color: g.text)),
                    ),
                    if (doc.favorite)
                      const Padding(
                        padding: EdgeInsets.only(left: 6),
                        child: PhosphorIcon(PhosphorIconsFill.star, size: 16, color: Color(0xFFF5B301)),
                      ),
                  ],
                ),
                const SizedBox(height: 3),
                Text(docMeta(doc), style: TextStyle(fontSize: 12.5, color: g.muted)),
                const SizedBox(height: 7),
                _Badges(store: store, doc: doc),
              ],
            ),
          ),
          const SizedBox(width: 6),
          selecting
              ? _SelectMark(selected: selected)
              : IconButton(
                  tooltip: 'More options',
                  onPressed: onMore,
                  icon: PhosphorIcon(PhosphorIconsBold.dotsThreeVertical, color: g.muted),
                ),
        ],
      ),
    );
  }
}

class DocGridTile extends StatelessWidget {
  final LibraryStore store;
  final DocItem doc;
  final bool selecting;
  final bool selected;
  final VoidCallback onTap;
  final VoidCallback onLongPress;
  const DocGridTile({
    super.key,
    required this.store,
    required this.doc,
    required this.selecting,
    required this.selected,
    required this.onTap,
    required this.onLongPress,
  });

  @override
  Widget build(BuildContext context) {
    final g = Glass.of(context);
    return GlassPanel(
      radius: 22,
      onTap: onTap,
      onLongPress: onLongPress,
      color: selected ? g.accent.primary.withValues(alpha: g.dark ? 0.18 : 0.12) : null,
      padding: const EdgeInsets.all(10),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Expanded(
            child: Stack(
              children: [
                Positioned.fill(
                  child: Container(
                    decoration: BoxDecoration(color: g.faint, borderRadius: BorderRadius.circular(14)),
                    alignment: Alignment.center,
                    padding: const EdgeInsets.all(12),
                    child: LayoutBuilder(
                      builder: (_, c) => PageThumb(
                        store: store,
                        doc: doc,
                        width: c.maxHeight * 0.74,
                        height: c.maxHeight,
                        radius: 6,
                      ),
                    ),
                  ),
                ),
                if (selecting) Positioned(top: 8, right: 8, child: _SelectMark(selected: selected)),
                if (doc.favorite && !selecting)
                  const Positioned(
                    top: 8,
                    right: 8,
                    child: PhosphorIcon(PhosphorIconsFill.star, size: 18, color: Color(0xFFF5B301)),
                  ),
                Positioned(
                  left: 8,
                  bottom: 8,
                  child: Container(
                    padding: const EdgeInsets.symmetric(horizontal: 8, vertical: 3),
                    decoration: BoxDecoration(
                      color: Colors.black.withValues(alpha: 0.55),
                      borderRadius: BorderRadius.circular(10),
                    ),
                    child: Text('${doc.pages.length}',
                        style: const TextStyle(color: Colors.white, fontSize: 11, fontWeight: FontWeight.w700)),
                  ),
                ),
              ],
            ),
          ),
          const SizedBox(height: 10),
          Text(doc.name,
              maxLines: 1,
              overflow: TextOverflow.ellipsis,
              style: TextStyle(fontSize: 14, fontWeight: FontWeight.w700, color: g.text)),
          const SizedBox(height: 2),
          Text(DateFormat('d MMM yyyy').format(doc.updatedAt), style: TextStyle(fontSize: 12, color: g.muted)),
        ],
      ),
    );
  }
}

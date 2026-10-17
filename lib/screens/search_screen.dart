import 'package:flutter/material.dart';
import '../app/icons.dart';
import 'package:provider/provider.dart';

import '../app/theme.dart';
import '../core/library_store.dart';
import '../core/models.dart';
import '../core/settings.dart';
import '../widgets/common.dart';
import '../widgets/doc_tile.dart';
import '../widgets/glass.dart';
import 'doc_actions.dart';

/// Full-text search across document names and OCR text.
class SearchScreen extends StatefulWidget {
  const SearchScreen({super.key});

  @override
  State<SearchScreen> createState() => _SearchScreenState();
}

class _SearchScreenState extends State<SearchScreen> {
  final _controller = TextEditingController();
  String _q = '';

  @override
  void dispose() {
    _controller.dispose();
    super.dispose();
  }

  /// First page index whose text matches, and a short snippet around it.
  (int, String)? _snippet(DocItem d) {
    final q = _q.trim().toLowerCase();
    for (var i = 0; i < d.pages.length; i++) {
      final t = d.pages[i].ocrText;
      final at = t.toLowerCase().indexOf(q);
      if (at >= 0) {
        final start = (at - 40).clamp(0, t.length);
        final end = (at + q.length + 60).clamp(0, t.length);
        final s = t.substring(start, end).replaceAll('\n', ' ');
        return (i, '${start > 0 ? '…' : ''}$s${end < t.length ? '…' : ''}');
      }
    }
    return null;
  }

  @override
  Widget build(BuildContext context) {
    final store = context.watch<LibraryStore>();
    final sort = context.select<SettingsStore, SortOrder>((s) => s.sort);
    final g = Glass.of(context);
    final results = _q.trim().isEmpty ? <DocItem>[] : store.query(text: _q, sort: sort);
    final top = MediaQuery.of(context).padding.top;

    return Column(
      children: [
        SizedBox(height: top + 14),
        Padding(
          padding: const EdgeInsets.symmetric(horizontal: 20),
          child: Align(
            alignment: Alignment.centerLeft,
            child: Text('Search', style: TextStyle(fontSize: 26, fontWeight: FontWeight.w800, color: g.text)),
          ),
        ),
        Padding(
          padding: const EdgeInsets.fromLTRB(16, 14, 16, 8),
          child: GlassPanel(
            radius: 18,
            padding: const EdgeInsets.symmetric(horizontal: 14),
            child: Row(
              children: [
                PhosphorIcon(PhosphorIconsRegular.magnifyingGlass, color: g.muted, size: 20),
                const SizedBox(width: 8),
                Expanded(
                  child: TextField(
                    controller: _controller,
                    autofocus: false,
                    textInputAction: TextInputAction.search,
                    onChanged: (v) => setState(() => _q = v),
                    style: TextStyle(color: g.text, fontSize: 15.5),
                    decoration: const InputDecoration(
                      hintText: 'Words inside your scans, or a name',
                      filled: false,
                      border: InputBorder.none,
                    ),
                  ),
                ),
                if (_q.isNotEmpty)
                  IconButton(
                    tooltip: 'Clear',
                    onPressed: () {
                      _controller.clear();
                      setState(() => _q = '');
                    },
                    icon: PhosphorIcon(PhosphorIconsFill.xCircle, color: g.muted, size: 20),
                  ),
              ],
            ),
          ),
        ),
        Expanded(
          child: _q.trim().isEmpty
              ? SingleChildScrollView(
                  child: EmptyState(
                    icon: PhosphorIconsDuotone.textAa,
                    title: 'Find anything you scanned',
                    message: 'DocMind reads the text on every page, so you can search inside bills, notes and letters.',
                  ),
                )
              : results.isEmpty
                  ? SingleChildScrollView(
                      child: EmptyState(
                        icon: PhosphorIconsDuotone.magnifyingGlassMinus,
                        title: 'No matches',
                        message: 'Nothing contains “${_q.trim()}”. Pages still being read will show up shortly.',
                      ),
                    )
                  : ListView.separated(
                      padding: const EdgeInsets.fromLTRB(16, 4, 16, 120),
                      itemCount: results.length,
                      separatorBuilder: (_, _) => const SizedBox(height: 10),
                      itemBuilder: (_, i) {
                        final d = results[i];
                        final snip = store.matchedInText(d, _q) ? _snippet(d) : null;
                        return FadeIn(
                          index: i,
                          child: GlassPanel(
                            radius: 20,
                            padding: const EdgeInsets.all(10),
                            onTap: () => DocActions.open(context, d, page: snip?.$1 ?? 0, highlight: _q.trim()),
                            child: Row(
                              crossAxisAlignment: CrossAxisAlignment.start,
                              children: [
                                PageThumb(
                                  store: store,
                                  doc: d,
                                  page: d.pages[snip?.$1 ?? 0],
                                  width: 52,
                                  height: 66,
                                ),
                                const SizedBox(width: 12),
                                Expanded(
                                  child: Column(
                                    crossAxisAlignment: CrossAxisAlignment.start,
                                    children: [
                                      _Highlighted(text: d.name, query: _q.trim(), bold: true),
                                      const SizedBox(height: 3),
                                      Text(
                                        snip == null ? docMeta(d) : 'Page ${snip.$1 + 1} · ${docMeta(d)}',
                                        style: TextStyle(fontSize: 12, color: g.muted),
                                      ),
                                      if (snip != null) ...[
                                        const SizedBox(height: 6),
                                        _Highlighted(text: snip.$2, query: _q.trim(), maxLines: 3),
                                      ],
                                    ],
                                  ),
                                ),
                              ],
                            ),
                          ),
                        );
                      },
                    ),
        ),
      ],
    );
  }
}

class _Highlighted extends StatelessWidget {
  final String text;
  final String query;
  final bool bold;
  final int maxLines;
  const _Highlighted({required this.text, required this.query, this.bold = false, this.maxLines = 1});

  @override
  Widget build(BuildContext context) {
    final g = Glass.of(context);
    final base = TextStyle(
      fontSize: bold ? 15.5 : 13.5,
      fontWeight: bold ? FontWeight.w700 : FontWeight.w400,
      color: bold ? g.text : g.muted,
      height: 1.35,
    );
    final spans = <TextSpan>[];
    final lower = text.toLowerCase();
    final q = query.toLowerCase();
    var i = 0;
    while (q.isNotEmpty) {
      final at = lower.indexOf(q, i);
      if (at < 0) break;
      spans.add(TextSpan(text: text.substring(i, at)));
      spans.add(TextSpan(
        text: text.substring(at, at + q.length),
        style: TextStyle(
          color: g.text,
          fontWeight: FontWeight.w800,
          backgroundColor: g.accent.primary.withValues(alpha: 0.22),
        ),
      ));
      i = at + q.length;
    }
    spans.add(TextSpan(text: text.substring(i)));
    return Text.rich(TextSpan(style: base, children: spans), maxLines: maxLines, overflow: TextOverflow.ellipsis);
  }
}

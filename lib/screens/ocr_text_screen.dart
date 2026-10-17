import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import '../app/icons.dart';
import 'package:provider/provider.dart';

import '../app/theme.dart';
import '../core/export_service.dart';
import '../core/library_store.dart';
import '../core/models.dart';
import '../widgets/common.dart';
import '../widgets/glass.dart';

/// Recognised text per page: select, copy, share, re-run.
class OcrTextScreen extends StatelessWidget {
  final DocItem doc;
  final int initialPage;
  const OcrTextScreen({super.key, required this.doc, this.initialPage = 0});

  @override
  Widget build(BuildContext context) {
    final store = context.watch<LibraryStore>();
    final g = Glass.of(context);
    final pending = doc.ocrPending;
    return Scaffold(
      body: GlassBackground(
        child: SafeArea(
          child: Column(
            children: [
              GlassTopBar(
                title: 'Text',
                subtitle: pending ? 'Recognising text…' : 'Recognised on this device',
                actions: [
                  GlassIconButton(
                    icon: PhosphorIconsDuotone.copy,
                    tooltip: 'Copy all',
                    onTap: doc.fullText.isEmpty
                        ? null
                        : () {
                            Clipboard.setData(ClipboardData(text: doc.fullText));
                            toast(context, 'Text copied');
                          },
                  ),
                  GlassIconButton(
                    icon: PhosphorIconsDuotone.shareNetwork,
                    tooltip: 'Share text',
                    onTap: doc.fullText.isEmpty ? null : () => ExportService.shareText(doc.fullText, subject: doc.name),
                  ),
                ],
              ),
              Expanded(
                child: ListView.builder(
                  padding: const EdgeInsets.fromLTRB(16, 6, 16, 24),
                  itemCount: doc.pages.length + 1,
                  itemBuilder: (_, i) {
                    if (i == doc.pages.length) {
                      return Padding(
                        padding: const EdgeInsets.only(top: 10),
                        child: GlassButton(
                          label: 'Re-run text recognition',
                          icon: PhosphorIconsDuotone.arrowsClockwise,
                          expand: true,
                          onTap: pending
                              ? null
                              : () async {
                                  await runBusy(context, 'Reading text…', (_) => store.runOcrNow(doc, force: true));
                                },
                        ),
                      );
                    }
                    final pg = doc.pages[i];
                    return FadeIn(
                      index: i,
                      child: GlassPanel(
                        margin: const EdgeInsets.only(bottom: 12),
                        padding: const EdgeInsets.fromLTRB(16, 12, 8, 14),
                        child: Column(
                          crossAxisAlignment: CrossAxisAlignment.start,
                          children: [
                            Row(
                              children: [
                                Text('PAGE ${i + 1}',
                                    style: TextStyle(
                                        fontSize: 12, letterSpacing: 1, fontWeight: FontWeight.w800, color: g.muted)),
                                const Spacer(),
                                if (pg.ocrText.isNotEmpty)
                                  IconButton(
                                    tooltip: 'Copy page text',
                                    onPressed: () {
                                      Clipboard.setData(ClipboardData(text: pg.ocrText));
                                      toast(context, 'Page ${i + 1} copied');
                                    },
                                    icon: PhosphorIcon(PhosphorIconsDuotone.copySimple, color: g.muted, size: 20),
                                  ),
                              ],
                            ),
                            Padding(
                              padding: const EdgeInsets.only(right: 8),
                              child: !pg.ocrDone
                                  ? Row(children: [
                                      SizedBox(
                                        width: 14,
                                        height: 14,
                                        child: CircularProgressIndicator(strokeWidth: 2, color: g.accent.primary),
                                      ),
                                      const SizedBox(width: 10),
                                      Text('Reading…', style: TextStyle(color: g.muted)),
                                    ])
                                  : pg.ocrText.isEmpty
                                      ? Text('No text found on this page.', style: TextStyle(color: g.muted))
                                      : SelectableText(pg.ocrText,
                                          style: TextStyle(fontSize: 15, height: 1.55, color: g.text)),
                            ),
                          ],
                        ),
                      ),
                    );
                  },
                ),
              ),
            ],
          ),
        ),
      ),
    );
  }
}

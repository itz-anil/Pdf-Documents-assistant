import 'package:flutter/material.dart';
import '../app/icons.dart';

import '../app/theme.dart';
import '../core/models.dart';
import '../widgets/common.dart';
import '../widgets/glass.dart';
import 'scan_flow.dart';
import 'tool_flows.dart';

class _Tool {
  final IconData icon;
  final String title;
  final String subtitle;
  final Future<void> Function(BuildContext) run;
  const _Tool(this.icon, this.title, this.subtitle, this.run);
}

class ToolsScreen extends StatelessWidget {
  const ToolsScreen({super.key});

  static final _sections = <(String, List<_Tool>)>[
    (
      'PDF tools',
      [
        _Tool(PhosphorIconsRegular.unite, 'Merge PDFs', 'Join files in any order', ToolFlows.merge),
        _Tool(PhosphorIconsRegular.scissors, 'Split PDF', 'Extract or separate pages', ToolFlows.split),
        _Tool(PhosphorIconsRegular.arrowsInSimple, 'Compress PDF', 'Shrink large files', ToolFlows.compress),
        _Tool(PhosphorIconsRegular.lockKey, 'Protect PDF', 'Add a password', ToolFlows.protect),
        _Tool(PhosphorIconsRegular.lockKeyOpen, 'Remove password', 'Unlock a PDF you own', ToolFlows.removePassword),
        _Tool(PhosphorIconsRegular.fileImage, 'PDF to JPG', 'Every page as an image', ToolFlows.pdfToImages),
        _Tool(PhosphorIconsRegular.filePdf, 'Images to PDF', 'Photos into one PDF', ToolFlows.imagesToPdf),
        _Tool(PhosphorIconsRegular.fileArrowDown, 'Import PDF', 'Edit & sign it in DocMind', (c) => ScanFlow.importPdf(c)),
      ]
    ),
    (
      'Archive',
      [
        _Tool(PhosphorIconsRegular.fileZip, 'Create ZIP', 'Bundle any files, optional password', ToolFlows.createZip),
        _Tool(PhosphorIconsRegular.folderOpen, 'Extract ZIP', 'Open ZIP archives', ToolFlows.extractZip),
      ]
    ),
    (
      'Scan & recognise',
      [
        _Tool(PhosphorIconsRegular.qrCode, 'QR & Barcode', 'Scan codes instantly',
            ScanFlow.openQr),
        _Tool(PhosphorIconsRegular.textAa, 'Text from image', 'Copy text from photos', ToolFlows.textFromImage),
        _Tool(PhosphorIconsRegular.identificationCard, 'ID Card', 'Front & back on one page',
            (c) => ScanFlow.scan(c, ScanMode.idCard)),
        _Tool(PhosphorIconsRegular.addressBook, 'Business card', 'Save as a contact',
            (c) => ScanFlow.scan(c, ScanMode.businessCard)),
        _Tool(PhosphorIconsRegular.bookOpen, 'Book', 'Split two-page spreads', (c) => ScanFlow.scan(c, ScanMode.book)),
        _Tool(PhosphorIconsRegular.chalkboard, 'Whiteboard', 'Clean, vivid boards',
            (c) => ScanFlow.scan(c, ScanMode.whiteboard)),
      ]
    ),
  ];

  @override
  Widget build(BuildContext context) {
    final g = Glass.of(context);
    final top = MediaQuery.of(context).padding.top;
    var index = 0;
    return CustomScrollView(
      physics: const BouncingScrollPhysics(parent: AlwaysScrollableScrollPhysics()),
      slivers: [
        SliverToBoxAdapter(
          child: Padding(
            padding: EdgeInsets.fromLTRB(20, top + 14, 20, 0),
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Text('Tools', style: TextStyle(fontSize: 26, fontWeight: FontWeight.w800, color: g.text)),
                const SizedBox(height: 4),
                Text('Everything runs offline on your phone', style: TextStyle(color: g.muted)),
              ],
            ),
          ),
        ),
        for (final (title, tools) in _sections) ...[
          SliverPadding(
            padding: const EdgeInsets.symmetric(horizontal: 16),
            sliver: SliverToBoxAdapter(child: SectionLabel(title)),
          ),
          SliverPadding(
            padding: const EdgeInsets.symmetric(horizontal: 16),
            sliver: SliverGrid(
              gridDelegate: const SliverGridDelegateWithFixedCrossAxisCount(
                crossAxisCount: 2,
                mainAxisSpacing: 12,
                crossAxisSpacing: 12,
                mainAxisExtent: 128,
              ),
              delegate: SliverChildListDelegate([
                for (final t in tools)
                  FadeIn(
                    index: index++,
                    child: Semantics(
                      button: true,
                      label: t.title,
                      child: GlassPanel(
                        radius: 22,
                        padding: const EdgeInsets.all(14),
                        onTap: () {
                          haptic(context);
                          t.run(context);
                        },
                        child: Column(
                          crossAxisAlignment: CrossAxisAlignment.start,
                          children: [
                            IconBadge(t.icon, size: 44),
                            const Spacer(),
                            Text(t.title,
                                maxLines: 1,
                                overflow: TextOverflow.ellipsis,
                                style: TextStyle(fontSize: 14.5, fontWeight: FontWeight.w700, color: g.text)),
                            const SizedBox(height: 2),
                            Text(t.subtitle,
                                maxLines: 1,
                                overflow: TextOverflow.ellipsis,
                                style: TextStyle(fontSize: 12, color: g.muted)),
                          ],
                        ),
                      ),
                    ),
                  ),
              ]),
            ),
          ),
        ],
        const SliverToBoxAdapter(child: SizedBox(height: 120)),
      ],
    );
  }
}

import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:url_launcher/url_launcher.dart';

import '../app/icons.dart';
import '../app/theme.dart';
import '../core/export_service.dart';
import '../widgets/common.dart';
import '../widgets/glass.dart';

/// Shows what a scanned QR code or barcode contains, with quick actions.
Future<void> showQrResult(BuildContext context, String value, String format) =>
    showGlassSheet<void>(context, builder: (_) => _ResultSheet(value: value, format: format));

class _ResultSheet extends StatelessWidget {
  final String value;
  final String format;
  const _ResultSheet({required this.value, required this.format});

  @override
  Widget build(BuildContext context) {
    final g = Glass.of(context);
    final uri = Uri.tryParse(value);
    final isLink = uri != null && (uri.scheme == 'http' || uri.scheme == 'https');
    final isSpecial = uri != null && ['mailto', 'tel', 'sms', 'geo'].contains(uri.scheme);
    return Padding(
      padding: const EdgeInsets.fromLTRB(20, 16, 20, 16),
      child: Column(
        mainAxisSize: MainAxisSize.min,
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Row(
            children: [
              IconBadge(isLink ? PhosphorIconsRegular.link : PhosphorIconsRegular.qrCode, filled: true, size: 48),
              const SizedBox(width: 12),
              Text(isLink ? 'Link found' : 'Code found',
                  style: TextStyle(fontSize: 19, fontWeight: FontWeight.w800, color: g.text)),
              const Spacer(),
              Text(format.toUpperCase(), style: TextStyle(fontSize: 11, fontWeight: FontWeight.w700, color: g.muted)),
            ],
          ),
          const SizedBox(height: 14),
          GlassPanel(
            padding: const EdgeInsets.all(14),
            child: SelectableText(value, style: TextStyle(color: g.text, fontSize: 15, height: 1.4)),
          ),
          const SizedBox(height: 16),
          if (isLink || isSpecial) ...[
            GradientButton(
              label: isLink ? 'Open link' : 'Open',
              icon: PhosphorIconsRegular.arrowSquareOut,
              expand: true,
              onTap: () => launchUrl(uri, mode: LaunchMode.externalApplication),
            ),
            const SizedBox(height: 10),
          ],
          Row(
            children: [
              Expanded(
                child: GlassButton(
                  label: 'Copy',
                  icon: PhosphorIconsRegular.copy,
                  onTap: () {
                    Clipboard.setData(ClipboardData(text: value));
                    toast(context, 'Copied');
                  },
                ),
              ),
              const SizedBox(width: 10),
              Expanded(
                child: GlassButton(
                  label: 'Share',
                  icon: PhosphorIconsRegular.shareNetwork,
                  onTap: () => ExportService.shareText(value),
                ),
              ),
            ],
          ),
        ],
      ),
    );
  }
}

import 'dart:ui';

import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:mobile_scanner/mobile_scanner.dart';
import '../app/icons.dart';
import 'package:url_launcher/url_launcher.dart';

import '../app/theme.dart';
import '../core/export_service.dart';
import '../widgets/common.dart';
import '../widgets/glass.dart';

/// QR code and barcode scanner (on-device).
class QrScreen extends StatefulWidget {
  const QrScreen({super.key});

  @override
  State<QrScreen> createState() => _QrScreenState();
}

class _QrScreenState extends State<QrScreen> {
  final _controller = MobileScannerController(detectionSpeed: DetectionSpeed.noDuplicates);
  bool _showing = false;
  bool _torch = false;

  @override
  void dispose() {
    _controller.dispose();
    super.dispose();
  }

  Future<void> _onDetect(BarcodeCapture capture) async {
    if (_showing || capture.barcodes.isEmpty) return;
    final code = capture.barcodes.first;
    final value = code.rawValue ?? code.displayValue;
    if (value == null || value.isEmpty) return;
    _showing = true;
    HapticFeedback.mediumImpact();
    await _controller.stop();
    if (!mounted) return;
    await showGlassSheet<void>(context, builder: (ctx) => _ResultSheet(value: value, format: code.format.name));
    _showing = false;
    if (mounted) await _controller.start();
  }

  @override
  Widget build(BuildContext context) {
    final g = Glass.of(context);
    return Scaffold(
      backgroundColor: Colors.black,
      body: Stack(
        children: [
          Positioned.fill(
            child: MobileScanner(
              controller: _controller,
              onDetect: _onDetect,
              errorBuilder: (ctx, error) => Center(
                child: Padding(
                  padding: const EdgeInsets.all(32),
                  child: Text(
                    'Camera unavailable. Allow camera access for DocMind in system settings.',
                    textAlign: TextAlign.center,
                    style: const TextStyle(color: Colors.white),
                  ),
                ),
              ),
            ),
          ),
          Positioned.fill(child: IgnorePointer(child: CustomPaint(painter: _FramePainter(g.accent.primary)))),
          SafeArea(
            child: Column(
              children: [
                Theme(
                  data: Theme.of(context).copyWith(extensions: [Glass.dark(g.accent)]),
                  child: GlassTopBar(
                    title: 'QR & Barcode',
                    subtitle: 'Point the camera at a code',
                    actions: [
                      GlassIconButton(
                        icon: _torch ? PhosphorIconsFill.lightning : PhosphorIconsDuotone.lightning,
                        tooltip: 'Torch',
                        onTap: () async {
                          await _controller.toggleTorch();
                          setState(() => _torch = !_torch);
                        },
                      ),
                    ],
                  ),
                ),
                const Spacer(),
                Padding(
                  padding: const EdgeInsets.only(bottom: 40),
                  child: ClipRRect(
                    borderRadius: BorderRadius.circular(20),
                    child: BackdropFilter(
                      filter: ImageFilter.blur(sigmaX: 16, sigmaY: 16),
                      child: Container(
                        padding: const EdgeInsets.symmetric(horizontal: 16, vertical: 10),
                        color: Colors.black.withValues(alpha: 0.35),
                        child: const Text('QR · EAN · UPC · Code 128 · Data Matrix and more',
                            style: TextStyle(color: Colors.white, fontSize: 12.5)),
                      ),
                    ),
                  ),
                ),
              ],
            ),
          ),
        ],
      ),
    );
  }
}

class _FramePainter extends CustomPainter {
  final Color accent;
  _FramePainter(this.accent);

  @override
  void paint(Canvas canvas, Size size) {
    final side = size.width * 0.68;
    final r = Rect.fromCenter(center: size.center(Offset.zero), width: side, height: side);
    final rr = RRect.fromRectAndRadius(r, const Radius.circular(28));
    canvas.drawPath(
      Path()
        ..fillType = PathFillType.evenOdd
        ..addRect(Offset.zero & size)
        ..addRRect(rr),
      Paint()..color = Colors.black.withValues(alpha: 0.45),
    );
    final p = Paint()
      ..color = accent
      ..style = PaintingStyle.stroke
      ..strokeWidth = 5
      ..strokeCap = StrokeCap.round;
    const l = 34.0;
    for (final c in [r.topLeft, r.topRight, r.bottomLeft, r.bottomRight]) {
      final dx = c.dx == r.left ? 1 : -1;
      final dy = c.dy == r.top ? 1 : -1;
      canvas.drawLine(c + Offset(0, dy * 14.0), c + Offset(0, dy * l), p);
      canvas.drawLine(c + Offset(dx * 14.0, 0), c + Offset(dx * l, 0), p);
    }
  }

  @override
  bool shouldRepaint(_FramePainter old) => old.accent != accent;
}

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
              IconBadge(isLink ? PhosphorIconsDuotone.link : PhosphorIconsDuotone.qrCode, filled: true, size: 48),
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
              icon: PhosphorIconsDuotone.arrowSquareOut,
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
                  icon: PhosphorIconsDuotone.copy,
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
                  icon: PhosphorIconsDuotone.shareNetwork,
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

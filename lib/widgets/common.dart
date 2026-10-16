import 'dart:io';

import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import '../app/icons.dart';
import 'package:provider/provider.dart';

import '../app/theme.dart';
import '../core/export_service.dart';
import '../core/library_store.dart';
import '../core/settings.dart';
import 'glass.dart';

void haptic(BuildContext context) {
  if (context.read<SettingsStore>().haptics) HapticFeedback.selectionClick();
}

void toast(BuildContext context, String message, {bool error = false}) {
  final messenger = ScaffoldMessenger.maybeOf(context);
  if (messenger == null) return;
  messenger
    ..hideCurrentSnackBar()
    ..showSnackBar(SnackBar(
      content: Row(
        children: [
          PhosphorIcon(
            error ? PhosphorIconsFill.warningCircle : PhosphorIconsFill.checkCircle,
            color: error ? const Color(0xFFFF8A96) : const Color(0xFF5EEAB0),
            size: 20,
          ),
          const SizedBox(width: 10),
          Expanded(child: Text(message)),
        ],
      ),
      duration: Duration(milliseconds: error ? 3500 : 2200),
    ));
}

/// Runs [task] behind a blocking glass progress dialog.
/// [progress] can be updated from inside the task for multi-step jobs.
Future<T?> runBusy<T>(
  BuildContext context,
  String message,
  Future<T> Function(ValueNotifier<String> progress) task,
) async {
  final progress = ValueNotifier<String>(message);
  final nav = Navigator.of(context, rootNavigator: true);
  var open = true;
  showDialog<void>(
    context: context,
    barrierDismissible: false,
    useRootNavigator: true,
    barrierColor: Colors.black.withValues(alpha: 0.4),
    builder: (ctx) {
      final g = Glass.of(ctx);
      return PopScope(
        canPop: false,
        child: Center(
          child: GlassPanel(
            blur: true,
            strong: true,
            radius: 24,
            padding: const EdgeInsets.fromLTRB(28, 26, 28, 24),
            child: Material(
              type: MaterialType.transparency,
              child: ConstrainedBox(
                constraints: const BoxConstraints(maxWidth: 260),
                child: Column(
                  mainAxisSize: MainAxisSize.min,
                  children: [
                    SizedBox(
                      width: 38,
                      height: 38,
                      child: CircularProgressIndicator(strokeWidth: 3.2, color: g.accent.primary),
                    ),
                    const SizedBox(height: 18),
                    ValueListenableBuilder<String>(
                      valueListenable: progress,
                      builder: (_, v, _) => Text(
                        v,
                        textAlign: TextAlign.center,
                        style: TextStyle(color: g.text, fontWeight: FontWeight.w600, fontSize: 15),
                      ),
                    ),
                  ],
                ),
              ),
            ),
          ),
        ),
      );
    },
  ).then((_) => open = false);
  try {
    return await task(progress);
  } catch (e) {
    if (context.mounted) toast(context, friendlyError(e), error: true);
    return null;
  } finally {
    if (open) nav.pop();
    progress.dispose();
  }
}

String friendlyError(Object e) {
  final s = e.toString();
  if (s.startsWith('Exception: ')) return s.substring(11);
  if (s.startsWith('FormatException: ')) return s.substring(17);
  return s.length > 140 ? '${s.substring(0, 140)}…' : s;
}

Future<String?> promptText(
  BuildContext context, {
  required String title,
  String initial = '',
  String hint = '',
  String action = 'Save',
  TextInputType keyboard = TextInputType.text,
}) {
  final controller = TextEditingController(text: initial);
  controller.selection = TextSelection(baseOffset: 0, extentOffset: initial.length);
  return showDialog<String>(
    context: context,
    builder: (ctx) => AlertDialog(
      title: Text(title, style: const TextStyle(fontWeight: FontWeight.w700)),
      content: TextField(
        controller: controller,
        autofocus: true,
        keyboardType: keyboard,
        textCapitalization: TextCapitalization.sentences,
        decoration: InputDecoration(hintText: hint),
        onSubmitted: (v) => Navigator.pop(ctx, v),
      ),
      actions: [
        TextButton(onPressed: () => Navigator.pop(ctx), child: const Text('Cancel')),
        FilledButton(onPressed: () => Navigator.pop(ctx, controller.text), child: Text(action)),
      ],
    ),
  );
}

Future<bool> confirm(
  BuildContext context, {
  required String title,
  required String message,
  String action = 'Delete',
  bool destructive = true,
}) async {
  final g = Glass.of(context);
  final r = await showDialog<bool>(
    context: context,
    builder: (ctx) => AlertDialog(
      title: Text(title, style: const TextStyle(fontWeight: FontWeight.w700)),
      content: Text(message),
      actions: [
        TextButton(onPressed: () => Navigator.pop(ctx, false), child: const Text('Cancel')),
        FilledButton(
          style: destructive ? FilledButton.styleFrom(backgroundColor: g.danger) : null,
          onPressed: () => Navigator.pop(ctx, true),
          child: Text(action),
        ),
      ],
    ),
  );
  return r ?? false;
}

/// Password entry with show/hide and optional confirmation field.
Future<String?> promptPassword(
  BuildContext context, {
  required String title,
  String message = '',
  bool confirmField = false,
  String action = 'Continue',
}) {
  return showDialog<String>(
    context: context,
    builder: (ctx) => _PasswordDialog(title: title, message: message, confirmField: confirmField, action: action),
  );
}

class _PasswordDialog extends StatefulWidget {
  final String title;
  final String message;
  final bool confirmField;
  final String action;
  const _PasswordDialog({required this.title, required this.message, required this.confirmField, required this.action});

  @override
  State<_PasswordDialog> createState() => _PasswordDialogState();
}

class _PasswordDialogState extends State<_PasswordDialog> {
  final _a = TextEditingController();
  final _b = TextEditingController();
  bool _hidden = true;
  String? _error;

  void _submit() {
    if (_a.text.isEmpty) {
      setState(() => _error = 'Enter a password');
      return;
    }
    if (widget.confirmField && _a.text.length < 4) {
      setState(() => _error = 'Use at least 4 characters');
      return;
    }
    if (widget.confirmField && _a.text != _b.text) {
      setState(() => _error = 'Passwords do not match');
      return;
    }
    Navigator.pop(context, _a.text);
  }

  @override
  Widget build(BuildContext context) {
    final g = Glass.of(context);
    final eye = IconButton(
      tooltip: _hidden ? 'Show password' : 'Hide password',
      icon: PhosphorIcon(_hidden ? PhosphorIconsRegular.eye : PhosphorIconsRegular.eyeSlash, color: g.muted),
      onPressed: () => setState(() => _hidden = !_hidden),
    );
    return AlertDialog(
      title: Row(
        children: [
          IconBadge(PhosphorIconsDuotone.lockKey, size: 36),
          const SizedBox(width: 12),
          Expanded(child: Text(widget.title, style: const TextStyle(fontWeight: FontWeight.w700))),
        ],
      ),
      content: Column(
        mainAxisSize: MainAxisSize.min,
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          if (widget.message.isNotEmpty) ...[
            Text(widget.message, style: TextStyle(color: g.muted)),
            const SizedBox(height: 14),
          ],
          TextField(
            controller: _a,
            obscureText: _hidden,
            autofocus: true,
            decoration: InputDecoration(labelText: 'Password', suffixIcon: eye),
            onSubmitted: (_) => widget.confirmField ? null : _submit(),
          ),
          if (widget.confirmField) ...[
            const SizedBox(height: 12),
            TextField(
              controller: _b,
              obscureText: _hidden,
              decoration: const InputDecoration(labelText: 'Confirm password'),
              onSubmitted: (_) => _submit(),
            ),
          ],
          if (_error != null) ...[
            const SizedBox(height: 10),
            Text(_error!, style: TextStyle(color: g.danger, fontWeight: FontWeight.w600)),
          ],
        ],
      ),
      actions: [
        TextButton(onPressed: () => Navigator.pop(context), child: const Text('Cancel')),
        FilledButton(onPressed: _submit, child: Text(widget.action)),
      ],
    );
  }
}

/// Generic option picker as a glass sheet.
Future<T?> pickOption<T>(
  BuildContext context, {
  required String title,
  required List<T> options,
  required String Function(T) label,
  String Function(T)? subtitle,
  IconData Function(T)? icon,
  T? selected,
}) {
  return showGlassSheet<T>(
    context,
    builder: (ctx) {
      final g = Glass.of(ctx);
      return ListView(
        shrinkWrap: true,
        padding: const EdgeInsets.fromLTRB(12, 14, 12, 16),
        children: [
          Padding(
            padding: const EdgeInsets.fromLTRB(12, 0, 12, 8),
            child: Text(title, style: TextStyle(fontSize: 18, fontWeight: FontWeight.w700, color: g.text)),
          ),
          for (final o in options)
            GlassTile(
              icon: icon?.call(o) ?? PhosphorIconsDuotone.circle,
              title: label(o),
              subtitle: subtitle?.call(o),
              trailing: o == selected
                  ? PhosphorIcon(PhosphorIconsFill.checkCircle, color: g.accent.primary)
                  : null,
              onTap: () => Navigator.pop(ctx, o),
            ),
        ],
      );
    },
  );
}

/// Sheet shown after a tool produces files: share, save, open.
Future<void> showResultSheet(BuildContext context, {required String title, required List<String> files, String? note}) {
  return showGlassSheet<void>(
    context,
    builder: (ctx) {
      final g = Glass.of(ctx);
      final single = files.length == 1;
      return Padding(
        padding: const EdgeInsets.fromLTRB(20, 16, 20, 16),
        child: Column(
          mainAxisSize: MainAxisSize.min,
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            Row(
              children: [
                IconBadge(PhosphorIconsDuotone.sealCheck, filled: true, size: 52),
                const SizedBox(width: 14),
                Expanded(
                  child: Column(
                    crossAxisAlignment: CrossAxisAlignment.start,
                    children: [
                      Text(title, style: TextStyle(fontSize: 18, fontWeight: FontWeight.w700, color: g.text)),
                      const SizedBox(height: 2),
                      FutureBuilder<int>(
                        future: Future.wait(files.map((f) => File(f).length())).then((l) => l.fold<int>(0, (a, b) => a + b)),
                        builder: (_, s) => Text(
                          '${files.length} file${single ? '' : 's'}${s.hasData ? ' · ${formatBytes(s.data!)}' : ''}',
                          style: TextStyle(color: g.muted),
                        ),
                      ),
                    ],
                  ),
                ),
              ],
            ),
            if (note != null) ...[
              const SizedBox(height: 12),
              Text(note, style: TextStyle(color: g.muted, fontSize: 13)),
            ],
            const SizedBox(height: 20),
            GradientButton(
              label: 'Share',
              icon: PhosphorIconsDuotone.shareNetwork,
              expand: true,
              onTap: () => ExportService.share(files),
            ),
            const SizedBox(height: 10),
            Row(
              children: [
                if (single) ...[
                  Expanded(
                    child: GlassButton(
                      label: 'Save',
                      icon: PhosphorIconsDuotone.downloadSimple,
                      onTap: () async {
                        final ok = await ExportService.saveToDevice(files.first);
                        if (ok && ctx.mounted) toast(ctx, 'Saved to device');
                      },
                    ),
                  ),
                  const SizedBox(width: 10),
                  Expanded(
                    child: GlassButton(
                      label: 'Open',
                      icon: PhosphorIconsDuotone.arrowSquareOut,
                      onTap: () => ExportService.open(files.first),
                    ),
                  ),
                ] else
                  Expanded(
                    child: GlassButton(
                      label: 'Save all as ZIP',
                      icon: PhosphorIconsDuotone.fileZip,
                      onTap: () async {
                        final store = ctx.read<LibraryStore>();
                        final dir = await store.scratch('zip');
                        final z = await ExportService.zip(
                          files.map((f) => ZipEntrySource(f.split(Platform.pathSeparator).last, f)).toList(),
                          '${dir.path}/DocMind files.zip',
                        );
                        await ExportService.saveToDevice(z.path);
                      },
                    ),
                  ),
              ],
            ),
          ],
        ),
      );
    },
  );
}

/// Empty-state illustration block.
class EmptyState extends StatelessWidget {
  final IconData icon;
  final String title;
  final String message;
  final Widget? action;
  const EmptyState({super.key, required this.icon, required this.title, required this.message, this.action});

  @override
  Widget build(BuildContext context) {
    final g = Glass.of(context);
    return Padding(
      padding: const EdgeInsets.symmetric(horizontal: 32, vertical: 40),
      child: Column(
        mainAxisSize: MainAxisSize.min,
        children: [
          IconBadge(icon, size: 84),
          const SizedBox(height: 20),
          Text(title,
              textAlign: TextAlign.center,
              style: TextStyle(fontSize: 19, fontWeight: FontWeight.w700, color: g.text)),
          const SizedBox(height: 8),
          Text(message, textAlign: TextAlign.center, style: TextStyle(color: g.muted, height: 1.4)),
          if (action != null) ...[const SizedBox(height: 22), action!],
        ],
      ),
    );
  }
}

/// Fades + slides children in on first build (staggered by [index]).
class FadeIn extends StatelessWidget {
  final Widget child;
  final int index;
  const FadeIn({super.key, required this.child, this.index = 0});

  @override
  Widget build(BuildContext context) {
    return TweenAnimationBuilder<double>(
      tween: Tween(begin: 0, end: 1),
      duration: Duration(milliseconds: 260 + (index.clamp(0, 8) * 35)),
      curve: Curves.easeOutCubic,
      builder: (_, v, c) => Opacity(
        opacity: v,
        child: Transform.translate(offset: Offset(0, (1 - v) * 12), child: c),
      ),
      child: child,
    );
  }
}

AccentPalette accentOf(BuildContext context) => Glass.of(context).accent;

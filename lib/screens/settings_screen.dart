import 'dart:io';

import 'package:flutter/material.dart';
import 'package:local_auth/local_auth.dart';
import 'package:path/path.dart' as p;
import '../app/icons.dart';
import 'package:provider/provider.dart';

import '../app/theme.dart';
import '../core/image_processing.dart';
import '../core/library_store.dart';
import '../core/models.dart';
import '../core/settings.dart';
import '../widgets/common.dart';
import '../widgets/glass.dart';
import 'signature_pad.dart';

class SettingsScreen extends StatefulWidget {
  const SettingsScreen({super.key});

  @override
  State<SettingsScreen> createState() => _SettingsScreenState();
}

class _SettingsScreenState extends State<SettingsScreen> {
  Future<(int, int)>? _usage;

  @override
  void initState() {
    super.initState();
    _usage = context.read<LibraryStore>().storageUsage();
  }

  Future<void> _toggleLock(SettingsStore s, bool v) async {
    if (!v) {
      s.setAppLock = false;
      return;
    }
    final auth = LocalAuthentication();
    if (!await auth.isDeviceSupported()) {
      if (mounted) toast(context, 'Set up a screen lock on your phone first', error: true);
      return;
    }
    try {
      final ok = await auth.authenticate(localizedReason: 'Turn on App Lock', biometricOnly: false);
      if (ok) {
        s.setAppLock = true;
        if (mounted) toast(context, 'App Lock is on');
      }
    } catch (_) {
      if (mounted) toast(context, 'Could not verify', error: true);
    }
  }

  @override
  Widget build(BuildContext context) {
    final s = context.watch<SettingsStore>();
    final store = context.read<LibraryStore>();
    final g = Glass.of(context);
    final top = MediaQuery.of(context).padding.top;
    Widget arrow() => PhosphorIcon(PhosphorIconsBold.caretRight, size: 16, color: g.muted);
    Widget group(List<Widget> children) => GlassPanel(
          padding: const EdgeInsets.symmetric(vertical: 4),
          child: Column(children: children),
        );

    return ListView(
      physics: const BouncingScrollPhysics(parent: AlwaysScrollableScrollPhysics()),
      padding: EdgeInsets.fromLTRB(16, top + 14, 16, 120),
      children: [
        Padding(
          padding: const EdgeInsets.symmetric(horizontal: 4),
          child: Text('Settings', style: TextStyle(fontSize: 26, fontWeight: FontWeight.w800, color: g.text)),
        ),

        const SectionLabel('Appearance'),
        group([
          Padding(
            padding: const EdgeInsets.fromLTRB(14, 10, 14, 6),
            child: Row(
              children: [
                for (final (mode, icon, label) in [
                  (ThemeMode.system, PhosphorIconsRegular.circleHalf, 'Auto'),
                  (ThemeMode.light, PhosphorIconsRegular.sun, 'Light'),
                  (ThemeMode.dark, PhosphorIconsRegular.moon, 'Dark'),
                ])
                  Expanded(
                    child: Padding(
                      padding: const EdgeInsets.symmetric(horizontal: 4),
                      child: Semantics(
                        button: true,
                        selected: s.themeMode == mode,
                        label: '$label theme',
                        child: Pressable(
                          onTap: () => s.setThemeMode = mode,
                          child: AnimatedContainer(
                            duration: const Duration(milliseconds: 180),
                            height: 74,
                            decoration: BoxDecoration(
                              color: s.themeMode == mode ? g.accent.primary : g.faint,
                                                            borderRadius: BorderRadius.circular(16),
                            ),
                            child: Column(
                              mainAxisAlignment: MainAxisAlignment.center,
                              children: [
                                PhosphorIcon(icon, color: s.themeMode == mode ? g.onAccent : g.text),
                                const SizedBox(height: 6),
                                Text(label,
                                    style: TextStyle(
                                      fontWeight: FontWeight.w700,
                                      color: s.themeMode == mode ? g.onAccent : g.text,
                                    )),
                              ],
                            ),
                          ),
                        ),
                      ),
                    ),
                  ),
              ],
            ),
          ),
          Padding(
            padding: const EdgeInsets.fromLTRB(18, 10, 18, 14),
            child: Row(
              children: [
                Text('Accent', style: TextStyle(fontWeight: FontWeight.w600, color: g.text)),
                const Spacer(),
                for (var i = 0; i < accentPalettes.length; i++)
                  Padding(
                    padding: const EdgeInsets.only(left: 10),
                    child: Semantics(
                      button: true,
                      selected: i == s.accentIndex,
                      label: '${accentPalettes[i].name} accent',
                      child: Pressable(
                        onTap: () => s.setAccent = i,
                        child: AnimatedContainer(
                          duration: const Duration(milliseconds: 180),
                          width: 32,
                          height: 32,
                          decoration: BoxDecoration(
                            shape: BoxShape.circle,
                            color: accentPalettes[i].resolve(g.dark).primary,
                            border: Border.all(
                              color: i == s.accentIndex ? g.text : g.border,
                              width: 2.5,
                            ),
                          ),
                        ),
                      ),
                    ),
                  ),
              ],
            ),
          ),
        ]),

        const SectionLabel('Scanning'),
        group([
          GlassTile(
            icon: PhosphorIconsRegular.magicWand,
            title: 'Default filter',
            subtitle: s.defaultFilter.label,
            trailing: arrow(),
            onTap: () async {
              final f = await pickOption<PageFilter>(
                context,
                title: 'Default filter',
                options: PageFilter.values,
                label: (f) => f.label,
                selected: s.defaultFilter,
                icon: (_) => PhosphorIconsRegular.magicWand,
              );
              if (f != null) s.setDefaultFilter = f;
            },
          ),
          GlassTile(
            icon: PhosphorIconsRegular.aperture,
            title: 'Auto-capture',
            subtitle: 'Take the photo when the page is steady',
            trailing: Switch(value: s.autoCapture, onChanged: (v) => s.setAutoCapture = v),
            onTap: () => s.setAutoCapture = !s.autoCapture,
          ),
          GlassTile(
            icon: PhosphorIconsRegular.identificationCard,
            title: 'ID card size',
            subtitle: '${s.idCardSize.label} · ${s.idCardSize.hint}',
            trailing: arrow(),
            onTap: () async {
              final v = await pickOption<IdCardSize>(
                context,
                title: 'ID card size on the page',
                options: IdCardSize.values,
                label: (v) => v.label,
                subtitle: (v) => v.hint,
                selected: s.idCardSize,
                icon: (_) => PhosphorIconsRegular.identificationCard,
              );
              if (v != null) s.setIdCardSize = v;
            },
          ),
          GlassTile(
            icon: PhosphorIconsRegular.image,
            title: 'Image quality',
            subtitle: '${s.quality.label} · ${s.quality.hint}',
            trailing: arrow(),
            onTap: () async {
              final q = await pickOption<ImageQuality>(
                context,
                title: 'Image quality',
                options: ImageQuality.values,
                label: (q) => q.label,
                subtitle: (q) => q.hint,
                selected: s.quality,
                icon: (_) => PhosphorIconsRegular.image,
              );
              if (q != null) s.setQuality = q;
            },
          ),
          GlassTile(
            icon: PhosphorIconsRegular.fileDashed,
            title: 'PDF page size',
            subtitle: s.pageSize.label,
            trailing: arrow(),
            onTap: () async {
              final v = await pickOption<PageSizeOption>(
                context,
                title: 'PDF page size',
                options: PageSizeOption.values,
                label: (v) => v.label,
                selected: s.pageSize,
                icon: (_) => PhosphorIconsRegular.fileDashed,
              );
              if (v != null) s.setPageSize = v;
            },
          ),
        ]),

        const SectionLabel('Text recognition'),
        group([
          GlassTile(
            icon: PhosphorIconsRegular.textAa,
            title: 'Read text automatically',
            subtitle: 'Makes scans searchable and PDFs selectable',
            trailing: Switch(value: s.autoOcr, onChanged: (v) => s.setAutoOcr = v),
            onTap: () => s.setAutoOcr = !s.autoOcr,
          ),
          GlassTile(
            icon: PhosphorIconsRegular.tag,
            title: 'Smart file names',
            subtitle: 'Name scans from their first line of text',
            trailing: Switch(value: s.smartNames, onChanged: (v) => s.setSmartNames = v),
            onTap: () => s.setSmartNames = !s.smartNames,
          ),
          GlassTile(
            icon: PhosphorIconsRegular.textbox,
            title: 'Name prefix',
            subtitle: '“${s.namePrefix} 16 Oct 2026, 10.30”',
            trailing: arrow(),
            onTap: () async {
              final v = await promptText(context, title: 'Name prefix', initial: s.namePrefix);
              if (v != null && v.trim().isNotEmpty) s.setNamePrefix = v.trim();
            },
          ),
        ]),

        const SectionLabel('Privacy & security'),
        group([
          GlassTile(
            icon: PhosphorIconsRegular.fingerprint,
            title: 'App Lock',
            subtitle: 'Fingerprint, face or screen lock to open DocMind',
            trailing: Switch(value: s.appLock, onChanged: (v) => _toggleLock(s, v)),
            onTap: () => _toggleLock(s, !s.appLock),
          ),
          GlassTile(
            icon: PhosphorIconsRegular.signature,
            title: 'Saved signature',
            subtitle: s.savedSignature == null ? 'None — draw one to reuse it' : 'Tap to redraw',
            trailing: s.savedSignature == null
                ? arrow()
                : IconButton(
                    tooltip: 'Delete signature',
                    onPressed: () async {
                      final f = File(p.join(store.root.path, s.savedSignature!));
                      if (await f.exists()) await f.delete();
                      s.setSavedSignature = null;
                    },
                    icon: PhosphorIcon(PhosphorIconsRegular.trash, color: g.danger),
                  ),
            onTap: () => Navigator.of(context).push(MaterialPageRoute(builder: (_) => const SignaturePadScreen())),
          ),
          GlassTile(
            icon: PhosphorIconsRegular.vibrate,
            title: 'Haptic feedback',
            trailing: Switch(value: s.haptics, onChanged: (v) => s.setHaptics = v),
            onTap: () => s.setHaptics = !s.haptics,
          ),
        ]),

        const SectionLabel('Storage'),
        group([
          FutureBuilder<(int, int)>(
            future: _usage,
            builder: (_, snap) => GlassTile(
              icon: PhosphorIconsRegular.hardDrives,
              title: 'Documents',
              subtitle: snap.hasData
                  ? '${store.docs.length} documents · ${formatBytes(snap.data!.$1)}'
                  : 'Calculating…',
            ),
          ),
          FutureBuilder<(int, int)>(
            future: _usage,
            builder: (_, snap) => GlassTile(
              icon: PhosphorIconsRegular.broom,
              title: 'Clear temporary files',
              subtitle: snap.hasData ? 'Exports and shares · ${formatBytes(snap.data!.$2)}' : 'Calculating…',
              onTap: () async {
                await store.clearCache();
                if (!mounted) return;
                setState(() => _usage = store.storageUsage());
                toast(context, 'Temporary files cleared');
              },
            ),
          ),
        ]),

        const SectionLabel('About'),
        group([
          GlassTile(
            icon: PhosphorIconsRegular.scan,
            title: 'DocMind 1.0',
            subtitle: 'Offline scanner · nothing leaves your phone unless you share it',
          ),
        ]),
      ],
    );
  }
}

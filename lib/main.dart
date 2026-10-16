import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:pdfrx/pdfrx.dart';
import 'package:provider/provider.dart';

import 'app/theme.dart';
import 'core/library_store.dart';
import 'core/settings.dart';
import 'screens/lock_gate.dart';
import 'screens/shell.dart';

Future<void> main() async {
  WidgetsFlutterBinding.ensureInitialized();
  SystemChrome.setEnabledSystemUIMode(SystemUiMode.edgeToEdge);
  SystemChrome.setSystemUIOverlayStyle(const SystemUiOverlayStyle(
    statusBarColor: Colors.transparent,
    systemNavigationBarColor: Colors.transparent,
    systemNavigationBarContrastEnforced: false,
  ));
  await pdfrxFlutterInitialize();
  final settings = SettingsStore();
  await settings.load();
  final library = LibraryStore(settings);
  await library.init();
  runApp(MultiProvider(
    providers: [
      ChangeNotifierProvider.value(value: settings),
      ChangeNotifierProvider.value(value: library),
    ],
    child: const DocMindApp(),
  ));
}

class DocMindApp extends StatelessWidget {
  const DocMindApp({super.key});

  @override
  Widget build(BuildContext context) {
    final mode = context.select<SettingsStore, ThemeMode>((s) => s.themeMode);
    final accent = context.select<SettingsStore, AccentPalette>((s) => s.accent);
    return MaterialApp(
      title: 'DocMind',
      debugShowCheckedModeBanner: false,
      themeMode: mode,
      theme: buildTheme(dark: false, accent: accent),
      darkTheme: buildTheme(dark: true, accent: accent),
      themeAnimationDuration: const Duration(milliseconds: 220),
      builder: (context, child) => LockGate(child: child!),
      home: const HomeShell(),
    );
  }
}

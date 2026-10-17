import 'package:flutter/material.dart';
import 'package:flutter/services.dart';

/// Accent palettes the user can pick in Settings. Solid colours only —
/// no gradients — for a calm, premium look. "Mono" follows the theme:
/// white accents in dark mode, near-black in light mode.
class AccentPalette {
  final String name;
  final Color primary;
  final Color secondary;
  const AccentPalette(this.name, this.primary, [Color? secondary]) : secondary = secondary ?? primary;

  bool get isMono => name == 'Mono';

  /// Kept for call sites that paint with a shader; it is a flat fill.
  LinearGradient get gradient => LinearGradient(colors: [primary, primary]);

  AccentPalette resolve(bool dark) => isMono
      ? AccentPalette('Mono', dark ? const Color(0xFFF5F5F4) : const Color(0xFF141416))
      : this;
}

const accentPalettes = <AccentPalette>[
  AccentPalette('Mono', Color(0xFFF5F5F4)),
  AccentPalette('Ocean', Color(0xFF3478F6)),
  AccentPalette('Jade', Color(0xFF1FA67A)),
  AccentPalette('Amber', Color(0xFFE59A2F)),
  AccentPalette('Crimson', Color(0xFFE5484D)),
];

/// Design tokens that change with brightness. Read with `Glass.of(context)`.
@immutable
class Glass extends ThemeExtension<Glass> {
  final Color background;
  final List<Color> blobs;
  final Color fill;
  final Color fillStrong;
  final Color border;
  final Color text;
  final Color muted;
  final Color faint;
  final Color danger;
  final Color success;
  final AccentPalette accent;

  /// Text/icon colour that sits on top of an accent fill.
  final Color onAccent;
  final bool dark;

  const Glass({
    required this.background,
    required this.blobs,
    required this.fill,
    required this.fillStrong,
    required this.border,
    required this.text,
    required this.muted,
    required this.faint,
    required this.danger,
    required this.success,
    required this.accent,
    required this.onAccent,
    required this.dark,
  });

  static Glass of(BuildContext context) => Theme.of(context).extension<Glass>()!;

  static Color _on(Color c) => c.computeLuminance() > 0.45 ? const Color(0xFF111113) : Colors.white;

  factory Glass.dark(AccentPalette palette) {
    final accent = palette.resolve(true);
    return Glass(
      background: const Color(0xFF0B0B0C),
      blobs: [
        const Color(0xFFFFFFFF).withValues(alpha: 0.035),
        const Color(0xFFFFFFFF).withValues(alpha: 0.0),
        const Color(0xFFFFFFFF).withValues(alpha: 0.0),
      ],
      fill: const Color(0xFF17171A),
      fillStrong: const Color(0xFF1C1C20).withValues(alpha: 0.96),
      border: const Color(0xFFFFFFFF).withValues(alpha: 0.07),
      text: const Color(0xFFF5F5F4),
      muted: const Color(0xFF8E8E93),
      faint: const Color(0xFFFFFFFF).withValues(alpha: 0.05),
      danger: const Color(0xFFFF5F57),
      success: const Color(0xFF32D399),
      accent: accent,
      onAccent: _on(accent.primary),
      dark: true,
    );
  }

  factory Glass.light(AccentPalette palette) {
    final accent = palette.resolve(false);
    return Glass(
      background: const Color(0xFFF4F4F5),
      blobs: [
        const Color(0xFFFFFFFF).withValues(alpha: 0.8),
        const Color(0xFFFFFFFF).withValues(alpha: 0.0),
        const Color(0xFFFFFFFF).withValues(alpha: 0.0),
      ],
      fill: const Color(0xFFFFFFFF),
      fillStrong: const Color(0xFFFFFFFF).withValues(alpha: 0.97),
      border: const Color(0xFF000000).withValues(alpha: 0.07),
      text: const Color(0xFF111113),
      muted: const Color(0xFF6E6E73),
      faint: const Color(0xFF000000).withValues(alpha: 0.045),
      danger: const Color(0xFFD70015),
      success: const Color(0xFF0B8A5E),
      accent: accent,
      onAccent: _on(accent.primary),
      dark: false,
    );
  }

  @override
  Glass copyWith() => this;

  @override
  Glass lerp(ThemeExtension<Glass>? other, double t) =>
      (other is Glass && t > 0.5) ? other : this;
}

/// Light, quick page transition: fade with a tiny upward drift.
class SoftPageTransitionsBuilder extends PageTransitionsBuilder {
  const SoftPageTransitionsBuilder();

  @override
  Duration get transitionDuration => const Duration(milliseconds: 260);

  @override
  Duration get reverseTransitionDuration => const Duration(milliseconds: 200);

  @override
  Widget buildTransitions<T>(
    PageRoute<T> route,
    BuildContext context,
    Animation<double> animation,
    Animation<double> secondaryAnimation,
    Widget child,
  ) {
    final curved = CurvedAnimation(
      parent: animation,
      curve: Curves.easeOutCubic,
      reverseCurve: Curves.easeInCubic,
    );
    return FadeTransition(
      opacity: curved,
      child: SlideTransition(
        position: Tween(begin: const Offset(0, 0.025), end: Offset.zero).animate(curved),
        child: child,
      ),
    );
  }
}

ThemeData buildTheme({required bool dark, required AccentPalette accent}) {
  final glass = dark ? Glass.dark(accent) : Glass.light(accent);
  accent = glass.accent;
  final scheme = ColorScheme.fromSeed(
    seedColor: accent.primary,
    brightness: dark ? Brightness.dark : Brightness.light,
  ).copyWith(
    primary: accent.primary,
    onPrimary: glass.onAccent,
    secondary: accent.secondary,
    surface: dark ? const Color(0xFF161618) : const Color(0xFFFFFFFF),
    error: glass.danger,
  );
  const transitions = SoftPageTransitionsBuilder();
  final base = ThemeData(
    useMaterial3: true,
    fontFamily: 'Manrope',
    brightness: dark ? Brightness.dark : Brightness.light,
    colorScheme: scheme,
  );
  return base.copyWith(
    scaffoldBackgroundColor: glass.background,
    extensions: [glass],
    textTheme: base.textTheme.apply(
      bodyColor: glass.text,
      displayColor: glass.text,
      fontFamily: 'Manrope',
    ),
    splashFactory: InkSparkle.splashFactory,
    pageTransitionsTheme: const PageTransitionsTheme(builders: {
      TargetPlatform.android: transitions,
      TargetPlatform.iOS: transitions,
      TargetPlatform.linux: transitions,
      TargetPlatform.macOS: transitions,
      TargetPlatform.windows: transitions,
    }),
    appBarTheme: AppBarTheme(
      backgroundColor: Colors.transparent,
      elevation: 0,
      scrolledUnderElevation: 0,
      foregroundColor: glass.text,
      systemOverlayStyle: dark ? SystemUiOverlayStyle.light : SystemUiOverlayStyle.dark,
    ),
    dialogTheme: DialogThemeData(
      backgroundColor: dark ? const Color(0xFF1A1A1D) : Colors.white,
      shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(24)),
    ),
    bottomSheetTheme: const BottomSheetThemeData(
      backgroundColor: Colors.transparent,
      elevation: 0,
    ),
    snackBarTheme: SnackBarThemeData(
      behavior: SnackBarBehavior.floating,
      backgroundColor: dark ? const Color(0xFF262629) : const Color(0xFF141416),
      contentTextStyle: const TextStyle(color: Colors.white, fontWeight: FontWeight.w500),
      shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(14)),
    ),
    inputDecorationTheme: InputDecorationTheme(
      filled: true,
      fillColor: glass.faint,
      border: OutlineInputBorder(
        borderRadius: BorderRadius.circular(14),
        borderSide: BorderSide.none,
      ),
      contentPadding: const EdgeInsets.symmetric(horizontal: 16, vertical: 14),
    ),
    switchTheme: SwitchThemeData(
      thumbColor: WidgetStateProperty.resolveWith(
        (s) => s.contains(WidgetState.selected) ? glass.onAccent : Colors.white,
      ),
      trackColor: WidgetStateProperty.resolveWith(
        (s) => s.contains(WidgetState.selected) ? accent.primary : glass.muted.withValues(alpha: 0.35),
      ),
      trackOutlineColor: WidgetStateProperty.all(Colors.transparent),
    ),
  );
}

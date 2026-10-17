import 'package:flutter/material.dart';
import 'package:flutter/services.dart';

/// Accent palettes the user can pick in Settings.
class AccentPalette {
  final String name;
  final Color primary;
  final Color secondary;
  const AccentPalette(this.name, this.primary, this.secondary);

  LinearGradient get gradient => LinearGradient(
        colors: [primary, secondary],
        begin: Alignment.topLeft,
        end: Alignment.bottomRight,
      );
}

/// Refined single-hue accents: each gradient stays within one colour family.
const accentPalettes = <AccentPalette>[
  AccentPalette('Sapphire', Color(0xFF3B7BFF), Color(0xFF2456E0)),
  AccentPalette('Emerald', Color(0xFF17B890), Color(0xFF0B8F6C)),
  AccentPalette('Champagne', Color(0xFFD8B26A), Color(0xFFB98D3E)),
  AccentPalette('Ruby', Color(0xFFE5484D), Color(0xFFC0303A)),
  AccentPalette('Graphite', Color(0xFF8C96AA), Color(0xFF5F6A80)),
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
    required this.dark,
  });

  static Glass of(BuildContext context) => Theme.of(context).extension<Glass>()!;

  factory Glass.dark(AccentPalette accent) => Glass(
        background: const Color(0xFF0A0B0E),
        blobs: [
          accent.primary.withValues(alpha: 0.16),
          const Color(0xFFFFFFFF).withValues(alpha: 0.025),
          accent.secondary.withValues(alpha: 0.08),
        ],
        fill: const Color(0xFFFFFFFF).withValues(alpha: 0.045),
        fillStrong: const Color(0xFF16181E).withValues(alpha: 0.86),
        border: const Color(0xFFFFFFFF).withValues(alpha: 0.08),
        text: const Color(0xFFF2F3F5),
        muted: const Color(0xFF9097A3),
        faint: const Color(0xFFFFFFFF).withValues(alpha: 0.04),
        danger: const Color(0xFFFF5A64),
        success: const Color(0xFF2FCB8F),
        accent: accent,
        dark: true,
      );

  factory Glass.light(AccentPalette accent) => Glass(
        background: const Color(0xFFF3F4F6),
        blobs: [
          accent.primary.withValues(alpha: 0.10),
          const Color(0xFFFFFFFF).withValues(alpha: 0.7),
          accent.secondary.withValues(alpha: 0.05),
        ],
        fill: const Color(0xFFFFFFFF).withValues(alpha: 0.78),
        fillStrong: const Color(0xFFFFFFFF).withValues(alpha: 0.92),
        border: const Color(0xFF0F1115).withValues(alpha: 0.07),
        text: const Color(0xFF0F1115),
        muted: const Color(0xFF5C6370),
        faint: const Color(0xFF0F1115).withValues(alpha: 0.045),
        danger: const Color(0xFFD7263D),
        success: const Color(0xFF0E9F6E),
        accent: accent,
        dark: false,
      );

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
  final scheme = ColorScheme.fromSeed(
    seedColor: accent.primary,
    brightness: dark ? Brightness.dark : Brightness.light,
  ).copyWith(
    primary: accent.primary,
    secondary: accent.secondary,
    surface: dark ? const Color(0xFF131519) : const Color(0xFFFFFFFF),
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
      backgroundColor: dark ? const Color(0xFF17191F) : Colors.white,
      shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(24)),
    ),
    bottomSheetTheme: const BottomSheetThemeData(
      backgroundColor: Colors.transparent,
      elevation: 0,
    ),
    snackBarTheme: SnackBarThemeData(
      behavior: SnackBarBehavior.floating,
      backgroundColor: dark ? const Color(0xFF22252D) : const Color(0xFF15171C),
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
      thumbColor: WidgetStateProperty.all(Colors.white),
      trackColor: WidgetStateProperty.resolveWith(
        (s) => s.contains(WidgetState.selected) ? accent.primary : glass.muted.withValues(alpha: 0.35),
      ),
      trackOutlineColor: WidgetStateProperty.all(Colors.transparent),
    ),
  );
}

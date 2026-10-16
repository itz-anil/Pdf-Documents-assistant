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

const accentPalettes = <AccentPalette>[
  AccentPalette('Indigo', Color(0xFF6366F1), Color(0xFF8B5CF6)),
  AccentPalette('Ocean', Color(0xFF0EA5E9), Color(0xFF6366F1)),
  AccentPalette('Mint', Color(0xFF10B981), Color(0xFF0EA5A4)),
  AccentPalette('Sunset', Color(0xFFF97316), Color(0xFFEC4899)),
  AccentPalette('Rose', Color(0xFFE11D48), Color(0xFF9333EA)),
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
        background: const Color(0xFF090B12),
        blobs: [
          accent.primary.withValues(alpha: 0.38),
          const Color(0xFF00BFB3).withValues(alpha: 0.20),
          accent.secondary.withValues(alpha: 0.30),
        ],
        fill: Colors.white.withValues(alpha: 0.07),
        fillStrong: const Color(0xFF161A26).withValues(alpha: 0.72),
        border: Colors.white.withValues(alpha: 0.12),
        text: const Color(0xFFF3F5FB),
        muted: const Color(0xFFA5ABBD),
        faint: Colors.white.withValues(alpha: 0.05),
        danger: const Color(0xFFFF6B7A),
        success: const Color(0xFF34D399),
        accent: accent,
        dark: true,
      );

  factory Glass.light(AccentPalette accent) => Glass(
        background: const Color(0xFFEFF2F9),
        blobs: [
          accent.primary.withValues(alpha: 0.22),
          const Color(0xFF00BFB3).withValues(alpha: 0.14),
          accent.secondary.withValues(alpha: 0.18),
        ],
        fill: Colors.white.withValues(alpha: 0.62),
        fillStrong: Colors.white.withValues(alpha: 0.80),
        border: Colors.white.withValues(alpha: 0.85),
        text: const Color(0xFF11131B),
        muted: const Color(0xFF586074),
        faint: const Color(0xFF11131B).withValues(alpha: 0.05),
        danger: const Color(0xFFD92D45),
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
    surface: dark ? const Color(0xFF12151F) : const Color(0xFFF7F8FC),
    error: glass.danger,
  );
  const transitions = SoftPageTransitionsBuilder();
  final base = ThemeData(
    useMaterial3: true,
    brightness: dark ? Brightness.dark : Brightness.light,
    colorScheme: scheme,
  );
  return base.copyWith(
    scaffoldBackgroundColor: glass.background,
    extensions: [glass],
    textTheme: base.textTheme.apply(
      bodyColor: glass.text,
      displayColor: glass.text,
      fontFamilyFallback: const ['Roboto', 'Noto Sans Devanagari'],
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
      backgroundColor: dark ? const Color(0xFF171B27) : Colors.white,
      shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(24)),
    ),
    bottomSheetTheme: const BottomSheetThemeData(
      backgroundColor: Colors.transparent,
      elevation: 0,
    ),
    snackBarTheme: SnackBarThemeData(
      behavior: SnackBarBehavior.floating,
      backgroundColor: dark ? const Color(0xFF232838) : const Color(0xFF1B1E29),
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

import 'dart:ui';

import 'package:flutter/material.dart';
import '../app/icons.dart';

import '../app/theme.dart';

/// Static gradient background with soft colour blobs. Painted once; cheap.
class GlassBackground extends StatelessWidget {
  final Widget child;
  const GlassBackground({super.key, required this.child});

  @override
  Widget build(BuildContext context) {
    final g = Glass.of(context);
    return DecoratedBox(
      decoration: BoxDecoration(color: g.background),
      child: Stack(
        children: [
          Positioned.fill(
            child: RepaintBoundary(
              child: CustomPaint(painter: _BlobPainter(g.blobs)),
            ),
          ),
          child,
        ],
      ),
    );
  }
}

class _BlobPainter extends CustomPainter {
  final List<Color> colors;
  _BlobPainter(this.colors);

  @override
  void paint(Canvas canvas, Size size) {
    void blob(Offset c, double r, Color color) {
      final paint = Paint()
        ..shader = RadialGradient(colors: [color, color.withValues(alpha: 0)])
            .createShader(Rect.fromCircle(center: c, radius: r));
      canvas.drawCircle(c, r, paint);
    }

    blob(Offset(size.width * 0.05, size.height * 0.05), size.width * 0.85, colors[0]);
    blob(Offset(size.width * 1.0, size.height * 0.38), size.width * 0.75, colors[1]);
    blob(Offset(size.width * 0.2, size.height * 0.95), size.width * 0.9, colors[2]);
  }

  @override
  bool shouldRepaint(_BlobPainter old) => old.colors != colors;
}

/// Frosted panel. Use [blur] only for floating chrome (bars, sheets);
/// list items look glassy without the cost of a backdrop filter.
class GlassPanel extends StatelessWidget {
  final Widget child;
  final EdgeInsetsGeometry? padding;
  final EdgeInsetsGeometry? margin;
  final double radius;
  final bool blur;
  final bool strong;
  final Color? color;
  final VoidCallback? onTap;
  final VoidCallback? onLongPress;
  final Border? borderOverride;

  const GlassPanel({
    super.key,
    required this.child,
    this.padding,
    this.margin,
    this.radius = 22,
    this.blur = false,
    this.strong = false,
    this.color,
    this.onTap,
    this.onLongPress,
    this.borderOverride,
  });

  @override
  Widget build(BuildContext context) {
    final g = Glass.of(context);
    final shape = BorderRadius.circular(radius);
    Widget content = Container(
      padding: padding,
      decoration: BoxDecoration(
        color: color ?? (strong ? g.fillStrong : g.fill),
        borderRadius: shape,
        border: borderOverride ?? Border.all(color: g.border, width: 1),
      ),
      child: child,
    );
    if (onTap != null || onLongPress != null) {
      content = Pressable(onTap: onTap, onLongPress: onLongPress, child: content);
    }
    if (blur) {
      content = ClipRRect(
        borderRadius: shape,
        child: BackdropFilter(
          filter: ImageFilter.blur(sigmaX: 22, sigmaY: 22),
          child: content,
        ),
      );
    }
    if (margin != null) content = Padding(padding: margin!, child: content);
    return content;
  }
}

/// Gentle scale-down on press. Gives every tappable surface a tactile feel.
class Pressable extends StatefulWidget {
  final Widget child;
  final VoidCallback? onTap;
  final VoidCallback? onLongPress;
  final double scale;
  const Pressable({super.key, required this.child, this.onTap, this.onLongPress, this.scale = 0.97});

  @override
  State<Pressable> createState() => _PressableState();
}

class _PressableState extends State<Pressable> {
  bool _down = false;

  void _set(bool v) {
    if (_down != v) setState(() => _down = v);
  }

  @override
  Widget build(BuildContext context) {
    final enabled = widget.onTap != null || widget.onLongPress != null;
    return GestureDetector(
      behavior: HitTestBehavior.opaque,
      onTapDown: enabled ? (_) => _set(true) : null,
      onTapUp: enabled ? (_) => _set(false) : null,
      onTapCancel: enabled ? () => _set(false) : null,
      onTap: widget.onTap,
      onLongPress: widget.onLongPress,
      child: AnimatedScale(
        scale: _down ? widget.scale : 1,
        duration: const Duration(milliseconds: 120),
        curve: Curves.easeOut,
        child: widget.child,
      ),
    );
  }
}

/// App icon renderer: duotone Phosphor icons tinted with the accent.
class AppIcon extends StatelessWidget {
  final IconData icon;
  final double size;
  final Color? color;
  const AppIcon(this.icon, {super.key, this.size = 22, this.color});

  @override
  Widget build(BuildContext context) {
    final g = Glass.of(context);
    final c = color ?? g.text;
    return PhosphorIcon(icon, size: size, color: c, duotoneSecondaryOpacity: 0.28);
  }
}

/// Rounded square with gradient fill holding an icon — the "premium" tile.
class IconBadge extends StatelessWidget {
  final IconData icon;
  final double size;
  final bool filled;
  final Color? tint;
  const IconBadge(this.icon, {super.key, this.size = 48, this.filled = false, this.tint});

  @override
  Widget build(BuildContext context) {
    final g = Glass.of(context);
    final base = tint ?? g.accent.primary;
    return Container(
      width: size,
      height: size,
      decoration: BoxDecoration(
        borderRadius: BorderRadius.circular(size * 0.32),
        gradient: filled
            ? LinearGradient(
                colors: [base, tint == null ? g.accent.secondary : base.withValues(alpha: 0.75)],
                begin: Alignment.topLeft,
                end: Alignment.bottomRight,
              )
            : null,
        color: filled ? null : base.withValues(alpha: g.dark ? 0.16 : 0.11),
        border: Border.all(color: base.withValues(alpha: filled ? 0 : 0.18)),
        boxShadow: filled
            ? [BoxShadow(color: base.withValues(alpha: 0.35), blurRadius: 16, offset: const Offset(0, 6))]
            : null,
      ),
      alignment: Alignment.center,
      child: PhosphorIcon(
        icon,
        size: size * 0.5,
        color: filled ? Colors.white : base,
        duotoneSecondaryOpacity: filled ? 0.4 : 0.3,
        duotoneSecondaryColor: filled ? Colors.white : null,
      ),
    );
  }
}

/// Circular glass button holding a single icon.
class GlassIconButton extends StatelessWidget {
  final IconData icon;
  final VoidCallback? onTap;
  final String tooltip;
  final double size;
  final Color? color;
  const GlassIconButton({
    super.key,
    required this.icon,
    required this.onTap,
    required this.tooltip,
    this.size = 44,
    this.color,
  });

  @override
  Widget build(BuildContext context) {
    final g = Glass.of(context);
    return Tooltip(
      message: tooltip,
      child: Semantics(
        button: true,
        label: tooltip,
        child: Pressable(
          onTap: onTap,
          scale: 0.9,
          child: Container(
            width: size,
            height: size,
            decoration: BoxDecoration(
              color: g.fill,
              shape: BoxShape.circle,
              border: Border.all(color: g.border),
            ),
            alignment: Alignment.center,
            child: AppIcon(icon, size: size * 0.48, color: color ?? g.text),
          ),
        ),
      ),
    );
  }
}

/// Primary gradient button.
class GradientButton extends StatelessWidget {
  final String label;
  final IconData? icon;
  final VoidCallback? onTap;
  final bool expand;
  final double height;
  const GradientButton({
    super.key,
    required this.label,
    this.icon,
    required this.onTap,
    this.expand = false,
    this.height = 52,
  });

  @override
  Widget build(BuildContext context) {
    final g = Glass.of(context);
    final enabled = onTap != null;
    return Semantics(
      button: true,
      enabled: enabled,
      child: Pressable(
        onTap: onTap,
        child: AnimatedOpacity(
          opacity: enabled ? 1 : 0.45,
          duration: const Duration(milliseconds: 150),
          child: Container(
            height: height,
            width: expand ? double.infinity : null,
            padding: const EdgeInsets.symmetric(horizontal: 22),
            decoration: BoxDecoration(
              gradient: g.accent.gradient,
              borderRadius: BorderRadius.circular(16),
              boxShadow: [
                BoxShadow(
                  color: g.accent.primary.withValues(alpha: 0.35),
                  blurRadius: 18,
                  offset: const Offset(0, 8),
                ),
              ],
            ),
            child: Row(
              mainAxisSize: expand ? MainAxisSize.max : MainAxisSize.min,
              mainAxisAlignment: MainAxisAlignment.center,
              children: [
                if (icon != null) ...[
                  PhosphorIcon(icon!, color: Colors.white, size: 20, duotoneSecondaryColor: Colors.white),
                  const SizedBox(width: 8),
                ],
                Text(label,
                    style: const TextStyle(color: Colors.white, fontWeight: FontWeight.w700, fontSize: 15)),
              ],
            ),
          ),
        ),
      ),
    );
  }
}

/// Secondary outlined glass button.
class GlassButton extends StatelessWidget {
  final String label;
  final IconData? icon;
  final VoidCallback? onTap;
  final bool expand;
  final Color? color;
  const GlassButton({super.key, required this.label, this.icon, this.onTap, this.expand = false, this.color});

  @override
  Widget build(BuildContext context) {
    final g = Glass.of(context);
    final c = color ?? g.text;
    return Semantics(
      button: true,
      child: Pressable(
        onTap: onTap,
        child: Container(
          height: 52,
          width: expand ? double.infinity : null,
          padding: const EdgeInsets.symmetric(horizontal: 20),
          decoration: BoxDecoration(
            color: g.fill,
            borderRadius: BorderRadius.circular(16),
            border: Border.all(color: g.border),
          ),
          child: Row(
            mainAxisSize: expand ? MainAxisSize.max : MainAxisSize.min,
            mainAxisAlignment: MainAxisAlignment.center,
            children: [
              if (icon != null) ...[AppIcon(icon!, size: 20, color: c), const SizedBox(width: 8)],
              Text(label, style: TextStyle(color: c, fontWeight: FontWeight.w600, fontSize: 15)),
            ],
          ),
        ),
      ),
    );
  }
}

/// Top bar used on every secondary screen.
class GlassTopBar extends StatelessWidget {
  final String title;
  final String? subtitle;
  final List<Widget> actions;
  final bool showBack;
  final VoidCallback? onBack;
  const GlassTopBar({
    super.key,
    required this.title,
    this.subtitle,
    this.actions = const [],
    this.showBack = true,
    this.onBack,
  });

  @override
  Widget build(BuildContext context) {
    final g = Glass.of(context);
    return Padding(
      padding: const EdgeInsets.fromLTRB(16, 8, 16, 8),
      child: Row(
        children: [
          if (showBack) ...[
            GlassIconButton(
              icon: PhosphorIconsBold.caretLeft,
              tooltip: 'Back',
              onTap: onBack ?? () => Navigator.of(context).maybePop(),
            ),
            const SizedBox(width: 12),
          ],
          Expanded(
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              mainAxisSize: MainAxisSize.min,
              children: [
                Text(title,
                    maxLines: 1,
                    overflow: TextOverflow.ellipsis,
                    style: TextStyle(fontSize: 18, fontWeight: FontWeight.w700, color: g.text)),
                if (subtitle != null)
                  Text(subtitle!,
                      maxLines: 1,
                      overflow: TextOverflow.ellipsis,
                      style: TextStyle(fontSize: 12.5, color: g.muted)),
              ],
            ),
          ),
          for (final a in actions) ...[const SizedBox(width: 8), a],
        ],
      ),
    );
  }
}

/// Section label in small caps.
class SectionLabel extends StatelessWidget {
  final String text;
  final Widget? trailing;
  const SectionLabel(this.text, {super.key, this.trailing});

  @override
  Widget build(BuildContext context) {
    final g = Glass.of(context);
    return Padding(
      padding: const EdgeInsets.fromLTRB(4, 18, 4, 10),
      child: Row(
        children: [
          Expanded(
            child: Text(text.toUpperCase(),
                style: TextStyle(
                    fontSize: 12, letterSpacing: 1.1, fontWeight: FontWeight.w700, color: g.muted)),
          ),
          ?trailing,
        ],
      ),
    );
  }
}

/// Pill chip used for filters and segmented choices.
class GlassChip extends StatelessWidget {
  final String label;
  final bool selected;
  final VoidCallback onTap;
  final IconData? icon;
  const GlassChip({super.key, required this.label, required this.selected, required this.onTap, this.icon});

  @override
  Widget build(BuildContext context) {
    final g = Glass.of(context);
    return Pressable(
      onTap: onTap,
      child: AnimatedContainer(
        duration: const Duration(milliseconds: 180),
        curve: Curves.easeOut,
        height: 38,
        padding: const EdgeInsets.symmetric(horizontal: 14),
        decoration: BoxDecoration(
          gradient: selected ? g.accent.gradient : null,
          color: selected ? null : g.fill,
          borderRadius: BorderRadius.circular(19),
          border: Border.all(color: selected ? Colors.transparent : g.border),
        ),
        child: Row(
          mainAxisSize: MainAxisSize.min,
          children: [
            if (icon != null) ...[
              AppIcon(icon!, size: 16, color: selected ? Colors.white : g.muted),
              const SizedBox(width: 6),
            ],
            Text(label,
                style: TextStyle(
                  fontSize: 13,
                  fontWeight: FontWeight.w600,
                  color: selected ? Colors.white : g.text,
                )),
          ],
        ),
      ),
    );
  }
}

/// Bottom sheet wrapper with frosted surface and grab handle.
Future<T?> showGlassSheet<T>(BuildContext context, {required WidgetBuilder builder}) {
  return showModalBottomSheet<T>(
    context: context,
    isScrollControlled: true,
    useSafeArea: true,
    barrierColor: Colors.black.withValues(alpha: 0.35),
    builder: (ctx) {
      final g = Glass.of(ctx);
      return Padding(
        padding: EdgeInsets.only(bottom: MediaQuery.of(ctx).viewInsets.bottom),
        child: ClipRRect(
          borderRadius: const BorderRadius.vertical(top: Radius.circular(28)),
          child: BackdropFilter(
            filter: ImageFilter.blur(sigmaX: 28, sigmaY: 28),
            child: Container(
              decoration: BoxDecoration(
                color: g.dark ? const Color(0xFF141824).withValues(alpha: 0.88) : Colors.white.withValues(alpha: 0.9),
                border: Border(top: BorderSide(color: g.border)),
              ),
              child: SafeArea(
                top: false,
                child: Column(
                  mainAxisSize: MainAxisSize.min,
                  children: [
                    const SizedBox(height: 10),
                    Container(
                      width: 40,
                      height: 4,
                      decoration: BoxDecoration(
                        color: g.muted.withValues(alpha: 0.4),
                        borderRadius: BorderRadius.circular(2),
                      ),
                    ),
                    Flexible(child: builder(ctx)),
                  ],
                ),
              ),
            ),
          ),
        ),
      );
    },
  );
}

/// One row inside an action sheet / settings list.
class GlassTile extends StatelessWidget {
  final IconData icon;
  final String title;
  final String? subtitle;
  final Widget? trailing;
  final VoidCallback? onTap;
  final Color? tint;
  final bool danger;
  const GlassTile({
    super.key,
    required this.icon,
    required this.title,
    this.subtitle,
    this.trailing,
    this.onTap,
    this.tint,
    this.danger = false,
  });

  @override
  Widget build(BuildContext context) {
    final g = Glass.of(context);
    final c = danger ? g.danger : tint;
    return Semantics(
      button: onTap != null,
      child: InkWell(
        onTap: onTap,
        borderRadius: BorderRadius.circular(16),
        child: Padding(
          padding: const EdgeInsets.symmetric(horizontal: 14, vertical: 11),
          child: Row(
            children: [
              IconBadge(icon, size: 40, tint: c),
              const SizedBox(width: 14),
              Expanded(
                child: Column(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    Text(title,
                        style: TextStyle(
                            fontSize: 15, fontWeight: FontWeight.w600, color: danger ? g.danger : g.text)),
                    if (subtitle != null) ...[
                      const SizedBox(height: 2),
                      Text(subtitle!, style: TextStyle(fontSize: 12.5, color: g.muted)),
                    ],
                  ],
                ),
              ),
              ?trailing,
            ],
          ),
        ),
      ),
    );
  }
}

import 'dart:ui';

import 'package:flutter/material.dart';
import '../app/icons.dart';

import '../app/theme.dart';
import '../widgets/common.dart';
import '../widgets/glass.dart';
import 'home_screen.dart';
import 'scan_flow.dart';
import 'search_screen.dart';
import 'settings_screen.dart';
import 'tools_screen.dart';

class HomeShell extends StatefulWidget {
  const HomeShell({super.key});

  @override
  State<HomeShell> createState() => _HomeShellState();
}

class _HomeShellState extends State<HomeShell> {
  int _index = 0;

  static const _tabs = <(IconData, IconData, String)>[
    (PhosphorIconsRegular.house, PhosphorIconsFill.house, 'Home'),
    (PhosphorIconsRegular.magnifyingGlass, PhosphorIconsBold.magnifyingGlass, 'Search'),
    (PhosphorIconsRegular.squaresFour, PhosphorIconsFill.squaresFour, 'Tools'),
    (PhosphorIconsRegular.gearSix, PhosphorIconsFill.gearSix, 'Settings'),
  ];

  void _select(int i) {
    if (i == _index) return;
    haptic(context);
    setState(() => _index = i);
  }

  @override
  Widget build(BuildContext context) {
    final pages = [
      HomeScreen(onOpenSearch: () => _select(1)),
      const SearchScreen(),
      const ToolsScreen(),
      const SettingsScreen(),
    ];
    return PopScope(
      canPop: _index == 0,
      onPopInvokedWithResult: (didPop, _) {
        if (!didPop) _select(0);
      },
      child: Scaffold(
        extendBody: true,
        body: GlassBackground(
          child: AnimatedSwitcher(
            duration: const Duration(milliseconds: 220),
            switchInCurve: Curves.easeOutCubic,
            switchOutCurve: Curves.easeInCubic,
            transitionBuilder: (child, anim) => FadeTransition(opacity: anim, child: child),
            child: KeyedSubtree(key: ValueKey(_index), child: pages[_index]),
          ),
        ),
        bottomNavigationBar: _NavBar(
          index: _index,
          tabs: _tabs,
          onSelect: _select,
          onScan: () => ScanFlow.chooseAndScan(context),
        ),
      ),
    );
  }
}

class _NavBar extends StatelessWidget {
  final int index;
  final List<(IconData, IconData, String)> tabs;
  final ValueChanged<int> onSelect;
  final VoidCallback onScan;
  const _NavBar({required this.index, required this.tabs, required this.onSelect, required this.onScan});

  @override
  Widget build(BuildContext context) {
    final g = Glass.of(context);
    final bottom = MediaQuery.of(context).padding.bottom;
    Widget item(int i) {
      final (icon, active, label) = tabs[i];
      final selected = i == index;
      return Expanded(
        child: Semantics(
          button: true,
          selected: selected,
          label: label,
          child: Pressable(
            onTap: () => onSelect(i),
            scale: 0.9,
            child: SizedBox(
              height: 64,
              child: Column(
                mainAxisAlignment: MainAxisAlignment.center,
                children: [
                  AnimatedContainer(
                    duration: const Duration(milliseconds: 200),
                    curve: Curves.easeOut,
                    padding: const EdgeInsets.symmetric(horizontal: 14, vertical: 5),
                    decoration: BoxDecoration(
                      color: selected ? g.accent.primary.withValues(alpha: g.dark ? 0.22 : 0.14) : Colors.transparent,
                      borderRadius: BorderRadius.circular(14),
                    ),
                    child: PhosphorIcon(
                      selected ? active : icon,
                      size: 23,
                      color: selected ? g.accent.primary : g.muted,
                    ),
                  ),
                  const SizedBox(height: 3),
                  Text(label,
                      style: TextStyle(
                        fontSize: 11,
                        fontWeight: selected ? FontWeight.w700 : FontWeight.w500,
                        color: selected ? g.text : g.muted,
                      )),
                ],
              ),
            ),
          ),
        ),
      );
    }

    return Padding(
      padding: EdgeInsets.fromLTRB(14, 0, 14, bottom > 0 ? bottom : 12),
      child: ClipRRect(
        borderRadius: BorderRadius.circular(28),
        child: BackdropFilter(
          filter: ImageFilter.blur(sigmaX: 24, sigmaY: 24),
          child: Container(
            height: 72,
            decoration: BoxDecoration(
              color: g.dark ? const Color(0xFF151927).withValues(alpha: 0.72) : Colors.white.withValues(alpha: 0.72),
              borderRadius: BorderRadius.circular(28),
              border: Border.all(color: g.border),
            ),
            child: Row(
              children: [
                item(0),
                item(1),
                Semantics(
                  button: true,
                  label: 'Scan',
                  child: Pressable(
                    onTap: onScan,
                    scale: 0.9,
                    child: Container(
                      width: 60,
                      height: 52,
                      margin: const EdgeInsets.symmetric(horizontal: 6),
                      decoration: BoxDecoration(
                        gradient: g.accent.gradient,
                        borderRadius: BorderRadius.circular(18),
                        boxShadow: [
                          BoxShadow(
                            color: g.accent.primary.withValues(alpha: 0.45),
                            blurRadius: 18,
                            offset: const Offset(0, 6),
                          ),
                        ],
                      ),
                      alignment: Alignment.center,
                      child: const PhosphorIcon(PhosphorIconsBold.scan, color: Colors.white, size: 27),
                    ),
                  ),
                ),
                item(2),
                item(3),
              ],
            ),
          ),
        ),
      ),
    );
  }
}

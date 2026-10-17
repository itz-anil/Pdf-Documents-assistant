import 'package:flutter/material.dart';
import 'package:local_auth/local_auth.dart';
import '../app/icons.dart';
import 'package:provider/provider.dart';

import '../app/theme.dart';
import '../core/settings.dart';
import '../widgets/glass.dart';

/// Covers the app with a lock screen when App Lock is on.
/// Re-locks after the app has been in the background for a while.
class LockGate extends StatefulWidget {
  final Widget child;
  const LockGate({super.key, required this.child});

  /// Set while an external screen (camera, file picker) is open so returning
  /// from it does not ask to unlock again.
  static bool externalActivity = false;

  @override
  State<LockGate> createState() => _LockGateState();
}

class _LockGateState extends State<LockGate> with WidgetsBindingObserver {
  final _auth = LocalAuthentication();
  bool _locked = false;
  bool _authenticating = false;
  DateTime? _pausedAt;
  String? _error;

  @override
  void initState() {
    super.initState();
    WidgetsBinding.instance.addObserver(this);
    _locked = context.read<SettingsStore>().appLock;
    if (_locked) WidgetsBinding.instance.addPostFrameCallback((_) => _unlock());
  }

  @override
  void dispose() {
    WidgetsBinding.instance.removeObserver(this);
    super.dispose();
  }

  @override
  void didChangeAppLifecycleState(AppLifecycleState state) {
    final enabled = context.read<SettingsStore>().appLock;
    if (!enabled || _authenticating) return;
    if (state == AppLifecycleState.paused) {
      _pausedAt = DateTime.now();
    } else if (state == AppLifecycleState.resumed && _pausedAt != null) {
      final away = DateTime.now().difference(_pausedAt!);
      _pausedAt = null;
      if (!LockGate.externalActivity && away > const Duration(seconds: 45)) {
        setState(() => _locked = true);
        _unlock();
      }
    }
  }

  Future<void> _unlock() async {
    if (_authenticating) return;
    setState(() {
      _authenticating = true;
      _error = null;
    });
    try {
      final supported = await _auth.isDeviceSupported();
      if (!supported) {
        setState(() => _locked = false);
        return;
      }
      final ok = await _auth.authenticate(
        localizedReason: 'Unlock DocMind',
        biometricOnly: false,
        persistAcrossBackgrounding: true,
      );
      if (mounted) setState(() => _locked = !ok);
    } catch (e) {
      if (mounted) setState(() => _error = 'Could not verify. Try again.');
    } finally {
      if (mounted) setState(() => _authenticating = false);
    }
  }

  @override
  Widget build(BuildContext context) {
    return Stack(
      children: [
        widget.child,
        if (_locked) Positioned.fill(child: _LockScreen(onUnlock: _unlock, busy: _authenticating, error: _error)),
      ],
    );
  }
}

class _LockScreen extends StatelessWidget {
  final VoidCallback onUnlock;
  final bool busy;
  final String? error;
  const _LockScreen({required this.onUnlock, required this.busy, this.error});

  @override
  Widget build(BuildContext context) {
    final g = Glass.of(context);
    return Material(
      child: GlassBackground(
        child: SafeArea(
          child: Center(
            child: Column(
              mainAxisSize: MainAxisSize.min,
              children: [
                IconBadge(PhosphorIconsRegular.lockKey, filled: true, size: 88),
                const SizedBox(height: 26),
                Text('DocMind is locked',
                    style: TextStyle(fontSize: 22, fontWeight: FontWeight.w800, color: g.text)),
                const SizedBox(height: 8),
                Text('Use your fingerprint, face or screen lock',
                    style: TextStyle(color: g.muted)),
                if (error != null) ...[
                  const SizedBox(height: 12),
                  Text(error!, style: TextStyle(color: g.danger, fontWeight: FontWeight.w600)),
                ],
                const SizedBox(height: 30),
                GradientButton(
                  label: busy ? 'Waiting…' : 'Unlock',
                  icon: PhosphorIconsRegular.fingerprint,
                  onTap: busy ? null : onUnlock,
                ),
              ],
            ),
          ),
        ),
      ),
    );
  }
}

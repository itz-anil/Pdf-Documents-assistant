import 'dart:async';
import 'dart:io';
import 'dart:isolate';
import 'dart:math' as math;
import 'dart:ui' as ui;

import 'package:camera/camera.dart';
import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:google_mlkit_barcode_scanning/google_mlkit_barcode_scanning.dart';
import 'package:path/path.dart' as p;
import 'package:provider/provider.dart';

import '../app/icons.dart';
import '../app/theme.dart';
import '../core/edge_detect.dart';
import '../core/image_processing.dart';
import '../core/library_store.dart';
import '../core/models.dart';
import '../core/settings.dart';
import '../widgets/common.dart';
import '../widgets/glass.dart';
import 'lock_gate.dart';
import 'qr_result_sheet.dart';
import '../core/scan_service.dart';

/// Every capture mode the one shared camera supports.
enum CameraMode { whiteboard, book, document, idCard, businessCard, receipt, qr }

extension CameraModeInfo on CameraMode {
  String get label => switch (this) {
    CameraMode.whiteboard => 'Whiteboard',
    CameraMode.book => 'Book',
    CameraMode.document => 'Document',
    CameraMode.idCard => 'ID Card',
    CameraMode.businessCard => 'Business Card',
    CameraMode.receipt => 'Receipt',
    CameraMode.qr => 'QR Code',
  };

  ScanMode get scanMode => switch (this) {
    CameraMode.whiteboard => ScanMode.whiteboard,
    CameraMode.book => ScanMode.book,
    CameraMode.idCard => ScanMode.idCard,
    CameraMode.businessCard => ScanMode.businessCard,
    CameraMode.receipt => ScanMode.receipt,
    _ => ScanMode.document,
  };

  static CameraMode fromScan(ScanMode m) => switch (m) {
    ScanMode.whiteboard => CameraMode.whiteboard,
    ScanMode.book => CameraMode.book,
    ScanMode.idCard => CameraMode.idCard,
    ScanMode.businessCard => CameraMode.businessCard,
    ScanMode.receipt => CameraMode.receipt,
    ScanMode.document => CameraMode.document,
  };

  /// Shots this mode needs before it finishes on its own (null = any number).
  int? get autoFinishAt => switch (this) {
    CameraMode.idCard => 2,
    CameraMode.businessCard => 1,
    _ => null,
  };

  bool get detectsPages => this != CameraMode.qr;
}

/// One captured photo and its detected document outline.
class Shot {
  final String path;
  Quad? quad;
  int quarterTurns;
  Shot(this.path, this.quad, {this.quarterTurns = 0});
}

class CaptureResult {
  final CameraMode mode;
  final List<Shot> shots;
  const CaptureResult(this.mode, this.shots);
}

/// Full-screen camera shared by every scan mode: live edge detection,
/// auto-capture, flash, tap-to-focus, pinch-zoom, gallery import and QR.
class CameraScreen extends StatefulWidget {
  final CameraMode initialMode;

  /// Hide the mode carousel (e.g. adding pages to an existing document).
  final bool lockMode;

  /// Finish after this many shots (e.g. retaking a single page).
  final int? maxShots;

  /// Title shown for single-purpose captures, e.g. "Retake page".
  final String? purpose;

  /// Test hook: shown instead of the live camera.
  final Widget? previewOverride;

  const CameraScreen({
    super.key,
    this.initialMode = CameraMode.document,
    this.lockMode = false,
    this.maxShots,
    this.purpose,
    this.previewOverride,
  });

  static Future<CaptureResult?> open(
    BuildContext context, {
    CameraMode mode = CameraMode.document,
    bool lockMode = false,
    int? maxShots,
    String? purpose,
  }) {
    return Navigator.of(context).push<CaptureResult>(
      PageRouteBuilder(
        opaque: true,
        transitionDuration: const Duration(milliseconds: 260),
        reverseTransitionDuration: const Duration(milliseconds: 200),
        pageBuilder: (_, _, _) =>
            CameraScreen(initialMode: mode, lockMode: lockMode, maxShots: maxShots, purpose: purpose),
        transitionsBuilder: (_, anim, _, child) => FadeTransition(
          opacity: CurvedAnimation(parent: anim, curve: Curves.easeOut),
          child: ScaleTransition(
            scale: Tween(begin: 1.04, end: 1.0).animate(CurvedAnimation(parent: anim, curve: Curves.easeOutCubic)),
            child: child,
          ),
        ),
      ),
    );
  }

  @override
  State<CameraScreen> createState() => _CameraScreenState();
}

class _CameraScreenState extends State<CameraScreen> with WidgetsBindingObserver, TickerProviderStateMixin {
  CameraController? _controller;
  String? _error;
  bool _initializing = false;
  late CameraMode _mode = widget.initialMode;
  final List<Shot> _shots = [];
  late Directory _session;

  FlashMode _flash = FlashMode.off;
  late bool _auto;
  late bool _grid;

  // live detection
  Quad? _liveQuad;
  Quad? _shownQuad;
  bool _armed = true;
  bool _analysing = false;
  DateTime _lastAnalysis = DateTime.fromMillisecondsSinceEpoch(0);
  int _sensorDegrees = 90;
  bool _capturing = false;
  late final AnimationController _quadAnim = AnimationController(
    vsync: this,
    duration: const Duration(milliseconds: 160),
  );
  Quad? _fromQuad;
  late final AnimationController _flashAnim = AnimationController(
    vsync: this,
    duration: const Duration(milliseconds: 260),
  );
  late final AnimationController _progress = AnimationController(
    vsync: this,
    duration: const Duration(milliseconds: 1100),
  );

  // QR
  BarcodeScanner? _barcodes;
  bool _qrShowing = false;

  // zoom & focus
  double _minZoom = 1, _maxZoom = 1, _zoom = 1, _zoomStart = 1;
  Offset? _focusPoint;
  Timer? _focusTimer;

  @override
  void initState() {
    super.initState();
    final s = context.read<SettingsStore>();
    _auto = s.autoCapture;
    _grid = s.cameraGrid;
    WidgetsBinding.instance.addObserver(this);
    SystemChrome.setEnabledSystemUIMode(SystemUiMode.immersiveSticky);
    SystemChrome.setPreferredOrientations([DeviceOrientation.portraitUp]);
    _progress.addStatusListener((st) {
      if (st == AnimationStatus.completed) _autoCapture();
    });
    _start();
  }

  Future<void> _start() async {
    _session = await context.read<LibraryStore>().scratch('camera');
    if (widget.previewOverride == null) await _initCamera();
  }

  @override
  void dispose() {
    WidgetsBinding.instance.removeObserver(this);
    SystemChrome.setEnabledSystemUIMode(SystemUiMode.edgeToEdge);
    SystemChrome.setPreferredOrientations(DeviceOrientation.values);
    _focusTimer?.cancel();
    _quadAnim.dispose();
    _flashAnim.dispose();
    _progress.dispose();
    _barcodes?.close();
    _disposeCamera();
    super.dispose();
  }

  @override
  void didChangeAppLifecycleState(AppLifecycleState state) {
    if (widget.previewOverride != null) return;
    if (state == AppLifecycleState.inactive || state == AppLifecycleState.paused) {
      _disposeCamera();
    } else if (state == AppLifecycleState.resumed && _controller == null) {
      _initCamera();
    }
  }

  Future<void> _disposeCamera() async {
    final c = _controller;
    _controller = null;
    if (c == null) return;
    try {
      if (c.value.isStreamingImages) await c.stopImageStream();
    } catch (_) {}
    await c.dispose();
  }

  Future<void> _initCamera() async {
    if (_initializing) return;
    _initializing = true;
    setState(() => _error = null);
    try {
      final cams = await availableCameras();
      if (cams.isEmpty) throw CameraException('noCamera', 'No camera found on this device');
      final back = cams.firstWhere((c) => c.lensDirection == CameraLensDirection.back, orElse: () => cams.first);
      _sensorDegrees = back.sensorOrientation;
      final c = CameraController(
        back,
        ResolutionPreset.max,
        enableAudio: false,
        imageFormatGroup: ImageFormatGroup.nv21,
      );
      await c.initialize();
      await c.lockCaptureOrientation(DeviceOrientation.portraitUp);
      try {
        await c.setFlashMode(_flash);
        await c.setFocusMode(FocusMode.auto);
      } catch (_) {}
      _minZoom = await c.getMinZoomLevel();
      _maxZoom = math.min(await c.getMaxZoomLevel(), 8);
      _zoom = _minZoom;
      if (!mounted) {
        await c.dispose();
        return;
      }
      setState(() => _controller = c);
      await c.startImageStream(_onFrame);
    } on CameraException catch (e) {
      final denied = e.code.toLowerCase().contains('access') || e.code.toLowerCase().contains('permission');
      if (mounted) {
        setState(
          () => _error = denied
              ? 'DocMind needs camera access to scan. Allow Camera for DocMind in your phone settings, then try again.'
              : 'The camera could not start (${e.description ?? e.code}).',
        );
      }
    } catch (e) {
      if (mounted) setState(() => _error = 'The camera could not start. ${friendlyError(e)}');
    } finally {
      _initializing = false;
    }
  }

  // ------------------------------------------------------------ live frames

  void _onFrame(CameraImage frame) {
    if (_analysing || _capturing || !mounted) return;
    final now = DateTime.now();
    if (now.difference(_lastAnalysis) < const Duration(milliseconds: 140)) return;
    _lastAnalysis = now;
    _analysing = true;
    if (_mode == CameraMode.qr) {
      _scanQr(frame).whenComplete(() => _analysing = false);
      return;
    }
    final plane = frame.planes.first;
    final (luma, w, h) = subsampleLuma(plane.bytes, frame.width, frame.height, plane.bytesPerRow, target: 200);
    Isolate.run(() => detectQuad(luma, w, h))
        .then((q) {
          if (!mounted) return;
          _onQuad(q == null ? null : rotateQuad(q, _sensorDegrees));
        })
        .whenComplete(() => _analysing = false);
  }

  void _onQuad(Quad? q) {
    final prev = _liveQuad;
    _liveQuad = q;
    if (q == null) {
      _armed = true;
      if (_progress.isAnimating || _progress.value > 0) _progress.reset();
    } else {
      final moved = prev == null ? 1.0 : quadDistance(prev, q);
      if (moved > 0.12) _armed = true;
      if (moved > 0.03) {
        if (_progress.value > 0) _progress.reset();
      } else if (_auto && _armed && !_capturing && _mode.detectsPages && !_progress.isAnimating) {
        _progress.forward(from: 0);
      }
    }
    _fromQuad = _currentDisplayedQuad();
    _shownQuad = q;
    _quadAnim.forward(from: 0);
    setState(() {});
  }

  Quad? _currentDisplayedQuad() {
    final from = _fromQuad, to = _shownQuad;
    if (to == null) return null;
    if (from == null) return to;
    final t = Curves.easeOut.transform(_quadAnim.value);
    return [for (var i = 0; i < 8; i++) from[i] + (to[i] - from[i]) * t];
  }

  Future<void> _scanQr(CameraImage frame) async {
    if (_qrShowing) return;
    _barcodes ??= BarcodeScanner();
    final input = InputImage.fromBytes(
      bytes: frame.planes.first.bytes,
      metadata: InputImageMetadata(
        size: ui.Size(frame.width.toDouble(), frame.height.toDouble()),
        rotation: InputImageRotationValue.fromRawValue(_sensorDegrees) ?? InputImageRotation.rotation90deg,
        format: InputImageFormat.nv21,
        bytesPerRow: frame.planes.first.bytesPerRow,
      ),
    );
    final codes = await _barcodes!.processImage(input);
    final code = codes.where((c) => (c.rawValue ?? c.displayValue ?? '').isNotEmpty).firstOrNull;
    if (code == null || !mounted || _mode != CameraMode.qr) return;
    _qrShowing = true;
    HapticFeedback.mediumImpact();
    await showQrResult(context, code.rawValue ?? code.displayValue!, code.format.name);
    _qrShowing = false;
  }

  // -------------------------------------------------------------- capture

  void _autoCapture() {
    if (!_auto || !_armed || _liveQuad == null || _capturing) return;
    _armed = false;
    _capture();
  }

  Future<void> _capture() async {
    final c = _controller;
    if (_capturing || _mode == CameraMode.qr) return;
    if (c == null && widget.previewOverride == null) return;
    setState(() => _capturing = true);
    _progress.reset();
    _flashAnim.forward(from: 0);
    HapticFeedback.mediumImpact();
    try {
      final liveQuad = _liveQuad;
      final file = await c!.takePicture();
      final dest = p.join(_session.path, 'shot_${DateTime.now().microsecondsSinceEpoch}.jpg');
      await File(file.path).copy(dest);
      unawaited(File(file.path).delete().catchError((_) => File(file.path)));
      final detected = await detectQuadInFile(dest);
      _shots.add(Shot(dest, detected ?? liveQuad));
      if (!mounted) return;
      setState(() {});
      _afterShot();
    } catch (e) {
      if (mounted) toast(context, 'Could not take the photo. ${friendlyError(e)}', error: true);
    } finally {
      if (mounted) setState(() => _capturing = false);
    }
  }

  void _afterShot() {
    final limit = widget.maxShots ?? _mode.autoFinishAt;
    if (limit != null && _shots.length >= limit) {
      _finish();
      return;
    }
    if (_mode == CameraMode.idCard && _shots.length == 1) {
      toast(context, 'Front captured — now flip the card');
    }
  }

  Future<void> _fromGallery() async {
    LockGate.externalActivity = true;
    List<String> paths;
    try {
      paths = await ScanService.pickPhotos();
    } finally {
      LockGate.externalActivity = false;
    }
    if (paths.isEmpty || !mounted) return;
    final limit = widget.maxShots ?? _mode.autoFinishAt;
    if (limit != null) paths = paths.take(limit - _shots.length).toList();
    await runBusy(context, 'Finding page edges…', (_) async {
      for (final src in paths) {
        final dest = p.join(_session.path, 'gal_${DateTime.now().microsecondsSinceEpoch}.jpg');
        await normaliseImage(src, dest);
        _shots.add(Shot(dest, await detectQuadInFile(dest)));
      }
    });
    if (!mounted) return;
    setState(() {});
    _afterShot();
  }

  void _finish() {
    if (_shots.isEmpty) return;
    Navigator.of(context).pop(CaptureResult(_mode, List.of(_shots)));
  }

  Future<void> _close() async {
    if (_shots.isNotEmpty) {
      final ok = await confirm(
        context,
        title: 'Discard ${_shots.length} photo${_shots.length == 1 ? '' : 's'}?',
        message: 'The pages you captured will not be saved.',
        action: 'Discard',
      );
      if (!ok) return;
    }
    if (mounted) Navigator.of(context).pop();
  }

  Future<void> _setMode(CameraMode m) async {
    if (m == _mode) return;
    if (_shots.isNotEmpty) {
      final ok = await confirm(
        context,
        title: 'Switch to ${m.label}?',
        message:
            'The ${_shots.length} photo${_shots.length == 1 ? '' : 's'} taken in ${_mode.label} mode will be discarded.',
        action: 'Switch',
      );
      if (!ok) return;
      _shots.clear();
    }
    HapticFeedback.selectionClick();
    _progress.reset();
    setState(() {
      _mode = m;
      _liveQuad = null;
      _shownQuad = null;
      _fromQuad = null;
    });
  }

  Future<void> _cycleFlash() async {
    final next = switch (_flash) {
      FlashMode.off => FlashMode.auto,
      FlashMode.auto => FlashMode.always,
      FlashMode.always => FlashMode.torch,
      FlashMode.torch => FlashMode.off,
    };
    try {
      await _controller?.setFlashMode(next);
      setState(() => _flash = next);
    } catch (_) {
      if (mounted) toast(context, 'Flash is not available', error: true);
    }
  }

  Future<void> _focusAt(Offset local, Size box) async {
    final c = _controller;
    if (c == null) return;
    final pt = Offset((local.dx / box.width).clamp(0.0, 1.0), (local.dy / box.height).clamp(0.0, 1.0));
    setState(() => _focusPoint = local);
    _focusTimer?.cancel();
    _focusTimer = Timer(const Duration(milliseconds: 900), () {
      if (mounted) setState(() => _focusPoint = null);
    });
    try {
      await c.setFocusPoint(pt);
      await c.setExposurePoint(pt);
    } catch (_) {}
  }

  // --------------------------------------------------------------- build

  String get _hint {
    if (_mode == CameraMode.qr) return 'Point at a QR code or barcode';
    if (_capturing) return 'Capturing…';
    if (_mode == CameraMode.idCard) {
      return _shots.isEmpty ? 'ID card · front side' : 'Flip the card · back side';
    }
    if (_mode == CameraMode.businessCard) return 'Fit the card inside the frame';
    if (_mode == CameraMode.book) return 'Line up the spine with the centre line';
    if (_liveQuad == null) return 'Looking for a document…';
    return _auto ? (_armed ? 'Hold steady…' : 'Move to the next page') : 'Tap the shutter to capture';
  }

  @override
  Widget build(BuildContext context) {
    final g = Glass.of(context);
    final accent = g.accent.primary;
    final pad = MediaQuery.of(context).padding;
    final modes = widget.lockMode ? [_mode] : CameraMode.values;
    final title = widget.purpose;

    return PopScope(
      canPop: _shots.isEmpty,
      onPopInvokedWithResult: (didPop, _) {
        if (!didPop) _close();
      },
      child: Theme(
        data: Theme.of(context).copyWith(extensions: [Glass.dark(g.accent)]),
        child: Scaffold(
          backgroundColor: Colors.black,
          body: Stack(
            children: [
              Positioned.fill(child: _preview(accent)),
              // capture flash
              Positioned.fill(
                child: IgnorePointer(
                  child: AnimatedBuilder(
                    animation: _flashAnim,
                    builder: (_, _) => Container(
                      color: Colors.white.withValues(
                        alpha: (1 - _flashAnim.value) * (_flashAnim.isAnimating ? 0.55 : 0),
                      ),
                    ),
                  ),
                ),
              ),
              // top bar
              Positioned(
                left: 0,
                right: 0,
                top: 0,
                child: _Scrim(
                  top: true,
                  child: Padding(
                    padding: EdgeInsets.fromLTRB(14, pad.top + 10, 14, 18),
                    child: Row(
                      children: [
                        _RoundButton(icon: PhosphorIconsBold.x, label: 'Close camera', onTap: _close),
                        const Spacer(),
                        if (title != null)
                          Text(
                            title,
                            style: const TextStyle(color: Colors.white, fontWeight: FontWeight.w700, fontSize: 16),
                          ),
                        const Spacer(),
                        if (_mode != CameraMode.qr) ...[
                          _RoundButton(
                            icon: _grid ? PhosphorIconsFill.gridFour : PhosphorIconsRegular.gridFour,
                            label: 'Grid',
                            onTap: () {
                              setState(() => _grid = !_grid);
                              context.read<SettingsStore>().setCameraGrid = _grid;
                            },
                          ),
                          const SizedBox(width: 10),
                          _PillButton(
                            label: _auto ? 'Auto' : 'Manual',
                            active: _auto,
                            onTap: () {
                              setState(() => _auto = !_auto);
                              _progress.reset();
                              context.read<SettingsStore>().setAutoCapture = _auto;
                            },
                          ),
                          const SizedBox(width: 10),
                        ],
                        _RoundButton(
                          icon: switch (_flash) {
                            FlashMode.off => PhosphorIconsRegular.lightningSlash,
                            FlashMode.auto => PhosphorIconsRegular.lightningA,
                            FlashMode.always => PhosphorIconsFill.lightning,
                            FlashMode.torch => PhosphorIconsFill.flashlight,
                          },
                          label: 'Flash',
                          active: _flash != FlashMode.off,
                          onTap: _cycleFlash,
                        ),
                      ],
                    ),
                  ),
                ),
              ),
              // bottom controls
              Positioned(
                left: 0,
                right: 0,
                bottom: 0,
                child: _Scrim(
                  top: false,
                  child: Padding(
                    padding: EdgeInsets.only(bottom: pad.bottom + 18, top: 26),
                    child: Column(
                      mainAxisSize: MainAxisSize.min,
                      children: [
                        AnimatedSwitcher(
                          duration: const Duration(milliseconds: 180),
                          child: _HintPill(key: ValueKey(_hint), text: _hint, highlight: _liveQuad != null),
                        ),
                        if (_mode == CameraMode.idCard && _shots.length == 1) ...[
                          const SizedBox(height: 10),
                          TextButton(
                            onPressed: _finish,
                            style: TextButton.styleFrom(foregroundColor: Colors.white),
                            child: const Text('No back side — continue'),
                          ),
                        ],
                        const SizedBox(height: 14),
                        if (modes.length > 1)
                          _ModeCarousel(modes: modes, current: _mode, onSelect: _setMode, accent: accent),
                        const SizedBox(height: 18),
                        Padding(
                          padding: const EdgeInsets.symmetric(horizontal: 28),
                          child: Row(
                            children: [
                              SizedBox(
                                width: 64,
                                child: _mode == CameraMode.qr
                                    ? null
                                    : _RoundButton(
                                        icon: PhosphorIconsRegular.images,
                                        label: 'Choose from gallery',
                                        size: 52,
                                        onTap: _fromGallery,
                                      ),
                              ),
                              const Spacer(),
                              _Shutter(
                                enabled: _mode != CameraMode.qr && !_capturing,
                                busy: _capturing,
                                progress: _progress,
                                accent: accent,
                                onTap: _capture,
                              ),
                              const Spacer(),
                              SizedBox(
                                width: 64,
                                child: _shots.isEmpty
                                    ? null
                                    : _ShotStack(shots: _shots, accent: accent, onTap: _finish),
                              ),
                            ],
                          ),
                        ),
                      ],
                    ),
                  ),
                ),
              ),
            ],
          ),
        ),
      ),
    );
  }

  Widget _preview(Color accent) {
    if (_error != null) {
      return Center(
        child: Padding(
          padding: const EdgeInsets.all(32),
          child: Column(
            mainAxisSize: MainAxisSize.min,
            children: [
              const PhosphorIcon(PhosphorIconsRegular.cameraSlash, color: Colors.white, size: 56),
              const SizedBox(height: 18),
              Text(
                _error!,
                textAlign: TextAlign.center,
                style: const TextStyle(color: Colors.white, height: 1.45),
              ),
              const SizedBox(height: 22),
              GradientButton(label: 'Try again', onTap: _initCamera),
              const SizedBox(height: 10),
              TextButton(
                onPressed: _fromGallery,
                style: TextButton.styleFrom(foregroundColor: Colors.white),
                child: const Text('Choose photos instead'),
              ),
            ],
          ),
        ),
      );
    }
    final c = _controller;
    final override = widget.previewOverride;
    if (override == null && (c == null || !c.value.isInitialized)) {
      return const Center(child: CircularProgressIndicator(color: Colors.white));
    }
    // Preview frames are landscape; on a portrait phone they show rotated.
    final ps = c?.value.previewSize ?? const Size(1440, 1080);
    final frame = Size(ps.height, ps.width);
    return LayoutBuilder(
      builder: (_, box) {
        // Full-width 4:3 preview (like Adobe Scan): the whole frame that will be
        // captured stays visible; controls sit in the bars above and below.
        final w = box.maxWidth;
        final h = math.min(box.maxHeight, w * frame.height / frame.width);
        final pad = MediaQuery.of(context).padding.top;
        final spare = box.maxHeight - h;
        final top = spare <= 0 ? 0.0 : math.min(spare, pad + 64.0);
        return Stack(
          children: [
            Positioned(
              left: 0,
              width: w,
              top: top,
              height: h,
              child: GestureDetector(
                onScaleStart: (_) => _zoomStart = _zoom,
                onScaleUpdate: (d) {
                  if (c == null || d.pointerCount < 2) return;
                  final z = (_zoomStart * d.scale).clamp(_minZoom, _maxZoom);
                  if ((z - _zoom).abs() > 0.01) {
                    _zoom = z;
                    c.setZoomLevel(z);
                    setState(() {});
                  }
                },
                child: ClipRRect(
                  borderRadius: BorderRadius.circular(spare <= 0 ? 0 : 18),
                  child: FittedBox(
                    fit: BoxFit.cover,
                    child: SizedBox(
                      width: frame.width,
                      height: frame.height,
                      child: Builder(
                        builder: (inner) => GestureDetector(
                          onTapUp: (d) => _focusAt(d.localPosition, frame),
                          child: Stack(
                            fit: StackFit.expand,
                            children: [
                              override ?? CameraPreview(c!),
                              AnimatedBuilder(
                                animation: _quadAnim,
                                builder: (_, _) => CustomPaint(
                                  painter: _OverlayPainter(
                                    mode: _mode,
                                    quad: _mode.detectsPages ? _currentDisplayedQuad() : null,
                                    accent: accent,
                                    grid: _grid && _mode != CameraMode.qr,
                                    idStep: _shots.length,
                                    scale: frame.width / w,
                                  ),
                                ),
                              ),
                              if (_focusPoint != null)
                                Positioned(
                                  left: _focusPoint!.dx - 40 * frame.width / w,
                                  top: _focusPoint!.dy - 40 * frame.width / w,
                                  child: IgnorePointer(
                                    child: TweenAnimationBuilder<double>(
                                      tween: Tween(begin: 1.4, end: 1),
                                      duration: const Duration(milliseconds: 220),
                                      builder: (_, s, _) => Transform.scale(
                                        scale: s,
                                        child: Container(
                                          width: 80 * frame.width / w,
                                          height: 80 * frame.width / w,
                                          decoration: BoxDecoration(
                                            shape: BoxShape.circle,
                                            border: Border.all(color: Colors.white, width: 2 * frame.width / w),
                                          ),
                                        ),
                                      ),
                                    ),
                                  ),
                                ),
                            ],
                          ),
                        ),
                      ),
                    ),
                  ),
                ),
              ),
            ),
          ],
        );
      },
    );
  }
}

// ---------------------------------------------------------------- overlay

class _OverlayPainter extends CustomPainter {
  final CameraMode mode;
  final Quad? quad;
  final Color accent;
  final bool grid;
  final int idStep;
  final double scale; // frame px per logical px
  _OverlayPainter({
    required this.mode,
    required this.quad,
    required this.accent,
    required this.grid,
    required this.idStep,
    required this.scale,
  });

  @override
  void paint(Canvas canvas, Size size) {
    final s = scale;
    if (grid) {
      final gp = Paint()
        ..color = Colors.white.withValues(alpha: 0.28)
        ..strokeWidth = 1 * s;
      for (var i = 1; i < 3; i++) {
        canvas.drawLine(Offset(size.width * i / 3, 0), Offset(size.width * i / 3, size.height), gp);
        canvas.drawLine(Offset(0, size.height * i / 3), Offset(size.width, size.height * i / 3), gp);
      }
    }

    // Mode guides (shown until a page is found).
    final guide = Paint()
      ..color = Colors.white.withValues(alpha: 0.75)
      ..style = PaintingStyle.stroke
      ..strokeWidth = 2 * s;
    Rect? frame;
    switch (mode) {
      case CameraMode.idCard:
      case CameraMode.businessCard:
        final w = size.width * 0.84;
        frame = Rect.fromCenter(center: size.center(Offset.zero), width: w, height: w * 54 / 85.6);
      case CameraMode.receipt:
        final w = size.width * 0.62;
        frame = Rect.fromCenter(center: size.center(Offset.zero), width: w, height: size.height * 0.72);
      case CameraMode.qr:
        final w = size.width * 0.66;
        frame = Rect.fromCenter(center: size.center(Offset.zero), width: w, height: w);
      case CameraMode.book:
        final dash = Paint()
          ..color = Colors.white.withValues(alpha: 0.7)
          ..strokeWidth = 2 * s;
        for (var y = size.height * 0.16; y < size.height * 0.84; y += 26 * s) {
          canvas.drawLine(Offset(size.width / 2, y), Offset(size.width / 2, y + 14 * s), dash);
        }
      default:
        break;
    }
    if (frame != null && quad == null) {
      final rr = RRect.fromRectAndRadius(frame, Radius.circular(18 * s));
      canvas.drawPath(
        Path()
          ..fillType = PathFillType.evenOdd
          ..addRect(Offset.zero & size)
          ..addRRect(rr),
        Paint()..color = Colors.black.withValues(alpha: 0.35),
      );
      // corner brackets
      final br = Paint()
        ..color = mode == CameraMode.qr ? accent : Colors.white
        ..style = PaintingStyle.stroke
        ..strokeCap = StrokeCap.round
        ..strokeWidth = 5 * s;
      final l = 34.0 * s;
      for (final c in [frame.topLeft, frame.topRight, frame.bottomLeft, frame.bottomRight]) {
        final dx = c.dx == frame.left ? 1 : -1, dy = c.dy == frame.top ? 1 : -1;
        canvas.drawLine(c + Offset(0, dy * 12.0 * s), c + Offset(0, dy * l), br);
        canvas.drawLine(c + Offset(dx * 12.0 * s, 0), c + Offset(dx * l, 0), br);
      }
      if (mode == CameraMode.idCard) {
        final tp = TextPainter(
          text: TextSpan(
            text: idStep == 0 ? 'FRONT' : 'BACK',
            style: TextStyle(
              fontFamily: 'Manrope',
              color: Colors.white,
              fontSize: 15 * s,
              fontWeight: FontWeight.w800,
              letterSpacing: 3 * s,
            ),
          ),
          textDirection: TextDirection.ltr,
        )..layout();
        tp.paint(canvas, Offset(frame.center.dx - tp.width / 2, frame.top - tp.height - 14 * s));
      }
      if (mode != CameraMode.qr) canvas.drawRRect(rr, guide..color = Colors.white.withValues(alpha: 0.18));
    }

    final q = quad;
    if (q == null) return;
    final path = Path()..moveTo(q[0] * size.width, q[1] * size.height);
    for (var i = 1; i < 4; i++) {
      path.lineTo(q[i * 2] * size.width, q[i * 2 + 1] * size.height);
    }
    path.close();
    canvas.drawPath(path, Paint()..color = accent.withValues(alpha: 0.22));
    canvas.drawPath(
      path,
      Paint()
        ..color = accent
        ..style = PaintingStyle.stroke
        ..strokeJoin = StrokeJoin.round
        ..strokeWidth = 3.5 * s,
    );
    for (var i = 0; i < 4; i++) {
      final c = Offset(q[i * 2] * size.width, q[i * 2 + 1] * size.height);
      canvas.drawCircle(c, 9 * s, Paint()..color = Colors.white);
      canvas.drawCircle(
        c,
        9 * s,
        Paint()
          ..color = accent
          ..style = PaintingStyle.stroke
          ..strokeWidth = 3 * s,
      );
    }
  }

  @override
  bool shouldRepaint(_OverlayPainter old) => true;
}

// ---------------------------------------------------------------- controls

class _Scrim extends StatelessWidget {
  final Widget child;
  final bool top;
  const _Scrim({required this.child, required this.top});

  @override
  Widget build(BuildContext context) {
    return DecoratedBox(
      decoration: BoxDecoration(
        gradient: LinearGradient(
          begin: top ? Alignment.topCenter : Alignment.bottomCenter,
          end: top ? Alignment.bottomCenter : Alignment.topCenter,
          colors: [Colors.black.withValues(alpha: 0.62), Colors.black.withValues(alpha: 0)],
        ),
      ),
      child: child,
    );
  }
}

class _RoundButton extends StatelessWidget {
  final IconData icon;
  final String label;
  final VoidCallback onTap;
  final double size;
  final bool active;
  const _RoundButton({
    required this.icon,
    required this.label,
    required this.onTap,
    this.size = 44,
    this.active = false,
  });

  @override
  Widget build(BuildContext context) {
    final accent = Glass.of(context).accent.primary;
    return Tooltip(
      message: label,
      child: Semantics(
        button: true,
        label: label,
        child: Pressable(
          onTap: onTap,
          scale: 0.9,
          child: ClipOval(
            child: BackdropFilter(
              filter: ui.ImageFilter.blur(sigmaX: 14, sigmaY: 14),
              child: Container(
                width: size,
                height: size,
                color: Colors.white.withValues(alpha: 0.14),
                alignment: Alignment.center,
                child: PhosphorIcon(icon, color: active ? accent : Colors.white, size: size * 0.46),
              ),
            ),
          ),
        ),
      ),
    );
  }
}

class _PillButton extends StatelessWidget {
  final String label;
  final bool active;
  final VoidCallback onTap;
  const _PillButton({required this.label, required this.active, required this.onTap});

  @override
  Widget build(BuildContext context) {
    return Semantics(
      button: true,
      toggled: active,
      label: 'Auto capture',
      child: Pressable(
        onTap: onTap,
        child: AnimatedContainer(
          duration: const Duration(milliseconds: 180),
          height: 44,
          padding: const EdgeInsets.symmetric(horizontal: 16),
          decoration: BoxDecoration(
            color: active ? Colors.white : Colors.white.withValues(alpha: 0.14),
            borderRadius: BorderRadius.circular(22),
          ),
          alignment: Alignment.center,
          child: Text(
            label,
            style: TextStyle(color: active ? Colors.black : Colors.white, fontWeight: FontWeight.w700, fontSize: 13.5),
          ),
        ),
      ),
    );
  }
}

class _HintPill extends StatelessWidget {
  final String text;
  final bool highlight;
  const _HintPill({super.key, required this.text, required this.highlight});

  @override
  Widget build(BuildContext context) {
    return ClipRRect(
      borderRadius: BorderRadius.circular(20),
      child: BackdropFilter(
        filter: ui.ImageFilter.blur(sigmaX: 16, sigmaY: 16),
        child: Container(
          padding: const EdgeInsets.symmetric(horizontal: 16, vertical: 9),
          color: Colors.black.withValues(alpha: 0.38),
          child: Row(
            mainAxisSize: MainAxisSize.min,
            children: [
              AnimatedContainer(
                duration: const Duration(milliseconds: 200),
                width: 8,
                height: 8,
                decoration: BoxDecoration(
                  shape: BoxShape.circle,
                  color: highlight ? const Color(0xFF2FCB8F) : Colors.white.withValues(alpha: 0.6),
                ),
              ),
              const SizedBox(width: 9),
              Text(
                text,
                style: const TextStyle(color: Colors.white, fontWeight: FontWeight.w600, fontSize: 13.5),
              ),
            ],
          ),
        ),
      ),
    );
  }
}

class _ModeCarousel extends StatefulWidget {
  final List<CameraMode> modes;
  final CameraMode current;
  final ValueChanged<CameraMode> onSelect;
  final Color accent;
  const _ModeCarousel({required this.modes, required this.current, required this.onSelect, required this.accent});

  @override
  State<_ModeCarousel> createState() => _ModeCarouselState();
}

class _ModeCarouselState extends State<_ModeCarousel> {
  final _scroll = ScrollController();
  final _keys = <CameraMode, GlobalKey>{};

  @override
  void initState() {
    super.initState();
    WidgetsBinding.instance.addPostFrameCallback((_) => _center(animate: false));
  }

  @override
  void didUpdateWidget(_ModeCarousel old) {
    super.didUpdateWidget(old);
    if (old.current != widget.current) WidgetsBinding.instance.addPostFrameCallback((_) => _center());
  }

  void _center({bool animate = true}) {
    final ctx = _keys[widget.current]?.currentContext;
    if (ctx == null) return;
    Scrollable.ensureVisible(
      ctx,
      alignment: 0.5,
      duration: animate ? const Duration(milliseconds: 260) : Duration.zero,
      curve: Curves.easeOutCubic,
    );
  }

  @override
  void dispose() {
    _scroll.dispose();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    final half = MediaQuery.of(context).size.width / 2;
    return SizedBox(
      height: 38,
      child: SingleChildScrollView(
        controller: _scroll,
        scrollDirection: Axis.horizontal,
        physics: const BouncingScrollPhysics(),
        padding: EdgeInsets.symmetric(horizontal: half - 50),
        child: Row(
          children: [
            for (final m in widget.modes)
              Semantics(
                button: true,
                selected: m == widget.current,
                label: '${m.label} mode',
                child: GestureDetector(
                  key: _keys.putIfAbsent(m, GlobalKey.new),
                  onTap: () => widget.onSelect(m),
                  child: AnimatedContainer(
                    duration: const Duration(milliseconds: 200),
                    margin: const EdgeInsets.symmetric(horizontal: 4),
                    padding: const EdgeInsets.symmetric(horizontal: 14, vertical: 8),
                    decoration: BoxDecoration(
                      color: m == widget.current ? Colors.white.withValues(alpha: 0.16) : Colors.transparent,
                      borderRadius: BorderRadius.circular(19),
                    ),
                    child: Text(
                      m.label.toUpperCase(),
                      style: TextStyle(
                        color: m == widget.current ? Colors.white : Colors.white.withValues(alpha: 0.62),
                        fontWeight: FontWeight.w800,
                        fontSize: 12.5,
                        letterSpacing: 1.1,
                      ),
                    ),
                  ),
                ),
              ),
          ],
        ),
      ),
    );
  }
}

class _Shutter extends StatelessWidget {
  final bool enabled;
  final bool busy;
  final Animation<double> progress;
  final Color accent;
  final VoidCallback onTap;
  const _Shutter({
    required this.enabled,
    required this.busy,
    required this.progress,
    required this.accent,
    required this.onTap,
  });

  @override
  Widget build(BuildContext context) {
    return Semantics(
      button: true,
      label: 'Capture',
      enabled: enabled,
      child: Pressable(
        onTap: enabled ? onTap : null,
        scale: 0.92,
        child: AnimatedOpacity(
          duration: const Duration(milliseconds: 180),
          opacity: enabled || busy ? 1 : 0.35,
          child: SizedBox(
            width: 82,
            height: 82,
            child: AnimatedBuilder(
              animation: progress,
              builder: (_, _) => CustomPaint(
                painter: _ShutterPainter(progress.value, accent),
                child: Center(
                  child: AnimatedContainer(
                    duration: const Duration(milliseconds: 160),
                    width: busy ? 52 : 64,
                    height: busy ? 52 : 64,
                    decoration: const BoxDecoration(shape: BoxShape.circle, color: Colors.white),
                  ),
                ),
              ),
            ),
          ),
        ),
      ),
    );
  }
}

class _ShutterPainter extends CustomPainter {
  final double t;
  final Color accent;
  _ShutterPainter(this.t, this.accent);

  @override
  void paint(Canvas canvas, Size size) {
    final c = size.center(Offset.zero);
    final r = size.width / 2 - 3;
    canvas.drawCircle(
      c,
      r,
      Paint()
        ..color = Colors.white
        ..style = PaintingStyle.stroke
        ..strokeWidth = 4,
    );
    if (t > 0) {
      canvas.drawArc(
        Rect.fromCircle(center: c, radius: r),
        -math.pi / 2,
        2 * math.pi * t,
        false,
        Paint()
          ..color = accent
          ..style = PaintingStyle.stroke
          ..strokeCap = StrokeCap.round
          ..strokeWidth = 5,
      );
    }
  }

  @override
  bool shouldRepaint(_ShutterPainter old) => old.t != t || old.accent != accent;
}

class _ShotStack extends StatelessWidget {
  final List<Shot> shots;
  final Color accent;
  final VoidCallback onTap;
  const _ShotStack({required this.shots, required this.accent, required this.onTap});

  @override
  Widget build(BuildContext context) {
    return Semantics(
      button: true,
      label: 'Continue with ${shots.length} page${shots.length == 1 ? '' : 's'}',
      child: Pressable(
        onTap: onTap,
        child: SizedBox(
          width: 60,
          height: 72,
          child: Stack(
            clipBehavior: Clip.none,
            children: [
              if (shots.length > 1)
                Positioned(
                  left: 6,
                  top: 2,
                  child: Transform.rotate(
                    angle: -0.12,
                    child: Container(
                      width: 48,
                      height: 64,
                      decoration: BoxDecoration(
                        color: Colors.white.withValues(alpha: 0.5),
                        borderRadius: BorderRadius.circular(8),
                      ),
                    ),
                  ),
                ),
              Positioned(
                left: 6,
                top: 4,
                child: Container(
                  width: 48,
                  height: 64,
                  decoration: BoxDecoration(
                    borderRadius: BorderRadius.circular(8),
                    border: Border.all(color: Colors.white, width: 2),
                    boxShadow: [BoxShadow(color: Colors.black.withValues(alpha: 0.4), blurRadius: 8)],
                  ),
                  clipBehavior: Clip.antiAlias,
                  child: Image.file(File(shots.last.path), fit: BoxFit.cover, cacheWidth: 150, gaplessPlayback: true),
                ),
              ),
              Positioned(
                right: -4,
                top: -6,
                child: Container(
                  constraints: const BoxConstraints(minWidth: 24),
                  height: 24,
                  padding: const EdgeInsets.symmetric(horizontal: 6),
                  decoration: BoxDecoration(color: accent, borderRadius: BorderRadius.circular(12)),
                  alignment: Alignment.center,
                  child: Text(
                    '${shots.length}',
                    style: const TextStyle(color: Colors.white, fontWeight: FontWeight.w800, fontSize: 12),
                  ),
                ),
              ),
              Positioned(
                left: 0,
                right: -6,
                bottom: -18,
                child: const Text(
                  'Done',
                  textAlign: TextAlign.center,
                  style: TextStyle(color: Colors.white, fontSize: 12, fontWeight: FontWeight.w700),
                ),
              ),
            ],
          ),
        ),
      ),
    );
  }
}

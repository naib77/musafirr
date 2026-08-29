import 'package:camera/camera.dart';
import 'dart:async';

import 'package:flutter/material.dart';
import 'package:flutter/services.dart';

import '../../core/theme/app_colors.dart';
import '../../services/camera/selfie_camera.dart';

/// Takes the identity-verification selfie with the front camera, in-app.
///
/// Replaces handing off to the system camera app, which is what caused the
/// reported bug: `preferredCameraDevice: CameraDevice.front` is only a hint,
/// and many Android camera apps (and browsers that delegate to them) ignore it
/// and open the rear lens. Here the lens is chosen by
/// [selectSelfieCamera], so there is nothing left to ignore.
///
/// Pops an [XFile] on success, or null if the guest backs out. Pops
/// [SelfieCaptureResult.unavailable] when there is no usable front camera, so
/// the caller can fall back to the picker rather than dead-ending.
class SelfieCaptureScreen extends StatefulWidget {
  const SelfieCaptureScreen({super.key});

  @override
  State<SelfieCaptureScreen> createState() => _SelfieCaptureScreenState();
}

/// Sentinel popped when the device has no front camera to offer.
class SelfieCaptureResult {
  const SelfieCaptureResult._();
  static const SelfieCaptureResult unavailable = SelfieCaptureResult._();
}

class _SelfieCaptureScreenState extends State<SelfieCaptureScreen>
    with WidgetsBindingObserver {
  CameraController? _controller;
  bool _initializing = true;
  bool _capturing = false;
  String? _error;

  @override
  void initState() {
    super.initState();
    WidgetsBinding.instance.addObserver(this);
    _start();
  }

  @override
  void dispose() {
    WidgetsBinding.instance.removeObserver(this);
    _controller?.dispose();
    super.dispose();
  }

  /// The camera must be released while the app is backgrounded — another app
  /// can claim it — and rebuilt on the way back, or the preview returns frozen.
  @override
  void didChangeAppLifecycleState(AppLifecycleState state) {
    // The guard belongs INSIDE the inactive branch, not above both. Hoisted, it
    // killed the feature: `inactive` sets _controller to null, so by the time
    // `resumed` arrives the null check returns early and _start() is never
    // reached. The camera never came back — permanent spinner, dead shutter,
    // and no way out of the verification flow but killing the app.
    switch (state) {
      case AppLifecycleState.inactive:
      case AppLifecycleState.paused:
      case AppLifecycleState.detached:
      case AppLifecycleState.hidden:
        final controller = _controller;
        if (controller == null) return;
        // Cleared before the await so a second lifecycle event cannot dispose
        // the same controller twice.
        _controller = null;
        unawaited(controller.dispose());
      case AppLifecycleState.resumed:
        // Only rebuild what was actually torn down. A resume with a live
        // controller (some platforms emit resumed without a prior inactive)
        // must not spawn a second camera.
        if (_controller == null) _start();
    }
  }

  Future<void> _start() async {
    setState(() {
      _initializing = true;
      _error = null;
    });
    try {
      // Bounded: if the platform never answers (a wedged camera service, or
      // no plugin at all) the guest must get an actionable error rather than
      // an indefinite spinner.
      final cameras = await availableCameras().timeout(
        const Duration(seconds: 10),
      );
      final front = selectSelfieCamera(cameras);
      if (front == null) {
        // No front lens at all. Hand the decision back rather than showing a
        // rear-camera preview and calling it a selfie.
        if (mounted) Navigator.pop(context, SelfieCaptureResult.unavailable);
        return;
      }
      final controller = CameraController(
        front,
        // A selfie is matched against an ID photo by a human, so a face that
        // reads clearly matters more than resolution. Medium keeps init fast
        // and the upload small on a Bangladeshi mobile connection.
        ResolutionPreset.medium,
        enableAudio: false,
      );
      await controller.initialize().timeout(const Duration(seconds: 15));
      if (!mounted) {
        await controller.dispose();
        return;
      }
      setState(() {
        _controller = controller;
        _initializing = false;
      });
    } on CameraException catch (e) {
      if (!mounted) return;
      setState(() {
        _initializing = false;
        _error = switch (e.code) {
          'CameraAccessDenied' ||
          'CameraAccessDeniedWithoutPrompt' ||
          'CameraAccessRestricted' =>
            'Camera access is blocked. Allow camera permission for Musafir, '
                'then try again.',
          _ => 'Could not open the camera. Please try again.',
        };
      });
    } catch (_) {
      if (!mounted) return;
      setState(() {
        _initializing = false;
        _error = 'Could not open the camera. Please try again.';
      });
    }
  }

  Future<void> _shoot() async {
    final controller = _controller;
    if (controller == null || !controller.value.isInitialized) return;
    if (_capturing) return; // a second tap would race two captures
    setState(() => _capturing = true);
    try {
      final file = await controller.takePicture();
      if (!mounted) return;
      Navigator.pop(context, file);
    } on CameraException {
      if (!mounted) return;
      setState(() {
        _capturing = false;
        _error = 'Could not take the photo. Please try again.';
      });
    }
  }

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);

    return Scaffold(
      backgroundColor: Colors.black,
      // Light icons on black, regardless of the app's theme.
      appBar: AppBar(
        backgroundColor: Colors.transparent,
        foregroundColor: Colors.white,
        elevation: 0,
        systemOverlayStyle: SystemUiOverlayStyle.light,
        title: const Text('Take a selfie'),
      ),
      extendBodyBehindAppBar: true,
      body: SafeArea(
        child: Column(
          children: [
            Expanded(child: _preview(theme)),
            _controls(theme),
          ],
        ),
      ),
    );
  }

  Widget _preview(ThemeData theme) {
    if (_error != null) {
      return Center(
        child: Padding(
          padding: const EdgeInsets.all(32),
          child: Column(
            mainAxisAlignment: MainAxisAlignment.center,
            children: [
              const Icon(Icons.no_photography_outlined,
                  size: 40, color: Colors.white54),
              const SizedBox(height: 14),
              Text(
                _error!,
                textAlign: TextAlign.center,
                style:
                    theme.textTheme.bodyMedium?.copyWith(color: Colors.white70),
              ),
              const SizedBox(height: 18),
              FilledButton.icon(
                onPressed: _start,
                icon: const Icon(Icons.refresh),
                label: const Text('Try again'),
              ),
            ],
          ),
        ),
      );
    }

    final controller = _controller;
    if (_initializing || controller == null) {
      return const Center(
        child: CircularProgressIndicator(color: Colors.white),
      );
    }

    // Mirrored, because a selfie preview that isn't feels like looking at
    // someone else — every phone camera app mirrors the front lens. The
    // CAPTURED file is deliberately left unmirrored: the admin reviewing it
    // against an ID document should see the face the right way round.
    return Center(
      child: Transform.flip(
        flipX: true,
        child: CameraPreview(controller),
      ),
    );
  }

  Widget _controls(ThemeData theme) {
    final ready = _controller?.value.isInitialized ?? false;

    return Padding(
      padding: const EdgeInsets.fromLTRB(24, 12, 24, 28),
      child: Column(
        children: [
          Text(
            'Look straight at the camera with your face fully visible.',
            textAlign: TextAlign.center,
            style: theme.textTheme.bodySmall?.copyWith(color: Colors.white70),
          ),
          const SizedBox(height: 18),
          Semantics(
            button: true,
            label: 'Take selfie',
            child: GestureDetector(
              onTap: ready && !_capturing ? _shoot : null,
              child: AnimatedScale(
                scale: _capturing ? 0.92 : 1.0,
                duration: const Duration(milliseconds: 150),
                curve: Curves.easeOut,
                child: Container(
                  width: 72,
                  height: 72,
                  decoration: BoxDecoration(
                    shape: BoxShape.circle,
                    color: Colors.white.withValues(alpha: ready ? 1 : 0.4),
                    border: Border.all(color: Colors.white24, width: 4),
                  ),
                  child: _capturing
                      ? Padding(
                          padding: EdgeInsets.all(22),
                          child: CircularProgressIndicator(
                            strokeWidth: 2,
                            color: AppColors.brand,
                          ),
                        )
                      : const Icon(Icons.camera_alt,
                          color: Colors.black87, size: 28),
                ),
              ),
            ),
          ),
        ],
      ),
    );
  }
}

import 'dart:convert';

import 'package:camera/camera.dart';
import 'package:flutter/material.dart';
import 'package:webview_flutter/webview_flutter.dart';
import 'package:webview_flutter_android/webview_flutter_android.dart';
import 'package:webview_flutter_wkwebview/webview_flutter_wkwebview.dart';

import '../../../services/camera/selfie_camera.dart';
import '../../../services/verification/face_verification_service.dart';

class FaceCaptureView extends StatefulWidget {
  const FaceCaptureView(
      {super.key,
      required this.attempt,
      required this.brand,
      required this.onCapture});
  final FaceAttempt attempt;
  final String brand;
  final ValueChanged<FaceCapture> onCapture;
  @override
  State<FaceCaptureView> createState() => _FaceCaptureViewState();
}

class _FaceCaptureViewState extends State<FaceCaptureView>
    with WidgetsBindingObserver {
  WebViewController? _controller;
  String? _error;
  bool _finished = false;
  // Same static assets as web, no session/auth token is sent to this origin.
  // Override for staging builds. HTTPS is required for getUserMedia.
  static const _origin = String.fromEnvironment('FACE_CAPTURE_ORIGIN',
      defaultValue: 'https://musafirr.knaib77.workers.dev');
  @override
  void initState() {
    super.initState();
    WidgetsBinding.instance.addObserver(this);
    _start();
  }

  Future<void> _start() async {
    try {
      final uri = Uri.parse(_origin).resolve('/face/index.html');
      if (uri.scheme != 'https') {
        throw StateError('Secure capture origin required');
      }
      // Ask through the existing camera plugin first. Granting a WebView media
      // request alone does not grant Android's runtime camera permission.
      final cameras =
          await availableCameras().timeout(const Duration(seconds: 10));
      final front = selectSelfieCamera(cameras);
      if (front == null) throw StateError('Front camera unavailable');
      final permissionCamera =
          CameraController(front, ResolutionPreset.low, enableAudio: false);
      try {
        await permissionCamera
            .initialize()
            .timeout(const Duration(seconds: 15));
      } finally {
        await permissionCamera.dispose();
      }
      if (!mounted) return;
      final params = WebViewPlatform.instance is WebKitWebViewPlatform
          ? WebKitWebViewControllerCreationParams(
              allowsInlineMediaPlayback: true,
              mediaTypesRequiringUserAction: const <PlaybackMediaTypes>{})
          : const PlatformWebViewControllerCreationParams();
      final controller = WebViewController.fromPlatformCreationParams(params,
          onPermissionRequest: (request) {
        if (request.types
            .every((type) => type == WebViewPermissionResourceType.camera)) {
          request.grant();
        } else {
          request.deny();
        }
      });
      if (controller.platform is AndroidWebViewController) {
        await (controller.platform as AndroidWebViewController)
            .setMediaPlaybackRequiresUserGesture(false);
      }
      await controller.setJavaScriptMode(JavaScriptMode.unrestricted);
      await controller.setNavigationDelegate(NavigationDelegate(
        onNavigationRequest: (request) {
          final target = Uri.tryParse(request.url);
          return target?.origin == uri.origin && target?.path == uri.path
              ? NavigationDecision.navigate
              : NavigationDecision.prevent;
        },
        onWebResourceError: (error) {
          if (mounted && error.isForMainFrame == true) {
            setState(() => _error =
                'Could not load face capture. Check your connection and try again.');
          }
        },
      ));
      await controller.addJavaScriptChannel('FaceCapture',
          onMessageReceived: (message) {
        if (!mounted || _finished) return;
        try {
          final capture =
              FaceCapture.fromMessage(message.message, widget.attempt);
          if (capture != null) {
            _finished = true;
            widget.onCapture(capture);
          }
        } catch (_) {
          setState(() =>
              _error = 'Capture could not be read. Go back and try again.');
        }
      });
      if (!mounted) return;
      _controller = controller;
      await controller.loadRequest(uri.replace(
          fragment: jsonEncode(widget.attempt.captureConfig(widget.brand))));
      if (mounted) setState(() => _controller = controller);
    } catch (_) {
      if (mounted) {
        setState(() => _error =
            'Could not open the front camera. Allow camera access, then go back and try again.');
      }
    }
  }

  @override
  void didChangeAppLifecycleState(AppLifecycleState state) {
    if (state != AppLifecycleState.resumed) {
      _stopCapture();
    }
  }

  Future<void> _stopCapture() async {
    try {
      await _controller?.runJavaScript('window.stopFaceCapture?.()');
    } catch (_) {/* The platform view may already have been disposed. */}
  }

  @override
  void dispose() {
    WidgetsBinding.instance.removeObserver(this);
    _stopCapture();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    if (_error != null) {
      return Center(
          child: Padding(
              padding: const EdgeInsets.all(24),
              child: Text(_error!, textAlign: TextAlign.center)));
    }
    if (_controller == null) {
      return const Center(child: CircularProgressIndicator());
    }
    return WebViewWidget(controller: _controller!);
  }
}

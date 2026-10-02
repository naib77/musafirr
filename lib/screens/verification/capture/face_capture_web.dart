import 'dart:convert';
import 'dart:js_interop';

import 'package:flutter/material.dart';
import 'package:web/web.dart' as web;

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

class _FaceCaptureViewState extends State<FaceCaptureView> {
  web.HTMLIFrameElement? _frame;
  late final JSFunction _listener;
  bool _finished = false;
  String? _error;
  @override
  void initState() {
    super.initState();
    _listener = ((web.MessageEvent event) {
      if (!mounted ||
          _finished ||
          event.origin != web.window.location.origin ||
          event.source != _frame?.contentWindow) {
        return;
      }
      try {
        final message = (event.data as JSString).toDart;
        final capture = FaceCapture.fromMessage(message, widget.attempt);
        if (capture != null) {
          _finished = true;
          widget.onCapture(capture);
        }
      } catch (_) {
        setState(() =>
            _error = 'Capture could not be read. Go back and start again.');
      }
    }).toJS;
    web.window.addEventListener('message', _listener);
  }

  @override
  void dispose() {
    web.window.removeEventListener('message', _listener);
    _frame?.contentWindow?.postMessage(
        'stop-face-capture'.toJS, web.window.location.origin.toJS);
    _frame?.src = 'about:blank';
    super.dispose();
  }

  @override
  Widget build(BuildContext context) => _error != null
      ? Center(child: Text(_error!))
      : HtmlElementView.fromTagName(
          tagName: 'iframe',
          onElementCreated: (element) {
            final frame = element as web.HTMLIFrameElement;
            _frame = frame;
            frame.title = 'Private face capture';
            frame.allow = 'camera';
            frame.style.border = '0';
            frame.style.width = '100%';
            frame.style.height = '100%';
            frame.src = Uri.base
                .resolve('face/index.html')
                .replace(
                    fragment:
                        jsonEncode(widget.attempt.captureConfig(widget.brand)))
                .toString();
          });
}

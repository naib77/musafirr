import 'package:flutter/foundation.dart' show kIsWeb;
import 'package:flutter/material.dart';

/// On web, delays building [builder] until after the first frame.
///
/// google_maps_flutter_web throws "Maps cannot be retrieved before calling
/// buildView!" when a GoogleMap is disposed before its platform view was ever
/// built — which happens on fast navigation / page transitions. Deferring the
/// mount by one frame means the map is either never created (the widget was
/// disposed first — no assertion) or fully built before any disposal.
///
/// No effect on non-web platforms: [builder] runs immediately.
class WebDeferredMount extends StatefulWidget {
  const WebDeferredMount({super.key, required this.builder, this.placeholder});

  final WidgetBuilder builder;
  final Widget? placeholder;

  @override
  State<WebDeferredMount> createState() => _WebDeferredMountState();
}

class _WebDeferredMountState extends State<WebDeferredMount> {
  bool _ready = !kIsWeb;

  @override
  void initState() {
    super.initState();
    if (kIsWeb) {
      WidgetsBinding.instance.addPostFrameCallback((_) {
        if (mounted) setState(() => _ready = true);
      });
    }
  }

  @override
  Widget build(BuildContext context) {
    if (!_ready) {
      return widget.placeholder ??
          Container(
              color: Theme.of(context).colorScheme.surfaceContainerHighest);
    }
    return widget.builder(context);
  }
}

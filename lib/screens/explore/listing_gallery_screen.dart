import 'package:flutter/material.dart';

import '../../widgets/app_network_image.dart';

/// Airbnb-style "photo tour": a white, scrollable gallery of every listing
/// photo — one full-width shot, then a pair, repeating. Tapping a photo opens
/// the full-screen zoomable viewer at that image.
class ListingGalleryScreen extends StatelessWidget {
  const ListingGalleryScreen({
    super.key,
    required this.images,
    this.title,
  });

  final List<String> images;
  final String? title;

  void _openViewer(BuildContext context, int index) {
    Navigator.push(
      context,
      PageRouteBuilder(
        opaque: false,
        barrierColor: Colors.black,
        pageBuilder: (_, __, ___) => GalleryPhotoViewer(
          images: images,
          initialIndex: index,
        ),
        transitionsBuilder: (_, animation, __, child) =>
            FadeTransition(opacity: animation, child: child),
      ),
    );
  }

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);

    // Airbnb pattern: full-width photo, then a side-by-side pair, repeat.
    final rows = <Widget>[];
    var i = 0;
    while (i < images.length) {
      if (i % 3 == 0 || i == images.length - 1) {
        rows.add(_GalleryImage(
          url: images[i],
          height: 260,
          onTap: () => _openViewer(context, i),
        ));
        i += 1;
      } else {
        final first = i;
        final second = i + 1 < images.length ? i + 1 : null;
        rows.add(Row(
          children: [
            Expanded(
              child: _GalleryImage(
                url: images[first],
                height: 150,
                onTap: () => _openViewer(context, first),
              ),
            ),
            if (second != null) ...[
              const SizedBox(width: 8),
              Expanded(
                child: _GalleryImage(
                  url: images[second],
                  height: 150,
                  onTap: () => _openViewer(context, second),
                ),
              ),
            ],
          ],
        ));
        i += second != null ? 2 : 1;
      }
      rows.add(const SizedBox(height: 8));
    }

    return Scaffold(
      backgroundColor: theme.colorScheme.surface,
      appBar: AppBar(
        backgroundColor: theme.colorScheme.surface,
        leading: IconButton(
          icon: const Icon(Icons.close),
          onPressed: () => Navigator.pop(context),
        ),
        title: Text(
          title ?? 'Photos',
          style: theme.textTheme.titleMedium?.copyWith(
            fontWeight: FontWeight.w600,
          ),
        ),
        centerTitle: true,
      ),
      body: ListView(
        padding: const EdgeInsets.fromLTRB(16, 8, 16, 24),
        children: rows,
      ),
    );
  }
}

class _GalleryImage extends StatelessWidget {
  const _GalleryImage({
    required this.url,
    required this.height,
    required this.onTap,
  });

  final String url;
  final double height;
  final VoidCallback onTap;

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    return GestureDetector(
      onTap: onTap,
      child: ClipRRect(
        borderRadius: BorderRadius.circular(12),
        child: AppNetworkImage(
          url: url,
          height: height,
          width: double.infinity,
          fit: BoxFit.cover,
          decodeWidth: 500,
          errorWidget: Container(
            height: height,
            color: theme.colorScheme.surfaceContainerHighest,
            child: Icon(
              Icons.broken_image_outlined,
              color: theme.colorScheme.onSurfaceVariant,
            ),
          ),
          placeholder: Container(
            height: height,
            color: theme.colorScheme.surfaceContainerHighest,
          ),
        ),
      ),
    );
  }
}

/// Full-screen photo viewer: black background, swipe between photos,
/// pinch or double-tap to zoom, "n / total" counter — Airbnb-style.
class GalleryPhotoViewer extends StatefulWidget {
  const GalleryPhotoViewer({
    super.key,
    required this.images,
    this.initialIndex = 0,
  });

  final List<String> images;
  final int initialIndex;

  @override
  State<GalleryPhotoViewer> createState() => _GalleryPhotoViewerState();
}

class _GalleryPhotoViewerState extends State<GalleryPhotoViewer> {
  late final PageController _pageController;
  late int _index;
  bool _zoomed = false;

  @override
  void initState() {
    super.initState();
    _index = widget.initialIndex;
    _pageController = PageController(initialPage: widget.initialIndex);
  }

  @override
  void dispose() {
    _pageController.dispose();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      backgroundColor: Colors.black,
      body: Stack(
        children: [
          PageView.builder(
            controller: _pageController,
            // While zoomed in, horizontal drags pan the photo, not the pager.
            physics: _zoomed
                ? const NeverScrollableScrollPhysics()
                : const PageScrollPhysics(),
            onPageChanged: (index) => setState(() => _index = index),
            itemCount: widget.images.length,
            itemBuilder: (context, index) => _ZoomablePhoto(
              url: widget.images[index],
              onZoomChanged: (zoomed) => setState(() => _zoomed = zoomed),
            ),
          ),

          // Close button
          Positioned(
            top: MediaQuery.of(context).padding.top + 8,
            left: 8,
            child: IconButton(
              onPressed: () => Navigator.pop(context),
              icon: const Icon(Icons.close, color: Colors.white),
              style: IconButton.styleFrom(
                backgroundColor: Colors.black.withValues(alpha: 0.4),
              ),
            ),
          ),

          // Counter
          Positioned(
            top: MediaQuery.of(context).padding.top + 16,
            left: 0,
            right: 0,
            child: IgnorePointer(
              child: Text(
                '${_index + 1} / ${widget.images.length}',
                textAlign: TextAlign.center,
                style: const TextStyle(
                  color: Colors.white,
                  fontSize: 14,
                  fontWeight: FontWeight.w600,
                ),
              ),
            ),
          ),
        ],
      ),
    );
  }
}

/// One photo with pinch and double-tap zoom. Its own controller so the zoom
/// resets when swiping to another photo.
class _ZoomablePhoto extends StatefulWidget {
  const _ZoomablePhoto({
    required this.url,
    required this.onZoomChanged,
  });

  final String url;
  final ValueChanged<bool> onZoomChanged;

  @override
  State<_ZoomablePhoto> createState() => _ZoomablePhotoState();
}

class _ZoomablePhotoState extends State<_ZoomablePhoto> {
  final _controller = TransformationController();
  TapDownDetails? _doubleTapDetails;

  @override
  void dispose() {
    _controller.dispose();
    super.dispose();
  }

  void _notifyZoom() {
    widget.onZoomChanged(_controller.value.getMaxScaleOnAxis() > 1.01);
  }

  void _handleDoubleTap() {
    if (_controller.value.getMaxScaleOnAxis() > 1.01) {
      _controller.value = Matrix4.identity();
    } else if (_doubleTapDetails != null) {
      // Zoom 2.5x centered on the tap position.
      final position = _doubleTapDetails!.localPosition;
      _controller.value = Matrix4.identity()
        ..translateByDouble(-position.dx * 1.5, -position.dy * 1.5, 0, 1)
        ..scaleByDouble(2.5, 2.5, 1, 1);
    }
    _notifyZoom();
  }

  @override
  Widget build(BuildContext context) {
    return GestureDetector(
      onDoubleTapDown: (details) => _doubleTapDetails = details,
      onDoubleTap: _handleDoubleTap,
      child: InteractiveViewer(
        transformationController: _controller,
        minScale: 1,
        maxScale: 5,
        onInteractionEnd: (_) => _notifyZoom(),
        child: Center(
          // Full-screen zoomable view — decode at native resolution (no
          // decodeWidth) so pinch-to-zoom stays sharp.
          child: AppNetworkImage(
            url: widget.url,
            fit: BoxFit.contain,
            errorWidget: const Icon(
              Icons.broken_image_outlined,
              color: Colors.white54,
              size: 48,
            ),
            placeholder: const Center(
              child: CircularProgressIndicator(
                strokeWidth: 2,
                color: Colors.white54,
              ),
            ),
          ),
        ),
      ),
    );
  }
}

import 'package:cached_network_image/cached_network_image.dart';
import 'package:flutter/material.dart';

/// Disk-cached network image for the app.
///
/// Wraps [CachedNetworkImage] so images survive app restarts (no re-download)
/// and decode at a downscaled size for grids/cards. Pass [decodeWidth] as the
/// image's *logical* on-screen width — it's multiplied by the device pixel
/// ratio to set `memCacheWidth`, so a 100px card thumbnail never decodes a full
/// 1920px master into memory. Omit it (detail/full-screen) to decode at native
/// resolution.
class AppNetworkImage extends StatelessWidget {
  const AppNetworkImage({
    super.key,
    required this.url,
    this.width,
    this.height,
    this.fit = BoxFit.cover,
    this.borderRadius,
    this.decodeWidth,
    this.placeholder,
    this.errorWidget,
  });

  final String url;
  final double? width;
  final double? height;
  final BoxFit fit;
  final BorderRadius? borderRadius;
  final int? decodeWidth;
  final Widget? placeholder;
  final Widget? errorWidget;

  @override
  Widget build(BuildContext context) {
    Widget child;

    if (url.isEmpty || !url.startsWith('http')) {
      child = errorWidget ?? _defaultError(context);
    } else {
      final dpr = MediaQuery.of(context).devicePixelRatio;
      final memWidth = decodeWidth != null ? (decodeWidth! * dpr).round() : null;
      child = CachedNetworkImage(
        imageUrl: url,
        width: width,
        height: height,
        fit: fit,
        memCacheWidth: memWidth,
        maxWidthDiskCache: memWidth,
        fadeInDuration: const Duration(milliseconds: 200),
        placeholder: (_, __) => placeholder ?? _defaultPlaceholder(context),
        errorWidget: (_, __, ___) => errorWidget ?? _defaultError(context),
      );
    }

    if (borderRadius != null) {
      return ClipRRect(borderRadius: borderRadius!, child: child);
    }
    return child;
  }

  Widget _defaultPlaceholder(BuildContext context) {
    return Container(
      width: width,
      height: height,
      color: Theme.of(context).colorScheme.surfaceContainerHighest,
    );
  }

  Widget _defaultError(BuildContext context) {
    return Container(
      width: width,
      height: height,
      color: Theme.of(context).colorScheme.surfaceContainerHighest,
      child: Icon(
        Icons.broken_image_outlined,
        color: Theme.of(context).colorScheme.onSurfaceVariant,
        size: 28,
      ),
    );
  }
}

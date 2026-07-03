import 'dart:async';
import 'dart:ui' as ui;

import 'package:flutter/foundation.dart';
import 'package:flutter/material.dart';

/// Image size preset
enum ImageSize {
  thumbnail(150),
  small(300),
  medium(600),
  large(1200),
  original(0);

  const ImageSize(this.maxDimension);
  final int maxDimension;
}

/// Image format options
enum ImageFormat { jpeg, png, webp }

/// Image loading state
enum ImageLoadingState { idle, loading, loaded, error }

/// Optimized image configuration
class ImageConfig {
  const ImageConfig({
    this.size = ImageSize.medium,
    this.quality = 85,
    this.format = ImageFormat.jpeg,
    this.enableCache = true,
    this.fadeInDuration = const Duration(milliseconds: 300),
    this.placeholderColor,
  });

  final ImageSize size;
  final int quality;
  final ImageFormat format;
  final bool enableCache;
  final Duration fadeInDuration;
  final Color? placeholderColor;

  /// Get optimized URL for common CDN patterns
  String getOptimizedUrl(String originalUrl) {
    if (size == ImageSize.original) return originalUrl;

    // Supabase Storage transformation
    if (originalUrl.contains('supabase.co/storage')) {
      final uri = Uri.parse(originalUrl);
      final params = Map<String, String>.from(uri.queryParameters);
      params['width'] = size.maxDimension.toString();
      params['quality'] = quality.toString();
      return uri.replace(queryParameters: params).toString();
    }

    // Cloudinary transformation
    if (originalUrl.contains('cloudinary.com')) {
      final parts = originalUrl.split('/upload/');
      if (parts.length == 2) {
        final transformation = 'w_${size.maxDimension},q_$quality,f_auto';
        return '${parts[0]}/upload/$transformation/${parts[1]}';
      }
    }

    // Imgix transformation
    if (originalUrl.contains('imgix.net')) {
      final uri = Uri.parse(originalUrl);
      final params = Map<String, String>.from(uri.queryParameters);
      params['w'] = size.maxDimension.toString();
      params['q'] = quality.toString();
      params['auto'] = 'format,compress';
      return uri.replace(queryParameters: params).toString();
    }

    return originalUrl;
  }
}

/// Image cache entry
class _CacheEntry {
  _CacheEntry({
    required this.image,
    required this.size,
    required this.accessTime,
  });

  final ImageProvider image;
  final int size;
  DateTime accessTime;
}

/// LRU image cache
class ImageCache {
  ImageCache({this.maxSize = 100 * 1024 * 1024}); // 100MB default

  final int maxSize;
  final _cache = <String, _CacheEntry>{};
  int _currentSize = 0;

  /// Get cached image
  ImageProvider? get(String key) {
    final entry = _cache[key];
    if (entry == null) return null;

    // Update access time and move to end (LRU)
    entry.accessTime = DateTime.now();
    _cache.remove(key);
    _cache[key] = entry;

    return entry.image;
  }

  /// Cache an image
  void put(String key, ImageProvider image, {int estimatedSize = 50000}) {
    // Remove if already exists
    if (_cache.containsKey(key)) {
      _currentSize -= _cache[key]!.size;
      _cache.remove(key);
    }

    // Evict until we have space
    while (_currentSize + estimatedSize > maxSize && _cache.isNotEmpty) {
      final oldest = _cache.keys.first;
      _currentSize -= _cache[oldest]!.size;
      _cache.remove(oldest);
    }

    _cache[key] = _CacheEntry(
      image: image,
      size: estimatedSize,
      accessTime: DateTime.now(),
    );
    _currentSize += estimatedSize;
  }

  /// Remove from cache
  void remove(String key) {
    final entry = _cache.remove(key);
    if (entry != null) {
      _currentSize -= entry.size;
    }
  }

  /// Clear cache
  void clear() {
    _cache.clear();
    _currentSize = 0;
  }

  /// Get cache statistics
  Map<String, dynamic> get stats => {
        'entries': _cache.length,
        'currentSize': _currentSize,
        'maxSize': maxSize,
        'fillPercentage': (_currentSize / maxSize * 100).toStringAsFixed(1),
      };
}

/// Global image cache instance
final imageCache = ImageCache();

/// Optimized network image widget
class OptimizedImage extends StatefulWidget {
  const OptimizedImage({
    super.key,
    required this.url,
    this.config = const ImageConfig(),
    this.width,
    this.height,
    this.fit = BoxFit.cover,
    this.placeholder,
    this.errorWidget,
    this.onLoaded,
    this.onError,
    this.heroTag,
  });

  final String url;
  final ImageConfig config;
  final double? width;
  final double? height;
  final BoxFit fit;
  final Widget? placeholder;
  final Widget? errorWidget;
  final VoidCallback? onLoaded;
  final void Function(Object error)? onError;
  final String? heroTag;

  @override
  State<OptimizedImage> createState() => _OptimizedImageState();
}

class _OptimizedImageState extends State<OptimizedImage>
    with SingleTickerProviderStateMixin {
  ImageLoadingState _state = ImageLoadingState.idle;
  late AnimationController _fadeController;
  late Animation<double> _fadeAnimation;
  ImageProvider? _imageProvider;
  Object? _error;

  @override
  void initState() {
    super.initState();
    _fadeController = AnimationController(
      duration: widget.config.fadeInDuration,
      vsync: this,
    );
    _fadeAnimation = Tween<double>(begin: 0, end: 1).animate(
      CurvedAnimation(parent: _fadeController, curve: Curves.easeIn),
    );
    _loadImage();
  }

  @override
  void didUpdateWidget(OptimizedImage oldWidget) {
    super.didUpdateWidget(oldWidget);
    if (oldWidget.url != widget.url) {
      _loadImage();
    }
  }

  void _loadImage() {
    setState(() {
      _state = ImageLoadingState.loading;
      _error = null;
    });

    final optimizedUrl = widget.config.getOptimizedUrl(widget.url);

    // Check cache first
    if (widget.config.enableCache) {
      final cached = imageCache.get(optimizedUrl);
      if (cached != null) {
        _imageProvider = cached;
        _state = ImageLoadingState.loaded;
        _fadeController.value = 1;
        return;
      }
    }

    _imageProvider = NetworkImage(optimizedUrl);

    // Pre-cache the image
    final imageStream = _imageProvider!.resolve(const ImageConfiguration());
    imageStream.addListener(ImageStreamListener(
      (info, sync) {
        if (mounted) {
          setState(() => _state = ImageLoadingState.loaded);
          _fadeController.forward();
          widget.onLoaded?.call();

          if (widget.config.enableCache) {
            final estimatedSize = (info.image.width * info.image.height * 4);
            imageCache.put(optimizedUrl, _imageProvider!, estimatedSize: estimatedSize);
          }
        }
      },
      onError: (error, stackTrace) {
        if (mounted) {
          setState(() {
            _state = ImageLoadingState.error;
            _error = error;
          });
          widget.onError?.call(error);

          if (kDebugMode) {
            print('❌ Image load error: $error');
          }
        }
      },
    ));
  }

  @override
  void dispose() {
    _fadeController.dispose();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    Widget imageWidget;

    switch (_state) {
      case ImageLoadingState.idle:
      case ImageLoadingState.loading:
        imageWidget = widget.placeholder ?? _buildPlaceholder(context);
        break;

      case ImageLoadingState.loaded:
        imageWidget = FadeTransition(
          opacity: _fadeAnimation,
          child: Image(
            image: _imageProvider!,
            width: widget.width,
            height: widget.height,
            fit: widget.fit,
            errorBuilder: (_, error, __) =>
                widget.errorWidget ?? _buildError(context, error),
          ),
        );
        break;

      case ImageLoadingState.error:
        imageWidget =
            widget.errorWidget ?? _buildError(context, _error ?? 'Unknown error');
        break;
    }

    if (widget.heroTag != null) {
      return Hero(
        tag: widget.heroTag!,
        child: imageWidget,
      );
    }

    return imageWidget;
  }

  Widget _buildPlaceholder(BuildContext context) {
    return Container(
      width: widget.width,
      height: widget.height,
      color: widget.config.placeholderColor ??
          Theme.of(context).colorScheme.surfaceContainerHighest,
      child: const Center(
        child: CircularProgressIndicator(strokeWidth: 2),
      ),
    );
  }

  Widget _buildError(BuildContext context, Object error) {
    return Container(
      width: widget.width,
      height: widget.height,
      color: Theme.of(context).colorScheme.errorContainer,
      child: Center(
        child: Icon(
          Icons.broken_image_outlined,
          color: Theme.of(context).colorScheme.onErrorContainer,
          size: 32,
        ),
      ),
    );
  }
}

/// Blur hash placeholder
class BlurHashPlaceholder extends StatelessWidget {
  const BlurHashPlaceholder({
    super.key,
    required this.hash,
    this.width,
    this.height,
    this.fit = BoxFit.cover,
  });

  final String hash;
  final double? width;
  final double? height;
  final BoxFit fit;

  @override
  Widget build(BuildContext context) {
    // In production, use flutter_blurhash package
    // This is a placeholder implementation
    return Container(
      width: width,
      height: height,
      decoration: BoxDecoration(
        gradient: LinearGradient(
          colors: [
            _hashToColor(hash, 0),
            _hashToColor(hash, 1),
          ],
          begin: Alignment.topLeft,
          end: Alignment.bottomRight,
        ),
      ),
    );
  }

  Color _hashToColor(String hash, int index) {
    if (hash.isEmpty) return Colors.grey;
    final charCode = hash.codeUnitAt(index % hash.length);
    return Color.fromARGB(
      255,
      (charCode * 7) % 256,
      (charCode * 13) % 256,
      (charCode * 17) % 256,
    );
  }
}

/// Progressive image loading (thumbnail first, then full)
class ProgressiveImage extends StatefulWidget {
  const ProgressiveImage({
    super.key,
    required this.thumbnailUrl,
    required this.fullUrl,
    this.width,
    this.height,
    this.fit = BoxFit.cover,
    this.fadeDuration = const Duration(milliseconds: 500),
  });

  final String thumbnailUrl;
  final String fullUrl;
  final double? width;
  final double? height;
  final BoxFit fit;
  final Duration fadeDuration;

  @override
  State<ProgressiveImage> createState() => _ProgressiveImageState();
}

class _ProgressiveImageState extends State<ProgressiveImage> {
  bool _fullImageLoaded = false;

  @override
  Widget build(BuildContext context) {
    return Stack(
      fit: StackFit.passthrough,
      children: [
        // Thumbnail (blurred)
        ImageFiltered(
          imageFilter: ui.ImageFilter.blur(sigmaX: 10, sigmaY: 10),
          child: Image.network(
            widget.thumbnailUrl,
            width: widget.width,
            height: widget.height,
            fit: widget.fit,
            errorBuilder: (_, __, ___) => const SizedBox.shrink(),
          ),
        ),

        // Full image
        AnimatedOpacity(
          opacity: _fullImageLoaded ? 1.0 : 0.0,
          duration: widget.fadeDuration,
          child: Image.network(
            widget.fullUrl,
            width: widget.width,
            height: widget.height,
            fit: widget.fit,
            loadingBuilder: (context, child, progress) {
              if (progress == null) {
                WidgetsBinding.instance.addPostFrameCallback((_) {
                  if (mounted && !_fullImageLoaded) {
                    setState(() => _fullImageLoaded = true);
                  }
                });
              }
              return child;
            },
            errorBuilder: (_, __, ___) => const SizedBox.shrink(),
          ),
        ),
      ],
    );
  }
}

/// Image preloader for critical images
class ImagePreloader {
  ImagePreloader._();

  static final _instance = ImagePreloader._();
  static ImagePreloader get instance => _instance;

  final _preloading = <String>{};
  final _preloaded = <String>{};

  /// Preload a single image
  Future<void> preload(String url, BuildContext context) async {
    if (_preloaded.contains(url) || _preloading.contains(url)) return;

    _preloading.add(url);

    try {
      await precacheImage(NetworkImage(url), context);
      _preloaded.add(url);
    } catch (e) {
      if (kDebugMode) {
        print('⚠️ Failed to preload image: $url');
      }
    } finally {
      _preloading.remove(url);
    }
  }

  /// Preload multiple images
  Future<void> preloadAll(List<String> urls, BuildContext context) async {
    await Future.wait(urls.map((url) => preload(url, context)));
  }

  /// Check if an image is preloaded
  bool isPreloaded(String url) => _preloaded.contains(url);

  /// Clear preload tracking
  void clear() {
    _preloaded.clear();
    _preloading.clear();
  }
}

/// Aspect ratio image with placeholder
class AspectRatioImage extends StatelessWidget {
  const AspectRatioImage({
    super.key,
    required this.url,
    this.aspectRatio = 16 / 9,
    this.config = const ImageConfig(),
    this.placeholder,
    this.errorWidget,
    this.borderRadius,
  });

  final String url;
  final double aspectRatio;
  final ImageConfig config;
  final Widget? placeholder;
  final Widget? errorWidget;
  final BorderRadius? borderRadius;

  @override
  Widget build(BuildContext context) {
    Widget image = AspectRatio(
      aspectRatio: aspectRatio,
      child: OptimizedImage(
        url: url,
        config: config,
        fit: BoxFit.cover,
        placeholder: placeholder,
        errorWidget: errorWidget,
      ),
    );

    if (borderRadius != null) {
      image = ClipRRect(
        borderRadius: borderRadius!,
        child: image,
      );
    }

    return image;
  }
}

/// Image gallery with lazy loading
class LazyImageGallery extends StatefulWidget {
  const LazyImageGallery({
    super.key,
    required this.imageUrls,
    this.crossAxisCount = 3,
    this.mainAxisSpacing = 4,
    this.crossAxisSpacing = 4,
    this.preloadCount = 6,
    this.onImageTap,
  });

  final List<String> imageUrls;
  final int crossAxisCount;
  final double mainAxisSpacing;
  final double crossAxisSpacing;
  final int preloadCount;
  final void Function(int index, String url)? onImageTap;

  @override
  State<LazyImageGallery> createState() => _LazyImageGalleryState();
}

class _LazyImageGalleryState extends State<LazyImageGallery> {
  final _scrollController = ScrollController();

  @override
  void initState() {
    super.initState();
    _scrollController.addListener(_onScroll);
    // Preload initial images
    WidgetsBinding.instance.addPostFrameCallback((_) {
      _preloadVisible();
    });
  }

  @override
  void dispose() {
    _scrollController.dispose();
    super.dispose();
  }

  void _onScroll() {
    _preloadVisible();
  }

  void _preloadVisible() {
    if (!mounted) return;

    // Calculate visible range and preload
    final viewportHeight = _scrollController.position.viewportDimension;
    final scrollOffset = _scrollController.offset;
    final itemHeight = viewportHeight / widget.crossAxisCount;

    final firstVisible = (scrollOffset / itemHeight).floor() * widget.crossAxisCount;
    final lastVisible = firstVisible + (viewportHeight / itemHeight).ceil() * widget.crossAxisCount;

    final start = (firstVisible - widget.preloadCount).clamp(0, widget.imageUrls.length);
    final end = (lastVisible + widget.preloadCount).clamp(0, widget.imageUrls.length);

    for (var i = start; i < end; i++) {
      ImagePreloader.instance.preload(widget.imageUrls[i], context);
    }
  }

  @override
  Widget build(BuildContext context) {
    return GridView.builder(
      controller: _scrollController,
      gridDelegate: SliverGridDelegateWithFixedCrossAxisCount(
        crossAxisCount: widget.crossAxisCount,
        mainAxisSpacing: widget.mainAxisSpacing,
        crossAxisSpacing: widget.crossAxisSpacing,
      ),
      itemCount: widget.imageUrls.length,
      itemBuilder: (context, index) {
        return GestureDetector(
          onTap: () => widget.onImageTap?.call(index, widget.imageUrls[index]),
          child: OptimizedImage(
            url: widget.imageUrls[index],
            config: const ImageConfig(size: ImageSize.thumbnail),
            fit: BoxFit.cover,
          ),
        );
      },
    );
  }
}

/// Memory-efficient image decoder
Future<ui.Image> decodeImageFromBytes(
  Uint8List bytes, {
  int? targetWidth,
  int? targetHeight,
}) async {
  final codec = await ui.instantiateImageCodec(
    bytes,
    targetWidth: targetWidth,
    targetHeight: targetHeight,
  );
  final frame = await codec.getNextFrame();
  return frame.image;
}

/// Calculate dimensions maintaining aspect ratio
Size calculateResizedDimensions({
  required int originalWidth,
  required int originalHeight,
  required int maxWidth,
  required int maxHeight,
}) {
  final aspectRatio = originalWidth / originalHeight;

  int newWidth = maxWidth;
  int newHeight = (newWidth / aspectRatio).round();

  if (newHeight > maxHeight) {
    newHeight = maxHeight;
    newWidth = (newHeight * aspectRatio).round();
  }

  return Size(newWidth.toDouble(), newHeight.toDouble());
}

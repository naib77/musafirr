import 'package:flutter/material.dart';

/// Async data state representing loading, error, or data
enum AsyncStatus { initial, loading, success, error }

/// Generic async value wrapper
class AsyncValue<T> {
  const AsyncValue._({
    required this.status,
    this.data,
    this.error,
    this.stackTrace,
  });

  factory AsyncValue.initial() => const AsyncValue._(status: AsyncStatus.initial);

  factory AsyncValue.loading() => const AsyncValue._(status: AsyncStatus.loading);

  factory AsyncValue.success(T data) => AsyncValue._(
        status: AsyncStatus.success,
        data: data,
      );

  factory AsyncValue.error(Object error, [StackTrace? stackTrace]) =>
      AsyncValue._(
        status: AsyncStatus.error,
        error: error,
        stackTrace: stackTrace,
      );

  final AsyncStatus status;
  final T? data;
  final Object? error;
  final StackTrace? stackTrace;

  bool get isInitial => status == AsyncStatus.initial;
  bool get isLoading => status == AsyncStatus.loading;
  bool get isSuccess => status == AsyncStatus.success;
  bool get isError => status == AsyncStatus.error;
  bool get hasData => data != null;

  /// Transform the data value
  AsyncValue<R> map<R>(R Function(T data) transform) {
    if (isSuccess && data != null) {
      return AsyncValue.success(transform(data as T));
    }
    return AsyncValue._(
      status: status,
      error: error,
      stackTrace: stackTrace,
    );
  }

  /// Render based on state
  R when<R>({
    required R Function() initial,
    required R Function() loading,
    required R Function(T data) success,
    required R Function(Object error, StackTrace? stackTrace) error,
  }) {
    switch (status) {
      case AsyncStatus.initial:
        return initial();
      case AsyncStatus.loading:
        return loading();
      case AsyncStatus.success:
        return success(data as T);
      case AsyncStatus.error:
        return error(this.error!, stackTrace);
    }
  }

  /// Render with optional overrides
  R maybeWhen<R>({
    R Function()? initial,
    R Function()? loading,
    R Function(T data)? success,
    R Function(Object error, StackTrace? stackTrace)? error,
    required R Function() orElse,
  }) {
    switch (status) {
      case AsyncStatus.initial:
        return initial?.call() ?? orElse();
      case AsyncStatus.loading:
        return loading?.call() ?? orElse();
      case AsyncStatus.success:
        return success?.call(data as T) ?? orElse();
      case AsyncStatus.error:
        return error?.call(this.error!, stackTrace) ?? orElse();
    }
  }
}

/// Loading indicator with optional message
class LoadingIndicator extends StatelessWidget {
  const LoadingIndicator({
    super.key,
    this.message,
    this.size = 24,
    this.strokeWidth = 2.5,
    this.color,
  });

  final String? message;
  final double size;
  final double strokeWidth;
  final Color? color;

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);

    return Column(
      mainAxisSize: MainAxisSize.min,
      mainAxisAlignment: MainAxisAlignment.center,
      children: [
        SizedBox(
          width: size,
          height: size,
          child: CircularProgressIndicator(
            strokeWidth: strokeWidth,
            valueColor: color != null
                ? AlwaysStoppedAnimation(color)
                : null,
          ),
        ),
        if (message != null) ...[
          const SizedBox(height: 16),
          Text(
            message!,
            style: theme.textTheme.bodyMedium?.copyWith(
              color: theme.colorScheme.onSurface.withValues(alpha: 0.7),
            ),
            textAlign: TextAlign.center,
          ),
        ],
      ],
    );
  }
}

/// Full screen loading overlay
class LoadingOverlay extends StatelessWidget {
  const LoadingOverlay({
    super.key,
    required this.isLoading,
    required this.child,
    this.message,
    this.dismissible = false,
    this.onDismiss,
  });

  final bool isLoading;
  final Widget child;
  final String? message;
  final bool dismissible;
  final VoidCallback? onDismiss;

  @override
  Widget build(BuildContext context) {
    return Stack(
      children: [
        child,
        if (isLoading)
          Positioned.fill(
            child: GestureDetector(
              onTap: dismissible ? onDismiss : null,
              child: Container(
                color: Colors.black.withValues(alpha: 0.3),
                child: Center(
                  child: Card(
                    elevation: 8,
                    shape: RoundedRectangleBorder(
                      borderRadius: BorderRadius.circular(16),
                    ),
                    child: Padding(
                      padding: const EdgeInsets.all(24),
                      child: LoadingIndicator(
                        message: message,
                        size: 32,
                      ),
                    ),
                  ),
                ),
              ),
            ),
          ),
      ],
    );
  }
}

/// Shimmer loading effect
class ShimmerLoading extends StatefulWidget {
  const ShimmerLoading({
    super.key,
    required this.child,
    this.baseColor,
    this.highlightColor,
  });

  final Widget child;
  final Color? baseColor;
  final Color? highlightColor;

  @override
  State<ShimmerLoading> createState() => _ShimmerLoadingState();
}

class _ShimmerLoadingState extends State<ShimmerLoading>
    with SingleTickerProviderStateMixin {
  late AnimationController _controller;
  late Animation<double> _animation;

  @override
  void initState() {
    super.initState();
    _controller = AnimationController(
      duration: const Duration(milliseconds: 1500),
      vsync: this,
    )..repeat();
    _animation = Tween<double>(begin: -1, end: 2).animate(
      CurvedAnimation(parent: _controller, curve: Curves.easeInOut),
    );
  }

  @override
  void dispose() {
    _controller.dispose();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    final colorScheme = Theme.of(context).colorScheme;
    final baseColor = widget.baseColor ?? colorScheme.surfaceContainerHighest;
    final highlightColor = widget.highlightColor ?? colorScheme.surface;

    return AnimatedBuilder(
      animation: _animation,
      builder: (context, child) {
        return ShaderMask(
          shaderCallback: (bounds) {
            return LinearGradient(
              begin: Alignment.centerLeft,
              end: Alignment.centerRight,
              colors: [
                baseColor,
                highlightColor,
                baseColor,
              ],
              stops: [
                (_animation.value - 0.3).clamp(0.0, 1.0),
                _animation.value.clamp(0.0, 1.0),
                (_animation.value + 0.3).clamp(0.0, 1.0),
              ],
            ).createShader(bounds);
          },
          blendMode: BlendMode.srcATop,
          child: widget.child,
        );
      },
    );
  }
}

/// Skeleton placeholder shapes
class SkeletonBox extends StatelessWidget {
  const SkeletonBox({
    super.key,
    this.width,
    this.height,
    this.borderRadius = 8,
  });

  final double? width;
  final double? height;
  final double borderRadius;

  @override
  Widget build(BuildContext context) {
    return Container(
      width: width,
      height: height,
      decoration: BoxDecoration(
        color: Theme.of(context).colorScheme.surfaceContainerHighest,
        borderRadius: BorderRadius.circular(borderRadius),
      ),
    );
  }
}

class SkeletonLine extends StatelessWidget {
  const SkeletonLine({
    super.key,
    this.width,
    this.height = 16,
  });

  final double? width;
  final double height;

  @override
  Widget build(BuildContext context) {
    return SkeletonBox(
      width: width,
      height: height,
      borderRadius: 4,
    );
  }
}

class SkeletonCircle extends StatelessWidget {
  const SkeletonCircle({
    super.key,
    this.size = 48,
  });

  final double size;

  @override
  Widget build(BuildContext context) {
    return Container(
      width: size,
      height: size,
      decoration: BoxDecoration(
        color: Theme.of(context).colorScheme.surfaceContainerHighest,
        shape: BoxShape.circle,
      ),
    );
  }
}

/// Skeleton for list items
class SkeletonListItem extends StatelessWidget {
  const SkeletonListItem({
    super.key,
    this.hasLeading = true,
    this.hasTrailing = false,
    this.lines = 2,
  });

  final bool hasLeading;
  final bool hasTrailing;
  final int lines;

  @override
  Widget build(BuildContext context) {
    return ShimmerLoading(
      child: Padding(
        padding: const EdgeInsets.symmetric(vertical: 12, horizontal: 16),
        child: Row(
          children: [
            if (hasLeading) ...[
              const SkeletonCircle(size: 48),
              const SizedBox(width: 16),
            ],
            Expanded(
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: List.generate(lines, (index) {
                  return Padding(
                    padding: EdgeInsets.only(top: index > 0 ? 8 : 0),
                    child: SkeletonLine(
                      width: index == 0
                          ? double.infinity
                          : MediaQuery.of(context).size.width * 0.6,
                      height: index == 0 ? 18 : 14,
                    ),
                  );
                }),
              ),
            ),
            if (hasTrailing) ...[
              const SizedBox(width: 16),
              const SkeletonBox(width: 60, height: 24),
            ],
          ],
        ),
      ),
    );
  }
}

/// Skeleton for cards
class SkeletonCard extends StatelessWidget {
  const SkeletonCard({
    super.key,
    this.height = 200,
    this.hasImage = true,
  });

  final double height;
  final bool hasImage;

  @override
  Widget build(BuildContext context) {
    return ShimmerLoading(
      child: Card(
        elevation: 0,
        shape: RoundedRectangleBorder(
          borderRadius: BorderRadius.circular(16),
          side: BorderSide(
            color: Theme.of(context).colorScheme.outline.withValues(alpha: 0.2),
          ),
        ),
        clipBehavior: Clip.antiAlias,
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            if (hasImage)
              SkeletonBox(
                width: double.infinity,
                height: height * 0.6,
                borderRadius: 0,
              ),
            Padding(
              padding: const EdgeInsets.all(16),
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  const SkeletonLine(height: 20),
                  const SizedBox(height: 8),
                  const SkeletonLine(width: 150, height: 14),
                  const SizedBox(height: 12),
                  Row(
                    mainAxisAlignment: MainAxisAlignment.spaceBetween,
                    children: [
                      const SkeletonLine(width: 80, height: 16),
                      SkeletonBox(width: 60, height: 28, borderRadius: 14),
                    ],
                  ),
                ],
              ),
            ),
          ],
        ),
      ),
    );
  }
}

/// Pull to refresh wrapper with loading state
class RefreshableContent<T> extends StatelessWidget {
  const RefreshableContent({
    super.key,
    required this.asyncValue,
    required this.onRefresh,
    required this.builder,
    this.loadingBuilder,
    this.errorBuilder,
    this.emptyBuilder,
    this.isEmpty,
  });

  final AsyncValue<T> asyncValue;
  final Future<void> Function() onRefresh;
  final Widget Function(T data) builder;
  final Widget Function()? loadingBuilder;
  final Widget Function(Object error, StackTrace? stackTrace)? errorBuilder;
  final Widget Function()? emptyBuilder;
  final bool Function(T data)? isEmpty;

  @override
  Widget build(BuildContext context) {
    return RefreshIndicator(
      onRefresh: onRefresh,
      child: asyncValue.when(
        initial: () => loadingBuilder?.call() ?? _defaultLoading(),
        loading: () => loadingBuilder?.call() ?? _defaultLoading(),
        success: (data) {
          if (isEmpty?.call(data) ?? false) {
            return emptyBuilder?.call() ?? _defaultEmpty(context);
          }
          return builder(data);
        },
        error: (error, stackTrace) =>
            errorBuilder?.call(error, stackTrace) ??
            _defaultError(context, error),
      ),
    );
  }

  Widget _defaultLoading() {
    return const Center(child: CircularProgressIndicator());
  }

  Widget _defaultEmpty(BuildContext context) {
    return Center(
      child: Column(
        mainAxisAlignment: MainAxisAlignment.center,
        children: [
          Icon(
            Icons.inbox_outlined,
            size: 64,
            color: Theme.of(context).colorScheme.outline,
          ),
          const SizedBox(height: 16),
          Text(
            'No data available',
            style: Theme.of(context).textTheme.bodyLarge?.copyWith(
                  color: Theme.of(context).colorScheme.onSurface.withValues(alpha: 0.7),
                ),
          ),
        ],
      ),
    );
  }

  Widget _defaultError(BuildContext context, Object error) {
    return Center(
      child: Padding(
        padding: const EdgeInsets.all(24),
        child: Column(
          mainAxisAlignment: MainAxisAlignment.center,
          children: [
            Icon(
              Icons.error_outline,
              size: 64,
              color: Theme.of(context).colorScheme.error,
            ),
            const SizedBox(height: 16),
            Text(
              error.toString(),
              style: Theme.of(context).textTheme.bodyLarge,
              textAlign: TextAlign.center,
            ),
            const SizedBox(height: 16),
            FilledButton(
              onPressed: onRefresh,
              child: const Text('Try Again'),
            ),
          ],
        ),
      ),
    );
  }
}

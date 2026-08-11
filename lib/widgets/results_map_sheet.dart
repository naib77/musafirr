import 'package:flutter/material.dart';
import 'package:pointer_interceptor/pointer_interceptor.dart';

/// Search results over a full-bleed map, the way Airbnb shows them on a phone:
/// the map is the context, the sheet is the answer, and the guest drags the
/// sheet to choose how much of each to see.
///
/// Lives in its own widget so it can be tested — [ExploreScreen] can't be built
/// in a test at all (it takes a concrete auth notifier that wires itself to
/// Supabase), and the sheet's drag behaviour is exactly the sort of thing only
/// a test catches. The map arrives as a widget for the same reason: the real
/// one needs a platform view, and none of the behaviour here depends on it.
class ResultsMapSheet extends StatelessWidget {
  const ResultsMapSheet({
    super.key,
    required this.map,
    required this.slivers,
  });

  /// Fills the space behind the sheet.
  final Widget map;

  /// The result content: banner, card grid, footer. Passed in so every layout
  /// in Explore shares one definition of it.
  final List<Widget> slivers;

  /// Sheet heights it comes to rest at, as a fraction of the available space:
  /// mostly-map, half-and-half, mostly-list.
  static const double minSize = 0.15;
  static const double initialSize = 0.45;
  static const double maxSize = 0.95;

  /// The sheet's own surface, so a test can measure where its top edge sits.
  static const Key surfaceKey = ValueKey('results-sheet-surface');

  /// The grab handle, so a test can drag exactly where a guest would.
  static const Key handleKey = ValueKey('results-sheet-handle');

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);

    return Stack(
      children: [
        Positioned.fill(child: map),
        DraggableScrollableSheet(
          initialChildSize: initialSize,
          minChildSize: minSize,
          maxChildSize: maxSize,
          snap: true,
          snapSizes: const [minSize, initialSize, maxSize],
          builder: (context, sheetController) {
            // On web the map is a DOM element that wins the browser's own
            // hit-test even where Flutter paints the sheet over it, so a drag
            // or a wheel meant for the sheet also reached Google Maps: the map
            // panned and zoomed under the guest's finger. PointerInterceptor
            // puts a real DOM blocker in front of it, the size of the sheet,
            // which is the only way to stop that. No-op off web.
            return PointerInterceptor(
              child: DecoratedBox(
                key: surfaceKey,
                decoration: BoxDecoration(
                  color: theme.colorScheme.surface,
                  borderRadius: const BorderRadius.vertical(
                    top: Radius.circular(20),
                  ),
                  boxShadow: [
                    BoxShadow(
                      color: Colors.black.withValues(alpha: 0.16),
                      blurRadius: 16,
                      offset: const Offset(0, -4),
                    ),
                  ],
                ),
                child: ClipRRect(
                  borderRadius: const BorderRadius.vertical(
                    top: Radius.circular(20),
                  ),
                  // Every part of the sheet is inside the scroll view,
                  // handle included. A DraggableScrollableSheet is moved by
                  // its scrollable and nothing else, so a handle sitting
                  // outside it — where the handle used to be — looks
                  // draggable and isn't.
                  //
                  // No RefreshIndicator: pulling down is how the sheet is
                  // collapsed, and search results come from a single query
                  // that a pull could not refresh anyway.
                  child: CustomScrollView(
                    controller: sheetController,
                    slivers: [
                      SliverPersistentHeader(
                        pinned: true,
                        delegate: _GrabHandle(
                          color: theme.colorScheme.outlineVariant,
                          background: theme.colorScheme.surface,
                        ),
                      ),
                      ...slivers,
                    ],
                  ),
                ),
              ),
            );
          },
        ),
      ],
    );
  }
}

/// The grab handle, pinned to the top of the sheet's scroll view: it stays put
/// as the results scroll under it, and because it is inside the scroll view a
/// drag on it moves the sheet.
class _GrabHandle extends SliverPersistentHeaderDelegate {
  const _GrabHandle({required this.color, required this.background});

  final Color color;
  final Color background;

  // Taller than the 4px bar it draws: this strip is the drag target, and a
  // 4px one is impossible to catch with a thumb.
  static const double _height = 28;

  @override
  double get minExtent => _height;

  @override
  double get maxExtent => _height;

  @override
  Widget build(
      BuildContext context, double shrinkOffset, bool overlapsContent) {
    return ColoredBox(
      key: ResultsMapSheet.handleKey,
      color: background,
      child: Center(
        child: Container(
          width: 40,
          height: 4,
          decoration: BoxDecoration(
            color: color,
            borderRadius: BorderRadius.circular(2),
          ),
        ),
      ),
    );
  }

  @override
  bool shouldRebuild(_GrabHandle oldDelegate) =>
      oldDelegate.color != color || oldDelegate.background != background;
}

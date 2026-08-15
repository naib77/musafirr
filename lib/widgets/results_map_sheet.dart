import 'package:flutter/gestures.dart'
    show PointerScrollEvent, PointerSignalEvent;
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
class ResultsMapSheet extends StatefulWidget {
  const ResultsMapSheet({
    super.key,
    required this.mapBuilder,
    required this.slivers,
  });

  /// Builds the map that fills the space behind the sheet. Receives the height
  /// (in px) the sheet currently covers at the bottom, so the map can inset its
  /// camera (Google Maps `padding`) and frame results in the VISIBLE strip
  /// above the sheet — otherwise a "Dhaka" fit centres behind the sheet and
  /// only the area north of it shows. Tracks the sheet live as it's dragged.
  final Widget Function(BuildContext context, double bottomInset) mapBuilder;

  /// The result content: banner, card grid, footer. Passed in so every layout
  /// in Explore shares one definition of it.
  final List<Widget> slivers;

  /// Sheet heights it comes to rest at, as a fraction of the available space:
  /// mostly-map, half-and-half, and full (covering the map right up to the
  /// search bar, the way Airbnb's list does).
  static const double minSize = 0.15;
  static const double initialSize = 0.45;
  static const double maxSize = 1.0;

  /// Past this extent the map is effectively hidden, so the floating "Map"
  /// button appears to bring it back.
  static const double _mapHiddenAbove = 0.85;

  /// The sheet's own surface, so a test can measure where its top edge sits.
  static const Key surfaceKey = ValueKey('results-sheet-surface');

  /// The grab handle, so a test can drag exactly where a guest would.
  static const Key handleKey = ValueKey('results-sheet-handle');

  /// The floating "Map" button, so a test can tap it.
  static const Key mapButtonKey = ValueKey('results-sheet-map-button');

  @override
  State<ResultsMapSheet> createState() => _ResultsMapSheetState();
}

class _ResultsMapSheetState extends State<ResultsMapSheet> {
  // The sheet's current size as a fraction of the available height. Seeded at
  // the resting size and updated live from the sheet's own drag notifications.
  // A ValueNotifier (not setState) so only the map subtree rebuilds as the
  // sheet moves — the DraggableScrollableSheet must not rebuild mid-drag.
  final ValueNotifier<double> _extent =
      ValueNotifier<double>(ResultsMapSheet.initialSize);

  // Drives the sheet programmatically so the floating "Map" button can slide it
  // back down to the half-and-half rest position.
  final DraggableScrollableController _sheetController =
      DraggableScrollableController();

  // The sheet's inner list controller (handed to us by the sheet builder). Read
  // to know whether the list is at its top, and pinned there while a wheel
  // gesture is growing the sheet instead of scrolling the list.
  ScrollController? _inner;

  @override
  void dispose() {
    _extent.dispose();
    _sheetController.dispose();
    super.dispose();
  }

  void _revealMap() {
    if (!_sheetController.isAttached) return;
    _sheetController.animateTo(
      ResultsMapSheet.initialSize,
      duration: const Duration(milliseconds: 300),
      curve: Curves.easeOutCubic,
    );
  }

  /// Translates a mouse-wheel / trackpad scroll into sheet growth, the piece
  /// DraggableScrollableSheet only does for touch drags. Scrolling down grows
  /// the sheet until it's full, then the list scrolls; scrolling up at the top
  /// of the list shrinks the sheet back toward the map. Below full the list is
  /// pinned to its top so the drawer grows first — exactly how a touch drag
  /// behaves, and how Airbnb's list feels.
  void _handleWheel(PointerSignalEvent event, double available) {
    if (event is! PointerScrollEvent ||
        !_sheetController.isAttached ||
        available <= 0) {
      return;
    }
    final size = _sheetController.size;
    final dy = event.scrollDelta.dy;
    final atTop =
        !(_inner?.hasClients ?? false) || _inner!.position.pixels <= 0;
    final growing = dy > 0 && size < ResultsMapSheet.maxSize - 1e-4;
    final shrinking = dy < 0 && atTop && size > ResultsMapSheet.minSize + 1e-4;
    if (!growing && !shrinking) return; // let the list scroll normally

    final next = (size + dy / available)
        .clamp(ResultsMapSheet.minSize, ResultsMapSheet.maxSize);
    _sheetController.jumpTo(next);
    // The Scrollable also handles this same wheel event (right after us), which
    // would scroll the list while we're growing the sheet. Keep it pinned to
    // the top until the sheet is actually full.
    if (growing && (_inner?.hasClients ?? false)) {
      WidgetsBinding.instance.addPostFrameCallback((_) {
        if ((_inner?.hasClients ?? false) &&
            _sheetController.isAttached &&
            _sheetController.size < ResultsMapSheet.maxSize - 1e-4 &&
            _inner!.position.pixels != 0) {
          _inner!.jumpTo(0);
        }
      });
    }
  }

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);

    return LayoutBuilder(
      builder: (context, constraints) {
        final available = constraints.maxHeight;
        return NotificationListener<DraggableScrollableNotification>(
          onNotification: (n) {
            _extent.value = n.extent;
            return false;
          },
          child: Stack(
            children: [
              Positioned.fill(
                child: ValueListenableBuilder<double>(
                  valueListenable: _extent,
                  builder: (context, extent, _) =>
                      widget.mapBuilder(context, extent * available),
                ),
              ),
              DraggableScrollableSheet(
                controller: _sheetController,
                initialChildSize: ResultsMapSheet.initialSize,
                minChildSize: ResultsMapSheet.minSize,
                maxChildSize: ResultsMapSheet.maxSize,
                // No snap: snapping fights scrolling. A mouse wheel / trackpad
                // arrives as many small discrete scroll events, and after each
                // one the snap would yank the sheet back to the nearest rest
                // size — so scrolling up never reached full screen. Without
                // snap the sheet follows the scroll continuously all the way to
                // full (and down to the peek), the way Airbnb's list does; the
                // floating "Map" button is the quick way back to the map.
                builder: (context, sheetController) {
                  _inner = sheetController;
                  // On web the map is a DOM element that wins the browser's own
                  // hit-test even where Flutter paints the sheet over it, so a drag
                  // or a wheel meant for the sheet also reached Google Maps: the map
                  // panned and zoomed under the guest's finger. PointerInterceptor
                  // puts a real DOM blocker in front of it, the size of the sheet,
                  // which is the only way to stop that. No-op off web.
                  //
                  // The Listener turns a wheel/trackpad scroll into sheet growth
                  // (see _handleWheel) — DraggableScrollableSheet only grows on touch
                  // drags, so without this, scrolling on desktop just moved the list
                  // inside a fixed-height drawer instead of expanding it to full.
                  return Listener(
                    onPointerSignal: (event) => _handleWheel(event, available),
                    child: PointerInterceptor(
                      child: DecoratedBox(
                        key: ResultsMapSheet.surfaceKey,
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
                              ...widget.slivers,
                            ],
                          ),
                        ),
                      ),
                    ),
                  );
                },
              ),
              // Floating "Map" button, Airbnb-style: once the sheet covers
              // the map it's the way back. It rebuilds only itself as the
              // sheet moves (ValueListenableBuilder on the extent), and slides
              // the sheet back to half-and-half on tap.
              Positioned(
                left: 0,
                right: 0,
                bottom: 20 + MediaQuery.paddingOf(context).bottom,
                child: Center(
                  child: ValueListenableBuilder<double>(
                    valueListenable: _extent,
                    builder: (context, extent, child) {
                      final visible = extent > ResultsMapSheet._mapHiddenAbove;
                      return IgnorePointer(
                        ignoring: !visible,
                        child: AnimatedSlide(
                          offset: visible ? Offset.zero : const Offset(0, 2),
                          duration: const Duration(milliseconds: 220),
                          curve: Curves.easeOutCubic,
                          child: AnimatedOpacity(
                            opacity: visible ? 1 : 0,
                            duration: const Duration(milliseconds: 160),
                            child: child,
                          ),
                        ),
                      );
                    },
                    // Built once; only its visibility animates.
                    child: PointerInterceptor(
                      child: Material(
                        color: const Color(0xFF222222),
                        borderRadius: BorderRadius.circular(24),
                        elevation: 4,
                        child: InkWell(
                          key: ResultsMapSheet.mapButtonKey,
                          borderRadius: BorderRadius.circular(24),
                          onTap: _revealMap,
                          child: const Padding(
                            padding: EdgeInsets.symmetric(
                                horizontal: 18, vertical: 12),
                            child: Row(
                              mainAxisSize: MainAxisSize.min,
                              children: [
                                Text(
                                  'Map',
                                  style: TextStyle(
                                    color: Colors.white,
                                    fontWeight: FontWeight.w600,
                                    fontSize: 14,
                                  ),
                                ),
                                SizedBox(width: 8),
                                Icon(Icons.map_outlined,
                                    color: Colors.white, size: 18),
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
          ),
        );
      },
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

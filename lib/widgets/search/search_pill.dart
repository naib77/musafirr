import 'package:flutter/foundation.dart' show mapEquals;
import 'package:flutter/material.dart';

import '../../core/theme/app_colors.dart';
import '../../models/geo_bounds.dart';
import '../../models/landmark.dart';
import '../../models/search_filters.dart';
import '../../services/search/search_summary.dart';
import '../map_place_search_bar.dart' show PlaceLocateFn, PlaceSuggestFn;
import '../voice_search_button.dart';
import 'filters_panel.dart';
import 'search_commit.dart';
import 'search_draft.dart';
import 'search_popover.dart';
import 'search_pill_segments.dart';
import 'when_panel.dart';
import 'where_panel.dart';
import 'who_panel.dart';

/// Resolves typed text to a place when no prediction was tapped. Injected so
/// the bar can be driven in a test without a network.
typedef GeocodeFn = Future<ResolvedPlace?> Function(String query);

/// What a geocode came back with — the subset of the geocoding result the bar
/// actually uses.
///
/// A point and a box are independent: a city resolves to a box with no centre,
/// a street address to a centre with no box, and the search treats the two
/// differently (extent versus expanding ring).
class ResolvedPlace {
  const ResolvedPlace({this.latitude, this.longitude, this.bounds});

  final double? latitude;
  final double? longitude;
  final GeoBounds? bounds;
}

/// The desktop search bar: Where | When | Who, each opening its own panel.
///
/// ## The one thing this exists to get right
///
/// Every mutator on `SearchStateNotifier` runs a search the moment it is
/// called. Three panels that each committed on close would fire three
/// `search_listings` round trips for a single search, and the feed would
/// rearrange itself twice while the guest was still deciding. So the panels
/// write to a [SearchDraft] and **exactly one** `updateFilters` fires, from the
/// Search button. Nothing else in this file talks to the notifier.
///
/// ## Why the draft is re-seeded rather than kept
///
/// The bar is rebuilt whenever the committed filters change — a ✕, a voice
/// search, a result arriving. A draft that survived those would keep describing
/// a search that no longer exists, so [didUpdateWidget] rebuilds it whenever
/// the incoming filters differ from what was last committed from here.
class SearchPill extends StatefulWidget {
  const SearchPill({
    super.key,
    required this.filters,
    required this.onCommit,
    required this.cities,
    required this.onPickLandmark,
    this.onClear,
    this.onVoice,
    this.geocode,
    this.suggest,
    this.locate,
    this.currentLocation,
    this.today,
  });

  /// The search currently running. Seeds the draft and fills the segments.
  final SearchFilters filters;

  /// Runs the search. Called once per Search press, never on panel close.
  final ValueChanged<SearchFilters> onCommit;

  /// Known cities matching a query, from the listing cache.
  final CitySuggestFn cities;

  /// Presents the landmark picker. It is a route-level sheet, so the bar closes
  /// the popover around it — see [_pickLandmark].
  final LandmarkPickFn onPickLandmark;

  /// Drops the running search. Null when there is nothing to drop.
  final VoidCallback? onClear;

  final VoidCallback? onVoice;
  final GeocodeFn? geocode;
  final PlaceSuggestFn? suggest;
  final PlaceLocateFn? locate;
  final CurrentLocationFn? currentLocation;

  /// Injected in tests so the calendar and its shortcuts are deterministic.
  final DateTime? today;

  @override
  State<SearchPill> createState() => _SearchPillState();
}

class _SearchPillState extends State<SearchPill> with WidgetsBindingObserver {
  late SearchDraft _draft;
  SearchSegment? _open;

  /// True while the typed text is being geocoded. Disables Search, the way the
  /// sheet's `_resolvingPlace` does, so a second press cannot race the first.
  bool _resolving = false;

  /// Shown and hidden from event handlers, never from build.
  ///
  /// `OverlayPortalController.show()` asserts it is not called during the
  /// build phase, and an assertion thrown inside the overlay child paints a
  /// full-screen dark red ErrorWidget — that child covers the window. The
  /// first version drove this from `initState`/`didUpdateWidget`, both of which
  /// run during build.
  final _portal = OverlayPortalController();

  final _barKey = GlobalKey();
  final _segmentKeys = {
    for (final segment in SearchSegment.values) segment: GlobalKey(),
  };

  /// Where the bar and each segment actually are, in global coordinates.
  ///
  /// Measured in a post-frame callback and held in state — **never read during
  /// build**. The first version called `localToGlobal` inside `build` to place
  /// the scrim, which reads layout from a tree that may be mid-update: it can
  /// hand back a stale rectangle (the scrim jumps for a frame) or assert
  /// outright, and an assertion in the overlay child paints a full-screen dark
  /// red ErrorWidget because that child covers the window.
  Rect? _barRect;
  final Map<SearchSegment, Rect> _segmentRects = {};

  @override
  void initState() {
    super.initState();
    _draft = SearchDraft.from(widget.filters);
    WidgetsBinding.instance.addObserver(this);
    // Measured before anything can be opened, so a panel never has to render a
    // frame without knowing where to go.
    _scheduleMeasure();
  }

  @override
  void didUpdateWidget(SearchPill oldWidget) {
    super.didUpdateWidget(oldWidget);
    // Re-seed when the running search changed underneath us. Identical filters
    // arrive on every unrelated rebuild, so compare rather than always reset —
    // otherwise typing in the Where panel would be wiped by the next repaint.
    if (!identical(widget.filters, oldWidget.filters) &&
        widget.filters != oldWidget.filters) {
      _draft.dispose();
      _draft = SearchDraft.from(widget.filters);
    }
  }

  /// The window resized, so every rectangle moved.
  @override
  void didChangeMetrics() => _scheduleMeasure();

  @override
  void dispose() {
    WidgetsBinding.instance.removeObserver(this);
    _draft.dispose();
    super.dispose();
  }

  void _scheduleMeasure() {
    WidgetsBinding.instance.addPostFrameCallback((_) => _measure());
  }

  void _measure() {
    if (!mounted) return;
    final barBox = _barKey.currentContext?.findRenderObject() as RenderBox?;
    // `attached` as well as `hasSize`: this runs a frame late, by which time
    // the bar may have been taken off screen, and localToGlobal on a detached
    // render object asserts.
    if (barBox == null || !barBox.attached || !barBox.hasSize) return;
    final barRect = barBox.localToGlobal(Offset.zero) & barBox.size;

    final rects = <SearchSegment, Rect>{};
    for (final entry in _segmentKeys.entries) {
      final box = entry.value.currentContext?.findRenderObject() as RenderBox?;
      if (box == null || !box.attached || !box.hasSize) continue;
      rects[entry.key] = box.localToGlobal(Offset.zero) & box.size;
    }

    // Guard the setState or this loops forever: a post-frame callback that
    // always rebuilds schedules another frame, which schedules another.
    if (barRect == _barRect && mapEquals(rects, _segmentRects)) return;
    setState(() {
      _barRect = barRect;
      _segmentRects
        ..clear()
        ..addAll(rects);
    });
  }

  void _toggle(SearchSegment segment) =>
      _setOpen(_open == segment ? null : segment);

  void _close() => _setOpen(null);

  /// The single writer of [_open].
  ///
  /// Callers are all event handlers — a tap, an Escape, the end of an await —
  /// which is what keeps the portal calls out of the build phase.
  void _setOpen(SearchSegment? next) {
    if (_open == next) return;
    setState(() => _open = next);
    if (next == null) {
      _portal.hide();
    } else {
      _portal.show();
    }
    // The bar's own layout shifts a little when a segment lifts, so the anchor
    // is re-read once the new frame exists.
    _scheduleMeasure();
  }

  Future<void> _submit() async {
    _close();
    final text = _draft.locationText.trim();

    // Nothing resolved yet and something was typed → resolve it, exactly as
    // the sheet does. A box beats a point: it lets the search cover a place's
    // real extent instead of a ring that spills into the next thana.
    if (text.isNotEmpty &&
        _draft.latitude == null &&
        _draft.bounds == null &&
        widget.geocode != null) {
      setState(() => _resolving = true);
      final place = await widget.geocode!(text);
      if (!mounted) return;
      setState(() => _resolving = false);
      if (place != null) {
        _draft.latitude = place.latitude;
        _draft.longitude = place.longitude;
        _draft.bounds = place.bounds;
      }
    }

    widget.onCommit(filtersFromDraft(_draft, widget.filters));
  }

  /// The landmark picker is a modal route, so the popover comes down first and
  /// goes back up afterwards. A bottom sheet sliding up over a dropdown reads
  /// as two competing surfaces.
  Future<Landmark?> _pickLandmark(
    BuildContext context, {
    required String type,
    required String title,
  }) async {
    final wasOpen = _open;
    _close();
    final chosen =
        await widget.onPickLandmark(context, type: type, title: title);
    if (!mounted) return chosen;
    setState(() => _open = wasOpen);
    return chosen;
  }

  @override
  Widget build(BuildContext context) {
    final today = widget.today ?? DateTime.now();

    return ListenableBuilder(
      listenable: _draft,
      builder: (context, _) {
        final summary = searchPillSummaryFor(filtersFromDraft(
          _draft,
          const SearchFilters(),
        ));

        return Row(
          mainAxisSize: MainAxisSize.min,
          crossAxisAlignment: CrossAxisAlignment.center,
          children: [
            Flexible(
              child: SearchPillBar(
                key: _barKey,
                segmentKeys: _segmentKeys,
                open: _open,
                where: summary.where,
                when: summary.when,
                who: summary.who,
                busy: _resolving,
                onSegmentTap: _toggle,
                onSubmit: _resolving ? null : _submit,
                onClear: widget.onClear,
                voice: widget.onVoice == null
                    ? null
                    : VoiceSearchMicButton(onTap: widget.onVoice!),
              ),
            ),
            const SizedBox(width: 10),
            FiltersButton(
              key: _segmentKeys[SearchSegment.filters],
              count: _activeFilterCount,
              open: _open == SearchSegment.filters,
              onTap: () => _toggle(SearchSegment.filters),
            ),
            // Zero-sized here: the panel itself lives in the Overlay, and this
            // is only where it is anchored in the tree. Always mounted — the
            // controller decides whether anything shows, so nothing has to be
            // added to or removed from the tree during a build.
            OverlayPortal(
              controller: _portal,
              overlayChildBuilder: (context) => _overlay(today),
              child: const SizedBox.shrink(),
            ),
          ],
        );
      },
    );
  }

  Widget _overlay(DateTime today) {
    final segment = _open;
    // Between hide() and the overlay's next build the segment can already be
    // null; and on the very first frame the anchor may not be measured yet.
    // Either way there is nothing to place, and guessing a position would show
    // the panel at the window's origin and then jump it.
    if (segment == null) return const SizedBox.shrink();
    final anchor = _segmentRects[segment];
    if (anchor == null) return const SizedBox.shrink();

    return SearchPopover(
      anchor: anchor,
      scrimTop: _scrimTop,
      align: segment.align,
      width: kSearchPanelWidth,
      contentKey: segment,
      onDismiss: _close,
      child: _panelFor(segment, today),
    );
  }

  /// Where the dim starts: the bar's bottom edge, so the header stays bright.
  double get _scrimTop => (_barRect?.bottom ?? 0) + 16;

  int get _activeFilterCount =>
      _draft.propertyTypes.length + (_draft.purpose == null ? 0 : 1);

  Widget _panelFor(SearchSegment segment, DateTime today) {
    switch (segment) {
      case SearchSegment.where:
        return WherePanel(
          draft: _draft,
          cities: widget.cities,
          onSubmit: _submit,
          suggest: widget.suggest,
          locate: widget.locate,
          currentLocation: widget.currentLocation,
        );
      case SearchSegment.when:
        return WhenPanel(draft: _draft, today: today);
      case SearchSegment.who:
        return WhoPanel(draft: _draft);
      case SearchSegment.filters:
        return FiltersPanel(draft: _draft, onPickLandmark: _pickLandmark);
    }
  }
}

/// The count badge on the Filters button.
class FiltersButton extends StatefulWidget {
  const FiltersButton({
    super.key,
    required this.count,
    required this.open,
    required this.onTap,
  });

  final int count;
  final bool open;
  final VoidCallback onTap;

  @override
  State<FiltersButton> createState() => _FiltersButtonState();
}

class _FiltersButtonState extends State<FiltersButton> {
  bool _hovered = false;

  @override
  Widget build(BuildContext context) {
    return Semantics(
      button: true,
      expanded: widget.open,
      label: widget.count == 0 ? 'Filters' : 'Filters, ${widget.count} on',
      excludeSemantics: true,
      child: Tooltip(
        message: 'More filters',
        child: MouseRegion(
          cursor: SystemMouseCursors.click,
          onEnter: (_) => setState(() => _hovered = true),
          onExit: (_) => setState(() => _hovered = false),
          child: InkWell(
            onTap: widget.onTap,
            borderRadius: BorderRadius.circular(24),
            child: AnimatedContainer(
              duration: const Duration(milliseconds: 160),
              height: 48,
              padding: const EdgeInsets.symmetric(horizontal: 16),
              decoration: BoxDecoration(
                color: AppColors.surface,
                borderRadius: BorderRadius.circular(24),
                border: Border.all(
                  color: widget.open || widget.count > 0
                      ? AppColors.brand
                      : AppColors.outline,
                  width: widget.open || widget.count > 0 ? 1.4 : 1,
                ),
                boxShadow: _hovered || widget.open
                    ? [
                        BoxShadow(
                          color: Colors.black.withValues(alpha: 0.10),
                          blurRadius: 10,
                          offset: const Offset(0, 2),
                        ),
                      ]
                    : const [],
              ),
              child: Row(
                mainAxisSize: MainAxisSize.min,
                children: [
                  Icon(Icons.tune_rounded, size: 18, color: AppColors.ink),
                  const SizedBox(width: 8),
                  Text(
                    'Filters',
                    style: TextStyle(
                      fontSize: 14,
                      fontWeight: FontWeight.w600,
                      color: AppColors.ink,
                    ),
                  ),
                  if (widget.count > 0) ...[
                    const SizedBox(width: 8),
                    Container(
                      width: 20,
                      height: 20,
                      alignment: Alignment.center,
                      decoration: BoxDecoration(
                        color: AppColors.brand,
                        shape: BoxShape.circle,
                      ),
                      child: Text(
                        '${widget.count}',
                        style: const TextStyle(
                          fontSize: 11,
                          fontWeight: FontWeight.w700,
                          color: Colors.white,
                        ),
                      ),
                    ),
                  ],
                ],
              ),
            ),
          ),
        ),
      ),
    );
  }
}

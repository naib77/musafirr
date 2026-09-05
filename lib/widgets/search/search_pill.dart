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

class _SearchPillState extends State<SearchPill> {
  late SearchDraft _draft;
  SearchSegment? _open;

  /// True while the typed text is being geocoded. Disables Search, the way the
  /// sheet's `_resolvingPlace` does, so a second press cannot race the first.
  bool _resolving = false;

  final _links = {
    for (final segment in SearchSegment.values) segment: LayerLink(),
  };
  final _barKey = GlobalKey();

  @override
  void initState() {
    super.initState();
    _draft = SearchDraft.from(widget.filters);
  }

  @override
  void didUpdateWidget(SearchPill oldWidget) {
    super.didUpdateWidget(oldWidget);
    // Re-seed when the running search changed underneath us. Identical filters
    // arrive on every unrelated rebuild, so compare rather than always reset —
    // otherwise typing in the Where panel would be wiped by the next repaint.
    if (!identical(widget.filters, oldWidget.filters) &&
        widget.filters != oldWidget.filters) {
      _draft = SearchDraft.from(widget.filters);
    }
  }

  @override
  void dispose() {
    _draft.dispose();
    super.dispose();
  }

  void _toggle(SearchSegment segment) {
    setState(() => _open = _open == segment ? null : segment);
  }

  void _close() {
    if (_open != null) setState(() => _open = null);
  }

  /// Global Y of the header's bottom edge, so the scrim starts below the bar
  /// rather than dimming it.
  double get _scrimTop {
    final box = _barKey.currentContext?.findRenderObject() as RenderBox?;
    if (box == null || !box.hasSize) return 0;
    // The header pads 16 below the pill; dimming from the pill's own bottom
    // would leave a bright strip that looks like a rendering seam.
    return box.localToGlobal(Offset.zero).dy + box.size.height + 16;
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
                links: _links,
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
              count: _activeFilterCount,
              open: _open == SearchSegment.filters,
              link: _links[SearchSegment.filters]!,
              onTap: () => _toggle(SearchSegment.filters),
            ),
            if (_open != null)
              // Zero-sized: the panel itself lives in the Overlay. This is only
              // where the OverlayPortal is anchored in the tree.
              _PanelPortal(
                open: true,
                child: SearchPopover(
                  link: _links[_open!]!,
                  align: _open!.align,
                  scrimTop: _scrimTop,
                  onDismiss: _close,
                  width: _open!.panelWidth,
                  child: _panelFor(_open!, today),
                ),
              ),
          ],
        );
      },
    );
  }

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

/// Mounts [child] into the [Overlay] while [open].
///
/// A tiny wrapper so the pill's build method stays readable: [OverlayPortal]
/// needs a controller whose lifetime is a State, and inlining that would put
/// three more fields on the bar for no gain.
class _PanelPortal extends StatefulWidget {
  const _PanelPortal({required this.open, required this.child});

  final bool open;
  final Widget child;

  @override
  State<_PanelPortal> createState() => _PanelPortalState();
}

class _PanelPortalState extends State<_PanelPortal> {
  final _controller = OverlayPortalController();

  @override
  void initState() {
    super.initState();
    if (widget.open) _controller.show();
  }

  @override
  void didUpdateWidget(_PanelPortal oldWidget) {
    super.didUpdateWidget(oldWidget);
    if (widget.open && !_controller.isShowing) _controller.show();
    if (!widget.open && _controller.isShowing) _controller.hide();
  }

  @override
  Widget build(BuildContext context) {
    return OverlayPortal(
      controller: _controller,
      overlayChildBuilder: (context) => widget.child,
      child: const SizedBox.shrink(),
    );
  }
}

/// The count badge on the Filters button.
class FiltersButton extends StatefulWidget {
  const FiltersButton({
    super.key,
    required this.count,
    required this.open,
    required this.link,
    required this.onTap,
  });

  final int count;
  final bool open;
  final LayerLink link;
  final VoidCallback onTap;

  @override
  State<FiltersButton> createState() => _FiltersButtonState();
}

class _FiltersButtonState extends State<FiltersButton> {
  bool _hovered = false;

  @override
  Widget build(BuildContext context) {
    return CompositedTransformTarget(
      link: widget.link,
      child: Semantics(
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
      ),
    );
  }
}

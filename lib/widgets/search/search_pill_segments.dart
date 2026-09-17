import 'package:flutter/foundation.dart' show mapEquals;
import 'package:flutter/material.dart';

import '../../core/theme/app_colors.dart';
import '../../core/theme/brand.dart';
import 'search_popover.dart';

/// The parts of the bar that can be open. `filters` is not a segment of the
/// pill — it is the button beside it — but it opens a panel the same way, so it
/// shares the enum rather than needing a second "what is open" field.
enum SearchSegment { where, when, who, filters }

extension SearchSegmentX on SearchSegment {
  String get label => switch (this) {
        SearchSegment.where => 'Where',
        SearchSegment.when => 'When',
        SearchSegment.who => 'Who',
        SearchSegment.filters => 'Filters',
      };

  String get placeholder => switch (this) {
        SearchSegment.where => 'Search destinations',
        SearchSegment.when => 'Add dates',
        SearchSegment.who => 'Add guests',
        SearchSegment.filters => '',
      };

  /// Which edge lines up with the segment. The right-hand ones open inwards so
  /// a wide panel cannot run off the side of the window.
  SearchPopoverAlign get align => switch (this) {
        SearchSegment.where => SearchPopoverAlign.left,
        SearchSegment.when => SearchPopoverAlign.center,
        SearchSegment.who => SearchPopoverAlign.right,
        SearchSegment.filters => SearchPopoverAlign.right,
      };
}

/// One width for every panel.
///
/// They used to differ per segment and the card's width animated between them,
/// which looked right for about one frame and then wasn't: mid-morph the
/// calendar was laid out at the Who panel's width and its month grid — 7 fixed
/// 40px cells beside a 132px shortcut rail — overflowed by 45 pixels, striping
/// the panel. Cross-fading two panels means BOTH are laid out during the
/// transition, so any width either one cannot survive is a width neither can
/// use.
///
/// 560 is what the calendar needs; everything else has room to spare, and a
/// bar whose dropdown is always the same size reads as one control rather than
/// four. It also means only the position animates, which is the movement that
/// actually communicates "the panel moved to this segment".
const double kSearchPanelWidth = 560;

/// The bar: three segments, a mic, a ✕ and the Search button.
///
/// Purely presentational — it reports taps and renders strings. Everything
/// about *what* is being searched lives in `SearchPill` and the draft, so this
/// file can be read as a picture of the chrome.
///
/// The open state is Airbnb's: the whole bar drops to a muted grey and the
/// active segment lifts back out of it in white with a shadow, which reads as
/// "this one is what you are editing" far better than a highlight would. The
/// divider beside an active segment hides, or the lifted card appears to have a
/// line stuck to its edge.
///
/// The lifted card is ONE widget that travels, not a colour on each segment.
/// It used to be the latter — every segment cross-faded its own background,
/// so Where faded to grey while When faded to white, two dissolves that happen
/// to line up. Filmed, that is a highlight that switches; Airbnb's glides. The
/// card is an `AnimatedPositioned` layered under the segments, moved between
/// their measured rectangles, and the segments paint nothing of their own
/// while active. Same mechanism the panel below uses for the same reason.
class SearchPillBar extends StatefulWidget {
  const SearchPillBar({
    super.key,
    required this.segmentKeys,
    required this.open,
    required this.onSegmentTap,
    required this.onSubmit,
    this.where,
    this.when,
    this.who,
    this.onClear,
    this.voice,
    this.busy = false,
  });

  /// Attached to each segment so `SearchPill` can measure where they are —
  /// the panel animates between those rectangles, which needs numbers rather
  /// than a LayerLink.
  final Map<SearchSegment, GlobalKey> segmentKeys;
  final SearchSegment? open;
  final ValueChanged<SearchSegment> onSegmentTap;

  /// Null while a place is being resolved, which is what disables the button.
  final VoidCallback? onSubmit;

  final String? where;
  final String? when;
  final String? who;
  final VoidCallback? onClear;
  final Widget? voice;
  final bool busy;

  static const _segments = [
    SearchSegment.where,
    SearchSegment.when,
    SearchSegment.who,
  ];

  /// How long the lifted card takes to reach the next segment, and how long
  /// the bar takes to go grey. One number, or the card arrives on a bar that
  /// is still changing colour under it.
  static const liftDuration = Duration(milliseconds: 180);

  /// The segment's own [AnimatedContainer] sits 3px inside its slot; the card
  /// has to match or it pokes out above and below the text.
  static const _liftInset = 3.0;

  @override
  State<SearchPillBar> createState() => _SearchPillBarState();
}

class _SearchPillBarState extends State<SearchPillBar> {
  /// The layer the card is positioned in — measured against, not the bar's
  /// outer box, because the border is 1px of `Container` padding and a rect
  /// taken against the outside would sit one pixel off the segment it covers.
  final _layer = GlobalKey();

  /// Each segment's slot, in the layer's coordinates. Measured a frame late,
  /// like `SearchPill` measures the bar: nothing reads layout during build.
  final Map<SearchSegment, Rect> _slots = {};

  /// Who's slot is wider than its segment: it holds the mic, the ✕ and the
  /// Search button too, and the lifted card covers the lot — Airbnb's open
  /// Who is a white card with the Search button sitting inside it. This is
  /// the key that outer slot is measured by; `segmentKeys[who]` stays on the
  /// tappable segment, which is what the panel below anchors to.
  final _whoSlot = GlobalKey();

  /// Where the card last was. Kept so it can fade out *in place* on close
  /// rather than vanishing the instant `open` goes null.
  Rect? _lastLift;

  /// Whether the previous build had a lifted segment. Opening from closed
  /// must put the card straight on the tapped segment — if it animated from
  /// [_lastLift] it would slide in from wherever the bar was last open, which
  /// is the sideways drift the panel already refuses to make.
  bool _wasLifted = false;

  bool get _anyOpen =>
      widget.open != null && widget.open != SearchSegment.filters;

  String? _valueFor(SearchSegment segment) => switch (segment) {
        SearchSegment.where => widget.where,
        SearchSegment.when => widget.when,
        SearchSegment.who => widget.who,
        SearchSegment.filters => null,
      };

  void _measure() {
    if (!mounted) return;
    final layer = _layer.currentContext?.findRenderObject();
    if (layer is! RenderBox || !layer.hasSize) return;
    final next = <SearchSegment, Rect>{};
    for (final segment in SearchPillBar._segments) {
      final key =
          segment == SearchSegment.who ? _whoSlot : widget.segmentKeys[segment];
      final box = key?.currentContext?.findRenderObject();
      if (box is! RenderBox || !box.attached || !box.hasSize) continue;
      next[segment] =
          box.localToGlobal(Offset.zero, ancestor: layer) & box.size;
    }
    if (mapEquals(next, _slots)) return;
    setState(() {
      _slots
        ..clear()
        ..addAll(next);
    });
  }

  Widget _segment(SearchSegment segment) => _Segment(
        key: widget.segmentKeys[segment],
        segment: segment,
        value: _valueFor(segment),
        active: widget.open == segment,
        dimmed: _anyOpen && widget.open != segment,
        onTap: () => widget.onSegmentTap(segment),
      );

  @override
  Widget build(BuildContext context) {
    WidgetsBinding.instance.addPostFrameCallback((_) => _measure());

    final lifted = _anyOpen ? _slots[widget.open] : null;
    // Reading the previous build's answer before overwriting it: this is the
    // one frame where "did the card exist a moment ago" decides whether it
    // travels or appears.
    final snap = lifted != null && !_wasLifted;
    _wasLifted = lifted != null;
    if (lifted != null) _lastLift = lifted;
    final card = _lastLift;

    return ConstrainedBox(
      constraints: const BoxConstraints(maxWidth: 780),
      child: AnimatedContainer(
        key: const ValueKey('search-bar'),
        duration: SearchPillBar.liftDuration,
        curve: Curves.easeOut,
        height: 68,
        decoration: BoxDecoration(
          color: _anyOpen ? AppColors.surfaceMuted : AppColors.surface,
          borderRadius: BorderRadius.circular(40),
          border: Border.all(color: AppColors.outline),
          boxShadow: [
            BoxShadow(
              color: Colors.black.withValues(alpha: _anyOpen ? 0.10 : 0.07),
              blurRadius: _anyOpen ? 20 : 16,
              offset: const Offset(0, 3),
            ),
          ],
        ),
        child: Stack(
          key: _layer,
          fit: StackFit.passthrough,
          children: [
            if (card != null)
              AnimatedPositioned.fromRect(
                key: const ValueKey('search-lifted'),
                rect: Rect.fromLTRB(
                  card.left,
                  card.top + SearchPillBar._liftInset,
                  card.right,
                  card.bottom - SearchPillBar._liftInset,
                ),
                duration: snap ? Duration.zero : SearchPillBar.liftDuration,
                curve: Curves.easeOut,
                // The segments above take the taps; the card is paint only.
                child: IgnorePointer(
                  child: AnimatedOpacity(
                    duration: SearchPillBar.liftDuration,
                    opacity: lifted != null ? 1 : 0,
                    child: DecoratedBox(
                      decoration: BoxDecoration(
                        // Opaque white over a grey bar: a fade between those
                        // two never passes through anything darker than the
                        // grey, which is the hover-flicker rule below.
                        color: AppColors.surface,
                        borderRadius: BorderRadius.circular(40),
                        boxShadow: [
                          BoxShadow(
                            color: Colors.black.withValues(alpha: 0.16),
                            blurRadius: 14,
                            offset: const Offset(0, 3),
                          ),
                        ],
                      ),
                    ),
                  ),
                ),
              ),
            Row(
              children: [
                for (var i = 0; i < SearchPillBar._segments.length; i++) ...[
                  if (i > 0)
                    _Divider(
                      // Hidden either side of the lifted segment, and while
                      // the whole bar is grey the dividers would otherwise
                      // read as seams in it.
                      visible: !_anyOpen &&
                          widget.open != SearchPillBar._segments[i] &&
                          widget.open != SearchPillBar._segments[i - 1],
                    ),
                  if (SearchPillBar._segments[i] == SearchSegment.who)
                    // The controls live INSIDE Who's slot, not after it. When
                    // the Search button grows its label it has to take that
                    // room from somewhere, and if the controls sat beside the
                    // three Expanded segments it took it from all three —
                    // Where and When slid left by 25px and 19px as the button
                    // opened, dragging the lifted card and the panel under it
                    // along a frame late. Airbnb's Where and When do not move;
                    // only Who's own text area gives way, and its label is
                    // left-aligned so even that is invisible.
                    Expanded(
                      flex: 5,
                      child: KeyedSubtree(
                        key: _whoSlot,
                        child: Row(
                          children: [
                            Expanded(child: _segment(SearchSegment.who)),
                            Padding(
                              padding: const EdgeInsets.only(left: 4, right: 9),
                              child: Row(
                                mainAxisSize: MainAxisSize.min,
                                children: [
                                  if (widget.onClear != null)
                                    IconButton(
                                      onPressed: widget.onClear,
                                      icon: const Icon(Icons.close, size: 19),
                                      color: AppColors.inkMuted,
                                      tooltip: 'Clear search',
                                      visualDensity: VisualDensity.compact,
                                    ),
                                  if (widget.voice != null) widget.voice!,
                                  const SizedBox(width: 4),
                                  _SearchButton(
                                    onTap: widget.onSubmit,
                                    busy: widget.busy,
                                    // Any panel, the Filters one included: the
                                    // moment the guest is editing, the button
                                    // says what it commits.
                                    expanded: widget.open != null,
                                  ),
                                ],
                              ),
                            ),
                          ],
                        ),
                      ),
                    )
                  else
                    Expanded(
                      flex: SearchPillBar._segments[i] == SearchSegment.where
                          ? 4
                          : 3,
                      child: _segment(SearchPillBar._segments[i]),
                    ),
                ],
              ],
            ),
          ],
        ),
      ),
    );
  }
}

class _Divider extends StatelessWidget {
  const _Divider({required this.visible});

  final bool visible;

  @override
  Widget build(BuildContext context) {
    return AnimatedOpacity(
      duration: const Duration(milliseconds: 160),
      opacity: visible ? 1 : 0,
      child: Container(width: 1, height: 30, color: AppColors.outline),
    );
  }
}

class _Segment extends StatefulWidget {
  const _Segment({
    super.key,
    required this.segment,
    required this.value,
    required this.active,
    required this.dimmed,
    required this.onTap,
  });

  final SearchSegment segment;
  final String? value;
  final bool active;

  /// True for the two segments that are *not* open while another one is.
  final bool dimmed;

  final VoidCallback onTap;

  @override
  State<_Segment> createState() => _SegmentState();
}

class _SegmentState extends State<_Segment> {
  bool _hovered = false;

  @override
  Widget build(BuildContext context) {
    final value = widget.value;
    final hasValue = value != null && value.isNotEmpty;

    // What the bar is painting behind this segment. It is the resting colour
    // too, and that is the whole of the hover-flicker fix.
    //
    // `Colors.transparent` is transparent *black*, and `Color.lerp` walks
    // r/g/b and alpha independently — so fading from it to any light colour
    // spends the middle of the animation painting a half-opaque near-black.
    // Filmed at 1440px with the cursor parked: the segment went 244 → 179 →
    // 225 in luminance, a dark pill that flashed and then lightened into the
    // real hover grey. It read as a flicker on every hover, and again on every
    // tap, because the lifted white card fades in the same way.
    //
    // Every colour below is therefore opaque or the bar's own colour at zero
    // alpha, so no interpolation between any two of them can pass through
    // something darker than both ends.
    final barColour = widget.active || widget.dimmed
        ? AppColors.surfaceMuted
        : AppColors.surface;

    final Color background;
    if (widget.active) {
      // The white is the travelling card in `SearchPillBar`, painted under
      // this segment. Painting it here as well is what the old design did,
      // and it is exactly what made the switch a dissolve instead of a slide.
      background = barColour.withValues(alpha: 0);
    } else if (_hovered) {
      // On a grey bar the hover has to go darker to be visible at all; on a
      // white one it goes lighter-grey, as it always did. Flattened against
      // the bar rather than left translucent, for the reason above.
      background = widget.dimmed
          ? Color.alphaBlend(
              Colors.black.withValues(alpha: 0.05),
              AppColors.surfaceMuted,
            )
          : AppColors.surfaceMuted;
    } else {
      background = barColour.withValues(alpha: 0);
    }

    return Semantics(
      button: true,
      expanded: widget.active,
      label: '${widget.segment.label}, '
          '${hasValue ? value : widget.segment.placeholder}',
      excludeSemantics: true,
      child: MouseRegion(
        cursor: SystemMouseCursors.click,
        onEnter: (_) => setState(() => _hovered = true),
        onExit: (_) => setState(() => _hovered = false),
        child: GestureDetector(
          onTap: widget.onTap,
          behavior: HitTestBehavior.opaque,
          child: AnimatedContainer(
            duration: const Duration(milliseconds: 180),
            curve: Curves.easeOut,
            height: 62,
            margin: const EdgeInsets.symmetric(vertical: 3),
            padding: const EdgeInsets.symmetric(horizontal: 22),
            decoration: BoxDecoration(
              color: background,
              borderRadius: BorderRadius.circular(40),
            ),
            child: Column(
              mainAxisSize: MainAxisSize.min,
              mainAxisAlignment: MainAxisAlignment.center,
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Text(
                  widget.segment.label,
                  style: TextStyle(
                    fontSize: 12,
                    fontWeight: FontWeight.w700,
                    color: AppColors.ink,
                    height: 1.1,
                  ),
                ),
                const SizedBox(height: 3),
                Text(
                  hasValue ? value : widget.segment.placeholder,
                  maxLines: 1,
                  overflow: TextOverflow.ellipsis,
                  style: TextStyle(
                    fontSize: 13.5,
                    fontWeight: FontWeight.w500,
                    // inkMuted for a placeholder, not a lighter grey: it still
                    // has to clear 4.5:1, and every palette is held to that.
                    color: hasValue ? AppColors.ink : AppColors.inkMuted,
                    height: 1.1,
                  ),
                ),
              ],
            ),
          ),
        ),
      ),
    );
  }
}

/// The commit button. A round icon while the bar is at rest, and the moment a
/// panel opens it grows a "Search" label — Airbnb's cue that the bar is now in
/// an editing state with something to commit. Width animates through
/// `AnimatedSize` so the label slides out rather than popping.
class _SearchButton extends StatelessWidget {
  const _SearchButton({
    required this.onTap,
    required this.busy,
    required this.expanded,
  });

  final VoidCallback? onTap;
  final bool busy;
  final bool expanded;

  @override
  Widget build(BuildContext context) {
    final enabled = onTap != null;
    return Tooltip(
      message: busy ? 'Finding that place…' : 'Search',
      child: Material(
        shape: const StadiumBorder(),
        clipBehavior: Clip.antiAlias,
        color: Colors.transparent,
        child: InkWell(
          onTap: onTap,
          child: MouseRegion(
            cursor:
                enabled ? SystemMouseCursors.click : SystemMouseCursors.basic,
            child: AnimatedContainer(
              key: const ValueKey('search-submit'),
              duration: SearchPillBar.liftDuration,
              curve: Curves.easeOut,
              height: 48,
              constraints: const BoxConstraints(minWidth: 48),
              padding: EdgeInsets.symmetric(horizontal: expanded ? 18 : 13),
              decoration: BoxDecoration(
                gradient: LinearGradient(
                  colors: enabled
                      ? const [Brand.rose, Brand.roseDeep]
                      : [AppColors.outline, AppColors.outline],
                  begin: Alignment.topLeft,
                  end: Alignment.bottomRight,
                ),
                borderRadius: BorderRadius.circular(24),
              ),
              child: Row(
                mainAxisSize: MainAxisSize.min,
                children: [
                  if (busy)
                    const SizedBox(
                      width: 20,
                      height: 20,
                      child: CircularProgressIndicator(
                        strokeWidth: 2,
                        color: Colors.white,
                      ),
                    )
                  else
                    const Icon(Icons.search, size: 22, color: Colors.white),
                  AnimatedSize(
                    duration: SearchPillBar.liftDuration,
                    curve: Curves.easeOut,
                    alignment: Alignment.centerLeft,
                    child: expanded
                        ? const Padding(
                            padding: EdgeInsets.only(left: 8),
                            child: Text(
                              'Search',
                              style: TextStyle(
                                fontSize: 15,
                                fontWeight: FontWeight.w700,
                                color: Colors.white,
                              ),
                            ),
                          )
                        : const SizedBox.shrink(),
                  ),
                ],
              ),
            ),
          ),
        ),
      ),
    );
  }
}

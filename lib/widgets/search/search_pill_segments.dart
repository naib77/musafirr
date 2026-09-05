import 'package:flutter/material.dart';

import '../../core/theme/app_colors.dart';
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
class SearchPillBar extends StatelessWidget {
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

  bool get _anyOpen => open != null && open != SearchSegment.filters;

  String? _valueFor(SearchSegment segment) => switch (segment) {
        SearchSegment.where => where,
        SearchSegment.when => when,
        SearchSegment.who => who,
        SearchSegment.filters => null,
      };

  @override
  Widget build(BuildContext context) {
    return ConstrainedBox(
      constraints: const BoxConstraints(maxWidth: 780),
      child: AnimatedContainer(
        key: const ValueKey('search-bar'),
        duration: const Duration(milliseconds: 180),
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
        child: Row(
          children: [
            for (var i = 0; i < _segments.length; i++) ...[
              if (i > 0)
                _Divider(
                  // Hidden either side of the lifted segment, and while the
                  // whole bar is grey the dividers would otherwise read as
                  // seams in it.
                  visible: !_anyOpen &&
                      open != _segments[i] &&
                      open != _segments[i - 1],
                ),
              Expanded(
                flex: _segments[i] == SearchSegment.where ? 4 : 3,
                child: _Segment(
                  key: segmentKeys[_segments[i]],
                  segment: _segments[i],
                  value: _valueFor(_segments[i]),
                  active: open == _segments[i],
                  dimmed: _anyOpen && open != _segments[i],
                  onTap: () => onSegmentTap(_segments[i]),
                ),
              ),
            ],
            Padding(
              padding: const EdgeInsets.only(left: 4, right: 9),
              child: Row(
                mainAxisSize: MainAxisSize.min,
                children: [
                  if (onClear != null)
                    IconButton(
                      onPressed: onClear,
                      icon: const Icon(Icons.close, size: 19),
                      color: AppColors.inkMuted,
                      tooltip: 'Clear search',
                      visualDensity: VisualDensity.compact,
                    ),
                  if (voice != null) voice!,
                  const SizedBox(width: 4),
                  _SearchButton(onTap: onSubmit, busy: busy),
                ],
              ),
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

    final Color background;
    if (widget.active) {
      background = AppColors.surface;
    } else if (_hovered) {
      // On a grey bar the hover has to go darker to be visible at all; on a
      // white one it goes lighter-grey, as it always did.
      background = widget.dimmed
          ? Colors.black.withValues(alpha: 0.05)
          : AppColors.surfaceMuted;
    } else {
      background = Colors.transparent;
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
              boxShadow: widget.active
                  ? [
                      BoxShadow(
                        color: Colors.black.withValues(alpha: 0.16),
                        blurRadius: 14,
                        offset: const Offset(0, 3),
                      ),
                    ]
                  : const [],
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

class _SearchButton extends StatelessWidget {
  const _SearchButton({required this.onTap, required this.busy});

  final VoidCallback? onTap;
  final bool busy;

  @override
  Widget build(BuildContext context) {
    return Tooltip(
      message: busy ? 'Finding that place…' : 'Search',
      child: Material(
        shape: const CircleBorder(),
        clipBehavior: Clip.antiAlias,
        color: Colors.transparent,
        child: InkWell(
          onTap: onTap,
          child: MouseRegion(
            cursor: onTap == null
                ? SystemMouseCursors.basic
                : SystemMouseCursors.click,
            child: Container(
              width: 48,
              height: 48,
              decoration: BoxDecoration(
                gradient: LinearGradient(
                  colors: onTap == null
                      ? [AppColors.outline, AppColors.outline]
                      : [AppColors.brand, AppColors.brandDark],
                  begin: Alignment.topLeft,
                  end: Alignment.bottomRight,
                ),
                shape: BoxShape.circle,
              ),
              child: busy
                  ? const Padding(
                      padding: EdgeInsets.all(14),
                      child: CircularProgressIndicator(
                        strokeWidth: 2,
                        color: Colors.white,
                      ),
                    )
                  : const Icon(Icons.search, size: 22, color: Colors.white),
            ),
          ),
        ),
      ),
    );
  }
}

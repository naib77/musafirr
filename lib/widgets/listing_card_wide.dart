import 'package:flutter/foundation.dart'
    show TargetPlatform, defaultTargetPlatform;
import 'package:flutter/material.dart';

import '../core/utils/distance_format.dart';
import '../models/listing.dart';
import '../models/listing_type.dart';
import '../models/rental_plan.dart';
import 'app_network_image.dart';

/// A search result as a single full-width row, the way Airbnb lists them: one
/// listing per row, a big photo you can swipe, and enough detail underneath to
/// decide without opening it — what kind of place it is and where, the host's
/// own name for it, how many beds, the dates searched for, and the rates.
///
/// The two-column [ListingCardModern] stays for browsing the curated rows,
/// where the point is to scan many places at a glance. This one is for results,
/// where the point is to compare a few carefully.
class ListingCardWide extends StatefulWidget {
  const ListingCardWide({
    super.key,
    required this.listing,
    required this.isFavorite,
    required this.onTap,
    required this.onFavoriteTap,
    this.stayLabel,
  });

  final Listing listing;
  final bool isFavorite;
  final VoidCallback onTap;
  final VoidCallback onFavoriteTap;

  /// The dates the guest searched for ("21 – 23 Aug"), shown so the row makes
  /// clear what it is priced against. Null when the search had no dates.
  final String? stayLabel;

  @override
  State<ListingCardWide> createState() => _ListingCardWideState();
}

class _ListingCardWideState extends State<ListingCardWide> {
  // Drives the photo carousel, so the arrow buttons can step it. Without a
  // controller the PageView can only be swiped, which on a desktop browser
  // means the extra photos are effectively unreachable.
  final PageController _photoController = PageController();

  int _page = 0;

  // Whether a mouse is over the photo. Arrows are a mouse's substitute for a
  // swipe, so on a pointer device they fade in on hover the way Airbnb's do and
  // the photo stays uncluttered until then.
  bool _hovered = false;

  @override
  void dispose() {
    _photoController.dispose();
    super.dispose();
  }

  /// Touch devices never fire a hover, so nothing there could ever reveal the
  /// arrows — they stay put instead. A guest on a phone can still swipe; the
  /// buttons are simply the visible way to do the same thing.
  bool get _arrowsAlwaysVisible =>
      defaultTargetPlatform == TargetPlatform.iOS ||
      defaultTargetPlatform == TargetPlatform.android;

  /// Whether the arrows should be showing at all right now. Each one still
  /// hides itself at the end of the carousel it points past.
  bool get _arrowsVisible => _arrowsAlwaysVisible || _hovered;

  /// Steps the carousel one photo. Stops at the ends rather than wrapping: the
  /// arrow that would wrap is hidden anyway, and a silent jump back to the
  /// first photo reads as a glitch.
  void _step(int delta) {
    final next = _page + delta;
    if (next < 0 || next >= widget.listing.imageUrls.length) return;
    // A guest who asked the system to cut animation gets the jump, not the slide.
    if (MediaQuery.disableAnimationsOf(context)) {
      _photoController.jumpToPage(next);
      setState(() => _page = next);
      return;
    }
    _photoController.animateToPage(
      next,
      duration: const Duration(milliseconds: 260),
      curve: Curves.easeOutCubic,
    );
  }

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    final listing = widget.listing;
    final hasReviews = listing.rating != null && listing.rating! > 0;

    return GestureDetector(
      onTap: widget.onTap,
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          AspectRatio(
            // A little wider than tall, so two rows still peek above the fold
            // when the sheet is half-open.
            aspectRatio: 1.15,
            child: ClipRRect(
              borderRadius: BorderRadius.circular(16),
              // Tracks the mouse so the arrows can fade in over the photo.
              // A no-op on touch, where there is no pointer to track.
              child: MouseRegion(
                onEnter: (_) => setState(() => _hovered = true),
                onExit: (_) => setState(() => _hovered = false),
                child: Stack(
                  fit: StackFit.expand,
                  children: [
                    _photos(theme),
                    _photoPill(theme, hasReviews: hasReviews),
                    Positioned(top: 10, right: 10, child: _favoriteButton()),
                    if (listing.imageUrls.length > 1) ...[
                      Positioned(
                        bottom: 10,
                        left: 0,
                        right: 0,
                        child: _dots(),
                      ),
                      // Centred on the photo's vertical midline and inset just
                      // enough to clear the rounded corner. Only the button's
                      // own 44px box takes a hit — the full-height strip around
                      // it stays transparent to the swipe underneath.
                      Positioned(
                        left: 4,
                        top: 0,
                        bottom: 0,
                        child: Center(
                          child: _SliderButton(
                            icon: Icons.chevron_left_rounded,
                            semanticLabel: 'Previous photo',
                            visible: _arrowsVisible && _page > 0,
                            onPressed: () => _step(-1),
                          ),
                        ),
                      ),
                      Positioned(
                        right: 4,
                        top: 0,
                        bottom: 0,
                        child: Center(
                          child: _SliderButton(
                            icon: Icons.chevron_right_rounded,
                            semanticLabel: 'Next photo',
                            visible: _arrowsVisible &&
                                _page < listing.imageUrls.length - 1,
                            onPressed: () => _step(1),
                          ),
                        ),
                      ),
                    ],
                  ],
                ),
              ),
            ),
          ),
          const SizedBox(height: 10),
          // What it is and where, with the rating on the same line — the two
          // things a guest sorts on.
          Row(
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              Expanded(
                child: Text(
                  _headline(),
                  style: theme.textTheme.titleMedium?.copyWith(
                    fontSize: 15,
                    fontWeight: FontWeight.w700,
                    height: 1.2,
                  ),
                  maxLines: 1,
                  overflow: TextOverflow.ellipsis,
                ),
              ),
              if (hasReviews) ...[
                const SizedBox(width: 8),
                Icon(Icons.star_rounded,
                    size: 15, color: Colors.amber.shade700),
                const SizedBox(width: 2),
                Text(
                  '${listing.rating!.toStringAsFixed(1)} (${listing.reviewCount})',
                  style: theme.textTheme.labelMedium?.copyWith(
                    fontSize: 13,
                    fontWeight: FontWeight.w600,
                  ),
                ),
              ],
            ],
          ),
          // The host's own name for the place. Skipped when it is already
          // doing duty as the headline.
          if (_headline() != listing.title) ...[
            const SizedBox(height: 2),
            Text(
              listing.title,
              style: theme.textTheme.bodyMedium?.copyWith(
                fontSize: 13,
                color: theme.colorScheme.onSurfaceVariant,
              ),
              maxLines: 1,
              overflow: TextOverflow.ellipsis,
            ),
          ],
          const SizedBox(height: 2),
          Text(
            _capacity(),
            style: theme.textTheme.bodyMedium?.copyWith(
              fontSize: 13,
              color: theme.colorScheme.onSurfaceVariant,
            ),
            maxLines: 1,
            overflow: TextOverflow.ellipsis,
          ),
          if (widget.stayLabel != null) ...[
            const SizedBox(height: 2),
            Text(
              widget.stayLabel!,
              style: theme.textTheme.bodyMedium?.copyWith(
                fontSize: 13,
                color: theme.colorScheme.onSurfaceVariant,
              ),
              maxLines: 1,
              overflow: TextOverflow.ellipsis,
            ),
          ],
          const SizedBox(height: 4),
          _rates(theme),
        ],
      ),
    );
  }

  /// "Room in Khilgaon" — the type and the neighbourhood, which is what a guest
  /// scanning results is actually choosing between. Falls back to the host's
  /// title where we have no area or city at all.
  String _headline() {
    final listing = widget.listing;
    final where = _firstNonEmpty([listing.area, listing.city]);
    if (where == null) return listing.title;
    return '${listing.type.title} in $where';
  }

  static String? _firstNonEmpty(List<String?> values) {
    for (final v in values) {
      if (v != null && v.trim().isNotEmpty) return v.trim();
    }
    return null;
  }

  /// "1 bedroom · 2 beds · 4 guests". A seat has no bedroom to speak of, so it
  /// counts seats instead of claiming the model's default of one bed.
  String _capacity() {
    final listing = widget.listing;
    if (listing.type == ListingType.seat) {
      return _plural(listing.maxGuests, 'seat');
    }
    return [
      _plural(listing.bedrooms, 'bedroom'),
      _plural(listing.beds, 'bed'),
      _plural(listing.maxGuests, 'guest'),
    ].join(' · ');
  }

  static String _plural(int n, String noun) => '$n $noun${n == 1 ? '' : 's'}';

  /// Every rate the host offers, in full — there is room for it on a full-width
  /// row, unlike the grid card, and exact figures are what a guest compares.
  Widget _rates(ThemeData theme) {
    final listing = widget.listing;
    final plans = listing.offeredPlans;
    if (plans.isEmpty) return const SizedBox.shrink();

    final text = plans
        .map((p) =>
            '${listing.moneyFor(p)!.format(showDecimal: false)}/${p.shortUnit}')
        .join('  ·  ');

    return Row(
      children: [
        Flexible(
          child: Text(
            text,
            style: theme.textTheme.bodyLarge?.copyWith(
              fontSize: 14,
              fontWeight: FontWeight.w700,
            ),
            maxLines: 1,
            overflow: TextOverflow.ellipsis,
          ),
        ),
        // Distance only exists after a proximity search, and it is the reason
        // those results are ordered the way they are.
        if (listing.distanceMeters != null) ...[
          const SizedBox(width: 8),
          Icon(Icons.near_me_rounded,
              size: 13, color: theme.colorScheme.primary),
          const SizedBox(width: 2),
          Text(
            formatDistanceMeters(listing.distanceMeters!),
            style: theme.textTheme.bodySmall?.copyWith(
              fontSize: 12,
              fontWeight: FontWeight.w600,
              color: theme.colorScheme.primary,
            ),
          ),
        ],
      ],
    );
  }

  Widget _photos(ThemeData theme) {
    final urls = widget.listing.imageUrls;
    if (urls.isEmpty) return _placeholder(theme);
    if (urls.length == 1) return _photo(urls.first, theme);

    return PageView.builder(
      controller: _photoController,
      itemCount: urls.length,
      onPageChanged: (i) => setState(() => _page = i),
      itemBuilder: (context, i) => _photo(urls[i], theme),
    );
  }

  Widget _photo(String url, ThemeData theme) {
    return AppNetworkImage(
      url: url,
      fit: BoxFit.cover,
      // Full-width row, so it needs a bigger decode than the grid thumbnail.
      decodeWidth: 800,
      placeholder: _shimmer(theme),
      errorWidget: _placeholder(theme),
    );
  }

  Widget _dots() {
    final count = widget.listing.imageUrls.length;
    return Row(
      mainAxisAlignment: MainAxisAlignment.center,
      children: [
        for (var i = 0; i < count; i++)
          Container(
            width: 6,
            height: 6,
            margin: const EdgeInsets.symmetric(horizontal: 3),
            decoration: BoxDecoration(
              shape: BoxShape.circle,
              color: i == _page
                  ? Colors.white
                  : Colors.white.withValues(alpha: 0.55),
            ),
          ),
      ],
    );
  }

  /// One pill, top-left, and only when it says something earned: a guest
  /// favourite, else a superhost, else that the place has no reviews yet.
  Widget _photoPill(ThemeData theme, {required bool hasReviews}) {
    final listing = widget.listing;

    if (listing.isGuestFavorite) {
      return const Positioned(
        top: 10,
        left: 10,
        child: _Pill(
          label: 'Guest favorite',
          icon: Icons.emoji_events_rounded,
          background: Colors.white,
          foreground: Colors.black87,
        ),
      );
    }
    if (listing.isSuperhost) {
      return Positioned(
        top: 10,
        left: 10,
        child: _Pill(
          label: 'Superhost',
          background: Colors.black.withValues(alpha: 0.55),
          foreground: Colors.white,
        ),
      );
    }
    if (!hasReviews) {
      return Positioned(
        top: 10,
        left: 10,
        child: _Pill(
          label: 'New',
          background: theme.colorScheme.primary,
          foreground: theme.colorScheme.onPrimary,
        ),
      );
    }
    return const SizedBox.shrink();
  }

  Widget _favoriteButton() {
    return GestureDetector(
      onTap: widget.onFavoriteTap,
      child: Container(
        padding: const EdgeInsets.all(7),
        decoration: BoxDecoration(
          color: Colors.white.withValues(alpha: 0.92),
          shape: BoxShape.circle,
        ),
        child: Icon(
          widget.isFavorite ? Icons.favorite : Icons.favorite_border,
          size: 18,
          color: widget.isFavorite ? Colors.redAccent : Colors.grey[800],
        ),
      ),
    );
  }

  Widget _placeholder(ThemeData theme) {
    return Container(
      color: theme.colorScheme.surfaceContainerHighest,
      child: Center(
        child: Icon(
          Icons.home_outlined,
          size: 48,
          color: theme.colorScheme.onSurfaceVariant,
        ),
      ),
    );
  }

  Widget _shimmer(ThemeData theme) {
    return Container(
      color: theme.colorScheme.surfaceContainerHighest,
      child: const Center(
        child: SizedBox(
          width: 24,
          height: 24,
          child: CircularProgressIndicator(strokeWidth: 2),
        ),
      ),
    );
  }
}

/// A round step-through button on the photo carousel — the pointer's answer to
/// a swipe. Styled to match the favourite button it shares the photo with:
/// near-white, softly shadowed so it reads against a bright photo as well as a
/// dark one, and it grows a little under the cursor.
class _SliderButton extends StatefulWidget {
  const _SliderButton({
    required this.icon,
    required this.semanticLabel,
    required this.visible,
    required this.onPressed,
  });

  final IconData icon;

  /// Spoken by a screen reader — the icon alone says nothing to one.
  final String semanticLabel;

  /// Faded out, and inert, at the end of the carousel it points past (and, on a
  /// pointer device, until the mouse is over the photo). Fading rather than
  /// removing keeps the photo from twitching as the arrow comes and goes.
  final bool visible;

  final VoidCallback onPressed;

  /// Big enough to read over a photo, small enough not to cover it.
  static const double _diameter = 30;

  /// The circle is 30px, but a 30px tap target is a miss waiting to happen, so
  /// the transparent box around it is the 44px minimum for a comfortable thumb.
  static const double _hitArea = 44;

  @override
  State<_SliderButton> createState() => _SliderButtonState();
}

class _SliderButtonState extends State<_SliderButton> {
  bool _hovered = false;

  @override
  Widget build(BuildContext context) {
    return IgnorePointer(
      ignoring: !widget.visible,
      child: AnimatedOpacity(
        opacity: widget.visible ? 1 : 0,
        duration: const Duration(milliseconds: 160),
        curve: Curves.easeOut,
        child: Semantics(
          button: true,
          label: widget.semanticLabel,
          child: MouseRegion(
            cursor: SystemMouseCursors.click,
            onEnter: (_) => setState(() => _hovered = true),
            onExit: (_) => setState(() => _hovered = false),
            child: GestureDetector(
              // Its own recogniser, so a tap here steps the photos instead of
              // opening the listing the way a tap anywhere else on the card
              // does. A horizontal drag still loses the arena to the PageView
              // underneath, so a swipe that starts on the button still swipes.
              onTap: widget.onPressed,
              behavior: HitTestBehavior.opaque,
              child: SizedBox(
                width: _SliderButton._hitArea,
                height: _SliderButton._hitArea,
                child: Center(
                  child: AnimatedScale(
                    scale: _hovered ? 1.08 : 1.0,
                    duration: const Duration(milliseconds: 150),
                    curve: Curves.easeOut,
                    child: Container(
                      width: _SliderButton._diameter,
                      height: _SliderButton._diameter,
                      alignment: Alignment.center,
                      decoration: BoxDecoration(
                        color: Colors.white.withValues(alpha: 0.92),
                        shape: BoxShape.circle,
                        boxShadow: [
                          BoxShadow(
                            color: Colors.black.withValues(alpha: 0.18),
                            blurRadius: 6,
                            offset: const Offset(0, 2),
                          ),
                        ],
                      ),
                      child: Icon(
                        widget.icon,
                        size: 18,
                        color: Colors.grey[900],
                      ),
                    ),
                  ),
                ),
              ),
            ),
          ),
        ),
      ),
    );
  }
}

class _Pill extends StatelessWidget {
  const _Pill({
    required this.label,
    required this.background,
    required this.foreground,
    this.icon,
  });

  final String label;
  final Color background;
  final Color foreground;
  final IconData? icon;

  @override
  Widget build(BuildContext context) {
    return Container(
      padding: const EdgeInsets.symmetric(horizontal: 10, vertical: 5),
      decoration: BoxDecoration(
        color: background,
        borderRadius: BorderRadius.circular(20),
      ),
      child: Row(
        children: [
          if (icon != null) ...[
            Icon(icon, size: 13, color: foreground),
            const SizedBox(width: 4),
          ],
          Text(
            label,
            style: TextStyle(
              fontSize: 12,
              fontWeight: FontWeight.w700,
              color: foreground,
            ),
          ),
        ],
      ),
    );
  }
}

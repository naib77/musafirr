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
  int _page = 0;

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
              child: Stack(
                fit: StackFit.expand,
                children: [
                  _photos(theme),
                  _photoPill(theme, hasReviews: hasReviews),
                  Positioned(top: 10, right: 10, child: _favoriteButton()),
                  if (listing.imageUrls.length > 1)
                    Positioned(
                      bottom: 10,
                      left: 0,
                      right: 0,
                      child: _dots(),
                    ),
                ],
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

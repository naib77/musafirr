import 'package:flutter/material.dart';

import '../core/theme/app_colors.dart';
import '../core/utils/distance_format.dart';
import 'app_network_image.dart';
import '../models/listing.dart';
import '../models/listing_type.dart';
import '../models/rental_plan.dart';

/// One size for every grid and carousel that renders a [ListingCardModern].
///
/// They were three copies of `300` / `0.72` (the search grid, the "See all"
/// grid and the curated rows), which is how the rows ended up 336px tall while
/// the grid was 378 — nothing forced them to agree.
///
/// The ratio is width / height and the text block below the photo is now its
/// own intrinsic height rather than 2/7 of the card, so height ≈ width + ~43.
/// 0.82 is that relationship at the widths these grids actually produce, which
/// keeps the photo roughly square — the shape the card was drawn for.
const double kListingCardMaxExtent = 240;
const double kListingCardAspectRatio = 0.82;

/// Explore-grid listing card, Airbnb-style: the photo is the hero — large,
/// rounded on all corners, floating on the scaffold with a soft shadow —
/// with tiny overlay pills and compact text below instead of a boxed card.
class ListingCardModern extends StatefulWidget {
  const ListingCardModern({
    super.key,
    required this.listing,
    required this.isFavorite,
    required this.onTap,
    required this.onFavoriteTap,
  });

  final Listing listing;
  final bool isFavorite;
  final VoidCallback onTap;
  final VoidCallback onFavoriteTap;

  @override
  State<ListingCardModern> createState() => _ListingCardModernState();
}

class _ListingCardModernState extends State<ListingCardModern>
    with SingleTickerProviderStateMixin {
  late AnimationController _heartController;
  late Animation<double> _heartScale;

  @override
  void initState() {
    super.initState();
    _heartController = AnimationController(
      duration: const Duration(milliseconds: 200),
      vsync: this,
    );
    _heartScale = Tween<double>(begin: 1.0, end: 1.3).animate(
      CurvedAnimation(parent: _heartController, curve: Curves.easeOutBack),
    );
  }

  @override
  void dispose() {
    _heartController.dispose();
    super.dispose();
  }

  void _onFavoriteTap() {
    _heartController.forward().then((_) => _heartController.reverse());
    widget.onFavoriteTap();
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
          // ── The hero photo: dominant, rounded everywhere, floating ──
          //
          // Takes whatever the text below does not. It used to be `flex: 5`
          // against the text's `flex: 2`, which made the text slot 2/7 of the
          // card — 108px at 1440px for 43px of text — and tied the text's
          // headroom to the card's width, so shrinking the card ate into it.
          Expanded(
            child: Container(
              decoration: BoxDecoration(
                borderRadius: BorderRadius.circular(18),
                boxShadow: [
                  BoxShadow(
                    color: Colors.black.withValues(alpha: 0.14),
                    blurRadius: 14,
                    offset: const Offset(0, 6),
                  ),
                ],
              ),
              child: ClipRRect(
                borderRadius: BorderRadius.circular(18),
                child: Stack(
                  fit: StackFit.expand,
                  children: [
                    if (listing.primaryImage != null)
                      AppNetworkImage(
                        url: listing.primaryImage!,
                        fit: BoxFit.cover,
                        // Grid thumbnail — decode small to keep scrolling smooth.
                        decodeWidth: 250,
                        placeholder: _buildShimmer(theme),
                        errorWidget: _buildPlaceholder(theme),
                      )
                    else
                      _buildPlaceholder(theme),

                    // Top scrim — sits behind the price pill and the favourite
                    // button, which share the top edge.
                    Positioned(
                      top: 0,
                      left: 0,
                      right: 0,
                      child: Container(
                        height: 44,
                        decoration: BoxDecoration(
                          gradient: LinearGradient(
                            begin: Alignment.bottomCenter,
                            end: Alignment.topCenter,
                            colors: [
                              Colors.transparent,
                              Colors.black.withValues(alpha: 0.35),
                            ],
                          ),
                        ),
                      ),
                    ),

                    // What this listing is, top-left — prefixed with "Guest
                    // favorite" when it has genuinely earned it. Rates are not
                    // shown on the photo: they live under it, where two of
                    // them can be compared.
                    // Stops short of the favourite button so a long label
                    // ("Guest favorite | Full House") ellipsizes inside the
                    // pill instead of running under the heart.
                    Positioned(
                      top: 6,
                      left: 6,
                      right: 40,
                      child: Align(
                        alignment: Alignment.centerLeft,
                        child: Container(
                          padding: const EdgeInsets.symmetric(
                            horizontal: 7,
                            vertical: 3,
                          ),
                          decoration: BoxDecoration(
                            color: Colors.white.withValues(alpha: 0.95),
                            borderRadius: BorderRadius.circular(20),
                          ),
                          child: _buildTypeBadge(),
                        ),
                      ),
                    ),

                    // Favorite button
                    Positioned(
                      top: 6,
                      right: 6,
                      child: GestureDetector(
                        onTap: _onFavoriteTap,
                        child: AnimatedBuilder(
                          animation: _heartScale,
                          builder: (context, child) {
                            return Transform.scale(
                              scale: _heartScale.value,
                              child: Container(
                                padding: const EdgeInsets.all(6),
                                decoration: BoxDecoration(
                                  color: Colors.white.withValues(alpha: 0.9),
                                  shape: BoxShape.circle,
                                ),
                                child: Icon(
                                  widget.isFavorite
                                      ? Icons.favorite
                                      : Icons.favorite_border,
                                  color: widget.isFavorite
                                      ? Colors.redAccent
                                      : Colors.grey[700],
                                  size: 16,
                                ),
                              ),
                            );
                          },
                        ),
                      ),
                    ),

                    // Status pill, bottom-left — the top-left slot belongs to
                    // the price. The listing type is NOT badged anywhere here:
                    // a coloured seat/room/full-house chip on every card made
                    // the grid noisy; the type now reads as part of the price
                    // ("from ৳500/hr/seat"), where it actually means something.
                    if (listing.isSuperhost || !hasReviews)
                      Positioned(
                        bottom: 6,
                        left: 6,
                        child: listing.isSuperhost
                            ? _MiniPill(
                                label: 'Superhost',
                                icon: Icons.workspace_premium,
                                background: Colors.orange.shade600,
                              )
                            : _MiniPill(
                                label: 'New',
                                background: theme.colorScheme.primary,
                              ),
                      ),
                  ],
                ),
              ),
            ),
          ),

          // ── Two lines below the photo, nothing more: the name, then the
          // headline rate with the rating. Secondary rates, bed/guest counts
          // and the city used to sit here too, which made the grid busy
          // without helping anyone choose. ──
          Padding(
            padding: const EdgeInsets.fromLTRB(4, 8, 4, 0),
            child: Column(
              // The parent Column hands a non-flex child unbounded height,
              // so this has to be min or it tries to take infinity.
              mainAxisSize: MainAxisSize.min,
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Text(
                  listing.title,
                  style: theme.textTheme.bodyMedium?.copyWith(
                    fontSize: 13,
                    fontWeight: FontWeight.w600,
                    height: 1.2,
                  ),
                  maxLines: 1,
                  overflow: TextOverflow.ellipsis,
                ),
                const SizedBox(height: 3),
                // Rate and rating read as one phrase, so they sit next to
                // each other. Nothing is Expanded here — that stretched the
                // gap to the full card width and left the rating stranded
                // on the far edge.
                Row(
                  children: [
                    Flexible(
                      child: _buildRates(
                        theme,
                        compact: listing.distanceMeters != null,
                      ),
                    ),
                    // Distance only exists after a proximity search, and
                    // it's the reason those results are ordered the way they
                    // are — worth the space when present.
                    if (listing.distanceMeters != null) ...[
                      const SizedBox(width: 5),
                      Icon(Icons.near_me_rounded,
                          size: 11, color: theme.colorScheme.primary),
                      const SizedBox(width: 2),
                      Flexible(
                        child: Text(
                          formatDistanceMeters(listing.distanceMeters!),
                          style: theme.textTheme.bodySmall?.copyWith(
                            fontSize: 11,
                            fontWeight: FontWeight.w600,
                            color: theme.colorScheme.primary,
                          ),
                          maxLines: 1,
                          overflow: TextOverflow.ellipsis,
                        ),
                      ),
                    ],
                    if (hasReviews) ...[
                      // More air than the 6px it had: the rate phrase now ends
                      // on a muted unit, and without it the star reads as part
                      // of that phrase rather than as a separate fact.
                      const SizedBox(width: 8),
                      Icon(
                        Icons.star_rounded,
                        size: 12,
                        color: Colors.amber.shade700,
                      ),
                      const SizedBox(width: 2),
                      Text(
                        listing.rating!.toStringAsFixed(1),
                        style: theme.textTheme.labelSmall?.copyWith(
                          fontSize: 10.5,
                          fontWeight: FontWeight.w600,
                          color: AppColors.ink,
                        ),
                      ),
                    ],
                  ],
                ),
              ],
            ),
          ),
        ],
      ),
    );
  }

  /// The photo pill: what you're booking ("Room"), with a "Guest favorite"
  /// prefix only when the listing has actually earned it.
  ///
  /// One rich Text rather than a Row of parts, so the ellipsis applies to the
  /// whole phrase — with separate children only the last one can shrink, which
  /// overflows a narrow two-column card by a few pixels instead of trimming.
  Widget _buildTypeBadge() {
    final listing = widget.listing;

    return Text.rich(
      TextSpan(
        children: [
          if (listing.isGuestFavorite)
            const TextSpan(
              text: 'Guest favorite  |  ',
              style: TextStyle(
                fontSize: 9,
                fontWeight: FontWeight.w700,
                color: Colors.black54,
              ),
            ),
          TextSpan(
            text: listing.type.title,
            style: const TextStyle(
              fontSize: 10,
              fontWeight: FontWeight.w700,
              color: Colors.black87,
            ),
          ),
        ],
      ),
      maxLines: 1,
      overflow: TextOverflow.ellipsis,
    );
  }

  /// Up to two rates, so a guest can weigh a short stay against a longer one
  /// without opening the listing: "৳500/hr · ৳3K/day". See
  /// [Listing.headlinePlans] for which two.
  ///
  /// A proximity search adds a distance to this line, and three figures plus a
  /// rating do not fit a grid cell — so one rate is dropped there rather than
  /// letting everything ellipsize into nonsense.
  Widget _buildRates(ThemeData theme, {required bool compact}) {
    final listing = widget.listing;
    var plans = listing.headlinePlans;
    if (compact && plans.length > 1) plans = plans.take(1).toList();
    if (plans.isEmpty) return const SizedBox.shrink();

    // One `Text.rich`, not a Row of parts, for the reason the type badge is:
    // with separate children only the last one can shrink, so a narrow card
    // ellipsizes the wrong half of the phrase. The concatenated string is
    // unchanged — the spans only carry weight, size and colour.
    final spans = <InlineSpan>[];
    for (var i = 0; i < plans.length; i++) {
      if (i > 0) {
        spans.add(TextSpan(
          text: ' · ',
          style: TextStyle(
            fontSize: 10,
            fontWeight: FontWeight.w400,
            color: AppColors.inkMuted,
          ),
        ));
      }
      // The first plan is the one the guest reads; the second is there to be
      // weighed against it. Flat w700 on both at one size — which is what this
      // was — gives a run of six numerals and two slashes with nothing
      // leading, and the rating immediately after has to compete with all of
      // it. So the lead rate is the only thing at full weight and full ink,
      // its unit is demoted, and the second rate is muted whole.
      final lead = i == 0;
      spans.add(TextSpan(
        text: listing.moneyFor(plans[i])!.format(useCompact: true),
        style: TextStyle(
          fontSize: lead ? 12.5 : 11,
          fontWeight: lead ? FontWeight.w700 : FontWeight.w600,
          color: lead ? AppColors.ink : AppColors.inkMuted,
        ),
      ));
      spans.add(TextSpan(
        // The unit is the quietest part of the phrase: it repeats across every
        // card in the grid, so it carries almost no information per card.
        text: '/${plans[i].shortUnit}',
        style: TextStyle(
          fontSize: lead ? 10 : 9.5,
          fontWeight: lead ? FontWeight.w600 : FontWeight.w500,
          color: AppColors.inkMuted,
        ),
      ));
    }

    return Text.rich(
      TextSpan(children: spans),
      maxLines: 1,
      overflow: TextOverflow.ellipsis,
    );
  }

  Widget _buildPlaceholder(ThemeData theme) {
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

  Widget _buildShimmer(ThemeData theme) {
    return Container(
      color: theme.colorScheme.surfaceContainerHighest,
      child: Center(
        child: SizedBox(
          width: 24,
          height: 24,
          child: CircularProgressIndicator(
            strokeWidth: 2,
            color: theme.colorScheme.onSurfaceVariant,
          ),
        ),
      ),
    );
  }
}

/// Tiny colored pill for Superhost / New badges on the photo.
class _MiniPill extends StatelessWidget {
  const _MiniPill({
    required this.label,
    required this.background,
    this.icon,
  });

  final String label;
  final Color background;
  final IconData? icon;

  @override
  Widget build(BuildContext context) {
    return Container(
      padding: const EdgeInsets.symmetric(horizontal: 6, vertical: 3),
      decoration: BoxDecoration(
        color: background.withValues(alpha: 0.95),
        borderRadius: BorderRadius.circular(20),
      ),
      child: Row(
        mainAxisSize: MainAxisSize.min,
        children: [
          if (icon != null) ...[
            Icon(icon, size: 9, color: Colors.white),
            const SizedBox(width: 3),
          ],
          Text(
            label,
            style: const TextStyle(
              color: Colors.white,
              fontWeight: FontWeight.w700,
              fontSize: 9,
            ),
          ),
        ],
      ),
    );
  }
}

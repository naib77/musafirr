import 'package:flutter/material.dart';

import '../core/theme/app_colors.dart';
import '../models/listing.dart';
import '../models/listing_type.dart';
import '../models/rental_plan.dart';

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
          Expanded(
            flex: 5,
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
                      Image.network(
                        listing.primaryImage!,
                        fit: BoxFit.cover,
                        errorBuilder: (_, __, ___) => _buildPlaceholder(theme),
                        loadingBuilder: (context, child, loadingProgress) {
                          if (loadingProgress == null) return child;
                          return _buildShimmer(theme);
                        },
                      )
                    else
                      _buildPlaceholder(theme),

                    // Bottom scrim so the price pill always reads.
                    Positioned(
                      bottom: 0,
                      left: 0,
                      right: 0,
                      child: Container(
                        height: 44,
                        decoration: BoxDecoration(
                          gradient: LinearGradient(
                            begin: Alignment.topCenter,
                            end: Alignment.bottomCenter,
                            colors: [
                              Colors.transparent,
                              Colors.black.withValues(alpha: 0.45),
                            ],
                          ),
                        ),
                      ),
                    ),

                    // Compact price pill
                    Positioned(
                      bottom: 6,
                      left: 6,
                      child: Container(
                        padding: const EdgeInsets.symmetric(
                          horizontal: 7,
                          vertical: 3,
                        ),
                        decoration: BoxDecoration(
                          color: Colors.white.withValues(alpha: 0.95),
                          borderRadius: BorderRadius.circular(20),
                        ),
                        child: _buildPriceTeaser(theme),
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

                    // Tiny type / status pills
                    Positioned(
                      top: 6,
                      left: 6,
                      child: Row(
                        children: [
                          _CategoryChip(type: listing.type),
                          const SizedBox(width: 4),
                          if (listing.isSuperhost)
                            _MiniPill(
                              label: 'Superhost',
                              icon: Icons.workspace_premium,
                              background: Colors.orange.shade600,
                            )
                          else if (!hasReviews)
                            _MiniPill(
                              label: 'New',
                              background: theme.colorScheme.primary,
                            ),
                        ],
                      ),
                    ),
                  ],
                ),
              ),
            ),
          ),

          // ── Compact info below, no box — Airbnb style ──
          Expanded(
            flex: 2,
            child: Padding(
              padding: const EdgeInsets.fromLTRB(4, 8, 4, 0),
              child: Column(
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
                  const SizedBox(height: 2),
                  // Place and rating share the second line.
                  Row(
                    children: [
                      Expanded(
                        child: Text(
                          listing.city ?? listing.address.split(',').first,
                          style: theme.textTheme.bodySmall?.copyWith(
                            fontSize: 11,
                            color: theme.colorScheme.onSurfaceVariant,
                          ),
                          maxLines: 1,
                          overflow: TextOverflow.ellipsis,
                        ),
                      ),
                      if (hasReviews) ...[
                        const SizedBox(width: 6),
                        Icon(
                          Icons.star_rounded,
                          size: 13,
                          color: Colors.amber.shade700,
                        ),
                        const SizedBox(width: 1),
                        Text(
                          listing.rating!.toStringAsFixed(1),
                          style: theme.textTheme.labelSmall?.copyWith(
                            fontSize: 11,
                            fontWeight: FontWeight.w600,
                          ),
                        ),
                      ],
                    ],
                  ),
                  const SizedBox(height: 4),
                  // Secondary rates + quick stats on one muted line.
                  Row(
                    children: [
                      Expanded(child: _buildSecondaryRates(theme)),
                      if (listing.bedrooms > 0) ...[
                        _buildStatChip(
                          Icons.bed_outlined,
                          '${listing.bedrooms}',
                          theme,
                        ),
                        const SizedBox(width: 6),
                      ],
                      if (listing.maxGuests > 0)
                        _buildStatChip(
                          Icons.person_outline,
                          '${listing.maxGuests}',
                          theme,
                        ),
                    ],
                  ),
                  const SizedBox(height: 4),
                ],
              ),
            ),
          ),
        ],
      ),
    );
  }

  /// Compact "from ৳X/unit" teaser for the cheapest offered plan.
  /// "from" only appears when more than one plan is offered.
  Widget _buildPriceTeaser(ThemeData theme) {
    final listing = widget.listing;
    final cheapest = listing.cheapestPlan;
    if (cheapest == null) {
      return const SizedBox.shrink();
    }
    final money = listing.moneyFor(cheapest)!;
    final hasMore = listing.offeredPlans.length > 1;

    return Row(
      mainAxisSize: MainAxisSize.min,
      crossAxisAlignment: CrossAxisAlignment.baseline,
      textBaseline: TextBaseline.alphabetic,
      children: [
        if (hasMore)
          const Text(
            'from ',
            style: TextStyle(
              fontSize: 9,
              fontWeight: FontWeight.w500,
              color: Colors.black54,
            ),
          ),
        Text(
          money.format(useCompact: true),
          style: const TextStyle(
            fontSize: 11,
            fontWeight: FontWeight.w700,
            color: Colors.black87,
          ),
        ),
        Text(
          '/${cheapest.shortUnit}',
          style: const TextStyle(
            fontSize: 9,
            color: Colors.black54,
          ),
        ),
      ],
    );
  }

  /// One compact, de-emphasized line listing the non-cheapest offered plans,
  /// e.g. "৳1.5k/day · ৳35k/mo". Hidden when only one plan is offered.
  Widget _buildSecondaryRates(ThemeData theme) {
    final listing = widget.listing;
    final cheapest = listing.cheapestPlan;
    final others = listing.offeredPlans.where((p) => p != cheapest).toList();
    if (others.isEmpty) {
      return const SizedBox.shrink();
    }

    final text = others
        .map((p) =>
            '${listing.moneyFor(p)!.format(useCompact: true)}/${p.shortUnit}')
        .join(' · ');

    return Text(
      text,
      style: theme.textTheme.labelSmall?.copyWith(
        fontSize: 10,
        color: theme.colorScheme.onSurfaceVariant,
      ),
      maxLines: 1,
      overflow: TextOverflow.ellipsis,
    );
  }

  Widget _buildStatChip(IconData icon, String label, ThemeData theme) {
    return Row(
      mainAxisSize: MainAxisSize.min,
      children: [
        Icon(
          icon,
          size: 12,
          color: theme.colorScheme.onSurfaceVariant,
        ),
        const SizedBox(width: 2),
        Text(
          label,
          style: theme.textTheme.bodySmall?.copyWith(
            fontSize: 11,
            color: theme.colorScheme.onSurfaceVariant,
            fontWeight: FontWeight.w500,
          ),
        ),
      ],
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

/// Small colorful pill identifying the listing type, shown on the card image.
class _CategoryChip extends StatelessWidget {
  const _CategoryChip({required this.type});

  final ListingType type;

  Color get _color => switch (type) {
        ListingType.seat => AppColors.seat,
        ListingType.room => AppColors.room,
        ListingType.fullHouse => AppColors.fullHouse,
      };

  IconData get _icon => switch (type) {
        ListingType.seat => Icons.event_seat_rounded,
        ListingType.room => Icons.meeting_room_rounded,
        ListingType.fullHouse => Icons.home_rounded,
      };

  @override
  Widget build(BuildContext context) {
    return Container(
      padding: const EdgeInsets.symmetric(horizontal: 6, vertical: 3),
      decoration: BoxDecoration(
        color: _color.withValues(alpha: 0.95),
        borderRadius: BorderRadius.circular(20),
      ),
      child: Row(
        mainAxisSize: MainAxisSize.min,
        children: [
          Icon(_icon, size: 9, color: Colors.white),
          const SizedBox(width: 3),
          Text(
            type.title,
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

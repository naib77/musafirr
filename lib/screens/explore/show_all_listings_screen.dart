import 'package:flutter/material.dart';

import '../../core/utils/responsive.dart';
import '../../models/listing.dart';
import '../../state/favorites_state.dart';
import '../../widgets/hover_lift.dart';
import '../../widgets/listing_card_modern.dart';
import '../../widgets/listing_card_wide.dart';

/// The full grid behind a category row's "See all" arrow on Explore.
///
/// Rendered INLINE inside the Explore tab (not a pushed route) so the shell's
/// bottom navigation bar stays visible — it carries its own back-and-title
/// header instead of an AppBar. Purely client-side: it renders the already
/// loaded curated list the row was built from (e.g. every "Top rated" stay), so
/// tapping through needs no extra fetch. The list layout mirrors the search
/// results — a single-column of wide cards on phones, a responsive grid of
/// compact cards on wide screens — so it reads as part of the same experience.
class ShowAllListingsView extends StatelessWidget {
  const ShowAllListingsView({
    super.key,
    required this.title,
    required this.listings,
    required this.favoritesState,
    required this.onOpenListing,
    required this.onBack,
  });

  final String title;
  final List<Listing> listings;
  final FavoritesStateNotifier favoritesState;
  final void Function(Listing) onOpenListing;
  final VoidCallback onBack;

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    final wide = Responsive.isWide(context);
    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        // Header: back to the browse feed + the category title.
        Padding(
          padding: EdgeInsets.fromLTRB(wide ? 12 : 4, 6, 16, 6),
          child: Row(
            children: [
              IconButton(
                onPressed: onBack,
                icon: const Icon(Icons.arrow_back),
                tooltip: 'Back',
              ),
              Expanded(
                child: Text(
                  title,
                  style: theme.textTheme.titleLarge?.copyWith(
                    fontWeight: FontWeight.w800,
                  ),
                  maxLines: 1,
                  overflow: TextOverflow.ellipsis,
                ),
              ),
            ],
          ),
        ),
        // Rebuild the list on favourite changes so the hearts stay in sync.
        Expanded(
          child: ListenableBuilder(
            listenable: favoritesState,
            builder: (context, _) => wide ? _grid(context) : _list(context),
          ),
        ),
      ],
    );
  }

  Widget _list(BuildContext context) {
    return ListView.separated(
      padding: const EdgeInsets.fromLTRB(16, 6, 16, 24),
      itemCount: listings.length,
      separatorBuilder: (_, __) => const SizedBox(height: 26),
      itemBuilder: (context, index) {
        final listing = listings[index];
        return ListingCardWide(
          listing: listing,
          isFavorite: favoritesState.isFavorite(listing.id),
          onTap: () => onOpenListing(listing),
          onFavoriteTap: () => favoritesState.toggleFavorite(listing.id),
        );
      },
    );
  }

  Widget _grid(BuildContext context) {
    return GridView.builder(
      padding: const EdgeInsets.fromLTRB(16, 4, 16, 24),
      itemCount: listings.length,
      // Max-extent so the column count grows with width, matching the
      // search-results grid.
      gridDelegate: const SliverGridDelegateWithMaxCrossAxisExtent(
        maxCrossAxisExtent: 300,
        mainAxisSpacing: 16,
        crossAxisSpacing: 12,
        childAspectRatio: 0.72,
      ),
      itemBuilder: (context, index) {
        final listing = listings[index];
        return HoverLift(
          child: ListingCardModern(
            listing: listing,
            isFavorite: favoritesState.isFavorite(listing.id),
            onTap: () => onOpenListing(listing),
            onFavoriteTap: () => favoritesState.toggleFavorite(listing.id),
          ),
        );
      },
    );
  }
}

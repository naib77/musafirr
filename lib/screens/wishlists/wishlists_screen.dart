import 'package:flutter/material.dart';

import '../../core/routing/listing_path.dart';
import '../../models/listing.dart';
import '../../repositories/musafir_repository.dart';
import '../../state/auth_state.dart';
import '../../state/favorites_state.dart';
import '../../state/messaging_state.dart';
import '../../widgets/listing_card_modern.dart';

class WishlistsScreen extends StatelessWidget {
  const WishlistsScreen({
    super.key,
    required this.repository,
    required this.favoritesState,
    required this.authState,
    this.messagingState,
    this.onNavigateToExplore,
  });

  final MusafirRepository repository;
  final FavoritesStateNotifier favoritesState;
  final AuthStateNotifier authState;
  final MessagingStateNotifier? messagingState;
  final VoidCallback? onNavigateToExplore;

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);

    // No Scaffold here - main_shell.dart provides the AppBar
    return ListenableBuilder(
      listenable: Listenable.merge([repository, favoritesState]),
      builder: (context, _) {
        final favoriteIds = favoritesState.favoriteIds;
        final favoriteListings = repository.listings
            .where((l) => favoriteIds.contains(l.id))
            .toList();

        // Don't flash the empty state while data is still arriving. Show the
        // loader when favorites are loading, OR when we know there are saved
        // ids but the listings that back them haven't loaded yet (favoriteIds
        // populated but not all resolved AND listings still fetching). Once
        // listings finish, an id with no match is a genuinely removed listing
        // and correctly falls through to the empty/partial state.
        final favoritesUnresolved = favoriteIds.isNotEmpty &&
            favoriteListings.length < favoriteIds.length;
        if (favoritesState.isLoading ||
            (favoritesUnresolved && repository.isLoadingListings)) {
          return const Center(child: CircularProgressIndicator());
        }

        // A saved listing the host has since hidden (or deleted) is not in
        // `repository.listings` — only active listings are loaded — so it
        // used to fall out of the grid without a word and the wishlist
        // silently shrank (QA report 2026-09-19, scenario 43). Those ids are
        // shown as a placeholder card that says so and offers the one action
        // that still makes sense: taking it off the list.
        final unavailableIds = favoriteIds
            .where((id) => !favoriteListings.any((l) => l.id == id))
            .toList()
          ..sort();

        if (favoriteListings.isEmpty && unavailableIds.isEmpty) {
          return _buildEmptyState(context, theme);
        }

        final itemCount = favoriteListings.length + unavailableIds.length;
        return GridView.builder(
          padding: const EdgeInsets.all(16),
          gridDelegate: const SliverGridDelegateWithFixedCrossAxisCount(
            crossAxisCount: 2,
            mainAxisSpacing: 24,
            crossAxisSpacing: 16,
            // Deliberately not kListingCardAspectRatio: this is a fixed
            // two-column grid, so the cell is much narrower than the Explore
            // grid's and needs a taller ratio to reach the same photo. 0.74
            // holds the photo at the ~188px it was before the card's text
            // block stopped being 2/7 of the cell height.
            childAspectRatio: 0.74,
          ),
          itemCount: itemCount,
          itemBuilder: (context, index) {
            if (index >= favoriteListings.length) {
              final id = unavailableIds[index - favoriteListings.length];
              return UnavailableFavoriteCard(
                key: ValueKey('unavailable-$id'),
                onRemove: () => favoritesState.toggleFavorite(id),
              );
            }
            final listing = favoriteListings[index];
            return ListingCardModern(
              listing: listing,
              isFavorite: true,
              onTap: () => _openListingDetail(context, listing),
              onFavoriteTap: () => favoritesState.toggleFavorite(listing.id),
            );
          },
        );
      },
    );
  }

  Widget _buildEmptyState(BuildContext context, ThemeData theme) {
    return Center(
      child: Padding(
        padding: const EdgeInsets.all(32),
        child: Column(
          mainAxisAlignment: MainAxisAlignment.center,
          children: [
            Icon(
              Icons.favorite_border,
              size: 80,
              color: theme.colorScheme.onSurfaceVariant,
            ),
            const SizedBox(height: 24),
            Text(
              'No wishlists yet',
              style: theme.textTheme.headlineSmall?.copyWith(
                fontWeight: FontWeight.bold,
              ),
            ),
            const SizedBox(height: 8),
            Text(
              'As you explore, tap the heart icon to save your favorite places to your wishlist.',
              style: theme.textTheme.bodyLarge?.copyWith(
                color: theme.colorScheme.onSurfaceVariant,
              ),
              textAlign: TextAlign.center,
            ),
            const SizedBox(height: 24),
            FilledButton(
              onPressed: onNavigateToExplore,
              child: const Text('Start exploring'),
            ),
          ],
        ),
      ),
    );
  }

  void _openListingDetail(BuildContext context, Listing listing) {
    // See explore_screen: named for the shareable URL, Listing passed through
    // so there is no re-fetch.
    Navigator.of(context)
        .pushNamed(listingRoutePath(listing.id), arguments: listing);
  }
}

/// Stands in for a saved listing the guest can no longer open — hidden by its
/// host, or gone. Says so plainly and lets them remove it; there is nothing
/// else to do with it, and a card that tried to load would spin forever.
class UnavailableFavoriteCard extends StatelessWidget {
  const UnavailableFavoriteCard({super.key, required this.onRemove});

  final VoidCallback onRemove;

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    return Semantics(
      label: 'Saved listing no longer available',
      child: Container(
        decoration: BoxDecoration(
          color: theme.colorScheme.surfaceContainerHighest,
          borderRadius: BorderRadius.circular(16),
        ),
        padding: const EdgeInsets.all(16),
        child: Column(
          mainAxisAlignment: MainAxisAlignment.center,
          children: [
            Icon(
              Icons.visibility_off_outlined,
              size: 36,
              color: theme.colorScheme.onSurfaceVariant,
            ),
            const SizedBox(height: 12),
            Text(
              'No longer available',
              textAlign: TextAlign.center,
              style: theme.textTheme.titleSmall?.copyWith(
                fontWeight: FontWeight.w600,
              ),
            ),
            const SizedBox(height: 4),
            Text(
              'The host has taken this listing down.',
              textAlign: TextAlign.center,
              style: theme.textTheme.bodySmall?.copyWith(
                color: theme.colorScheme.onSurfaceVariant,
              ),
            ),
            const SizedBox(height: 12),
            TextButton.icon(
              onPressed: onRemove,
              icon: const Icon(Icons.favorite, size: 18),
              label: const Text('Remove'),
            ),
          ],
        ),
      ),
    );
  }
}

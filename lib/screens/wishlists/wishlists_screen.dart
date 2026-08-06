import 'package:flutter/material.dart';

import '../../models/listing.dart';
import '../../repositories/musafir_repository.dart';
import '../../state/auth_state.dart';
import '../../state/favorites_state.dart';
import '../../state/messaging_state.dart';
import '../../widgets/listing_card_modern.dart';
import '../explore/listing_detail_screen.dart';

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

        if (favoriteListings.isEmpty) {
          return _buildEmptyState(context, theme);
        }

        return GridView.builder(
          padding: const EdgeInsets.all(16),
          gridDelegate: const SliverGridDelegateWithFixedCrossAxisCount(
            crossAxisCount: 2,
            mainAxisSpacing: 24,
            crossAxisSpacing: 16,
            childAspectRatio: 0.65,
          ),
          itemCount: favoriteListings.length,
          itemBuilder: (context, index) {
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
    Navigator.of(context).push(
      MaterialPageRoute(
        builder: (_) => ListingDetailScreen(
          listing: listing,
          repository: repository,
          authState: authState,
          favoritesState: favoritesState,
          messagingState: messagingState,
        ),
      ),
    );
  }
}

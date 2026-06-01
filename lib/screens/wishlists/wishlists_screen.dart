import 'package:flutter/material.dart';

import '../../models/listing.dart';
import '../../repositories/musafir_repository.dart';
import '../../state/favorites_state.dart';
import '../../widgets/listing_card_modern.dart';
import '../../widgets/modern_banner.dart';

class WishlistsScreen extends StatelessWidget {
  const WishlistsScreen({
    super.key,
    required this.repository,
    required this.favoritesState,
  });

  final MusafirRepository repository;
  final FavoritesStateNotifier favoritesState;

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);

    return Scaffold(
      appBar: AppBar(
        title: const Text('Wishlists'),
        centerTitle: false,
      ),
      body: ListenableBuilder(
        listenable: Listenable.merge([repository, favoritesState]),
        builder: (context, _) {
          final favoriteIds = favoritesState.favoriteIds;
          final favoriteListings = repository.listings
              .where((l) => favoriteIds.contains(l.id))
              .toList();

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
      ),
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
              onPressed: () {
                // Navigate to explore tab
                // This would be handled by the parent MainShell
              },
              child: const Text('Start exploring'),
            ),
          ],
        ),
      ),
    );
  }

  void _openListingDetail(BuildContext context, Listing listing) {
    // TODO: Navigate to listing detail
    // This would need access to authState, which we don't have here
    // For now, show a info banner
    ModernBanner.showInfo(context, 'Opening ${listing.title}');
  }
}

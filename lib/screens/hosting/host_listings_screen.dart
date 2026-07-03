import 'package:flutter/material.dart';

import '../../models/listing.dart';
import '../../repositories/musafir_repository.dart';
import '../../state/auth_state.dart';
import '../../state/favorites_state.dart';
import '../../widgets/modern_banner.dart';
import '../explore/listing_detail_screen.dart';

/// Screen showing host's listings with stats
class HostListingsScreen extends StatelessWidget {
  const HostListingsScreen({
    super.key,
    required this.repository,
    required this.authState,
    required this.favoritesState,
  });

  final MusafirRepository repository;
  final AuthStateNotifier authState;
  final FavoritesStateNotifier favoritesState;

  @override
  Widget build(BuildContext context) {
    return ListenableBuilder(
      listenable: Listenable.merge([repository, authState]),
      builder: (context, _) {
        final user = authState.currentUser;
        if (user == null) {
          return const _NotLoggedInView();
        }

        final hostListings = repository.listings
            .where((l) => l.hostId == user.id)
            .toList();

        if (hostListings.isEmpty) {
          return _EmptyListingsView(onCreateListing: () => _createListing(context));
        }

        return _ListingsGrid(
          listings: hostListings,
          repository: repository,
          onListingTap: (listing) => _openListing(context, listing),
          onCreateListing: () => _createListing(context),
        );
      },
    );
  }

  void _openListing(BuildContext context, Listing listing) {
    Navigator.push(
      context,
      MaterialPageRoute(
        builder: (context) => ListingDetailScreen(
          listing: listing,
          repository: repository,
          authState: authState,
          favoritesState: favoritesState,
        ),
      ),
    );
  }

  void _createListing(BuildContext context) {
    // TODO: Navigate to listing creation flow
    ModernBanner.showInfo(context, 'Listing creation coming soon!');
  }
}

class _NotLoggedInView extends StatelessWidget {
  const _NotLoggedInView();

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);

    return Center(
      child: Padding(
        padding: const EdgeInsets.all(32),
        child: Column(
          mainAxisAlignment: MainAxisAlignment.center,
          children: [
            Icon(
              Icons.login,
              size: 64,
              color: theme.colorScheme.onSurfaceVariant.withValues(alpha: 0.5),
            ),
            const SizedBox(height: 16),
            Text(
              'Login to manage listings',
              style: theme.textTheme.titleMedium,
            ),
          ],
        ),
      ),
    );
  }
}

class _EmptyListingsView extends StatelessWidget {
  const _EmptyListingsView({required this.onCreateListing});

  final VoidCallback onCreateListing;

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);

    return Center(
      child: Padding(
        padding: const EdgeInsets.all(32),
        child: Column(
          mainAxisAlignment: MainAxisAlignment.center,
          children: [
            Container(
              width: 100,
              height: 100,
              decoration: BoxDecoration(
                color: theme.colorScheme.primaryContainer,
                shape: BoxShape.circle,
              ),
              child: Icon(
                Icons.home_work,
                size: 48,
                color: theme.colorScheme.primary,
              ),
            ),
            const SizedBox(height: 24),
            Text(
              'Start hosting on Musafir',
              style: theme.textTheme.headlineSmall?.copyWith(
                fontWeight: FontWeight.bold,
              ),
            ),
            const SizedBox(height: 12),
            Text(
              'List your space and start earning. Share your home with travelers from around the world.',
              textAlign: TextAlign.center,
              style: theme.textTheme.bodyLarge?.copyWith(
                color: theme.colorScheme.onSurfaceVariant,
              ),
            ),
            const SizedBox(height: 32),
            FilledButton.icon(
              onPressed: onCreateListing,
              icon: const Icon(Icons.add),
              label: const Text('Create your first listing'),
            ),
          ],
        ),
      ),
    );
  }
}

class _ListingsGrid extends StatelessWidget {
  const _ListingsGrid({
    required this.listings,
    required this.repository,
    required this.onListingTap,
    required this.onCreateListing,
  });

  final List<Listing> listings;
  final MusafirRepository repository;
  final ValueChanged<Listing> onListingTap;
  final VoidCallback onCreateListing;

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      body: RefreshIndicator(
        onRefresh: () async {
          // Trigger repository refresh if available
        },
        child: GridView.builder(
          padding: const EdgeInsets.all(16),
          gridDelegate: const SliverGridDelegateWithFixedCrossAxisCount(
            crossAxisCount: 2,
            childAspectRatio: 0.75,
            crossAxisSpacing: 12,
            mainAxisSpacing: 12,
          ),
          itemCount: listings.length,
          itemBuilder: (context, index) {
            final listing = listings[index];
            return _ListingCard(
              listing: listing,
              repository: repository,
              onTap: () => onListingTap(listing),
            );
          },
        ),
      ),
      floatingActionButton: FloatingActionButton.extended(
        onPressed: onCreateListing,
        icon: const Icon(Icons.add),
        label: const Text('Add listing'),
      ),
    );
  }
}

class _ListingCard extends StatelessWidget {
  const _ListingCard({
    required this.listing,
    required this.repository,
    required this.onTap,
  });

  final Listing listing;
  final MusafirRepository repository;
  final VoidCallback onTap;

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);

    // Get booking stats for this listing
    final bookings = repository.bookings
        .where((b) => b.listingId == listing.id)
        .toList();
    final activeBookings = bookings.where((b) =>
        b.status.name == 'active' || b.status.name == 'confirmed').length;

    return GestureDetector(
      onTap: onTap,
      child: Container(
        decoration: BoxDecoration(
          color: theme.colorScheme.surface,
          borderRadius: BorderRadius.circular(12),
          boxShadow: [
            BoxShadow(
              color: Colors.black.withValues(alpha: 0.08),
              blurRadius: 8,
              offset: const Offset(0, 2),
            ),
          ],
        ),
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            // Image
            Expanded(
              flex: 3,
              child: Stack(
                children: [
                  ClipRRect(
                    borderRadius: const BorderRadius.vertical(
                      top: Radius.circular(12),
                    ),
                    child: listing.primaryImage != null
                        ? Image.network(
                            listing.primaryImage!,
                            width: double.infinity,
                            height: double.infinity,
                            fit: BoxFit.cover,
                            errorBuilder: (_, __, ___) => _buildPlaceholder(theme),
                          )
                        : _buildPlaceholder(theme),
                  ),
                  // Status badge
                  Positioned(
                    top: 8,
                    left: 8,
                    child: Container(
                      padding: const EdgeInsets.symmetric(
                        horizontal: 8,
                        vertical: 4,
                      ),
                      decoration: BoxDecoration(
                        color: listing.available
                            ? Colors.green
                            : Colors.orange,
                        borderRadius: BorderRadius.circular(4),
                      ),
                      child: Text(
                        listing.available ? 'Active' : 'Paused',
                        style: theme.textTheme.labelSmall?.copyWith(
                          color: Colors.white,
                          fontWeight: FontWeight.bold,
                        ),
                      ),
                    ),
                  ),
                ],
              ),
            ),
            // Info
            Expanded(
              flex: 2,
              child: Padding(
                padding: const EdgeInsets.all(10),
                child: Column(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    Text(
                      listing.title,
                      style: theme.textTheme.bodyMedium?.copyWith(
                        fontWeight: FontWeight.w600,
                      ),
                      maxLines: 2,
                      overflow: TextOverflow.ellipsis,
                    ),
                    const Spacer(),
                    // Stats row
                    Row(
                      children: [
                        // Rating
                        if (listing.rating != null && listing.rating! > 0) ...[
                          const Icon(Icons.star, size: 14, color: Colors.amber),
                          const SizedBox(width: 2),
                          Text(
                            listing.rating!.toStringAsFixed(1),
                            style: theme.textTheme.bodySmall,
                          ),
                          const SizedBox(width: 8),
                        ],
                        // Active bookings
                        Icon(
                          Icons.calendar_today,
                          size: 14,
                          color: theme.colorScheme.onSurfaceVariant,
                        ),
                        const SizedBox(width: 2),
                        Text(
                          '$activeBookings',
                          style: theme.textTheme.bodySmall?.copyWith(
                            color: theme.colorScheme.onSurfaceVariant,
                          ),
                        ),
                      ],
                    ),
                  ],
                ),
              ),
            ),
          ],
        ),
      ),
    );
  }

  Widget _buildPlaceholder(ThemeData theme) {
    return Container(
      color: theme.colorScheme.surfaceContainerHighest,
      child: Center(
        child: Icon(
          Icons.home_outlined,
          size: 32,
          color: theme.colorScheme.onSurfaceVariant,
        ),
      ),
    );
  }
}

import 'package:flutter/material.dart';

import '../../models/listing.dart';
import '../../repositories/in_memory_musafir_repository.dart';
import '../../state/auth_state.dart';
import 'create_listing_screen.dart';

class HostListingsScreen extends StatelessWidget {
  const HostListingsScreen({
    super.key,
    required this.repository,
    required this.authState,
  });

  final InMemoryMusafirRepository repository;
  final AuthStateNotifier authState;

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    final user = authState.currentUser;

    return Scaffold(
      appBar: AppBar(
        title: const Text('Your Listings'),
      ),
      body: ListenableBuilder(
        listenable: Listenable.merge([repository, authState]),
        builder: (context, _) {
          final hostListings = user != null
              ? repository.listings
                  .where((l) => l.hostId == user.id || l.ownerName == user.name)
                  .toList()
              : <Listing>[];

          if (hostListings.isEmpty) {
            return _buildEmptyState(context, theme);
          }

          return ListView.separated(
            padding: const EdgeInsets.all(16),
            itemCount: hostListings.length,
            separatorBuilder: (_, __) => const SizedBox(height: 12),
            itemBuilder: (context, index) {
              final listing = hostListings[index];
              return _ListingCard(
                listing: listing,
                onEdit: () => _editListing(context, listing),
                onDelete: () => _confirmDelete(context, listing),
                onToggleAvailability: () => _toggleAvailability(listing),
                repository: repository,
              );
            },
          );
        },
      ),
      floatingActionButton: FloatingActionButton.extended(
        onPressed: () => _createListing(context),
        icon: const Icon(Icons.add),
        label: const Text('Add Listing'),
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
              Icons.home_work_outlined,
              size: 80,
              color: theme.colorScheme.onSurfaceVariant,
            ),
            const SizedBox(height: 24),
            Text(
              'No listings yet',
              style: theme.textTheme.headlineSmall?.copyWith(
                fontWeight: FontWeight.bold,
              ),
            ),
            const SizedBox(height: 8),
            Text(
              'Create your first listing and start hosting guests.',
              style: theme.textTheme.bodyLarge?.copyWith(
                color: theme.colorScheme.onSurfaceVariant,
              ),
              textAlign: TextAlign.center,
            ),
            const SizedBox(height: 24),
            FilledButton.icon(
              onPressed: () => _createListing(context),
              icon: const Icon(Icons.add),
              label: const Text('Create Listing'),
            ),
          ],
        ),
      ),
    );
  }

  void _createListing(BuildContext context) {
    Navigator.push(
      context,
      MaterialPageRoute(
        builder: (context) => CreateListingScreen(
          repository: repository,
          authState: authState,
        ),
      ),
    );
  }

  void _editListing(BuildContext context, Listing listing) {
    // For now, show a coming soon message
    ScaffoldMessenger.of(context).showSnackBar(
      const SnackBar(content: Text('Edit listing coming soon!')),
    );
  }

  void _confirmDelete(BuildContext context, Listing listing) {
    showDialog(
      context: context,
      builder: (context) => AlertDialog(
        title: const Text('Delete Listing'),
        content: Text('Are you sure you want to delete "${listing.title}"?'),
        actions: [
          TextButton(
            onPressed: () => Navigator.pop(context),
            child: const Text('Cancel'),
          ),
          FilledButton(
            onPressed: () {
              repository.deleteListing(listing.id);
              Navigator.pop(context);
              ScaffoldMessenger.of(context).showSnackBar(
                const SnackBar(content: Text('Listing deleted')),
              );
            },
            style: FilledButton.styleFrom(
              backgroundColor: Colors.red,
            ),
            child: const Text('Delete'),
          ),
        ],
      ),
    );
  }

  void _toggleAvailability(Listing listing) {
    final updated = listing.copyWith(available: !listing.available);
    repository.updateListing(updated);
  }
}

class _ListingCard extends StatelessWidget {
  const _ListingCard({
    required this.listing,
    required this.onEdit,
    required this.onDelete,
    required this.onToggleAvailability,
    required this.repository,
  });

  final Listing listing;
  final VoidCallback onEdit;
  final VoidCallback onDelete;
  final VoidCallback onToggleAvailability;
  final InMemoryMusafirRepository repository;

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);

    // Get booking count for this listing
    final bookings = repository.bookings
        .where((b) => b.listingId == listing.id)
        .length;

    return Card(
      clipBehavior: Clip.antiAlias,
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          // Image
          Stack(
            children: [
              AspectRatio(
                aspectRatio: 2.5,
                child: listing.primaryImage != null
                    ? Image.network(
                        listing.primaryImage!,
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
                    color: listing.available ? Colors.green : Colors.red,
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

          Padding(
            padding: const EdgeInsets.all(16),
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                // Title
                Text(
                  listing.title,
                  style: theme.textTheme.titleMedium?.copyWith(
                    fontWeight: FontWeight.bold,
                  ),
                  maxLines: 1,
                  overflow: TextOverflow.ellipsis,
                ),
                const SizedBox(height: 4),

                // Location
                Text(
                  '${listing.city ?? listing.address}',
                  style: theme.textTheme.bodyMedium?.copyWith(
                    color: theme.colorScheme.onSurfaceVariant,
                  ),
                ),
                const SizedBox(height: 8),

                // Stats row
                Row(
                  children: [
                    _StatChip(
                      icon: Icons.attach_money,
                      label: '\$${listing.displayPrice.toStringAsFixed(0)}/night',
                      theme: theme,
                    ),
                    const SizedBox(width: 8),
                    _StatChip(
                      icon: Icons.book_online,
                      label: '$bookings bookings',
                      theme: theme,
                    ),
                    if (listing.rating != null) ...[
                      const SizedBox(width: 8),
                      _StatChip(
                        icon: Icons.star,
                        label: listing.rating!.toStringAsFixed(1),
                        theme: theme,
                      ),
                    ],
                  ],
                ),
                const SizedBox(height: 12),

                // Actions
                Row(
                  children: [
                    Expanded(
                      child: OutlinedButton.icon(
                        onPressed: onToggleAvailability,
                        icon: Icon(
                          listing.available
                              ? Icons.pause
                              : Icons.play_arrow,
                        ),
                        label: Text(listing.available ? 'Pause' : 'Activate'),
                      ),
                    ),
                    const SizedBox(width: 8),
                    IconButton(
                      icon: const Icon(Icons.edit),
                      onPressed: onEdit,
                      tooltip: 'Edit',
                    ),
                    IconButton(
                      icon: const Icon(Icons.delete_outline),
                      onPressed: onDelete,
                      tooltip: 'Delete',
                      color: Colors.red,
                    ),
                  ],
                ),
              ],
            ),
          ),
        ],
      ),
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
}

class _StatChip extends StatelessWidget {
  const _StatChip({
    required this.icon,
    required this.label,
    required this.theme,
  });

  final IconData icon;
  final String label;
  final ThemeData theme;

  @override
  Widget build(BuildContext context) {
    return Container(
      padding: const EdgeInsets.symmetric(horizontal: 8, vertical: 4),
      decoration: BoxDecoration(
        color: theme.colorScheme.surfaceContainerHighest,
        borderRadius: BorderRadius.circular(4),
      ),
      child: Row(
        mainAxisSize: MainAxisSize.min,
        children: [
          Icon(icon, size: 14, color: theme.colorScheme.onSurfaceVariant),
          const SizedBox(width: 4),
          Text(
            label,
            style: theme.textTheme.labelSmall?.copyWith(
              color: theme.colorScheme.onSurfaceVariant,
            ),
          ),
        ],
      ),
    );
  }
}

import 'package:flutter/material.dart';

import '../../core/theme/app_colors.dart';
import '../../core/utils/responsive.dart';
import '../../models/listing.dart';
import '../../models/property.dart';
import '../../models/rental_plan.dart';
import '../../repositories/musafir_repository.dart';
import '../../services/verification/publish_gate.dart';
import '../../state/auth_state.dart';
import '../../widgets/modern_banner.dart';
import 'create_listing_screen.dart';
import 'edit_listing_screen.dart';
import 'listing_availability_screen.dart';
import 'property_dashboard_screen.dart';
import '../../widgets/app_network_image.dart';

class HostListingsScreen extends StatelessWidget {
  const HostListingsScreen({
    super.key,
    required this.repository,
    required this.authState,
  });

  final MusafirRepository repository;
  final AuthStateNotifier authState;

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    final user = authState.currentUser;

    return Scaffold(
      appBar: AppBar(
        title: const Text('Your Listings'),
      ),
      body: ResponsiveCenter(
        maxWidth: 960,
        child: ListenableBuilder(
          listenable: Listenable.merge([repository, authState]),
          builder: (context, _) {
            final own = user != null
                ? repository.listings.where((l) => l.hostId == user.id).toList()
                : <Listing>[];
            // A hotel's room types are listed under the hotel (its card
            // opens the dashboard with every type and room), not again here
            // one by one: the host thinks of Sea Crown as one place.
            final hostListings = own.where((l) => !l.isHotelRoomType).toList();
            final hasHotelTypes = own.any((l) => l.isHotelRoomType);

            final hotels = _HotelsSection(
              repository: repository,
              authState: authState,
            );
            if (hostListings.isEmpty && hasHotelTypes) {
              return ListView(
                padding: const EdgeInsets.fromLTRB(16, 16, 16, 96),
                children: [hotels],
              );
            }
            if (hostListings.isEmpty) {
              // A hotel just created has no room type yet, so no listing --
              // it must still be reachable, or the host loses it.
              return Column(
                children: [
                  hotels,
                  Expanded(child: _buildEmptyState(context, theme)),
                ],
              );
            }

            return ListView.separated(
              // Extra bottom padding so the last card's action row (Edit/Delete)
              // clears the "Add Listing" FAB that floats over the list.
              padding: const EdgeInsets.fromLTRB(16, 16, 16, 96),
              itemCount: hostListings.length + 1,
              separatorBuilder: (_, __) => const SizedBox(height: 12),
              itemBuilder: (context, index) {
                if (index == 0) return hotels;
                final listing = hostListings[index - 1];
                return _ListingCard(
                  listing: listing,
                  onEdit: () => _editListing(context, listing),
                  onDelete: () => _confirmDelete(context, listing),
                  onToggleAvailability: () =>
                      _toggleAvailability(context, listing),
                  onManageDates: () => _manageDates(context, listing),
                  repository: repository,
                );
              },
            );
          },
        ),
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

  Future<void> _createListing(BuildContext context) async {
    // Sign-in, identity and address-proof all live in PublishGate now, so the
    // dashboard and profile entry points enforce exactly the same thing rather
    // than nothing at all.
    if (!await PublishGate.ensure(context, authState)) return;
    if (!context.mounted) return;
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
    Navigator.push(
      context,
      MaterialPageRoute(
        builder: (context) => EditListingScreen(
          repository: repository,
          listing: listing,
        ),
      ),
    );
  }

  void _confirmDelete(BuildContext context, Listing listing) {
    showDialog(
      context: context,
      builder: (dialogContext) => AlertDialog(
        title: const Text('Delete Listing'),
        content: Text('Are you sure you want to delete "${listing.title}"?'),
        actions: [
          TextButton(
            onPressed: () => Navigator.pop(dialogContext),
            child: const Text('Cancel'),
          ),
          FilledButton(
            onPressed: () async {
              Navigator.pop(dialogContext);
              try {
                await repository.deleteListing(listing.id);
                // Use the screen context (not the popped dialog's) for the banner.
                if (context.mounted) {
                  ModernBanner.showSuccess(context, 'Listing deleted');
                }
              } catch (e) {
                if (context.mounted) {
                  ModernBanner.showError(
                    context,
                    e.toString().replaceFirst('Exception: ', ''),
                  );
                }
              }
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

  void _manageDates(BuildContext context, Listing listing) {
    Navigator.push(
      context,
      MaterialPageRoute(
        builder: (context) => ListingAvailabilityScreen(
          repository: repository,
          listing: listing,
        ),
      ),
    );
  }

  Future<void> _toggleAvailability(
      BuildContext context, Listing listing) async {
    final hiding = listing.available;
    final confirmed = await showDialog<bool>(
      context: context,
      builder: (dialogContext) => AlertDialog(
        title: Text(hiding ? 'Hide listing?' : 'Show listing?'),
        content: Text(
          hiding
              ? 'Guests won\'t be able to find or book "${listing.title}" '
                  'until you show it again.'
              : '"${listing.title}" will be visible to guests and available '
                  'to book.',
        ),
        actions: [
          TextButton(
            onPressed: () => Navigator.pop(dialogContext, false),
            child: const Text('Cancel'),
          ),
          FilledButton(
            onPressed: () => Navigator.pop(dialogContext, true),
            child: Text(hiding ? 'Hide' : 'Show'),
          ),
        ],
      ),
    );
    if (confirmed != true) return;

    try {
      await repository.setListingAvailability(
        listing.id,
        !listing.available,
      );
    } catch (e) {
      if (context.mounted) {
        ModernBanner.showError(
          context,
          e.toString().replaceFirst('Exception: ', ''),
        );
      }
    }
  }
}

class _ListingCard extends StatelessWidget {
  const _ListingCard({
    required this.listing,
    required this.onEdit,
    required this.onDelete,
    required this.onToggleAvailability,
    required this.onManageDates,
    required this.repository,
  });

  final Listing listing;
  final VoidCallback onEdit;
  final VoidCallback onDelete;
  final VoidCallback onToggleAvailability;
  final VoidCallback onManageDates;
  final MusafirRepository repository;

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);

    // Get booking count for this listing
    final bookings =
        repository.bookings.where((b) => b.listingId == listing.id).length;

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
                    ? AppNetworkImage(
                        url: listing.primaryImage!,
                        // Card-width hero in a scrolling list, never full-screen.
                        decodeWidth: 600,
                        fit: BoxFit.cover,
                        errorWidget: _buildPlaceholder(theme),
                      )
                    : _buildPlaceholder(theme),
              ),
              // Visibility badge
              Positioned(
                top: 10,
                left: 10,
                child: Container(
                  padding: const EdgeInsets.symmetric(
                    horizontal: 10,
                    vertical: 5,
                  ),
                  decoration: BoxDecoration(
                    color: listing.available
                        ? AppColors.success
                        : AppColors.inkMuted,
                    borderRadius: BorderRadius.circular(30),
                  ),
                  child: Row(
                    mainAxisSize: MainAxisSize.min,
                    children: [
                      Icon(
                        listing.available
                            ? Icons.visibility_rounded
                            : Icons.visibility_off_rounded,
                        size: 13,
                        color: Colors.white,
                      ),
                      const SizedBox(width: 5),
                      Text(
                        listing.available ? 'Live' : 'Hidden',
                        style: theme.textTheme.labelSmall?.copyWith(
                          color: Colors.white,
                          fontWeight: FontWeight.w700,
                        ),
                      ),
                    ],
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
                  listing.city ?? listing.address,
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
                      label:
                          '${listing.displayPriceMoney.format(showDecimal: false)}/${listing.cheapestPlan?.shortUnit ?? 'day'}',
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
                              ? Icons.visibility_off_outlined
                              : Icons.visibility_outlined,
                          size: 18,
                        ),
                        label: Text(listing.available ? 'Hide' : 'Show'),
                      ),
                    ),
                    const SizedBox(width: 8),
                    // Sits next to Hide/Show because the two answer the same
                    // question at different granularities: Hide takes the
                    // listing off the market entirely, Dates takes specific
                    // days off it.
                    Expanded(
                      child: OutlinedButton.icon(
                        onPressed: onManageDates,
                        icon: const Icon(Icons.event_busy_outlined, size: 18),
                        label: const Text('Dates'),
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

/// The host's hotels (153), each opening its room-type dashboard. Room types
/// also appear below as ordinary listing cards -- they are listings -- but
/// rooms, moves and new types are managed from the hotel.
class _HotelsSection extends StatefulWidget {
  const _HotelsSection({required this.repository, required this.authState});

  final MusafirRepository repository;
  final AuthStateNotifier authState;

  @override
  State<_HotelsSection> createState() => _HotelsSectionState();
}

class _HotelsSectionState extends State<_HotelsSection> {
  List<Property> _hotels = const [];
  bool _loading = false;

  @override
  void initState() {
    super.initState();
    widget.repository.addListener(_load);
    _load();
  }

  @override
  void dispose() {
    widget.repository.removeListener(_load);
    super.dispose();
  }

  Future<void> _load() async {
    // The repository notifies in bursts (optimistic add, then refresh); one
    // query in flight is enough.
    if (_loading) return;
    _loading = true;
    try {
      final hotels = await widget.repository.myProperties();
      if (mounted) setState(() => _hotels = hotels);
    } catch (e) {
      // Before 153 is live the table does not exist; no section, no error.
      debugPrint('Error loading hotels: $e');
    } finally {
      _loading = false;
    }
  }

  @override
  Widget build(BuildContext context) {
    if (_hotels.isEmpty) return const SizedBox.shrink();
    final theme = Theme.of(context);
    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        Padding(
          padding: const EdgeInsets.fromLTRB(4, 0, 4, 8),
          child: Text(
            'Your hotels',
            style: theme.textTheme.titleMedium
                ?.copyWith(fontWeight: FontWeight.bold),
          ),
        ),
        for (final h in _hotels)
          Card(
            margin: const EdgeInsets.only(bottom: 8),
            child: ListTile(
              leading: const Icon(Icons.apartment),
              title: Text(h.name),
              subtitle: h.publicAddress.isEmpty ? null : Text(h.publicAddress),
              trailing: const Icon(Icons.chevron_right),
              onTap: () => Navigator.push(
                context,
                MaterialPageRoute(
                  builder: (_) => PropertyDashboardScreen(
                    repository: widget.repository,
                    authState: widget.authState,
                    property: h,
                  ),
                ),
              ),
            ),
          ),
        const SizedBox(height: 4),
      ],
    );
  }
}

import 'package:flutter/material.dart';

import '../../core/theme/app_colors.dart';
import '../../core/utils/responsive.dart';
import '../../models/listing.dart';
import '../../models/rental_plan.dart';
import '../../repositories/musafir_repository.dart';
import '../../services/app_settings_service.dart';
import '../../services/image_upload_service.dart';
import '../../services/verification/identity_gate.dart';
import '../../state/auth_state.dart';
import '../../widgets/modern_banner.dart';
import 'address_proof_screen.dart';
import 'create_listing_screen.dart';
import 'edit_listing_screen.dart';
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
            final hostListings = user != null
                ? repository.listings.where((l) => l.hostId == user.id).toList()
                : <Listing>[];

            if (hostListings.isEmpty) {
              return _buildEmptyState(context, theme);
            }

            return ListView.separated(
              // Extra bottom padding so the last card's action row (Edit/Delete)
              // clears the "Add Listing" FAB that floats over the list.
              padding: const EdgeInsets.fromLTRB(16, 16, 16, 96),
              itemCount: hostListings.length,
              separatorBuilder: (_, __) => const SizedBox(height: 12),
              itemBuilder: (context, index) {
                final listing = hostListings[index];
                return _ListingCard(
                  listing: listing,
                  onEdit: () => _editListing(context, listing),
                  onDelete: () => _confirmDelete(context, listing),
                  onToggleAvailability: () =>
                      _toggleAvailability(context, listing),
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
    final userId = authState.currentUser?.id;

    // Identity gate: a host must have an admin-approved identity (ID document +
    // selfie, verified by an admin) before publishing a listing.
    if (userId != null) {
      final verified = await IdentityGate.ensure(
        context,
        userId,
        reason: 'to publish a listing',
      );
      if (!verified) return;
    }

    // When configured, a host must have submitted their address — the billed
    // copy AND the address in writing — before publishing a listing.
    //
    // SUBMITTING is the gate, not the verdict: an admin's physical visit takes
    // days, and a host who has done their part must not sit on an unpublishable
    // listing waiting for one. The "Address verified" badge is what waits for
    // the visit. A rejected submission is also allowed through — the host is
    // told why on the profile screen and can resubmit; blocking them here would
    // pull a live host's ability to list out from under them over a bad photo.
    if (!context.mounted) return;
    if (userId != null &&
        await AppSettingsService.instance.ensureRequireListingAddressProof()) {
      final address =
          await ImageUploadService.instance.addressVerification(userId);
      if (!address.isSubmitted) {
        if (!context.mounted) return;
        final uploaded = await Navigator.push<bool>(
          context,
          MaterialPageRoute(
            builder: (context) => AddressProofScreen(userId: userId),
          ),
        );
        // Host backed out without submitting — don't proceed to the form.
        if (uploaded != true) return;
      }
    }

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
    required this.repository,
  });

  final Listing listing;
  final VoidCallback onEdit;
  final VoidCallback onDelete;
  final VoidCallback onToggleAvailability;
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

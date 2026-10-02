import 'package:flutter/material.dart';

import '../../core/theme/app_colors.dart';
import '../../core/utils/responsive.dart';
import '../../models/listing.dart';
import '../../models/property.dart';
import '../../models/rental_plan.dart';
import '../../repositories/musafir_repository.dart';
import '../../state/auth_state.dart';
import '../../state/favorites_state.dart';
import '../../state/messaging_state.dart';
import '../../widgets/app_network_image.dart';
import 'listing_detail_screen.dart';

/// A hotel and its room types (plan hotel-room-types.md §5). Search shows a
/// hotel once (154), so this page is where a guest picks Deluxe or Sea
/// Front; each room type then opens its own [ListingDetailScreen], which
/// books one room through the unchanged single-room path.
///
/// Reached from [ListingRoute] whenever the listing is a room type, so a
/// card, a map pin, a wishlist entry and an old `/listing/<room type>` link
/// all land here. [focusListingId] is the room type that led here, marked so
/// the guest can still find what they saved or were sent.
class HotelScreen extends StatefulWidget {
  const HotelScreen({
    super.key,
    required this.propertyId,
    required this.repository,
    required this.authState,
    required this.favoritesState,
    this.messagingState,
    this.focusListingId,
  });

  final String propertyId;
  final MusafirRepository repository;
  final AuthStateNotifier authState;
  final FavoritesStateNotifier favoritesState;
  final MessagingStateNotifier? messagingState;
  final String? focusListingId;

  @override
  State<HotelScreen> createState() => _HotelScreenState();
}

class _HotelScreenState extends State<HotelScreen> {
  Property? _property;
  List<Listing> _types = const [];
  bool _loading = true;
  bool _failed = false;

  @override
  void initState() {
    super.initState();
    _load();
  }

  Future<void> _load() async {
    setState(() {
      _loading = true;
      _failed = false;
    });
    try {
      final results = await Future.wait([
        widget.repository.fetchProperty(widget.propertyId),
        widget.repository.propertyRoomTypes(widget.propertyId),
      ]);
      if (!mounted) return;
      setState(() {
        _property = results[0] as Property?;
        // The select policy already hides inactive types from guests; a
        // paused one (host_available) is hidden here too, since search
        // would not offer it either. The host previewing their own hotel
        // gets the same view a guest does.
        _types = (results[1] as List<Listing>)
            .where((l) => l.available && l.hostAvailable)
            .toList();
        _loading = false;
      });
    } catch (e) {
      debugPrint('Error loading hotel ${widget.propertyId}: $e');
      if (mounted) {
        setState(() {
          _loading = false;
          _failed = true;
        });
      }
    }
  }

  void _openType(Listing listing) {
    Navigator.of(context).push(MaterialPageRoute(
      builder: (_) => ListingDetailScreen(
        listing: listing,
        repository: widget.repository,
        authState: widget.authState,
        favoritesState: widget.favoritesState,
        messagingState: widget.messagingState,
      ),
    ));
  }

  @override
  Widget build(BuildContext context) {
    final property = _property;
    if (_loading) {
      return const Scaffold(body: Center(child: CircularProgressIndicator()));
    }
    if (property == null || _types.isEmpty) {
      return Scaffold(
        appBar: AppBar(),
        body: Center(
          child: Padding(
            padding: const EdgeInsets.all(32),
            child: Column(
              mainAxisSize: MainAxisSize.min,
              children: [
                Text(
                  _failed
                      ? 'Could not load this hotel'
                      : 'This hotel is no longer listed',
                  style: Theme.of(context).textTheme.titleMedium,
                  textAlign: TextAlign.center,
                ),
                if (_failed) ...[
                  const SizedBox(height: 16),
                  FilledButton(
                      onPressed: _load, child: const Text('Try again')),
                ],
              ],
            ),
          ),
        ),
      );
    }

    final theme = Theme.of(context);
    // No hotel photos yet (phase 1 has none on the property), so the cover
    // is the first room type's first photo.
    final cover = property.imageUrls.isNotEmpty
        ? property.imageUrls.first
        : _types
            .expand((t) => t.imageUrls)
            .cast<String?>()
            .firstWhere((_) => true, orElse: () => null);
    final stars = property.hotelDetails.starRating;
    final times = [
      if (property.checkInTime != null) 'Check-in ${property.checkInTime}',
      if (property.checkOutTime != null) 'Check-out ${property.checkOutTime}',
    ].join(' · ');

    return Scaffold(
      appBar: AppBar(title: Text(property.name)),
      body: ResponsiveCenter(
        maxWidth: 900,
        child: ListView(
          padding: const EdgeInsets.fromLTRB(16, 8, 16, 32),
          children: [
            if (cover != null)
              AspectRatio(
                aspectRatio: 16 / 9,
                child: AppNetworkImage(
                  url: cover,
                  borderRadius: BorderRadius.circular(16),
                ),
              ),
            const SizedBox(height: 16),
            Text(
              property.name,
              style: theme.textTheme.headlineSmall
                  ?.copyWith(fontWeight: FontWeight.bold),
            ),
            const SizedBox(height: 4),
            Text(
              [
                if (stars != null) '$stars-star hotel',
                if (property.publicAddress.isNotEmpty) property.publicAddress,
              ].join(' · '),
              style: theme.textTheme.bodyMedium
                  ?.copyWith(color: theme.colorScheme.onSurfaceVariant),
            ),
            if (times.isNotEmpty) ...[
              const SizedBox(height: 4),
              Text(times, style: theme.textTheme.bodyMedium),
            ],
            if ((property.description ?? '').isNotEmpty) ...[
              const SizedBox(height: 12),
              Text(property.description!, style: theme.textTheme.bodyLarge),
            ],
            const SizedBox(height: 24),
            Text(
              _types.length == 1
                  ? '1 room type'
                  : 'Choose from ${_types.length} room types',
              style: theme.textTheme.titleLarge
                  ?.copyWith(fontWeight: FontWeight.bold),
            ),
            const SizedBox(height: 12),
            for (final t in _types) ...[
              _RoomTypeRow(
                listing: t,
                highlighted: t.id == widget.focusListingId,
                onTap: () => _openType(t),
              ),
              const SizedBox(height: 12),
            ],
          ],
        ),
      ),
    );
  }
}

/// One room type: photo, name, who it sleeps, its rates. The whole row opens
/// the room type's page, which has the dates and Reserve.
class _RoomTypeRow extends StatelessWidget {
  const _RoomTypeRow({
    required this.listing,
    required this.highlighted,
    required this.onTap,
  });

  final Listing listing;
  final bool highlighted;
  final VoidCallback onTap;

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    final rates = listing.headlinePlans
        .map((p) => '${listing.moneyFor(p)!.format()}/${p.shortUnit}')
        .join(' · ');
    final sleeps = [
      'Up to ${listing.maxGuests} guest${listing.maxGuests == 1 ? '' : 's'}',
      if (listing.beds > 0)
        '${listing.beds} bed${listing.beds == 1 ? '' : 's'}',
    ].join(' · ');
    final photo = listing.imageUrls.isEmpty ? null : listing.imageUrls.first;

    return Semantics(
      button: true,
      label: 'Room type ${listing.title}',
      child: Material(
        color: theme.colorScheme.surface,
        shape: RoundedRectangleBorder(
          borderRadius: BorderRadius.circular(14),
          side: BorderSide(
            color: highlighted
                ? theme.colorScheme.primary
                : theme.colorScheme.outlineVariant,
            width: highlighted ? 2 : 1,
          ),
        ),
        clipBehavior: Clip.antiAlias,
        child: InkWell(
          onTap: onTap,
          child: Padding(
            padding: const EdgeInsets.all(12),
            child: Row(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                SizedBox(
                  width: 112,
                  height: 84,
                  child: photo == null
                      ? DecoratedBox(
                          decoration: BoxDecoration(
                            color: theme.colorScheme.surfaceContainerHighest,
                            borderRadius: BorderRadius.circular(10),
                          ),
                          child: const Icon(Icons.bed_outlined),
                        )
                      : AppNetworkImage(
                          url: photo,
                          borderRadius: BorderRadius.circular(10),
                          decodeWidth: 240,
                        ),
                ),
                const SizedBox(width: 12),
                Expanded(
                  child: Column(
                    crossAxisAlignment: CrossAxisAlignment.start,
                    children: [
                      Text(
                        listing.title,
                        style: theme.textTheme.titleMedium
                            ?.copyWith(fontWeight: FontWeight.w600),
                        maxLines: 2,
                        overflow: TextOverflow.ellipsis,
                      ),
                      const SizedBox(height: 4),
                      Text(
                        sleeps,
                        style: theme.textTheme.bodyMedium?.copyWith(
                            color: theme.colorScheme.onSurfaceVariant),
                      ),
                      if (rates.isNotEmpty) ...[
                        const SizedBox(height: 6),
                        Text(
                          rates,
                          style: theme.textTheme.bodyMedium?.copyWith(
                            fontWeight: FontWeight.w700,
                            color: AppColors.ink,
                          ),
                        ),
                      ],
                    ],
                  ),
                ),
                const Icon(Icons.chevron_right),
              ],
            ),
          ),
        ),
      ),
    );
  }
}

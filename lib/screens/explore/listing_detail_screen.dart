import 'dart:ui' show ImageFilter;

import 'package:flutter/foundation.dart' show kIsWeb;
import 'package:flutter/material.dart';
import 'package:google_maps_flutter/google_maps_flutter.dart';
import '../../core/utils/distance_format.dart';
import '../../core/utils/external_launcher.dart';

import '../../core/currency/money.dart';
import '../../core/privacy/listing_location.dart';
import '../../core/theme/app_colors.dart';
import '../../core/utils/responsive.dart';
import '../../widgets/app_network_image.dart';
import '../../models/booking.dart';
import '../../models/booking_conflict_exception.dart';
import '../../models/booking_rejected_exception.dart';
import '../../models/host_verifications.dart';
import '../../models/listing.dart';
import '../../models/listing_exact_address.dart';
import '../../models/listing_purpose.dart';
import '../../models/listing_type.dart';
import '../../models/rental_plan.dart';
import '../../models/review.dart';
import '../../repositories/musafir_repository.dart';
import '../../services/discount/coupon_service.dart';
import '../../services/verification/identity_gate.dart';
import '../../state/auth_state.dart';
import '../../state/favorites_state.dart';
import '../../state/messaging_state.dart';
import '../../state/shell_nav_state.dart';
import '../messaging/chat_screen.dart';
import 'listing_gallery_screen.dart';
import '../../widgets/host_verification_badges.dart';
import '../../widgets/map_focus_button.dart';
import '../../widgets/modern_banner.dart';
import '../../widgets/price_breakdown_card.dart';
import '../../widgets/price_display.dart';
import '../../widgets/report_sheet.dart';
import '../../widgets/web_deferred_mount.dart';
import '../../widgets/success_sheet.dart';
import 'navigation_screen.dart';

class ListingDetailScreen extends StatefulWidget {
  const ListingDetailScreen({
    super.key,
    required this.listing,
    required this.repository,
    required this.authState,
    required this.favoritesState,
    this.messagingState,
  });

  final Listing listing;
  final MusafirRepository repository;
  final AuthStateNotifier authState;
  final FavoritesStateNotifier favoritesState;

  /// Enables the pre-booking "Message host" action when provided.
  final MessagingStateNotifier? messagingState;

  @override
  State<ListingDetailScreen> createState() => _ListingDetailScreenState();
}

class _ListingDetailScreenState extends State<ListingDetailScreen> {
  final PageController _imageController = PageController();
  int _currentImageIndex = 0;

  bool get _isOwnListing {
    final currentUserId = widget.authState.currentUser?.id;
    return currentUserId != null && widget.listing.hostId == currentUserId;
  }

  /// The exact street address, once the server has agreed to disclose it. Null
  /// while the request is in flight and null forever for a viewer who isn't
  /// entitled — the two are indistinguishable on purpose, and both mean "show
  /// the area".
  ListingExactAddress? _exactAddress;
  bool _loadingExactAddress = false;

  /// The host's verified credentials, once fetched. Null until then, which the
  /// badge strip reads as "claim nothing yet".
  HostVerifications? _hostVerifications;

  /// True while the conversation is being created. Drives the button's spinner
  /// and blocks a duplicate tap.
  bool _openingChat = false;

  /// Asks the server which of the host's credentials are verified. Fails
  /// closed: anything other than a clear yes leaves the badge unshown.
  Future<void> _loadHostVerifications() async {
    final hostId = widget.listing.hostId;
    if (hostId == null || hostId.isEmpty) return;
    final verifications =
        await widget.repository.fetchHostVerifications(hostId);
    if (!mounted) return;
    setState(() => _hostVerifications = verifications);
  }

  /// How much of this listing's location the viewer gets. Decided entirely by
  /// what came back from `listing_addresses`, whose RLS is the actual gate.
  ListingLocation get _viewerLocation =>
      ListingLocation.forListing(widget.listing, _exactAddress);

  /// Asks the server for the exact address. A no is silent and final for this
  /// attempt; [_onRepositoryChanged] retries when something (a host accepting
  /// this booking, say) suggests the answer may have changed.
  Future<void> _loadExactAddress() async {
    if (_loadingExactAddress || _exactAddress != null) return;
    _loadingExactAddress = true;
    final exact =
        await widget.repository.fetchListingExactAddress(widget.listing.id);
    if (!mounted) return;
    _loadingExactAddress = false;
    if (exact == null) return;
    setState(() => _exactAddress = exact);
  }

  /// The host may accept while the guest is sitting on this screen. The
  /// repository notifies when bookings change, so re-ask then — but only while
  /// we still have no address, so this can't turn into a request loop.
  void _onRepositoryChanged() {
    if (_exactAddress == null) _loadExactAddress();
  }

  /// Pre-booking inquiry is offered when messaging is available, the host is
  /// known, and the viewer isn't the host themselves.
  bool get _canContactHost {
    final hostId = widget.listing.hostId;
    return widget.messagingState != null &&
        hostId != null &&
        hostId.isNotEmpty &&
        !_isOwnListing;
  }

  /// Opens (or creates) the general conversation with the host — no booking
  /// required, like Airbnb's pre-booking inquiry.
  ///
  /// Waits on ONE round trip (the conversation has to exist server-side before
  /// there is anything to open) and then navigates. It used to wait on four:
  /// the create, then the conversation row, the host's profile and the unread
  /// count — none of which this screen uses, because it passes ChatScreen the
  /// host's name and avatar itself and ChatScreen loads its own messages. On a
  /// remote database that was three extra seconds of a screen that had not
  /// visibly changed.
  Future<void> _contactHost() async {
    final messagingState = widget.messagingState;
    final hostId = widget.listing.hostId;
    if (messagingState == null || hostId == null || hostId.isEmpty) return;

    if (!widget.authState.isLoggedIn) {
      ModernBanner.showInfo(context, 'Please log in to message the host.');
      return;
    }
    // Guard against a second tap while the first is in flight: without it, an
    // impatient guest gets two conversations opened on top of each other.
    if (_openingChat) return;
    setState(() => _openingChat = true);

    final conversationId = await messagingState.startConversationId(
      otherUserId: hostId,
      listingId: widget.listing.id,
    );

    if (!mounted) return;
    setState(() => _openingChat = false);

    if (conversationId == null) {
      ModernBanner.showError(
        context,
        'Could not start the conversation. Please try again.',
      );
      return;
    }

    Navigator.push(
      context,
      MaterialPageRoute(
        builder: (context) => ChatScreen(
          conversationId: conversationId,
          messagingState: messagingState,
          // The listing already knows who the host is, so the chat header is
          // correct on the first frame with nothing left to fetch for it.
          otherParticipantName: widget.listing.ownerName,
          otherParticipantAvatarUrl: widget.listing.hostAvatarUrl,
          repository: widget.repository,
          otherParticipantId: hostId,
        ),
      ),
    );
  }

  @override
  void initState() {
    super.initState();
    _loadExactAddress();
    _loadHostVerifications();
    widget.repository.addListener(_onRepositoryChanged);
  }

  @override
  void dispose() {
    widget.repository.removeListener(_onRepositoryChanged);
    _imageController.dispose();
    super.dispose();
  }

  Future<void> _openBookingSheet() async {
    // Block booking when the host has marked themselves unavailable.
    final hostId = widget.listing.hostId;
    if (hostId != null) {
      final available = await widget.repository.isHostAvailable(hostId);
      if (!available) {
        if (!mounted) return;
        ModernBanner.showWarning(
          context,
          "This host isn't accepting bookings right now.",
        );
        return;
      }
    }

    // Identity gate before booking: the guest must have an admin-approved
    // identity (ID document + selfie, verified by an admin) to proceed.
    final userId = widget.authState.currentUser?.id;
    if (userId != null) {
      if (!mounted) return;
      final verified = await IdentityGate.ensure(
        context,
        userId,
        reason: 'to confirm your booking',
      );
      if (!verified) return;
    }

    if (!mounted) return;
    showModalBottomSheet(
      context: context,
      isScrollControlled: true,
      backgroundColor: Colors.transparent,
      builder: (context) => _BookingSheet(
        listing: widget.listing,
        repository: widget.repository,
        authState: widget.authState,
      ),
    );
  }

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    final listing = widget.listing;
    final reviews = widget.repository.getReviewsForListing(listing.id);
    final topPad = MediaQuery.of(context).padding.top;

    return Scaffold(
      backgroundColor: theme.colorScheme.surface,
      body: ResponsiveCenter(
        maxWidth: 960,
        child: Stack(
          children: [
            // Scrollable content
            CustomScrollView(
              slivers: [
                // Immersive image header (scrolls away beneath the content sheet)
                SliverAppBar(
                  expandedHeight: 300,
                  pinned: false,
                  stretch: true,
                  automaticallyImplyLeading: false,
                  backgroundColor: theme.colorScheme.surface,
                  flexibleSpace: FlexibleSpaceBar(
                    stretchModes: const [StretchMode.zoomBackground],
                    background: _buildImageHeader(theme, listing),
                  ),
                ),

                // Content sheet — overlaps the image with a rounded top for depth
                SliverToBoxAdapter(
                  child: Transform.translate(
                    offset: const Offset(0, -28),
                    child: Container(
                      decoration: BoxDecoration(
                        color: theme.colorScheme.surface,
                        borderRadius: const BorderRadius.vertical(
                          top: Radius.circular(28),
                        ),
                      ),
                      padding: const EdgeInsets.fromLTRB(20, 14, 20, 0),
                      child: Column(
                        crossAxisAlignment: CrossAxisAlignment.start,
                        children: [
                          // Drag handle accent
                          Center(
                            child: Container(
                              width: 44,
                              height: 5,
                              decoration: BoxDecoration(
                                color: theme.colorScheme.outlineVariant,
                                borderRadius: BorderRadius.circular(3),
                              ),
                            ),
                          ),
                          const SizedBox(height: 20),

                          // Title — brand-gradient coloured, compact
                          ShaderMask(
                            shaderCallback: (bounds) =>
                                AppColors.brandGradient.createShader(bounds),
                            child: Text(
                              listing.title,
                              style: theme.textTheme.titleMedium?.copyWith(
                                fontWeight: FontWeight.w900,
                                height: 1.2,
                                color: Colors.white,
                              ),
                            ),
                          ),
                          const SizedBox(height: 10),

                          // Location & rating
                          Row(
                            children: [
                              Icon(
                                Icons.location_on_outlined,
                                size: 18,
                                color: theme.colorScheme.onSurfaceVariant,
                              ),
                              const SizedBox(width: 4),
                              Expanded(
                                child: Text(
                                  '${listing.city ?? listing.approximateAddress}, ${listing.country ?? 'Bangladesh'}',
                                  style: theme.textTheme.bodyMedium?.copyWith(
                                    color: theme.colorScheme.onSurfaceVariant,
                                  ),
                                ),
                              ),
                              if (listing.rating != null)
                                _RatingPill(listing: listing),
                            ],
                          ),
                          const SizedBox(height: 16),

                          // Host info
                          _HostInfoCard(
                            listing: listing,
                            verifications: _hostVerifications,
                            onContactHost:
                                _canContactHost ? _contactHost : null,
                            openingChat: _openingChat,
                          ),
                          const SizedBox(height: 16),

                          // Property details
                          _PropertyDetails(listing: listing),
                          const SizedBox(height: 20),

                          // Good for (purpose tags) + distance from a searched
                          // landmark, when relevant.
                          if (listing.purposeTags
                                  .any((p) => p != ListingPurpose.general) ||
                              listing.distanceMeters != null) ...[
                            const _SectionTitle('Good for'),
                            const SizedBox(height: 8),
                            Wrap(
                              spacing: 8,
                              runSpacing: 8,
                              children: [
                                for (final p in listing.purposeTags
                                    .where((p) => p != ListingPurpose.general))
                                  Chip(
                                    avatar: Icon(p.icon, size: 16),
                                    label: Text(p.label),
                                    visualDensity: VisualDensity.compact,
                                  ),
                              ],
                            ),
                            if (listing.distanceMeters != null) ...[
                              const SizedBox(height: 8),
                              Row(
                                children: [
                                  Icon(Icons.near_me_rounded,
                                      size: 16,
                                      color: theme.colorScheme.primary),
                                  const SizedBox(width: 4),
                                  Text(
                                    '${formatDistanceMeters(listing.distanceMeters!)} from your search',
                                    style: theme.textTheme.bodySmall?.copyWith(
                                      color: theme.colorScheme.primary,
                                      fontWeight: FontWeight.w600,
                                    ),
                                  ),
                                ],
                              ),
                            ],
                            const SizedBox(height: 20),
                          ],

                          // Description
                          if (listing.description != null) ...[
                            const _SectionTitle('About this place'),
                            const SizedBox(height: 8),
                            Text(
                              listing.description!,
                              style: theme.textTheme.bodyMedium?.copyWith(
                                color: theme.colorScheme.onSurfaceVariant,
                                height: 1.5,
                              ),
                            ),
                            const SizedBox(height: 20),
                          ],

                          // Location & Navigation
                          // _onRepositoryChanged re-asks the server for the
                          // address when bookings change, so the exact location
                          // appears as soon as the host's acceptance arrives
                          // without the guest reopening the screen. No
                          // ListenableBuilder needed — that setState rebuilds
                          // this.
                          _LocationSection(
                            listing: listing,
                            location: _viewerLocation,
                          ),
                          const SizedBox(height: 20),

                          // Amenities — hide the whole section when there are none
                          if (listing.facilities.isNotEmpty) ...[
                            _AmenitiesGrid(listing: listing),
                            const SizedBox(height: 20),
                          ],

                          // House rules
                          if (listing.houseRules.hasAny) ...[
                            _HouseRulesSection(rules: listing.houseRules),
                            const SizedBox(height: 20),
                          ],

                          // Reviews
                          if (reviews.isNotEmpty)
                            _ReviewsSection(reviews: reviews),

                          // Report entry — hidden on the host's own listing.
                          if (!_isOwnListing)
                            Center(
                              child: TextButton.icon(
                                onPressed: () => showReportSheet(
                                  context,
                                  repository: widget.repository,
                                  listingId: listing.id,
                                  reportedUserId: listing.hostId,
                                  subjectLabel: listing.title,
                                  offerBlock: true,
                                ),
                                icon: const Icon(Icons.flag_outlined, size: 18),
                                label: const Text('Report this listing'),
                                style: TextButton.styleFrom(
                                  foregroundColor:
                                      theme.colorScheme.onSurfaceVariant,
                                ),
                              ),
                            ),
                          SizedBox(height: _isOwnListing ? 24 : 120),
                        ],
                      ),
                    ),
                  ),
                ),
              ],
            ),

            // Fixed frosted-glass controls (stay reachable while scrolling)
            Positioned(
              top: topPad + 10,
              left: 16,
              child: _CircleGlassButton(
                icon: Icons.arrow_back,
                onTap: () => Navigator.pop(context),
              ),
            ),
            Positioned(
              top: topPad + 10,
              right: 16,
              child: ListenableBuilder(
                listenable: widget.favoritesState,
                builder: (context, _) {
                  final isFavorite =
                      widget.favoritesState.isFavorite(listing.id);
                  return _CircleGlassButton(
                    icon: isFavorite ? Icons.favorite : Icons.favorite_border,
                    iconColor: isFavorite ? AppColors.coral : null,
                    onTap: () =>
                        widget.favoritesState.toggleFavorite(listing.id),
                  );
                },
              ),
            ),

            // Bottom booking bar (hidden for own listings)
            if (!_isOwnListing)
              Positioned(
                left: 0,
                right: 0,
                bottom: 0,
                child: _buildBottomBar(theme, listing),
              ),
          ],
        ),
      ),
    );
  }

  void _openGallery(Listing listing) {
    if (listing.imageUrls.isEmpty) return;
    Navigator.push(
      context,
      MaterialPageRoute(
        builder: (_) => ListingGalleryScreen(
          images: listing.imageUrls,
          title: listing.title,
        ),
      ),
    );
  }

  Widget _buildImageHeader(ThemeData theme, Listing listing) {
    return Stack(
      fit: StackFit.expand,
      children: [
        listing.imageUrls.isNotEmpty
            ? PageView.builder(
                controller: _imageController,
                onPageChanged: (index) {
                  setState(() => _currentImageIndex = index);
                },
                itemCount: listing.imageUrls.length,
                itemBuilder: (context, index) {
                  return GestureDetector(
                    onTap: () => _openGallery(listing),
                    child: AppNetworkImage(
                      url: listing.imageUrls[index],
                      fit: BoxFit.cover,
                      errorWidget: _buildImagePlaceholder(theme),
                    ),
                  );
                },
              )
            : _buildImagePlaceholder(theme),

        // Gradient scrim — darkens top (for buttons) and bottom (for overlap)
        IgnorePointer(
          child: DecoratedBox(
            decoration: BoxDecoration(
              gradient: LinearGradient(
                begin: Alignment.topCenter,
                end: Alignment.bottomCenter,
                stops: const [0.0, 0.22, 0.6, 1.0],
                colors: [
                  Colors.black.withValues(alpha: 0.28),
                  Colors.transparent,
                  Colors.transparent,
                  Colors.black.withValues(alpha: 0.32),
                ],
              ),
            ),
          ),
        ),

        // Category badge
        Positioned(
          left: 20,
          bottom: 46,
          child: _CategoryBadge(type: listing.type),
        ),

        // "N photos" chip → full gallery (Airbnb-style)
        if (listing.imageUrls.isNotEmpty)
          Positioned(
            right: 16,
            bottom: 46,
            child: GestureDetector(
              onTap: () => _openGallery(listing),
              child: Container(
                padding:
                    const EdgeInsets.symmetric(horizontal: 10, vertical: 6),
                decoration: BoxDecoration(
                  color: Colors.black.withValues(alpha: 0.55),
                  borderRadius: BorderRadius.circular(20),
                ),
                child: Row(
                  mainAxisSize: MainAxisSize.min,
                  children: [
                    const Icon(Icons.grid_view_rounded,
                        size: 12, color: Colors.white),
                    const SizedBox(width: 5),
                    Text(
                      '${listing.imageUrls.length} photos',
                      style: const TextStyle(
                        color: Colors.white,
                        fontSize: 11,
                        fontWeight: FontWeight.w600,
                      ),
                    ),
                  ],
                ),
              ),
            ),
          ),

        // Animated page indicators
        if (listing.imageUrls.length > 1)
          Positioned(
            bottom: 48,
            left: 0,
            right: 0,
            child: Row(
              mainAxisAlignment: MainAxisAlignment.center,
              children: List.generate(listing.imageUrls.length, (index) {
                final active = index == _currentImageIndex;
                return AnimatedContainer(
                  duration: const Duration(milliseconds: 250),
                  curve: Curves.easeOut,
                  width: active ? 22 : 8,
                  height: 8,
                  margin: const EdgeInsets.symmetric(horizontal: 3),
                  decoration: BoxDecoration(
                    borderRadius: BorderRadius.circular(4),
                    color: active
                        ? Colors.white
                        : Colors.white.withValues(alpha: 0.5),
                  ),
                );
              }),
            ),
          ),
      ],
    );
  }

  Widget _buildBottomBar(ThemeData theme, Listing listing) {
    return Container(
      padding: EdgeInsets.fromLTRB(
        20,
        14,
        20,
        14 + MediaQuery.of(context).padding.bottom,
      ),
      decoration: BoxDecoration(
        color: theme.colorScheme.surface,
        borderRadius: const BorderRadius.vertical(top: Radius.circular(24)),
        boxShadow: [
          BoxShadow(
            color: Colors.black.withValues(alpha: 0.08),
            blurRadius: 24,
            offset: const Offset(0, -6),
          ),
        ],
      ),
      child: Row(
        children: [
          Expanded(
            child: Column(
              mainAxisSize: MainAxisSize.min,
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Text(
                  'From',
                  style: theme.textTheme.bodySmall?.copyWith(
                    color: theme.colorScheme.onSurfaceVariant,
                  ),
                ),
                const SizedBox(height: 2),
                PriceDisplay(
                  amount: listing.displayPriceMoney,
                  perUnit: listing.cheapestPlan?.displayUnit ?? 'night',
                  style: PriceDisplayStyle.normal,
                ),
              ],
            ),
          ),
          const SizedBox(width: 16),
          _GradientButton(
            label: 'Reserve',
            icon: Icons.arrow_forward_rounded,
            onTap: _openBookingSheet,
          ),
        ],
      ),
    );
  }

  Widget _buildImagePlaceholder(ThemeData theme) {
    return Container(
      color: theme.colorScheme.surfaceContainerHighest,
      child: Center(
        child: Icon(
          Icons.home_outlined,
          size: 64,
          color: theme.colorScheme.onSurfaceVariant,
        ),
      ),
    );
  }
}

/// Frosted-glass circular control used over the image header.
class _CircleGlassButton extends StatelessWidget {
  const _CircleGlassButton({
    required this.icon,
    required this.onTap,
    this.iconColor,
  });

  final IconData icon;
  final VoidCallback onTap;
  final Color? iconColor;

  @override
  Widget build(BuildContext context) {
    return Container(
      decoration: BoxDecoration(
        shape: BoxShape.circle,
        boxShadow: [
          BoxShadow(
            color: Colors.black.withValues(alpha: 0.12),
            blurRadius: 12,
            offset: const Offset(0, 4),
          ),
        ],
      ),
      child: ClipOval(
        child: BackdropFilter(
          filter: ImageFilter.blur(sigmaX: 8, sigmaY: 8),
          child: Material(
            color: Colors.white.withValues(alpha: 0.82),
            shape: const CircleBorder(),
            child: InkWell(
              onTap: onTap,
              customBorder: const CircleBorder(),
              child: SizedBox(
                width: 42,
                height: 42,
                child: Icon(icon, size: 20, color: iconColor ?? AppColors.ink),
              ),
            ),
          ),
        ),
      ),
    );
  }
}

/// Colored listing-type badge shown over the image.
class _CategoryBadge extends StatelessWidget {
  const _CategoryBadge({required this.type});

  final ListingType type;

  @override
  Widget build(BuildContext context) {
    final color = switch (type) {
      ListingType.seat => AppColors.seat,
      ListingType.room => AppColors.room,
      ListingType.fullHouse => AppColors.fullHouse,
    };
    final icon = switch (type) {
      ListingType.seat => Icons.event_seat_rounded,
      ListingType.room => Icons.meeting_room_rounded,
      ListingType.fullHouse => Icons.house_rounded,
    };
    return Container(
      padding: const EdgeInsets.symmetric(horizontal: 12, vertical: 7),
      decoration: BoxDecoration(
        color: color,
        borderRadius: BorderRadius.circular(30),
        boxShadow: [
          BoxShadow(
            color: color.withValues(alpha: 0.45),
            blurRadius: 12,
            offset: const Offset(0, 4),
          ),
        ],
      ),
      child: Row(
        mainAxisSize: MainAxisSize.min,
        children: [
          Icon(icon, size: 15, color: Colors.white),
          const SizedBox(width: 6),
          Text(
            type.title,
            style: const TextStyle(
              color: Colors.white,
              fontWeight: FontWeight.w700,
              fontSize: 12.5,
              letterSpacing: 0.2,
            ),
          ),
        ],
      ),
    );
  }
}

/// Amber rating pill shown next to the location.
class _RatingPill extends StatelessWidget {
  const _RatingPill({required this.listing});

  final Listing listing;

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    return Container(
      padding: const EdgeInsets.symmetric(horizontal: 10, vertical: 6),
      decoration: BoxDecoration(
        color: AppColors.amber.withValues(alpha: 0.12),
        borderRadius: BorderRadius.circular(30),
      ),
      child: Row(
        mainAxisSize: MainAxisSize.min,
        children: [
          Icon(Icons.star_rounded, size: 16, color: AppColors.amber),
          const SizedBox(width: 4),
          Text(
            listing.rating!.toStringAsFixed(2),
            style: theme.textTheme.labelLarge?.copyWith(
              fontWeight: FontWeight.w700,
            ),
          ),
          if (listing.reviewCount > 0) ...[
            const SizedBox(width: 4),
            Text(
              '(${listing.reviewCount})',
              style: theme.textTheme.bodySmall?.copyWith(
                color: theme.colorScheme.onSurfaceVariant,
              ),
            ),
          ],
        ],
      ),
    );
  }
}

/// Consistent section heading.
class _SectionTitle extends StatelessWidget {
  const _SectionTitle(this.text);

  final String text;

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    return Text(
      text,
      style: theme.textTheme.titleMedium?.copyWith(fontWeight: FontWeight.w700),
    );
  }
}

/// Brand-gradient call-to-action button.
class _GradientButton extends StatelessWidget {
  const _GradientButton({
    required this.label,
    required this.onTap,
    this.icon,
    this.expand = false,
    this.enabled = true,
    this.loading = false,
  });

  final String label;
  final VoidCallback onTap;
  final IconData? icon;
  final bool expand;
  final bool enabled;
  final bool loading;

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    final active = enabled && !loading;

    final decoration = active
        ? BoxDecoration(
            gradient: AppColors.brandGradient,
            borderRadius: BorderRadius.circular(16),
            boxShadow: [
              BoxShadow(
                color: AppColors.brand.withValues(alpha: 0.35),
                blurRadius: 16,
                offset: const Offset(0, 6),
              ),
            ],
          )
        : BoxDecoration(
            color: AppColors.surfaceMuted,
            borderRadius: BorderRadius.circular(16),
          );

    final fg = active ? Colors.white : theme.colorScheme.onSurfaceVariant;

    final Widget content = loading
        ? const SizedBox(
            height: 22,
            width: 22,
            child: CircularProgressIndicator(
              strokeWidth: 2.5,
              color: Colors.white,
            ),
          )
        : Row(
            mainAxisSize: expand ? MainAxisSize.max : MainAxisSize.min,
            mainAxisAlignment: MainAxisAlignment.center,
            children: [
              Text(
                label,
                style: TextStyle(
                  color: fg,
                  fontWeight: FontWeight.w700,
                  fontSize: 15.5,
                ),
              ),
              if (icon != null) ...[
                const SizedBox(width: 8),
                Icon(icon, color: fg, size: 19),
              ],
            ],
          );

    final button = DecoratedBox(
      decoration: decoration,
      child: Material(
        color: Colors.transparent,
        child: InkWell(
          onTap: active ? onTap : null,
          borderRadius: BorderRadius.circular(16),
          child: Padding(
            padding: EdgeInsets.symmetric(
              horizontal: expand ? 20 : 28,
              vertical: 16,
            ),
            child: content,
          ),
        ),
      ),
    );

    return expand ? SizedBox(width: double.infinity, child: button) : button;
  }
}

class _HostInfoCard extends StatelessWidget {
  const _HostInfoCard({
    required this.listing,
    required this.verifications,
    this.onContactHost,
    this.openingChat = false,
  });

  final Listing listing;

  /// The host's real verification flags, or null while the lookup is in flight.
  final HostVerifications? verifications;

  /// When provided, shows the pre-booking "Message host" action.
  final VoidCallback? onContactHost;

  /// Whether the conversation is being created right now. Creating it needs a
  /// network round trip, and a button that looks idle through it reads as a
  /// button that did not register the tap.
  final bool openingChat;

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);

    return Container(
      padding: const EdgeInsets.all(12),
      decoration: BoxDecoration(
        color: AppColors.surfaceMuted,
        borderRadius: BorderRadius.circular(16),
      ),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          _buildHostRow(theme),
          // An unverified host shows no strip at all, so no empty gap either.
          if (verifications?.hasAny ?? false) ...[
            const SizedBox(height: 12),
            HostVerificationBadges(verifications: verifications),
          ],
          if (onContactHost != null) ...[
            const SizedBox(height: 14),
            SizedBox(
              width: double.infinity,
              child: FilledButton.icon(
                onPressed: openingChat ? null : onContactHost,
                icon: openingChat
                    ? const SizedBox(
                        width: 20,
                        height: 20,
                        child: CircularProgressIndicator(
                          strokeWidth: 2,
                          color: Colors.white,
                        ),
                      )
                    : const Icon(Icons.chat_bubble_outline, size: 20),
                label: Text(openingChat ? 'Opening…' : 'Message host'),
                style: FilledButton.styleFrom(
                  backgroundColor: AppColors.brand,
                  foregroundColor: Colors.white,
                  minimumSize: const Size.fromHeight(48),
                  textStyle: theme.textTheme.titleSmall?.copyWith(
                    fontWeight: FontWeight.w700,
                  ),
                ),
              ),
            ),
          ],
        ],
      ),
    );
  }

  Widget _buildHostRow(ThemeData theme) {
    return Row(
      children: [
        Container(
          padding: const EdgeInsets.all(1.5),
          decoration: BoxDecoration(
            shape: BoxShape.circle,
            gradient: AppColors.brandGradient,
          ),
          child: CircleAvatar(
            radius: 17,
            backgroundColor: theme.colorScheme.surface,
            backgroundImage: listing.hostAvatarUrl != null
                ? NetworkImage(listing.hostAvatarUrl!)
                : null,
            child: listing.hostAvatarUrl == null
                ? Text(
                    listing.ownerName.isNotEmpty
                        ? listing.ownerName[0].toUpperCase()
                        : 'H',
                    style: theme.textTheme.titleSmall,
                  )
                : null,
          ),
        ),
        const SizedBox(width: 10),
        Expanded(
          child: Column(
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              Text(
                'Hosted by ${listing.ownerName}',
                style: theme.textTheme.bodyMedium?.copyWith(
                  fontWeight: FontWeight.w700,
                ),
                maxLines: 1,
                overflow: TextOverflow.ellipsis,
              ),
              const SizedBox(height: 1),
              if (listing.isSuperhost)
                Row(
                  children: [
                    Icon(
                      Icons.workspace_premium,
                      size: 13,
                      color: AppColors.amber,
                    ),
                    const SizedBox(width: 4),
                    Text(
                      'Superhost',
                      style: theme.textTheme.labelSmall?.copyWith(
                        color: AppColors.amber,
                        fontWeight: FontWeight.w600,
                      ),
                    ),
                  ],
                )
              else
                Text(
                  'Your host',
                  style: theme.textTheme.labelSmall?.copyWith(
                    color: theme.colorScheme.onSurfaceVariant,
                  ),
                ),
            ],
          ),
        ),
      ],
    );
  }
}

class _LocationSection extends StatefulWidget {
  const _LocationSection({required this.listing, required this.location});

  final Listing listing;

  /// How much of the location this viewer may see. Governs the address line,
  /// the map (pin vs area circle), and whether directions are offered at all.
  final ListingLocation location;

  @override
  State<_LocationSection> createState() => _LocationSectionState();
}

class _LocationSectionState extends State<_LocationSection> {
  GoogleMapController? _mapController;
  bool _mapCreated = false;

  /// The point the map is about: the stay's front door for a viewer entitled to
  /// it, otherwise the coarsened centre of the area circle.
  LatLng get _location =>
      LatLng(widget.location.latitude, widget.location.longitude);

  /// A pin only once the address is disclosed. A pin on the exact roof would
  /// hand over what the redacted address line just withheld.
  Set<Marker> get _markers => widget.location.isExact
      ? {
          Marker(
            markerId: MarkerId(widget.listing.id),
            position: _location,
            infoWindow: InfoWindow(
              title: widget.listing.title,
              snippet: widget.location.label,
            ),
          ),
        }
      : const {};

  /// The "somewhere in here" circle shown in place of a pin. Airbnb's approach:
  /// a guest can read the neighbourhood off it without learning which building.
  Set<Circle> get _circles {
    final radius = widget.location.radiusMeters;
    if (radius == null) return const {};
    return {
      Circle(
        circleId: CircleId('${widget.listing.id}-area'),
        center: _location,
        radius: radius,
        fillColor: AppColors.brand.withValues(alpha: 0.16),
        strokeColor: AppColors.brand.withValues(alpha: 0.55),
        strokeWidth: 2,
      ),
    };
  }

  void _openDirections() {
    Navigator.of(context).push(
      MaterialPageRoute(
        builder: (context) => NavigationScreen(
          listing: widget.listing,
          location: widget.location,
        ),
      ),
    );
  }

  /// Puts the stay back in the middle of this small map. On a 150dp map a couple
  /// of pinches is enough to lose it off-screen entirely, with no way back short
  /// of leaving the screen and returning.
  ///
  /// Zooms out a step for the area circle, which needs more room than a pin.
  Future<void> _recenterOnStay() => focusCamera(
        context,
        _mapController,
        CameraUpdate.newLatLngZoom(
            _location, widget.location.isExact ? 15 : 13),
      );

  Future<void> _openInMaps() async {
    // The redacted centre, not the listing's real coordinates — an external
    // Maps link is as much of a disclosure as the inline map.
    final lat = widget.location.latitude;
    final lng = widget.location.longitude;

    final googleMapsUrl =
        'https://www.google.com/maps/search/?api=1&query=$lat,$lng';

    try {
      final launched = await openExternalUrl(googleMapsUrl);
      if (!launched && mounted) {
        ModernBanner.showError(context, 'Could not open maps');
      }
    } catch (e) {
      if (mounted) {
        ModernBanner.showError(context, 'Could not open maps');
      }
    }
  }

  @override
  void dispose() {
    // Only dispose controller if map was fully created (fixes web bug)
    if (_mapCreated && _mapController != null) {
      _mapController!.dispose();
    }
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    final exact = widget.location.isExact;

    final actions = <Widget>[
      // The inline map above is already interactive on web, so "View on Map"
      // (which hands off to the native Maps app) is mobile-only. It opens the
      // redacted centre, so it stays available before acceptance.
      if (!kIsWeb)
        Expanded(
          child: OutlinedButton.icon(
            onPressed: _openInMaps,
            icon: const Icon(Icons.map_outlined),
            label: Text(exact ? 'View on Map' : 'View the area'),
          ),
        ),
      // Directions route to the front door, so they wait on the host's
      // acceptance along with the address itself.
      if (exact)
        Expanded(
          child: FilledButton.icon(
            onPressed: _openDirections,
            icon: const Icon(Icons.directions),
            label: const Text('Get Directions'),
          ),
        ),
    ];

    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        const _SectionTitle('Location'),
        const SizedBox(height: 8),

        // Address — the area only until the host accepts the booking.
        Row(
          children: [
            Icon(
              widget.location.isExact
                  ? Icons.location_on
                  : Icons.location_searching_rounded,
              size: 17,
              color: theme.colorScheme.primary,
            ),
            const SizedBox(width: 6),
            Expanded(
              child: Text(
                widget.location.label,
                style: theme.textTheme.bodySmall?.copyWith(
                  color: theme.colorScheme.onSurfaceVariant,
                ),
              ),
            ),
          ],
        ),
        const SizedBox(height: 10),

        // Google Map
        Container(
          height: 150,
          decoration: BoxDecoration(
            borderRadius: BorderRadius.circular(12),
            border: Border.all(color: theme.colorScheme.outlineVariant),
          ),
          clipBehavior: Clip.antiAlias,
          child: Stack(
            children: [
              // WebDeferredMount defers the map by one frame on web so the
              // google_maps_flutter_web "disposed before buildView" assertion
              // can't fire on fast navigation. That makes the SAME inline
              // interactive map safe to render on web and mobile alike (no
              // placeholder/new-tab).
              Positioned.fill(
                child: WebDeferredMount(
                  builder: (context) => GoogleMap(
                    initialCameraPosition: CameraPosition(
                      target: _location,
                      // The area circle needs more room in frame than a pin.
                      zoom: widget.location.isExact ? 15 : 13,
                    ),
                    markers: _markers,
                    circles: _circles,
                    onMapCreated: (controller) {
                      _mapController = controller;
                      _mapCreated = true;
                    },
                    zoomControlsEnabled: false,
                    mapToolbarEnabled: false,
                    myLocationButtonEnabled: false,
                    scrollGesturesEnabled: true,
                    zoomGesturesEnabled: true,
                    rotateGesturesEnabled: false,
                    tiltGesturesEnabled: false,
                  ),
                ),
              ),
              Positioned(
                right: 8,
                bottom: 8,
                child: MapFocusControls(
                  children: [
                    MapFocusButton(
                      icon: Icons.center_focus_strong_rounded,
                      label: widget.location.isExact
                          ? 'Center the map on this stay'
                          : 'Center the map on the area',
                      emphasized: true,
                      onPressed: _recenterOnStay,
                    ),
                  ],
                ),
              ),
            ],
          ),
        ),

        // Why the map is a circle and what makes it a pin. Without this the
        // vague location reads as missing data rather than a deliberate
        // protection the guest will get past by booking.
        if (widget.location.disclosure case final note?) ...[
          const SizedBox(height: 10),
          Container(
            padding: const EdgeInsets.all(10),
            decoration: BoxDecoration(
              color: AppColors.surfaceMuted,
              borderRadius: BorderRadius.circular(10),
            ),
            child: Row(
              children: [
                Icon(
                  Icons.lock_outline_rounded,
                  size: 16,
                  color: theme.colorScheme.onSurfaceVariant,
                ),
                const SizedBox(width: 8),
                Expanded(
                  child: Text(
                    note,
                    style: theme.textTheme.bodySmall?.copyWith(
                      color: theme.colorScheme.onSurfaceVariant,
                    ),
                  ),
                ),
              ],
            ),
          ),
        ],
        if (actions.isNotEmpty) ...[
          const SizedBox(height: 12),
          Row(
            children: [
              for (var i = 0; i < actions.length; i++) ...[
                if (i > 0) const SizedBox(width: 12),
                actions[i],
              ],
            ],
          ),
        ],
      ],
    );
  }
}

class _PropertyDetails extends StatelessWidget {
  const _PropertyDetails({required this.listing});

  final Listing listing;

  @override
  Widget build(BuildContext context) {
    final items = <(IconData, String, String, Color)>[
      (
        Icons.people_alt_rounded,
        '${listing.maxGuests}',
        'Guests',
        AppColors.blue
      ),
      (
        Icons.meeting_room_rounded,
        '${listing.bedrooms}',
        'Bedrooms',
        AppColors.violet
      ),
      (Icons.king_bed_rounded, '${listing.beds}', 'Beds', AppColors.brand),
      (Icons.bathtub_rounded, '${listing.bathrooms}', 'Baths', AppColors.amber),
    ];

    return Row(
      children: [
        for (var i = 0; i < items.length; i++) ...[
          if (i > 0) const SizedBox(width: 12),
          Expanded(
            child: _StatCard(
              icon: items[i].$1,
              value: items[i].$2,
              label: items[i].$3,
              color: items[i].$4,
            ),
          ),
        ],
      ],
    );
  }
}

class _StatCard extends StatelessWidget {
  const _StatCard({
    required this.icon,
    required this.value,
    required this.label,
    required this.color,
  });

  final IconData icon;
  final String value;
  final String label;
  final Color color;

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    return Container(
      padding: const EdgeInsets.symmetric(vertical: 8, horizontal: 4),
      decoration: BoxDecoration(
        color: AppColors.surfaceMuted,
        borderRadius: BorderRadius.circular(12),
      ),
      child: FittedBox(
        fit: BoxFit.scaleDown,
        child: Row(
          mainAxisSize: MainAxisSize.min,
          children: [
            Icon(icon, size: 15, color: color),
            const SizedBox(width: 5),
            Text(
              value,
              style: theme.textTheme.bodySmall?.copyWith(
                fontWeight: FontWeight.w800,
              ),
            ),
            const SizedBox(width: 3),
            Text(
              label,
              style: theme.textTheme.labelSmall?.copyWith(
                color: theme.colorScheme.onSurfaceVariant,
              ),
            ),
          ],
        ),
      ),
    );
  }
}

class _AmenitiesGrid extends StatelessWidget {
  const _AmenitiesGrid({required this.listing});

  final Listing listing;

  @override
  Widget build(BuildContext context) {
    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        const _SectionTitle('What this place offers'),
        const SizedBox(height: 16),
        Wrap(
          spacing: 10,
          runSpacing: 10,
          children: [
            for (final facility in listing.facilities)
              _AmenityChip(icon: facility.icon, label: facility.name),
          ],
        ),
      ],
    );
  }
}

class _HouseRulesSection extends StatelessWidget {
  const _HouseRulesSection({required this.rules});

  final HouseRules rules;

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);

    Widget row(IconData icon, String text) => Padding(
          padding: const EdgeInsets.only(bottom: 12),
          child: Row(
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              Icon(icon, size: 20, color: AppColors.brand),
              const SizedBox(width: 12),
              Expanded(
                child: Text(text, style: theme.textTheme.bodyMedium),
              ),
            ],
          ),
        );

    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        const _SectionTitle('House rules'),
        const SizedBox(height: 16),
        if (rules.checkInTime != null)
          row(Icons.login, 'Check-in: ${rules.checkInTime}'),
        if (rules.checkOutTime != null)
          row(Icons.logout, 'Check-out: ${rules.checkOutTime}'),
        if (rules.quietHours != null && rules.quietHours!.isNotEmpty)
          row(Icons.bedtime_outlined, 'Quiet hours: ${rules.quietHours}'),
        row(
          rules.smokingAllowed ? Icons.smoking_rooms : Icons.smoke_free,
          rules.smokingAllowed ? 'Smoking allowed' : 'No smoking',
        ),
        row(
          rules.petsAllowed ? Icons.pets : Icons.pets_outlined,
          rules.petsAllowed ? 'Pets allowed' : 'No pets',
        ),
        row(
          rules.partiesAllowed
              ? Icons.celebration
              : Icons.do_not_disturb_on_outlined,
          rules.partiesAllowed
              ? 'Parties/events allowed'
              : 'No parties or events',
        ),
        if (rules.additionalRules != null && rules.additionalRules!.isNotEmpty)
          row(Icons.info_outline, rules.additionalRules!),
      ],
    );
  }
}

class _AmenityChip extends StatelessWidget {
  const _AmenityChip({required this.icon, required this.label});

  final IconData icon;
  final String label;

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    return Container(
      padding: const EdgeInsets.symmetric(horizontal: 14, vertical: 10),
      decoration: BoxDecoration(
        color: AppColors.surfaceMuted,
        borderRadius: BorderRadius.circular(14),
        border: Border.all(color: theme.colorScheme.outlineVariant),
      ),
      child: Row(
        mainAxisSize: MainAxisSize.min,
        children: [
          Icon(icon, size: 18, color: AppColors.brand),
          const SizedBox(width: 8),
          Text(
            label,
            style: theme.textTheme.bodyMedium?.copyWith(
              fontWeight: FontWeight.w500,
            ),
          ),
        ],
      ),
    );
  }
}

class _ReviewsSection extends StatelessWidget {
  const _ReviewsSection({required this.reviews});

  final List<Review> reviews;

  void _showAllReviews(BuildContext context) {
    showModalBottomSheet(
      context: context,
      isScrollControlled: true,
      backgroundColor: Colors.transparent,
      builder: (sheetContext) {
        final theme = Theme.of(sheetContext);
        return ConstrainedBox(
          constraints: BoxConstraints(
            maxHeight: MediaQuery.of(sheetContext).size.height * 0.85,
          ),
          child: Material(
            color: theme.colorScheme.surface,
            clipBehavior: Clip.antiAlias,
            borderRadius: const BorderRadius.vertical(top: Radius.circular(24)),
            child: Column(
              mainAxisSize: MainAxisSize.min,
              children: [
                const SizedBox(height: 12),
                Center(
                  child: Container(
                    width: 44,
                    height: 5,
                    decoration: BoxDecoration(
                      color: theme.colorScheme.outlineVariant,
                      borderRadius: BorderRadius.circular(3),
                    ),
                  ),
                ),
                Padding(
                  padding: const EdgeInsets.fromLTRB(20, 14, 8, 8),
                  child: Row(
                    children: [
                      Expanded(
                        child: _SectionTitle('${reviews.length} reviews'),
                      ),
                      IconButton(
                        icon: const Icon(Icons.close_rounded),
                        onPressed: () => Navigator.pop(sheetContext),
                        tooltip: 'Close',
                      ),
                    ],
                  ),
                ),
                Flexible(
                  child: ListView.separated(
                    padding: const EdgeInsets.fromLTRB(20, 8, 20, 24),
                    itemCount: reviews.length,
                    separatorBuilder: (_, __) => Divider(
                      height: 24,
                      color: theme.colorScheme.outlineVariant,
                    ),
                    itemBuilder: (context, i) =>
                        _ReviewCard(review: reviews[i]),
                  ),
                ),
              ],
            ),
          ),
        );
      },
    );
  }

  @override
  Widget build(BuildContext context) {
    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        const _SectionTitle('Reviews'),
        const SizedBox(height: 16),
        ...reviews.take(3).map((review) => _ReviewCard(review: review)),
        if (reviews.length > 3)
          TextButton(
            onPressed: () => _showAllReviews(context),
            child: Text('Show all ${reviews.length} reviews'),
          ),
      ],
    );
  }
}

class _ReviewCard extends StatelessWidget {
  const _ReviewCard({required this.review});

  final Review review;

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);

    return Padding(
      padding: const EdgeInsets.only(bottom: 16),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Row(
            children: [
              CircleAvatar(
                radius: 20,
                backgroundImage: review.userAvatarUrl != null
                    ? NetworkImage(review.userAvatarUrl!)
                    : null,
                child: review.userAvatarUrl == null
                    ? Text(review.userName.isNotEmpty
                        ? review.userName[0].toUpperCase()
                        : '?')
                    : null,
              ),
              const SizedBox(width: 12),
              Expanded(
                child: Column(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    Text(
                      review.userName,
                      style: theme.textTheme.bodyMedium?.copyWith(
                        fontWeight: FontWeight.w600,
                      ),
                    ),
                    Text(
                      _formatDate(review.createdAt),
                      style: theme.textTheme.bodySmall?.copyWith(
                        color: theme.colorScheme.onSurfaceVariant,
                      ),
                    ),
                  ],
                ),
              ),
              Row(
                children: [
                  const Icon(Icons.star, size: 16),
                  const SizedBox(width: 4),
                  Text(
                    review.rating.toStringAsFixed(1),
                    style: theme.textTheme.bodyMedium?.copyWith(
                      fontWeight: FontWeight.w500,
                    ),
                  ),
                ],
              ),
            ],
          ),
          const SizedBox(height: 8),
          Text(
            review.comment ?? '',
            style: theme.textTheme.bodyMedium?.copyWith(
              color: theme.colorScheme.onSurfaceVariant,
              height: 1.4,
            ),
          ),
        ],
      ),
    );
  }

  String _formatDate(DateTime date) {
    final months = [
      'January',
      'February',
      'March',
      'April',
      'May',
      'June',
      'July',
      'August',
      'September',
      'October',
      'November',
      'December'
    ];
    return '${months[date.month - 1]} ${date.year}';
  }
}

class _BookingSheet extends StatefulWidget {
  const _BookingSheet({
    required this.listing,
    required this.repository,
    required this.authState,
  });

  final Listing listing;
  final MusafirRepository repository;
  final AuthStateNotifier authState;

  @override
  State<_BookingSheet> createState() => _BookingSheetState();
}

class _BookingSheetState extends State<_BookingSheet> {
  DurationType _durationType = DurationType.daily;

  // Daily booking
  DateTimeRange? _dateRange;

  // Hourly booking
  DateTime? _hourlyDate;
  TimeOfDay? _startTime;
  int _hours = 1;

  // Monthly booking
  DateTime? _monthlyStartDate;
  int _months = 1;

  int _guestCount = 1;
  bool _isBooking = false;

  // Coupon
  final _couponController = TextEditingController();
  CouponValidation? _coupon;
  bool _checkingCoupon = false;

  // Conflict tracking
  List<Booking> _conflictingBookings = [];
  List<Booking> _userConflictingBookings = [];
  bool _isCheckingAvailability = false;
  // Set from the server-authoritative is_booking_available RPC — the only way
  // to detect OTHER guests' bookings, which RLS keeps out of the local cache.
  bool _listingUnavailable = false;
  // Guards against out-of-order async availability responses when the guest
  // rapidly changes the selection: only the latest request may apply its result.
  int _availabilityCheckId = 0;

  bool get _hasListingConflict =>
      _conflictingBookings.isNotEmpty || _listingUnavailable;
  bool get _hasUserConflict => _userConflictingBookings.isNotEmpty;
  bool get _hasConflict => _hasListingConflict || _hasUserConflict;

  @override
  void initState() {
    super.initState();
    // Default to the cheapest offered plan so the price matches the
    // "from ৳X" teaser the guest tapped on the explore card.
    _durationType = widget.listing.cheapestPlan ?? DurationType.daily;

    // Pre-fill the selection with sensible "now" defaults so the guest starts
    // from a ready-to-book state instead of an empty form; they can change any
    // of it before confirming. The start time is now + 5 min: a small buffer
    // that keeps _checkIn in the future (booking requires _checkIn.isAfter(now))
    // and correctly rolls the date forward when we're within 5 min of midnight.
    final start = DateTime.now().add(const Duration(minutes: 5));
    final today = DateTime(start.year, start.month, start.day);
    _hourlyDate = today;
    _startTime = TimeOfDay(hour: start.hour, minute: start.minute);
    _dateRange =
        DateTimeRange(start: today, end: today.add(const Duration(days: 1)));
    _monthlyStartDate = today;

    // Reflect availability/conflicts for the prefilled selection once built.
    WidgetsBinding.instance.addPostFrameCallback((_) {
      if (mounted) _checkAvailability();
    });
  }

  @override
  void dispose() {
    _couponController.dispose();
    super.dispose();
  }

  // ---- Coupon ------------------------------------------------------------
  double get _discountAmount =>
      (_coupon?.valid ?? false) ? _coupon!.discountAmount : 0;
  Money get _discountMoney => Money(_discountAmount, _totalPriceMoney.currency);
  Money get _finalPriceMoney => _totalPriceMoney.subtract(_discountMoney);

  /// Validates the typed coupon against the current total (server-authoritative).
  Future<void> _applyCoupon() async {
    final code = _couponController.text.trim();
    if (code.isEmpty) return;
    if (!_isSelectionComplete) {
      _showWarningBanner('Choose your dates before applying a coupon');
      return;
    }
    setState(() => _checkingCoupon = true);
    final result = await CouponService.instance.validate(code, _totalPrice);
    if (!mounted) return;
    setState(() {
      _checkingCoupon = false;
      _coupon = result.valid ? result : null;
    });
    if (result.valid) {
      ModernBanner.showSuccess(
        context,
        'Coupon applied — you saved ${_discountMoney.format()}',
      );
    } else {
      _showErrorBanner(result.message);
    }
  }

  void _removeCoupon() {
    setState(() {
      _coupon = null;
      _couponController.clear();
    });
  }

  Widget _buildCouponSection(ThemeData theme) {
    if (_coupon?.valid ?? false) {
      return Row(
        children: [
          Icon(Icons.local_offer_rounded, size: 18, color: AppColors.success),
          const SizedBox(width: 8),
          Expanded(
            child: Text(
              '${_coupon!.code} applied',
              style: theme.textTheme.bodyMedium
                  ?.copyWith(fontWeight: FontWeight.w700),
            ),
          ),
          TextButton(
            onPressed: _removeCoupon,
            style: TextButton.styleFrom(
              visualDensity: VisualDensity.compact,
              tapTargetSize: MaterialTapTargetSize.shrinkWrap,
            ),
            child: const Text('Remove'),
          ),
        ],
      );
    }
    return Row(
      children: [
        Expanded(
          child: TextField(
            controller: _couponController,
            textCapitalization: TextCapitalization.characters,
            decoration: InputDecoration(
              isDense: true,
              hintText: 'Coupon code',
              prefixIcon: const Icon(Icons.local_offer_outlined, size: 18),
              border: OutlineInputBorder(
                borderRadius: BorderRadius.circular(12),
              ),
              contentPadding:
                  const EdgeInsets.symmetric(horizontal: 12, vertical: 10),
            ),
            onSubmitted: (_) => _applyCoupon(),
          ),
        ),
        const SizedBox(width: 8),
        SizedBox(
          height: 42,
          child: FilledButton(
            onPressed: _checkingCoupon ? null : _applyCoupon,
            style: FilledButton.styleFrom(
              padding: const EdgeInsets.symmetric(horizontal: 16),
            ),
            child: _checkingCoupon
                ? const SizedBox(
                    height: 16,
                    width: 16,
                    child: CircularProgressIndicator(
                        strokeWidth: 2, color: Colors.white),
                  )
                : const Text('Apply'),
          ),
        ),
      ],
    );
  }

  /// Modern animated error toast (see [ModernBanner]).
  void _showErrorBanner(String message) {
    ModernBanner.showError(context, message);
  }

  /// Modern animated warning toast (see [ModernBanner]).
  void _showWarningBanner(String message) {
    ModernBanner.showWarning(context, message);
  }

  Future<void> _checkAvailability() async {
    // The total may have changed → drop any applied coupon so its discount
    // isn't stale (the guest re-applies against the new amount).
    _coupon = null;
    if (!_isSelectionComplete) {
      setState(() {
        _conflictingBookings = [];
        _userConflictingBookings = [];
        _listingUnavailable = false;
        _isCheckingAvailability = false;
      });
      return;
    }

    final requestId = ++_availabilityCheckId;
    final checkIn = _checkIn;
    final checkOut = _checkOut;

    // User conflicts (the guest's OWN bookings ARE in the local cache).
    List<Booking> userConflicts = [];
    final user = widget.authState.currentUser;
    if (user != null) {
      userConflicts = widget.repository.getUserConflictingBookings(
        userId: user.id,
        checkIn: checkIn,
        checkOut: checkOut,
      );
    }
    // Local listing conflicts only surface the guest's own bookings on this
    // listing (for the detailed list). Other guests' bookings are invisible to
    // the cache under RLS — the server check below is what actually detects them.
    final localListingConflicts = widget.repository.getConflictingBookings(
      listingId: widget.listing.id,
      checkIn: checkIn,
      checkOut: checkOut,
    );

    setState(() {
      _conflictingBookings = localListingConflicts;
      _userConflictingBookings = userConflicts;
      _isCheckingAvailability = true;
    });

    // Server-authoritative, cross-user availability.
    bool available;
    try {
      available = await widget.repository.isBookingAvailable(
        listingId: widget.listing.id,
        checkIn: checkIn,
        checkOut: checkOut,
      );
    } catch (_) {
      // Transient RPC/network error — don't hard-block on it; the server
      // re-checks atomically (and the DB constraint enforces) at booking time.
      available = true;
    }

    // Drop a stale response if the selection changed while we awaited.
    if (!mounted || requestId != _availabilityCheckId) return;
    setState(() {
      _listingUnavailable = !available;
      _isCheckingAvailability = false;
    });
  }

  IconData _planIcon(DurationType plan) => switch (plan) {
        DurationType.hourly => Icons.schedule,
        DurationType.daily => Icons.today,
        DurationType.monthly => Icons.calendar_month,
      };

  double get _rate => widget.listing.rateFor(_durationType) ?? 0;

  Money get _rateMoney =>
      widget.listing.moneyFor(_durationType) ??
      Money.zero(widget.listing.currency);

  /// Display label for UI (user-friendly)
  String get _rateLabel => _durationType.displayUnit;

  /// Database pricing_unit value (must match enum: hour, day, month)
  String get _pricingUnit => _durationType.pricingUnit;

  int get _duration {
    return switch (_durationType) {
      DurationType.hourly => _hours,
      DurationType.daily => _dateRange != null
          ? _dateRange!.end.difference(_dateRange!.start).inDays
          : 0,
      DurationType.monthly => _months,
    };
  }

  double get _totalPrice {
    return _rate * _duration;
  }

  Money get _totalPriceMoney {
    return _rateMoney.multiply(_duration.toDouble());
  }

  bool get _isSelectionComplete {
    return switch (_durationType) {
      DurationType.hourly => _hourlyDate != null && _startTime != null,
      // A same-day range (start == end) is 0 nights / ৳0 — require ≥ 1 night.
      DurationType.daily => _dateRange != null &&
          _dateRange!.end.difference(_dateRange!.start).inDays >= 1,
      DurationType.monthly => _monthlyStartDate != null,
    };
  }

  DateTime get _checkIn {
    return switch (_durationType) {
      DurationType.hourly => DateTime(
          _hourlyDate!.year,
          _hourlyDate!.month,
          _hourlyDate!.day,
          _startTime!.hour,
          _startTime!.minute,
        ),
      DurationType.daily => _dateRange!.start,
      DurationType.monthly => _monthlyStartDate!,
    };
  }

  DateTime get _checkOut {
    return switch (_durationType) {
      DurationType.hourly => _checkIn.add(Duration(hours: _hours)),
      DurationType.daily => _dateRange!.end,
      DurationType.monthly => DateTime(
          _monthlyStartDate!.year,
          _monthlyStartDate!.month + _months,
          _monthlyStartDate!.day,
        ),
    };
  }

  Future<void> _selectDates() async {
    final picked = await showDateRangePicker(
      context: context,
      firstDate: DateTime.now(),
      lastDate: DateTime.now().add(const Duration(days: 365)),
      initialDateRange: _dateRange,
    );
    if (picked != null) {
      setState(() => _dateRange = picked);
      _checkAvailability();
    }
  }

  Future<void> _selectHourlyDate() async {
    final picked = await showDatePicker(
      context: context,
      initialDate: _hourlyDate ?? DateTime.now(),
      firstDate: DateTime.now(),
      lastDate: DateTime.now().add(const Duration(days: 365)),
    );
    if (picked != null) {
      setState(() => _hourlyDate = picked);
      _checkAvailability();
    }
  }

  Future<void> _selectStartTime() async {
    final picked = await showTimePicker(
      context: context,
      initialTime: _startTime ?? TimeOfDay.now(),
    );
    if (picked != null) {
      setState(() => _startTime = picked);
      _checkAvailability();
    }
  }

  Future<void> _selectMonthlyStartDate() async {
    final now = DateTime.now();
    final initialDate = _monthlyStartDate ?? DateTime(now.year, now.month, 1);

    final picked = await showDialog<DateTime>(
      context: context,
      builder: (context) => _MonthPickerDialog(
        initialDate: initialDate,
        firstDate: DateTime(now.year, now.month, 1),
        lastDate: DateTime(now.year + 1, now.month, 1),
      ),
    );

    if (picked != null) {
      // Set to 1st of the selected month
      setState(
          () => _monthlyStartDate = DateTime(picked.year, picked.month, 1));
      _checkAvailability();
    }
  }

  Future<void> _confirmBooking() async {
    if (!_isSelectionComplete) {
      _showWarningBanner('Please complete your selection');
      return;
    }

    // The start must be in the future — the hourly time picker allows any
    // time-of-day, so a slot earlier today would otherwise be bookable.
    if (!_checkIn.isAfter(DateTime.now())) {
      _showWarningBanner('Please choose a start time in the future');
      return;
    }

    // Enforce the host's per-plan min/max booking duration.
    final limits = widget.listing.bookingLimits;
    final unit = switch (_durationType) {
      DurationType.hourly => 'hour',
      DurationType.daily => 'night',
      DurationType.monthly => 'month',
    };
    final minUnits = limits.minFor(_durationType);
    final maxUnits = limits.maxFor(_durationType);
    if (_duration < minUnits) {
      _showWarningBanner(
          'Minimum booking is $minUnits $unit${minUnits == 1 ? '' : 's'}');
      return;
    }
    if (maxUnits != null && _duration > maxUnits) {
      _showWarningBanner(
          'Maximum booking is $maxUnits $unit${maxUnits == 1 ? '' : 's'}');
      return;
    }

    // Double-check availability (server-authoritative) right before booking.
    await _checkAvailability();
    if (!mounted) return;
    if (_hasConflict) {
      _showErrorBanner('This time slot is no longer available');
      return;
    }

    final user = widget.authState.currentUser;
    if (user == null) {
      _showWarningBanner('Please log in to book');
      return;
    }

    setState(() => _isBooking = true);

    // Re-validate the coupon against the final total right before booking, so a
    // changed selection can't lock in a stale discount. Server is authoritative.
    String? couponCode;
    String? couponId;
    double discountAmount = 0;
    if (_coupon?.valid ?? false) {
      final fresh =
          await CouponService.instance.validate(_coupon!.code!, _totalPrice);
      if (!mounted) return;
      if (!fresh.valid) {
        setState(() {
          _coupon = null;
          _isBooking = false;
        });
        _showErrorBanner(fresh.message);
        return;
      }
      couponCode = fresh.code;
      couponId = fresh.couponId;
      discountAmount = fresh.discountAmount;
    }

    try {
      await widget.repository.createMarketplaceBooking(
        listingId: widget.listing.id,
        userId: user.id,
        userName: user.name,
        checkIn: _checkIn,
        checkOut: _checkOut,
        guestCount: _guestCount,
        totalPrice: _totalPrice - discountAmount,
        unitLabel: _pricingUnit,
        couponCode: couponCode,
        discountAmount: discountAmount,
        couponId: couponId,
      );

      if (mounted) {
        // Capture the root navigator before popping the booking sheet — this
        // State's context is disposed by the time the success sheet closes.
        final rootNav = Navigator.of(context, rootNavigator: true);
        Navigator.pop(context);
        // Celebrate the milestone with a modern confirmation sheet instead of a
        // flat banner — a booking request is a "done!" moment.
        await SuccessSheet.show(
          context,
          title: 'Request sent!',
          message:
              'Your booking request for ${widget.listing.title} is on its way. '
              "You'll be notified as soon as the host confirms.",
          primaryLabel: 'Got it',
        );
        // Once acknowledged (or auto-dismissed), return to the shell and land
        // the guest on their Trips list so they can watch for confirmation.
        rootNav.popUntil((route) => route.isFirst);
        ShellNavState.instance.openGuestTrips();
      }
    } on BookingConflictException catch (e) {
      if (mounted) {
        // Refresh conflict check to show updated conflicts
        _checkAvailability();

        String message;
        if (e.conflictType == ConflictType.user) {
          message =
              'You already have a booking during this time. You cannot book multiple places at the same time.';
        } else {
          message =
              'This time slot was just booked by someone else. Please select different dates.';
        }

        _showErrorBanner(message);
      }
    } on BookingRejectedException catch (e) {
      // The server refused for a reason the guest can fix (capacity, dates,
      // duration, coupon, an expired session). Its sentence names the field to
      // change; "please try again" would send them round the same loop.
      if (mounted) {
        _showErrorBanner(e.message);
      }
    } catch (e) {
      if (mounted) {
        _showErrorBanner('Booking failed. Please try again.');
      }
    } finally {
      if (mounted) {
        setState(() => _isBooking = false);
      }
    }
  }

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    final maxSheetHeight = MediaQuery.of(context).size.height * 0.9;

    return ConstrainedBox(
      constraints: BoxConstraints(maxHeight: maxSheetHeight),
      child: Material(
        color: theme.colorScheme.surface,
        clipBehavior: Clip.antiAlias,
        borderRadius: const BorderRadius.vertical(top: Radius.circular(24)),
        child: Padding(
          padding: EdgeInsets.only(
            bottom: MediaQuery.of(context).viewInsets.bottom,
          ),
          child: Column(
            mainAxisSize: MainAxisSize.min,
            children: [
              // Drag handle
              Padding(
                padding: const EdgeInsets.only(top: 12, bottom: 6),
                child: Center(
                  child: Container(
                    width: 44,
                    height: 5,
                    decoration: BoxDecoration(
                      color: theme.colorScheme.outlineVariant,
                      borderRadius: BorderRadius.circular(3),
                    ),
                  ),
                ),
              ),
              // Contextual listing header — reminds the guest what they're booking
              Padding(
                padding: const EdgeInsets.fromLTRB(20, 6, 8, 12),
                child: Row(
                  children: [
                    ClipRRect(
                      borderRadius: BorderRadius.circular(14),
                      child: SizedBox(
                        width: 54,
                        height: 54,
                        child: widget.listing.primaryImage != null
                            ? AppNetworkImage(
                                url: widget.listing.primaryImage!,
                                fit: BoxFit.cover,
                                decodeWidth: 54,
                                errorWidget: Container(
                                  color: AppColors.surfaceMuted,
                                  child: const Icon(Icons.home_outlined),
                                ),
                              )
                            : Container(
                                color: AppColors.surfaceMuted,
                                child: const Icon(Icons.home_outlined),
                              ),
                      ),
                    ),
                    const SizedBox(width: 12),
                    Expanded(
                      child: Column(
                        crossAxisAlignment: CrossAxisAlignment.start,
                        mainAxisSize: MainAxisSize.min,
                        children: [
                          Text(
                            widget.listing.title,
                            maxLines: 1,
                            overflow: TextOverflow.ellipsis,
                            style: theme.textTheme.titleMedium?.copyWith(
                              fontWeight: FontWeight.w700,
                            ),
                          ),
                          const SizedBox(height: 2),
                          Row(
                            children: [
                              Icon(
                                Icons.location_on_outlined,
                                size: 14,
                                color: theme.colorScheme.onSurfaceVariant,
                              ),
                              const SizedBox(width: 3),
                              Expanded(
                                child: Text(
                                  widget.listing.city ??
                                      widget.listing.approximateAddress,
                                  maxLines: 1,
                                  overflow: TextOverflow.ellipsis,
                                  style: theme.textTheme.bodySmall?.copyWith(
                                    color: theme.colorScheme.onSurfaceVariant,
                                  ),
                                ),
                              ),
                            ],
                          ),
                        ],
                      ),
                    ),
                    IconButton(
                      icon: const Icon(Icons.close_rounded),
                      onPressed: () => Navigator.pop(context),
                      tooltip: 'Close',
                    ),
                  ],
                ),
              ),
              // Scrollable content
              Flexible(
                child: SingleChildScrollView(
                  padding: const EdgeInsets.fromLTRB(24, 0, 24, 24),
                  child: Column(
                    crossAxisAlignment: CrossAxisAlignment.stretch,
                    mainAxisSize: MainAxisSize.min,
                    children: [
                      // Duration type selector — only the plans this listing
                      // offers. Hidden when a single plan is offered (no choice).
                      if (widget.listing.offeredPlans.length > 1) ...[
                        const _SectionTitle('Choose a plan'),
                        const SizedBox(height: 10),
                        _PlanSegments(
                          plans: widget.listing.offeredPlans,
                          selected: _durationType,
                          iconFor: _planIcon,
                          onChanged: (plan) {
                            setState(() => _durationType = plan);
                          },
                        ),
                        const SizedBox(height: 16),
                      ],

                      // Rate display — hero price card
                      Container(
                        padding: const EdgeInsets.symmetric(
                          horizontal: 16,
                          vertical: 18,
                        ),
                        decoration: BoxDecoration(
                          gradient: LinearGradient(
                            begin: Alignment.topLeft,
                            end: Alignment.bottomRight,
                            colors: [
                              AppColors.brand.withValues(alpha: 0.10),
                              AppColors.brandLight.withValues(alpha: 0.06),
                            ],
                          ),
                          borderRadius: BorderRadius.circular(18),
                          border: Border.all(
                            color: AppColors.brand.withValues(alpha: 0.18),
                          ),
                        ),
                        child: Center(
                          child: PriceDisplay(
                            amount: _rateMoney,
                            perUnit: _rateLabel,
                            style: PriceDisplayStyle.large,
                            color: AppColors.brandDark,
                            alignment: CrossAxisAlignment.center,
                          ),
                        ),
                      ),
                      const SizedBox(height: 16),

                      // Existing bookings preview
                      _buildExistingBookingsPreview(theme),
                      const SizedBox(height: 16),

                      // Duration-specific selection UI
                      ..._buildDurationSelector(theme),
                      const SizedBox(height: 16),

                      // Guest count
                      _StepperBox(
                        icon: Icons.people_alt_rounded,
                        label: 'Guests',
                        value:
                            '$_guestCount guest${_guestCount > 1 ? 's' : ''}',
                        color: AppColors.blue,
                        onDecrement: _guestCount > 1
                            ? () => setState(() => _guestCount--)
                            : null,
                        onIncrement: _guestCount < widget.listing.maxGuests
                            ? () => setState(() => _guestCount++)
                            : null,
                      ),
                      const SizedBox(height: 16),

                      // User conflict warning (you already have a booking)
                      if (_hasUserConflict) ...[
                        _StatusBanner(
                          icon: Icons.person_off_rounded,
                          color: AppColors.warning,
                          title: 'You have another booking',
                          subtitle:
                              'You cannot book multiple places at the same time',
                        ),
                        const SizedBox(height: 8),
                        // Show user's conflicting bookings
                        ..._userConflictingBookings.map((booking) => Padding(
                              padding: const EdgeInsets.only(bottom: 8),
                              child: Container(
                                padding: const EdgeInsets.all(10),
                                decoration: BoxDecoration(
                                  color:
                                      AppColors.warning.withValues(alpha: 0.08),
                                  borderRadius: BorderRadius.circular(10),
                                ),
                                child: Row(
                                  children: [
                                    Icon(
                                      Icons.event_busy_rounded,
                                      size: 16,
                                      color: AppColors.warning,
                                    ),
                                    const SizedBox(width: 8),
                                    Expanded(
                                      child: Text(
                                        '${booking.listingTitle ?? 'Your booking'}: ${_formatDateTime(booking.effectiveCheckIn)} - ${_formatDateTime(booking.effectiveCheckOut)}',
                                        style:
                                            theme.textTheme.bodySmall?.copyWith(
                                          color: AppColors.warning,
                                        ),
                                      ),
                                    ),
                                  ],
                                ),
                              ),
                            )),
                        const SizedBox(height: 8),
                      ],

                      // Listing conflict warning (this place is already booked)
                      if (_hasListingConflict) ...[
                        _StatusBanner(
                          icon: Icons.warning_amber_rounded,
                          color: AppColors.error,
                          title: 'Time slot not available',
                          subtitle: _conflictingBookings.isNotEmpty
                              ? '${_conflictingBookings.length} existing booking${_conflictingBookings.length > 1 ? 's' : ''} conflict with your selection'
                              : 'This time was just booked. Please pick another slot.',
                        ),
                        const SizedBox(height: 8),
                        // Show conflicting bookings
                        ..._conflictingBookings.map((booking) => Padding(
                              padding: const EdgeInsets.only(bottom: 8),
                              child: Container(
                                padding: const EdgeInsets.all(10),
                                decoration: BoxDecoration(
                                  color: AppColors.surfaceMuted,
                                  borderRadius: BorderRadius.circular(10),
                                ),
                                child: Row(
                                  children: [
                                    Icon(
                                      Icons.event_busy_rounded,
                                      size: 16,
                                      color: theme.colorScheme.onSurfaceVariant,
                                    ),
                                    const SizedBox(width: 8),
                                    Expanded(
                                      child: Text(
                                        '${_formatDateTime(booking.effectiveCheckIn)} - ${_formatDateTime(booking.effectiveCheckOut)}',
                                        style:
                                            theme.textTheme.bodySmall?.copyWith(
                                          color: theme
                                              .colorScheme.onSurfaceVariant,
                                        ),
                                      ),
                                    ),
                                  ],
                                ),
                              ),
                            )),
                        const SizedBox(height: 8),
                      ],

                      // Availability indicator
                      if (_isSelectionComplete &&
                          !_hasConflict &&
                          !_isCheckingAvailability) ...[
                        _StatusBanner(
                          icon: Icons.check_circle_rounded,
                          color: AppColors.success,
                          title: 'This time slot is available',
                        ),
                        const SizedBox(height: 16),
                      ],

                      // Price breakdown
                      if (_isSelectionComplete && !_hasConflict) ...[
                        Container(
                          padding: const EdgeInsets.all(16),
                          decoration: BoxDecoration(
                            color: AppColors.surfaceMuted,
                            borderRadius: BorderRadius.circular(18),
                          ),
                          child: Column(
                            children: [
                              PriceSummaryRow(
                                basePrice: _rateMoney,
                                units: _duration,
                                unitType: _rateLabel,
                                total: _totalPriceMoney,
                              ),
                              const SizedBox(height: 12),
                              _buildCouponSection(theme),
                              const Divider(height: 24),
                              if (_discountAmount > 0) ...[
                                Row(
                                  mainAxisAlignment:
                                      MainAxisAlignment.spaceBetween,
                                  children: [
                                    Text(
                                      'Coupon${_coupon?.code != null ? ' (${_coupon!.code})' : ''}',
                                      style:
                                          theme.textTheme.bodyMedium?.copyWith(
                                        color: AppColors.success,
                                        fontWeight: FontWeight.w600,
                                      ),
                                    ),
                                    Text(
                                      '-${_discountMoney.format()}',
                                      style:
                                          theme.textTheme.bodyMedium?.copyWith(
                                        color: AppColors.success,
                                        fontWeight: FontWeight.w700,
                                      ),
                                    ),
                                  ],
                                ),
                                const SizedBox(height: 10),
                              ],
                              Row(
                                mainAxisAlignment:
                                    MainAxisAlignment.spaceBetween,
                                children: [
                                  Text(
                                    'Total',
                                    style:
                                        theme.textTheme.titleMedium?.copyWith(
                                      fontWeight: FontWeight.w800,
                                    ),
                                  ),
                                  Text(
                                    _finalPriceMoney.format(),
                                    style:
                                        theme.textTheme.titleMedium?.copyWith(
                                      fontWeight: FontWeight.w800,
                                      color: AppColors.brandDark,
                                    ),
                                  ),
                                ],
                              ),
                            ],
                          ),
                        ),
                        const SizedBox(height: 20),
                      ],

                      // Confirm button
                      _GradientButton(
                        label: _hasConflict
                            ? 'Time slot unavailable'
                            : _isSelectionComplete
                                ? 'Confirm booking'
                                : 'Complete your selection',
                        icon: (_isSelectionComplete && !_hasConflict)
                            ? Icons.check_rounded
                            : null,
                        expand: true,
                        enabled: !_isBooking &&
                            !_hasConflict &&
                            _isSelectionComplete,
                        loading: _isBooking,
                        onTap: _confirmBooking,
                      ),
                      const SizedBox(height: 16),
                    ],
                  ),
                ),
              ),
            ],
          ),
        ),
      ),
    );
  }

  List<Widget> _buildDurationSelector(ThemeData theme) {
    return switch (_durationType) {
      DurationType.hourly => _buildHourlySelector(theme),
      DurationType.daily => _buildDailySelector(theme),
      DurationType.monthly => _buildMonthlySelector(theme),
    };
  }

  List<Widget> _buildHourlySelector(ThemeData theme) {
    return [
      _BookingFieldCard(
        icon: Icons.calendar_today_rounded,
        label: 'Date',
        value: _hourlyDate != null ? _formatDate(_hourlyDate!) : 'Select date',
        color: AppColors.blue,
        filled: _hourlyDate != null,
        onTap: _selectHourlyDate,
      ),
      const SizedBox(height: 12),
      _BookingFieldCard(
        icon: Icons.access_time_rounded,
        label: 'Start time',
        value: _startTime != null ? _formatTime(_startTime!) : 'Select time',
        color: AppColors.violet,
        filled: _startTime != null,
        onTap: _selectStartTime,
      ),
      const SizedBox(height: 12),
      _StepperBox(
        icon: Icons.hourglass_bottom_rounded,
        label: 'Duration',
        value: '$_hours hour${_hours > 1 ? 's' : ''}',
        color: AppColors.amber,
        onDecrement: _hours > 1
            ? () {
                setState(() => _hours--);
                _checkAvailability();
              }
            : null,
        onIncrement: _hours < 12
            ? () {
                setState(() => _hours++);
                _checkAvailability();
              }
            : null,
      ),

      // End time preview
      if (_hourlyDate != null && _startTime != null) ...[
        const SizedBox(height: 12),
        _PreviewPill(
          icon: Icons.info_outline_rounded,
          text:
              'Ends at ${_formatTime(TimeOfDay(hour: (_startTime!.hour + _hours) % 24, minute: _startTime!.minute))}',
        ),
      ],
    ];
  }

  List<Widget> _buildDailySelector(ThemeData theme) {
    return [
      _BookingFieldCard(
        icon: Icons.calendar_today_rounded,
        label: 'Dates',
        value: _dateRange != null
            ? '${_formatDate(_dateRange!.start)} – ${_formatDate(_dateRange!.end)}'
            : 'Select dates',
        color: AppColors.blue,
        filled: _dateRange != null,
        onTap: _selectDates,
      ),
    ];
  }

  List<Widget> _buildMonthlySelector(ThemeData theme) {
    return [
      _BookingFieldCard(
        icon: Icons.event_rounded,
        label: 'Start month',
        value: _monthlyStartDate != null
            ? _formatMonthYear(_monthlyStartDate!)
            : 'Select start month',
        color: AppColors.blue,
        filled: _monthlyStartDate != null,
        onTap: _selectMonthlyStartDate,
      ),
      const SizedBox(height: 12),
      _StepperBox(
        icon: Icons.calendar_month_rounded,
        label: 'Duration',
        value: '$_months month${_months > 1 ? 's' : ''}',
        color: AppColors.violet,
        onDecrement: _months > 1
            ? () {
                setState(() => _months--);
                _checkAvailability();
              }
            : null,
        onIncrement: _months < 12
            ? () {
                setState(() => _months++);
                _checkAvailability();
              }
            : null,
      ),

      // Booking period preview
      if (_monthlyStartDate != null) ...[
        const SizedBox(height: 12),
        _PreviewPill(
          icon: Icons.date_range_rounded,
          text:
              '${_formatMonthYear(_monthlyStartDate!)} - ${_formatMonthYear(DateTime(_monthlyStartDate!.year, _monthlyStartDate!.month + _months - 1, 1))}',
        ),
      ],
    ];
  }

  Widget _buildExistingBookingsPreview(ThemeData theme) {
    final activeBookings = widget.repository.getActiveBookingsForListing(
      widget.listing.id,
    );

    // Filter to show only future bookings
    final now = DateTime.now();
    final upcomingBookings = activeBookings
        .where((b) => b.effectiveCheckOut.isAfter(now))
        .take(5)
        .toList();

    if (upcomingBookings.isEmpty) {
      return const SizedBox.shrink();
    }

    return ExpansionTile(
      tilePadding: EdgeInsets.zero,
      childrenPadding: const EdgeInsets.only(bottom: 8),
      leading: Icon(
        Icons.event_note,
        color: theme.colorScheme.primary,
      ),
      title: Text(
        'View booked dates',
        style: theme.textTheme.bodyMedium?.copyWith(
          color: theme.colorScheme.primary,
          fontWeight: FontWeight.w500,
        ),
      ),
      subtitle: Text(
        '${upcomingBookings.length} upcoming booking${upcomingBookings.length > 1 ? 's' : ''}',
        style: theme.textTheme.bodySmall?.copyWith(
          color: theme.colorScheme.onSurfaceVariant,
        ),
      ),
      children: upcomingBookings.map((booking) {
        return Container(
          margin: const EdgeInsets.only(bottom: 8),
          padding: const EdgeInsets.all(12),
          decoration: BoxDecoration(
            color: theme.colorScheme.surfaceContainerHighest,
            borderRadius: BorderRadius.circular(8),
          ),
          child: Row(
            children: [
              Container(
                width: 4,
                height: 48,
                decoration: BoxDecoration(
                  color: _getBookingTypeColor(booking.unitLabel),
                  borderRadius: BorderRadius.circular(2),
                ),
              ),
              const SizedBox(width: 12),
              Expanded(
                child: Column(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    Row(
                      children: [
                        Expanded(
                          child: Text(
                            '${_formatDate(booking.effectiveCheckIn)} - ${_formatDate(booking.effectiveCheckOut)}',
                            style: theme.textTheme.bodyMedium?.copyWith(
                              fontWeight: FontWeight.w500,
                            ),
                          ),
                        ),
                        Container(
                          padding: const EdgeInsets.symmetric(
                              horizontal: 8, vertical: 2),
                          decoration: BoxDecoration(
                            color: _getBookingTypeColor(booking.unitLabel)
                                .withValues(alpha: 0.15),
                            borderRadius: BorderRadius.circular(12),
                          ),
                          child: Text(
                            _getBookingTypeLabel(booking.unitLabel),
                            style: theme.textTheme.labelSmall?.copyWith(
                              color: _getBookingTypeColor(booking.unitLabel),
                              fontWeight: FontWeight.w600,
                            ),
                          ),
                        ),
                      ],
                    ),
                    const SizedBox(height: 2),
                    Text(
                      _getBookingTimeDescription(booking),
                      style: theme.textTheme.bodySmall?.copyWith(
                        color: theme.colorScheme.onSurfaceVariant,
                      ),
                    ),
                  ],
                ),
              ),
            ],
          ),
        );
      }).toList(),
    );
  }

  String _getBookingTimeDescription(Booking booking) {
    final checkIn = booking.effectiveCheckIn;
    final checkOut = booking.effectiveCheckOut;
    final duration = checkOut.difference(checkIn);

    if (duration.inHours < 24) {
      return '${duration.inHours} hour${duration.inHours > 1 ? 's' : ''} (${_formatTimeFromDateTime(checkIn)} - ${_formatTimeFromDateTime(checkOut)})';
    } else if (duration.inDays < 30) {
      return '${duration.inDays} night${duration.inDays > 1 ? 's' : ''}';
    } else {
      final months = (duration.inDays / 30).round();
      return '$months month${months > 1 ? 's' : ''}';
    }
  }

  String _getBookingTypeLabel(String unitLabel) {
    return switch (unitLabel.toLowerCase()) {
      'hour' => 'Hourly',
      'day' => 'Daily',
      'month' => 'Monthly',
      _ => unitLabel,
    };
  }

  Color _getBookingTypeColor(String unitLabel) {
    return switch (unitLabel.toLowerCase()) {
      'hour' => Colors.orange,
      'day' => Colors.blue,
      'month' => Colors.purple,
      _ => Colors.grey,
    };
  }

  String _formatTimeFromDateTime(DateTime dateTime) {
    final hour = dateTime.hour % 12 == 0 ? 12 : dateTime.hour % 12;
    final minute = dateTime.minute.toString().padLeft(2, '0');
    final period = dateTime.hour < 12 ? 'AM' : 'PM';
    return '$hour:$minute $period';
  }

  String _formatDate(DateTime date) {
    final months = [
      'Jan',
      'Feb',
      'Mar',
      'Apr',
      'May',
      'Jun',
      'Jul',
      'Aug',
      'Sep',
      'Oct',
      'Nov',
      'Dec'
    ];
    return '${months[date.month - 1]} ${date.day}, ${date.year}';
  }

  String _formatMonthYear(DateTime date) {
    final months = [
      'January',
      'February',
      'March',
      'April',
      'May',
      'June',
      'July',
      'August',
      'September',
      'October',
      'November',
      'December'
    ];
    return '${months[date.month - 1]} ${date.year}';
  }

  String _formatTime(TimeOfDay time) {
    final hour = time.hourOfPeriod == 0 ? 12 : time.hourOfPeriod;
    final minute = time.minute.toString().padLeft(2, '0');
    final period = time.period == DayPeriod.am ? 'AM' : 'PM';
    return '$hour:$minute $period';
  }

  String _formatDateTime(DateTime dateTime) {
    final months = [
      'Jan',
      'Feb',
      'Mar',
      'Apr',
      'May',
      'Jun',
      'Jul',
      'Aug',
      'Sep',
      'Oct',
      'Nov',
      'Dec'
    ];
    final hour = dateTime.hour % 12 == 0 ? 12 : dateTime.hour % 12;
    final minute = dateTime.minute.toString().padLeft(2, '0');
    final period = dateTime.hour < 12 ? 'AM' : 'PM';
    return '${months[dateTime.month - 1]} ${dateTime.day}, $hour:$minute $period';
  }
}

/// Month picker dialog for monthly bookings
class _MonthPickerDialog extends StatefulWidget {
  const _MonthPickerDialog({
    required this.initialDate,
    required this.firstDate,
    required this.lastDate,
  });

  final DateTime initialDate;
  final DateTime firstDate;
  final DateTime lastDate;

  @override
  State<_MonthPickerDialog> createState() => _MonthPickerDialogState();
}

class _MonthPickerDialogState extends State<_MonthPickerDialog> {
  late int _selectedYear;
  late int _selectedMonth;

  static const _monthNames = [
    'January',
    'February',
    'March',
    'April',
    'May',
    'June',
    'July',
    'August',
    'September',
    'October',
    'November',
    'December'
  ];

  @override
  void initState() {
    super.initState();
    _selectedYear = widget.initialDate.year;
    _selectedMonth = widget.initialDate.month;
  }

  bool _isMonthSelectable(int year, int month) {
    final date = DateTime(year, month, 1);
    return !date.isBefore(
            DateTime(widget.firstDate.year, widget.firstDate.month, 1)) &&
        !date.isAfter(DateTime(widget.lastDate.year, widget.lastDate.month, 1));
  }

  List<int> get _availableYears {
    final years = <int>[];
    for (int year = widget.firstDate.year;
        year <= widget.lastDate.year;
        year++) {
      years.add(year);
    }
    return years;
  }

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);

    return Dialog(
      child: Padding(
        padding: const EdgeInsets.all(24),
        child: Column(
          mainAxisSize: MainAxisSize.min,
          crossAxisAlignment: CrossAxisAlignment.stretch,
          children: [
            Text(
              'Select Start Month',
              style: theme.textTheme.titleLarge,
            ),
            const SizedBox(height: 24),

            // Year selector
            Row(
              mainAxisAlignment: MainAxisAlignment.center,
              children: [
                IconButton(
                  icon: const Icon(Icons.chevron_left),
                  onPressed: _availableYears.first < _selectedYear
                      ? () => setState(() => _selectedYear--)
                      : null,
                ),
                Text(
                  '$_selectedYear',
                  style: theme.textTheme.titleMedium?.copyWith(
                    fontWeight: FontWeight.bold,
                  ),
                ),
                IconButton(
                  icon: const Icon(Icons.chevron_right),
                  onPressed: _availableYears.last > _selectedYear
                      ? () => setState(() => _selectedYear++)
                      : null,
                ),
              ],
            ),
            const SizedBox(height: 16),

            // Month grid
            GridView.builder(
              shrinkWrap: true,
              physics: const NeverScrollableScrollPhysics(),
              gridDelegate: const SliverGridDelegateWithFixedCrossAxisCount(
                crossAxisCount: 3,
                childAspectRatio: 1.8,
                crossAxisSpacing: 8,
                mainAxisSpacing: 8,
              ),
              itemCount: 12,
              itemBuilder: (context, index) {
                final month = index + 1;
                final isSelectable = _isMonthSelectable(_selectedYear, month);
                final isSelected = _selectedYear == widget.initialDate.year &&
                    month == _selectedMonth;

                return Material(
                  color: isSelected
                      ? theme.colorScheme.primary
                      : isSelectable
                          ? theme.colorScheme.surfaceContainerHighest
                          : theme.colorScheme.surfaceContainerHighest
                              .withValues(alpha: 0.5),
                  borderRadius: BorderRadius.circular(8),
                  child: InkWell(
                    onTap: isSelectable
                        ? () => setState(() => _selectedMonth = month)
                        : null,
                    borderRadius: BorderRadius.circular(8),
                    child: Center(
                      child: Text(
                        _monthNames[index].substring(0, 3),
                        style: theme.textTheme.bodyMedium?.copyWith(
                          color: isSelected
                              ? theme.colorScheme.onPrimary
                              : isSelectable
                                  ? theme.colorScheme.onSurface
                                  : theme.colorScheme.onSurface
                                      .withValues(alpha: 0.4),
                          fontWeight: isSelected ? FontWeight.bold : null,
                        ),
                      ),
                    ),
                  ),
                );
              },
            ),
            const SizedBox(height: 24),

            // Actions
            Row(
              mainAxisAlignment: MainAxisAlignment.end,
              children: [
                TextButton(
                  onPressed: () => Navigator.pop(context),
                  child: const Text('Cancel'),
                ),
                const SizedBox(width: 8),
                FilledButton(
                  onPressed: () {
                    Navigator.pop(
                      context,
                      DateTime(_selectedYear, _selectedMonth, 1),
                    );
                  },
                  child: const Text('Select'),
                ),
              ],
            ),
          ],
        ),
      ),
    );
  }
}

/// Tappable selection field used in the booking sheet (date, time, month).
class _BookingFieldCard extends StatelessWidget {
  const _BookingFieldCard({
    required this.icon,
    required this.label,
    required this.value,
    required this.color,
    this.onTap,
    this.filled = false,
  });

  final IconData icon;
  final String label;
  final String value;
  final Color color;
  final VoidCallback? onTap;

  /// Whether a value has been chosen (emphasises the value text).
  final bool filled;

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    return Material(
      color: AppColors.surfaceMuted,
      borderRadius: BorderRadius.circular(16),
      child: InkWell(
        onTap: onTap,
        borderRadius: BorderRadius.circular(16),
        child: Padding(
          padding: const EdgeInsets.all(14),
          child: Row(
            children: [
              Container(
                width: 38,
                height: 38,
                decoration: BoxDecoration(
                  color: color.withValues(alpha: 0.12),
                  shape: BoxShape.circle,
                ),
                child: Icon(icon, size: 19, color: color),
              ),
              const SizedBox(width: 12),
              Expanded(
                child: Column(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  mainAxisSize: MainAxisSize.min,
                  children: [
                    Text(
                      label,
                      style: theme.textTheme.labelMedium?.copyWith(
                        color: theme.colorScheme.onSurfaceVariant,
                      ),
                    ),
                    const SizedBox(height: 2),
                    Text(
                      value,
                      style: theme.textTheme.bodyLarge?.copyWith(
                        fontWeight: filled ? FontWeight.w700 : FontWeight.w500,
                        color: filled
                            ? theme.colorScheme.onSurface
                            : theme.colorScheme.onSurfaceVariant,
                      ),
                    ),
                  ],
                ),
              ),
              if (onTap != null)
                Icon(
                  Icons.chevron_right_rounded,
                  color: theme.colorScheme.onSurfaceVariant,
                ),
            ],
          ),
        ),
      ),
    );
  }
}

/// Tinted stepper (− value +) for counts (guests, hours, months).
class _StepperBox extends StatelessWidget {
  const _StepperBox({
    required this.icon,
    required this.label,
    required this.value,
    required this.color,
    required this.onDecrement,
    required this.onIncrement,
  });

  final IconData icon;
  final String label;
  final String value;
  final Color color;
  final VoidCallback? onDecrement;
  final VoidCallback? onIncrement;

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    return Container(
      padding: const EdgeInsets.all(14),
      decoration: BoxDecoration(
        color: AppColors.surfaceMuted,
        borderRadius: BorderRadius.circular(16),
      ),
      child: Row(
        children: [
          Container(
            width: 38,
            height: 38,
            decoration: BoxDecoration(
              color: color.withValues(alpha: 0.12),
              shape: BoxShape.circle,
            ),
            child: Icon(icon, size: 19, color: color),
          ),
          const SizedBox(width: 12),
          Expanded(
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              mainAxisSize: MainAxisSize.min,
              children: [
                Text(
                  label,
                  style: theme.textTheme.labelMedium?.copyWith(
                    color: theme.colorScheme.onSurfaceVariant,
                  ),
                ),
                const SizedBox(height: 2),
                Text(
                  value,
                  style: theme.textTheme.bodyLarge?.copyWith(
                    fontWeight: FontWeight.w700,
                  ),
                ),
              ],
            ),
          ),
          _StepBtn(icon: Icons.remove_rounded, onTap: onDecrement),
          const SizedBox(width: 10),
          _StepBtn(icon: Icons.add_rounded, onTap: onIncrement),
        ],
      ),
    );
  }
}

class _StepBtn extends StatelessWidget {
  const _StepBtn({required this.icon, required this.onTap});

  final IconData icon;
  final VoidCallback? onTap;

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    final enabled = onTap != null;
    return Material(
      color: theme.colorScheme.surface,
      shape: const CircleBorder(),
      child: InkWell(
        onTap: onTap,
        customBorder: const CircleBorder(),
        child: SizedBox(
          width: 34,
          height: 34,
          child: Icon(
            icon,
            size: 20,
            color: enabled
                ? AppColors.brand
                : theme.colorScheme.onSurface.withValues(alpha: 0.3),
          ),
        ),
      ),
    );
  }
}

/// Subtle centered info pill (e.g. "Ends at 5:00 PM" / booking period).
class _PreviewPill extends StatelessWidget {
  const _PreviewPill({required this.icon, required this.text});

  final IconData icon;
  final String text;

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    return Container(
      padding: const EdgeInsets.all(12),
      decoration: BoxDecoration(
        color: AppColors.surfaceMuted,
        borderRadius: BorderRadius.circular(12),
      ),
      child: Row(
        mainAxisAlignment: MainAxisAlignment.center,
        children: [
          Icon(icon, size: 18, color: theme.colorScheme.onSurfaceVariant),
          const SizedBox(width: 8),
          Flexible(
            child: Text(
              text,
              textAlign: TextAlign.center,
              style: theme.textTheme.bodyMedium?.copyWith(
                color: theme.colorScheme.onSurfaceVariant,
              ),
            ),
          ),
        ],
      ),
    );
  }
}

/// Semantic status banner (info / warning / error / success).
class _StatusBanner extends StatelessWidget {
  const _StatusBanner({
    required this.icon,
    required this.color,
    required this.title,
    this.subtitle,
  });

  final IconData icon;
  final Color color;
  final String title;
  final String? subtitle;

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    return Container(
      padding: const EdgeInsets.all(14),
      decoration: BoxDecoration(
        color: color.withValues(alpha: 0.10),
        borderRadius: BorderRadius.circular(16),
        border: Border.all(color: color.withValues(alpha: 0.25)),
      ),
      child: Row(
        crossAxisAlignment: subtitle != null
            ? CrossAxisAlignment.start
            : CrossAxisAlignment.center,
        children: [
          Icon(icon, color: color, size: 22),
          const SizedBox(width: 12),
          Expanded(
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              mainAxisSize: MainAxisSize.min,
              children: [
                Text(
                  title,
                  style: theme.textTheme.titleSmall?.copyWith(
                    color: color,
                    fontWeight: FontWeight.w700,
                  ),
                ),
                if (subtitle != null) ...[
                  const SizedBox(height: 2),
                  Text(
                    subtitle!,
                    style: theme.textTheme.bodySmall?.copyWith(
                      color: color.withValues(alpha: 0.85),
                    ),
                  ),
                ],
              ],
            ),
          ),
        ],
      ),
    );
  }
}

/// Modern plan selector (replaces SegmentedButton) for hourly/daily/monthly.
class _PlanSegments extends StatelessWidget {
  const _PlanSegments({
    required this.plans,
    required this.selected,
    required this.iconFor,
    required this.onChanged,
  });

  final List<DurationType> plans;
  final DurationType selected;
  final IconData Function(DurationType) iconFor;
  final ValueChanged<DurationType> onChanged;

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    return Container(
      padding: const EdgeInsets.all(4),
      decoration: BoxDecoration(
        color: AppColors.surfaceMuted,
        borderRadius: BorderRadius.circular(16),
      ),
      child: Row(
        children: [
          for (final plan in plans)
            Expanded(
              child: GestureDetector(
                onTap: () => onChanged(plan),
                child: AnimatedContainer(
                  duration: const Duration(milliseconds: 200),
                  curve: Curves.easeOut,
                  padding: const EdgeInsets.symmetric(vertical: 12),
                  decoration: BoxDecoration(
                    gradient: plan == selected ? AppColors.brandGradient : null,
                    borderRadius: BorderRadius.circular(12),
                    boxShadow: plan == selected
                        ? [
                            BoxShadow(
                              color: AppColors.brand.withValues(alpha: 0.3),
                              blurRadius: 8,
                              offset: const Offset(0, 3),
                            ),
                          ]
                        : null,
                  ),
                  child: Column(
                    children: [
                      Icon(
                        iconFor(plan),
                        size: 20,
                        color: plan == selected
                            ? Colors.white
                            : theme.colorScheme.onSurfaceVariant,
                      ),
                      const SizedBox(height: 4),
                      Text(
                        plan.label,
                        style: theme.textTheme.labelMedium?.copyWith(
                          color: plan == selected
                              ? Colors.white
                              : theme.colorScheme.onSurfaceVariant,
                          fontWeight: FontWeight.w700,
                        ),
                      ),
                    ],
                  ),
                ),
              ),
            ),
        ],
      ),
    );
  }
}

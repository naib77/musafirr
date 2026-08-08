import 'dart:async';

import 'package:flutter/material.dart';

import '../../core/utils/responsive.dart';
import '../../models/listing.dart';
import '../../models/listing_type.dart';
import '../../models/listing_purpose.dart';
import '../../models/search_filters.dart';
import '../../repositories/musafir_repository.dart';
import '../leaderboard/host_leaderboard_screen.dart';
import '../../services/booking/booking_lifecycle_service.dart';
import '../../services/booking/booking_messaging_coordinator.dart';
import '../../services/geocoding_service.dart';
import '../../services/location_service.dart';
import '../../services/places_service.dart';
import '../../state/auth_state.dart';
import '../../state/favorites_state.dart';
import '../../state/messaging_state.dart';
import '../../state/notification_state.dart';
import '../../state/search_state.dart';
import '../../widgets/animations/fade_slide_in.dart';
import '../../widgets/category_scroll.dart';
import '../../widgets/landmark_picker_sheet.dart';
import '../../widgets/purpose_scroll.dart';
import '../../widgets/hover_lift.dart';
import '../../widgets/listing_card_modern.dart';
import '../../widgets/notification_bell.dart';
import '../notifications/notification_center_screen.dart';
import 'listing_detail_screen.dart';

class ExploreScreen extends StatefulWidget {
  const ExploreScreen({
    super.key,
    required this.repository,
    required this.authState,
    required this.favoritesState,
    required this.searchState,
    this.notificationState,
    this.bookingLifecycleService,
    this.bookingMessagingCoordinator,
    this.messagingState,
  });

  final MusafirRepository repository;
  final AuthStateNotifier authState;
  final FavoritesStateNotifier favoritesState;
  final SearchStateNotifier searchState;
  final NotificationStateNotifier? notificationState;
  final BookingLifecycleService? bookingLifecycleService;
  final BookingMessagingCoordinator? bookingMessagingCoordinator;
  final MessagingStateNotifier? messagingState;

  @override
  State<ExploreScreen> createState() => _ExploreScreenState();
}

class _ExploreScreenState extends State<ExploreScreen> {
  ListingType? _selectedType;
  final TextEditingController _searchController = TextEditingController();
  final ScrollController _scrollController = ScrollController();

  @override
  void initState() {
    super.initState();
    _scrollController.addListener(_onScroll);
  }

  @override
  void dispose() {
    _searchController.dispose();
    _scrollController.removeListener(_onScroll);
    _scrollController.dispose();
    super.dispose();
  }

  void _onScroll() {
    if (_scrollController.position.pixels >=
        _scrollController.position.maxScrollExtent * 0.8) {
      // Near bottom (80% scrolled), load more
      _loadMoreListings();
    }
  }

  Future<void> _loadMoreListings() async {
    // Search results come from a single server-side query, not the feed
    // paginator — don't load feed pages behind an active search.
    if (_searchActive ||
        widget.repository.isLoadingListings ||
        !widget.repository.hasMoreListings) {
      return;
    }
    await widget.repository.fetchNextListingsPage();
  }

  Future<void> _onRefresh() async {
    await widget.repository.resetListingsPagination();
  }

  /// Whether a server-side search is currently driving the results.
  bool get _searchActive => widget.searchState.filters.hasActiveFilters;

  /// The active guest-facing purpose (null for "Any purpose"; general is a host
  /// default, not a guest filter, so it reads as "Any").
  ListingPurpose? get _selectedPurpose {
    final tags = widget.searchState.filters.purposeTags;
    final p = tags.isEmpty ? null : tags.first;
    return (p == null || p == ListingPurpose.general) ? null : p;
  }

  Future<void> _onPurposeSelected(ListingPurpose? purpose) async {
    final filters = widget.searchState.filters;
    if (purpose == null) {
      widget.searchState.updateFilters(
          filters.copyWith(purposeTags: const [], clearLandmark: true));
      return;
    }
    final type = purpose.landmarkType;
    if (type == null) {
      widget.searchState.updateFilters(
          filters.copyWith(purposeTags: [purpose], clearLandmark: true));
      return;
    }
    // Purpose needs a landmark to rank distance from — let the guest pick one.
    final title = switch (purpose) {
      ListingPurpose.medical => 'Choose a hospital',
      ListingPurpose.exam => 'Choose an exam center',
      ListingPurpose.tourism => 'Choose an attraction',
      ListingPurpose.business => 'Choose a business hub',
      ListingPurpose.student => 'Choose a university',
      ListingPurpose.general => '',
    };
    final chosen = await showLandmarkPicker(
      context,
      repository: widget.repository,
      type: type,
      title: title,
    );
    if (chosen == null) return; // dismissed — leave current filters untouched
    widget.searchState.updateFilters(filters.copyWith(
      purposeTags: [purpose],
      landmark: chosen,
      radiusMeters: 15000,
    ));
  }

  List<Listing> get _filteredListings {
    // When a search is active, show its server-side results (already ranked and
    // filtered to available + host_available) — even if empty, so a no-match
    // search shows the empty state instead of falling back to the whole feed.
    // Otherwise show the default ranked feed.
    var listings = _searchActive
        ? widget.searchState.results
        : widget.repository.listings
            .where((l) => l.available && l.hostAvailable)
            .toList();
    if (_selectedType != null) {
      listings = listings.where((l) => l.type == _selectedType).toList();
    }
    // Exclude own listings when logged in
    final currentUserId = widget.authState.currentUser?.id;
    if (currentUserId != null) {
      listings = listings.where((l) => l.hostId != currentUserId).toList();
    }
    // Hide listings from hosts this user has blocked.
    final blocked = widget.repository.blockedUserIds;
    if (blocked.isNotEmpty) {
      listings = listings.where((l) => !blocked.contains(l.hostId)).toList();
    }
    return listings;
  }

  void _openListingDetail(Listing listing) {
    Navigator.of(context).push(
      MaterialPageRoute(
        builder: (context) => ListingDetailScreen(
          listing: listing,
          repository: widget.repository,
          authState: widget.authState,
          favoritesState: widget.favoritesState,
          messagingState: widget.messagingState,
        ),
      ),
    );
  }

  void _openSearch() {
    showModalBottomSheet(
      context: context,
      isScrollControlled: true,
      backgroundColor: Colors.transparent,
      builder: (context) => _SearchSheet(
        searchController: _searchController,
        searchState: widget.searchState,
        onSearch: () {
          Navigator.pop(context);
          setState(() {});
        },
        repository: widget.repository,
      ),
    );
  }

  void _openNotificationCenter() {
    if (widget.notificationState == null) return;
    if (widget.bookingLifecycleService == null) return;

    Navigator.push(
      context,
      MaterialPageRoute(
        builder: (context) => NotificationCenterScreen(
          notificationState: widget.notificationState!,
          repository: widget.repository,
          bookingLifecycleService: widget.bookingLifecycleService!,
          authState: widget.authState,
          messagingState: widget.messagingState,
          bookingMessagingCoordinator: widget.bookingMessagingCoordinator,
        ),
      ),
    );
  }

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    final wide = Responsive.isWide(context);

    return Scaffold(
      body: SafeArea(
        child: Column(
          children: [
            // Desktop hero title — gives the landing an identity above the
            // search field. Hidden on mobile, which keeps its compact layout.
            if (wide)
              Padding(
                padding: const EdgeInsets.fromLTRB(24, 22, 24, 2),
                child: Column(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    Text(
                      'Find your stay',
                      style: theme.textTheme.headlineSmall?.copyWith(
                        fontWeight: FontWeight.w800,
                        letterSpacing: -0.5,
                      ),
                    ),
                    const SizedBox(height: 2),
                    Text(
                      'Rooms, seats and full houses across Bangladesh',
                      style: theme.textTheme.bodyMedium?.copyWith(
                        color: theme.colorScheme.onSurfaceVariant,
                      ),
                    ),
                  ],
                ),
              ),
            // Search bar with notification bell
            Padding(
              padding: wide
                  ? const EdgeInsets.fromLTRB(24, 12, 24, 10)
                  : const EdgeInsets.fromLTRB(16, 10, 16, 8),
              child: Row(
                children: [
                  Expanded(
                    child: GestureDetector(
                      onTap: _openSearch,
                      child: Container(
                        height: 44,
                        padding: const EdgeInsets.symmetric(horizontal: 14),
                        decoration: BoxDecoration(
                          color: theme.colorScheme.surface,
                          borderRadius: BorderRadius.circular(32),
                          border: Border.all(
                            color: theme.colorScheme.outlineVariant,
                          ),
                          boxShadow: [
                            BoxShadow(
                              color: Colors.black.withValues(alpha: 0.05),
                              blurRadius: 10,
                              offset: const Offset(0, 2),
                            ),
                          ],
                        ),
                        child: Row(
                          children: [
                            // Balances the trailing icon so the label stays
                            // visually centered.
                            const SizedBox(width: 24),
                            Expanded(
                              child: Row(
                                mainAxisAlignment: MainAxisAlignment.center,
                                children: [
                                  Icon(
                                    Icons.search,
                                    size: 20,
                                    color: theme.colorScheme.primary,
                                  ),
                                  const SizedBox(width: 8),
                                  Flexible(
                                    child: Text(
                                      widget.searchState.filters.location ??
                                          'Search your comfort',
                                      style:
                                          theme.textTheme.bodyMedium?.copyWith(
                                        fontWeight: FontWeight.w600,
                                      ),
                                      maxLines: 1,
                                      overflow: TextOverflow.ellipsis,
                                    ),
                                  ),
                                ],
                              ),
                            ),
                            if (widget.searchState.filters.hasActiveFilters)
                              GestureDetector(
                                onTap: () {
                                  widget.searchState.clearFilters();
                                  _searchController.clear();
                                  setState(() {});
                                },
                                child: Icon(
                                  Icons.close,
                                  size: 18,
                                  color: theme.colorScheme.onSurfaceVariant,
                                ),
                              )
                            else
                              const SizedBox(width: 18),
                            const SizedBox(width: 6),
                          ],
                        ),
                      ),
                    ),
                  ),
                  // Top Hosts leaderboard — gold chip so it reads as a reward
                  // worth tapping, not just another grey action.
                  const SizedBox(width: 6),
                  Tooltip(
                    message: 'Top Hosts',
                    child: Material(
                      shape: const CircleBorder(),
                      clipBehavior: Clip.antiAlias,
                      color: Colors.transparent,
                      child: InkWell(
                        onTap: () => Navigator.of(context).push(
                          MaterialPageRoute(
                            builder: (_) => HostLeaderboardScreen(
                              repository: widget.repository,
                              currentUserId: widget.authState.currentUser?.id,
                            ),
                          ),
                        ),
                        child: Container(
                          padding: const EdgeInsets.all(9),
                          decoration: BoxDecoration(
                            gradient: const LinearGradient(
                              colors: [Color(0xFFFFB300), Color(0xFFFF8F00)],
                              begin: Alignment.topLeft,
                              end: Alignment.bottomRight,
                            ),
                            shape: BoxShape.circle,
                            boxShadow: [
                              BoxShadow(
                                color: const Color(0xFFFFB300)
                                    .withValues(alpha: 0.45),
                                blurRadius: 12,
                                offset: const Offset(0, 3),
                              ),
                            ],
                          ),
                          child: const Icon(Icons.emoji_events_rounded,
                              size: 22, color: Colors.white),
                        ),
                      ),
                    ),
                  ),
                  // Notification bell
                  if (widget.notificationState != null) ...[
                    const SizedBox(width: 4),
                    AnimatedNotificationBell(
                      notificationState: widget.notificationState!,
                      onTap: _openNotificationCenter,
                    ),
                  ],
                ],
              ),
            ),

            // Category scroll
            CategoryScroll(
              selectedType: _selectedType,
              onTypeSelected: (type) {
                setState(() => _selectedType = type);
              },
            ),

            // Purpose scroll (stay near a hospital / exam center / …).
            ListenableBuilder(
              listenable: widget.searchState,
              builder: (context, _) => PurposeScroll(
                selected: _selectedPurpose,
                onSelected: _onPurposeSelected,
              ),
            ),

            const Divider(height: 1),

            // Listings grid with pull-to-refresh
            Expanded(
              child: ListenableBuilder(
                listenable: Listenable.merge([
                  widget.repository,
                  widget.favoritesState,
                  widget.searchState,
                ]),
                builder: (context, _) {
                  final listings = _filteredListings;
                  final isLoading = _searchActive
                      ? widget.searchState.isSearching
                      : widget.repository.isLoadingListings;

                  // Show loading indicator when loading and no listings yet
                  if (listings.isEmpty && isLoading) {
                    return const Center(
                      child: CircularProgressIndicator(),
                    );
                  }

                  // Show empty state only when not loading and truly no listings
                  if (listings.isEmpty && !isLoading) {
                    return RefreshIndicator(
                      onRefresh: () => widget.repository.refresh(),
                      child: CustomScrollView(
                        physics: const AlwaysScrollableScrollPhysics(),
                        slivers: [
                          SliverFillRemaining(
                            child: Center(
                              child: Column(
                                mainAxisAlignment: MainAxisAlignment.center,
                                children: [
                                  Icon(
                                    Icons.search_off,
                                    size: 64,
                                    color: theme.colorScheme.onSurfaceVariant,
                                  ),
                                  const SizedBox(height: 16),
                                  Text(
                                    'No listings found',
                                    style: theme.textTheme.titleMedium,
                                  ),
                                  const SizedBox(height: 8),
                                  Text(
                                    'Try adjusting your filters',
                                    style: theme.textTheme.bodyMedium?.copyWith(
                                      color: theme.colorScheme.onSurfaceVariant,
                                    ),
                                  ),
                                ],
                              ),
                            ),
                          ),
                        ],
                      ),
                    );
                  }

                  // Airbnb-style curated rows whenever browsing (no active
                  // search). `listings` is already filtered by the selected
                  // category chip, so picking Room/Seat/Full house re-curates
                  // the same rows within that type. Only an explicit search
                  // (incl. a city "See all") falls back to the grid.
                  if (!_searchActive) {
                    return RefreshIndicator(
                      onRefresh: _onRefresh,
                      child: _buildCategoryRows(listings),
                    );
                  }

                  return RefreshIndicator(
                    onRefresh: _onRefresh,
                    child: CustomScrollView(
                      controller: _scrollController,
                      physics: const AlwaysScrollableScrollPhysics(),
                      slivers: [
                        // Proximity banner: which ring the results came from,
                        // or that we fell back to the nearest stays.
                        if (widget.searchState.matchedRadiusMeters != null ||
                            widget.searchState.usedNearestFallback)
                          SliverToBoxAdapter(
                            child: _ProximityBanner(
                              count: listings.length,
                              radiusMeters:
                                  widget.searchState.matchedRadiusMeters,
                              usedNearestFallback:
                                  widget.searchState.usedNearestFallback,
                              placeLabel: widget.searchState.filters.location,
                            ),
                          ),
                        SliverPadding(
                          padding: const EdgeInsets.all(16),
                          sliver: SliverGrid(
                            // Max-extent so the column count grows with width:
                            // 2 on phones, 3–4 across the desktop content panel,
                            // with cards kept a consistent, readable size.
                            gridDelegate:
                                const SliverGridDelegateWithMaxCrossAxisExtent(
                              maxCrossAxisExtent: 300,
                              mainAxisSpacing: 16,
                              crossAxisSpacing: 12,
                              // ~square photo like Airbnb (the photo takes
                              // 5/7 of the cell height in ListingCardModern).
                              childAspectRatio: 0.72,
                            ),
                            delegate: SliverChildBuilderDelegate(
                              (context, index) {
                                final listing = listings[index];
                                // Staggered entrance; modulo keeps the delay
                                // small for items revealed far down on scroll.
                                return FadeSlideIn(
                                  delay:
                                      Duration(milliseconds: 45 * (index % 6)),
                                  child: HoverLift(
                                    child: ListingCardModern(
                                      listing: listing,
                                      isFavorite: widget.favoritesState
                                          .isFavorite(listing.id),
                                      onTap: () => _openListingDetail(listing),
                                      onFavoriteTap: () {
                                        widget.favoritesState
                                            .toggleFavorite(listing.id);
                                      },
                                    ),
                                  ),
                                );
                              },
                              childCount: listings.length,
                            ),
                          ),
                        ),
                        // Loading indicator or end message
                        SliverToBoxAdapter(
                          child: Padding(
                            padding: const EdgeInsets.all(16),
                            child: Center(
                              child: widget.repository.isLoadingListings
                                  ? const SizedBox(
                                      height: 32,
                                      width: 32,
                                      child: CircularProgressIndicator(
                                        strokeWidth: 2,
                                      ),
                                    )
                                  : !widget.repository.hasMoreListings &&
                                          listings.isNotEmpty
                                      ? Text(
                                          'No more listings',
                                          style: theme.textTheme.bodySmall
                                              ?.copyWith(
                                            color: theme
                                                .colorScheme.onSurfaceVariant,
                                          ),
                                        )
                                      : const SizedBox.shrink(),
                            ),
                          ),
                        ),
                      ],
                    ),
                  );
                },
              ),
            ),
          ],
        ),
      ),
    );
  }

  /// Airbnb-style curated rows shown while browsing (no search, no single
  /// category filter): Popular, Featured, Top rated, Budget-friendly, and
  /// location-wise sections — each a horizontal, left-to-right scrolling list.
  Widget _buildCategoryRows(List<Listing> listings) {
    final sections = <Widget>[];

    void add(String title, List<Listing> items, {VoidCallback? onSeeAll}) {
      if (items.isEmpty) return;
      sections.add(
        _CategorySection(
          title: title,
          listings: items.take(12).toList(),
          favoritesState: widget.favoritesState,
          onOpen: _openListingDetail,
          onSeeAll: onSeeAll,
        ),
      );
    }

    // Popular — most reviewed, then highest rated.
    final popular = [...listings]..sort((a, b) {
        final byReviews = b.reviewCount.compareTo(a.reviewCount);
        if (byReviews != 0) return byReviews;
        return (b.rating ?? 0).compareTo(a.rating ?? 0);
      });
    add(
      'Popular',
      popular.where((l) => l.reviewCount > 0 || (l.rating ?? 0) > 0).toList(),
    );

    // Budget-friendly — cheapest first (surfaced right after Popular).
    final budget = listings.where((l) => l.displayPrice > 0).toList()
      ..sort((a, b) => a.displayPrice.compareTo(b.displayPrice));
    add('Budget-friendly stays', budget);

    // Newly available — most recently created first.
    final newest = listings.where((l) => l.createdAt != null).toList()
      ..sort((a, b) => b.createdAt!.compareTo(a.createdAt!));
    add('Newly available', newest);

    // Featured stays — superhosts.
    add('Featured stays', listings.where((l) => l.isSuperhost).toList());

    // Top rated.
    final topRated = listings.where((l) => (l.rating ?? 0) > 0).toList()
      ..sort((a, b) => (b.rating ?? 0).compareTo(a.rating ?? 0));
    add('Top rated', topRated);

    // Location-wise — the busiest cities, "Stays in {city}". "See all" runs a
    // location search so the grid shows every stay there.
    final byCity = <String, List<Listing>>{};
    for (final l in listings) {
      final c = l.city?.trim();
      if (c == null || c.isEmpty) continue;
      (byCity[c] ??= []).add(l);
    }
    final cities = byCity.keys.toList()
      ..sort((a, b) => byCity[b]!.length.compareTo(byCity[a]!.length));
    for (final city in cities.take(3)) {
      if (byCity[city]!.length < 2) continue;
      add(
        'Stays in $city',
        byCity[city]!,
        onSeeAll: () {
          widget.searchState.updateLocation(location: city);
          setState(() {});
        },
      );
    }

    // Fallback so the screen is never blank when nothing matched a curation.
    if (sections.isEmpty) add('All stays', listings);

    return ListView(
      controller: _scrollController,
      physics: const AlwaysScrollableScrollPhysics(),
      padding: const EdgeInsets.only(top: 8, bottom: 24),
      children: sections,
    );
  }
}

/// Tells the guest how the proximity results were found: the radius ring that
/// matched ("12 stays within 3 km of Dakshinkhan"), or that no ring matched
/// and these are simply the nearest stays.
class _ProximityBanner extends StatelessWidget {
  const _ProximityBanner({
    required this.count,
    required this.radiusMeters,
    required this.usedNearestFallback,
    required this.placeLabel,
  });

  final int count;
  final int? radiusMeters;
  final bool usedNearestFallback;
  final String? placeLabel;

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    final place = (placeLabel == null || placeLabel!.trim().isEmpty)
        ? 'the selected location'
        : placeLabel!.trim();

    final String text;
    if (usedNearestFallback) {
      text = 'No stays close to $place — showing the nearest ones instead';
    } else {
      final km = radiusMeters! / 1000;
      final kmLabel =
          km == km.roundToDouble() ? km.round().toString() : km.toString();
      text =
          '$count ${count == 1 ? 'stay' : 'stays'} within $kmLabel km of $place';
    }

    return Padding(
      padding: const EdgeInsets.fromLTRB(16, 12, 16, 0),
      child: Container(
        padding: const EdgeInsets.symmetric(horizontal: 12, vertical: 10),
        decoration: BoxDecoration(
          color: theme.colorScheme.secondaryContainer.withValues(alpha: 0.6),
          borderRadius: BorderRadius.circular(12),
        ),
        child: Row(
          children: [
            Icon(
              usedNearestFallback ? Icons.explore_outlined : Icons.near_me,
              size: 18,
              color: theme.colorScheme.onSecondaryContainer,
            ),
            const SizedBox(width: 8),
            Expanded(
              child: Text(
                text,
                style: theme.textTheme.bodySmall?.copyWith(
                  color: theme.colorScheme.onSecondaryContainer,
                  fontWeight: FontWeight.w600,
                ),
              ),
            ),
          ],
        ),
      ),
    );
  }
}

/// A single Airbnb-style category: a heading with a "See all" action and a
/// horizontal, left-to-right scrolling list of listing cards.
class _CategorySection extends StatelessWidget {
  const _CategorySection({
    required this.title,
    required this.listings,
    required this.favoritesState,
    required this.onOpen,
    required this.onSeeAll,
  });

  final String title;
  final List<Listing> listings;
  final FavoritesStateNotifier favoritesState;
  final void Function(Listing) onOpen;
  final VoidCallback? onSeeAll;

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    final wide = Responsive.isWide(context);
    // Larger cards on desktop so the carousels feel substantial; the width /
    // height ratio is kept at ~0.72 to match ListingCardModern's layout.
    final cardWidth = wide ? 242.0 : 186.0;
    final rowHeight = wide ? 336.0 : 258.0;

    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        Padding(
          padding: wide
              ? const EdgeInsets.fromLTRB(24, 22, 16, 12)
              : const EdgeInsets.fromLTRB(16, 14, 8, 10),
          child: Row(
            children: [
              Expanded(
                child: Text(
                  title,
                  style: (wide
                          ? theme.textTheme.titleLarge
                          : theme.textTheme.titleMedium)
                      ?.copyWith(fontWeight: FontWeight.w800),
                ),
              ),
              if (onSeeAll != null)
                TextButton(
                  onPressed: onSeeAll,
                  style: TextButton.styleFrom(
                    visualDensity: VisualDensity.compact,
                    tapTargetSize: MaterialTapTargetSize.shrinkWrap,
                  ),
                  child: const Text('See all'),
                ),
            ],
          ),
        ),
        SizedBox(
          height: rowHeight,
          child: ListView.separated(
            scrollDirection: Axis.horizontal,
            padding: EdgeInsets.symmetric(horizontal: wide ? 24 : 16),
            itemCount: listings.length,
            separatorBuilder: (_, __) => SizedBox(width: wide ? 16 : 12),
            itemBuilder: (context, index) {
              final listing = listings[index];
              return SizedBox(
                width: cardWidth,
                // Cursor-only hover here (scale would be cropped by the
                // fixed-height horizontal list); the grid uses a scale lift.
                child: HoverLift(
                  scale: 1.0,
                  child: ListingCardModern(
                    listing: listing,
                    isFavorite: favoritesState.isFavorite(listing.id),
                    onTap: () => onOpen(listing),
                    onFavoriteTap: () =>
                        favoritesState.toggleFavorite(listing.id),
                  ),
                ),
              );
            },
          ),
        ),
      ],
    );
  }
}

class _SearchSheet extends StatefulWidget {
  const _SearchSheet({
    required this.searchController,
    required this.searchState,
    required this.onSearch,
    required this.repository,
  });

  final TextEditingController searchController;
  final SearchStateNotifier searchState;
  final VoidCallback onSearch;
  final MusafirRepository repository;

  @override
  State<_SearchSheet> createState() => _SearchSheetState();
}

class _SearchSheetState extends State<_SearchSheet> {
  late int _guestCount;
  DateTimeRange? _dateRange;
  List<ListingType> _selectedTypes = [];
  SearchDateMode _dateMode = SearchDateMode.dateRange;
  DateTime? _singleDate;
  TimeOfDay? _startTime;
  TimeOfDay? _endTime;

  // Location suggestions: instant city matches from loaded listings, plus
  // debounced Google Places type-ahead (any area / address / POI in BD).
  List<_CitySuggestion> _suggestions = [];
  List<PlaceSuggestion> _placeSuggestions = [];
  bool _showSuggestions = false;
  bool _searchingPlaces = false;
  String? _resolvingSuggestionId;
  Timer? _placeDebounce;
  // Guards against out-of-order autocomplete responses while typing.
  int _placeRequestId = 0;

  // A resolved center point for proximity search ("use my location" or a
  // previously geocoded place). Cleared whenever the guest edits the text —
  // the point belonged to the old text.
  double? _pickedLat;
  double? _pickedLng;
  bool _settingTextProgrammatically = false;
  bool _locatingMe = false;
  bool _resolvingPlace = false;

  @override
  void initState() {
    super.initState();
    final filters = widget.searchState.filters;
    _guestCount = filters.guestCount;
    _selectedTypes = List.from(filters.propertyTypes);
    _dateMode = filters.dateMode;
    _settingTextProgrammatically = true;
    widget.searchController.text = filters.location ?? '';
    _settingTextProgrammatically = false;
    _pickedLat = filters.latitude;
    _pickedLng = filters.longitude;

    if (filters.checkIn != null && filters.checkOut != null) {
      _dateRange = DateTimeRange(
        start: filters.checkIn!,
        end: filters.checkOut!,
      );
    }

    _singleDate = filters.singleDate;
    _startTime = filters.startTime;
    _endTime = filters.endTime;

    // Listen for location input changes
    widget.searchController.addListener(_onLocationChanged);
  }

  @override
  void dispose() {
    _placeDebounce?.cancel();
    widget.searchController.removeListener(_onLocationChanged);
    super.dispose();
  }

  void _onLocationChanged() {
    if (_settingTextProgrammatically) return;
    // Manual edit: any previously resolved point no longer matches the text.
    _pickedLat = null;
    _pickedLng = null;
    final query = widget.searchController.text.toLowerCase();
    _placeDebounce?.cancel();
    if (query.isEmpty) {
      setState(() {
        _suggestions = [];
        _placeSuggestions = [];
        _searchingPlaces = false;
        _showSuggestions = false;
      });
      return;
    }

    // Extract unique cities with counts from listings
    final cityMap = <String, int>{};
    for (final listing in widget.repository.listings) {
      final city = listing.city;
      if (city != null && city.isNotEmpty) {
        cityMap[city] = (cityMap[city] ?? 0) + 1;
      }
    }

    // Filter cities matching the query
    final filtered = cityMap.entries
        .where((e) => e.key.toLowerCase().contains(query))
        .map((e) => _CitySuggestion(city: e.key, count: e.value))
        .toList();

    // Sort by count (most listings first) and limit to 5
    filtered.sort((a, b) => b.count.compareTo(a.count));
    final limited = filtered.take(5).toList();

    // Google type-ahead from 3 letters, debounced; city matches stay instant.
    final raw = widget.searchController.text.trim();
    final wantPlaces = raw.length >= 3;
    if (wantPlaces) {
      _placeDebounce =
          Timer(const Duration(milliseconds: 300), () => _fetchPlaces(raw));
    }

    setState(() {
      _suggestions = limited;
      _searchingPlaces = wantPlaces;
      if (!wantPlaces) _placeSuggestions = [];
      _showSuggestions =
          limited.isNotEmpty || _placeSuggestions.isNotEmpty || wantPlaces;
    });
  }

  Future<void> _fetchPlaces(String query) async {
    final id = ++_placeRequestId;
    final results =
        await PlacesService().suggest(query, establishmentsOnly: false);
    if (!mounted || id != _placeRequestId) return;
    // Drop predictions that duplicate a listing-city row already shown.
    final cityNames =
        _suggestions.map((c) => c.city.toLowerCase().trim()).toSet();
    setState(() {
      _placeSuggestions = results
          .where((s) => !cityNames.contains(s.name.toLowerCase().trim()))
          .toList();
      _searchingPlaces = false;
      _showSuggestions =
          _suggestions.isNotEmpty || _placeSuggestions.isNotEmpty;
    });
  }

  void _selectSuggestion(_CitySuggestion suggestion) {
    _placeDebounce?.cancel();
    _placeRequestId++; // invalidate any in-flight autocomplete
    widget.searchController.text = suggestion.city;
    widget.searchController.selection = TextSelection.fromPosition(
      TextPosition(offset: suggestion.city.length),
    );
    setState(() {
      _showSuggestions = false;
      _placeSuggestions = [];
      _searchingPlaces = false;
    });
  }

  /// A Google prediction was tapped: put its name in the field and resolve it
  /// to coordinates so Search runs the expanding-ring proximity search.
  Future<void> _selectPlaceSuggestion(PlaceSuggestion s) async {
    if (_resolvingSuggestionId != null) return;
    _placeDebounce?.cancel();
    _placeRequestId++;
    _settingTextProgrammatically = true;
    widget.searchController.text = s.name;
    widget.searchController.selection = TextSelection.fromPosition(
      TextPosition(offset: s.name.length),
    );
    _settingTextProgrammatically = false;
    setState(() => _resolvingSuggestionId = s.placeId);
    final place = await PlacesService().resolve(s, type: '');
    if (!mounted) return;
    setState(() {
      _resolvingSuggestionId = null;
      _showSuggestions = false;
      _placeSuggestions = [];
      _searchingPlaces = false;
      // If resolving failed, _applySearch will geocode the text as fallback.
      if (place != null) {
        _pickedLat = place.latitude;
        _pickedLng = place.longitude;
      }
    });
  }

  Future<void> _useCurrentLocation() async {
    setState(() => _locatingMe = true);
    final position = await LocationService().getCurrentLocation();
    if (!mounted) return;
    if (position == null) {
      setState(() => _locatingMe = false);
      ScaffoldMessenger.of(context).showSnackBar(
        const SnackBar(
          content: Text("Couldn't get your location — check permission."),
        ),
      );
      return;
    }
    // Nicer label than raw coordinates where the platform can reverse-geocode
    // (mobile); web just shows "Current location".
    final label = await LocationService()
            .getAddressFromCoordinates(position.latitude, position.longitude) ??
        'Current location';
    if (!mounted) return;
    _settingTextProgrammatically = true;
    widget.searchController.text = label;
    _settingTextProgrammatically = false;
    setState(() {
      _pickedLat = position.latitude;
      _pickedLng = position.longitude;
      _locatingMe = false;
      _suggestions = [];
      _showSuggestions = false;
    });
  }

  /// Whether the query matches a city we already know listings for — then a
  /// classic text search (all stays in that city) beats a 1 km proximity ring
  /// centered on the city's geometric center.
  bool _isKnownCity(String query) {
    final q = query.trim().toLowerCase();
    return widget.repository.listings
        .any((l) => (l.city ?? '').trim().toLowerCase() == q);
  }

  Future<void> _selectDateRange() async {
    final picked = await showDateRangePicker(
      context: context,
      firstDate: DateTime.now(),
      lastDate: DateTime.now().add(const Duration(days: 365)),
      initialDateRange: _dateRange,
    );
    if (picked != null) {
      setState(() => _dateRange = picked);
    }
  }

  Future<void> _selectSingleDate() async {
    final picked = await showDatePicker(
      context: context,
      initialDate: _singleDate ?? DateTime.now(),
      firstDate: DateTime.now(),
      lastDate: DateTime.now().add(const Duration(days: 365)),
    );
    if (picked != null) {
      setState(() => _singleDate = picked);
    }
  }

  Future<void> _selectStartTime() async {
    final picked = await showTimePicker(
      context: context,
      initialTime: _startTime ?? const TimeOfDay(hour: 9, minute: 0),
    );
    if (picked != null) {
      setState(() => _startTime = picked);
    }
  }

  Future<void> _selectEndTime() async {
    final picked = await showTimePicker(
      context: context,
      initialTime: _endTime ?? const TimeOfDay(hour: 17, minute: 0),
    );
    if (picked != null) {
      setState(() => _endTime = picked);
    }
  }

  void _togglePropertyType(ListingType type) {
    setState(() {
      if (_selectedTypes.contains(type)) {
        _selectedTypes.remove(type);
      } else {
        _selectedTypes.add(type);
      }
    });
  }

  Future<void> _applySearch() async {
    final text = widget.searchController.text.trim();
    double? lat = _pickedLat;
    double? lng = _pickedLng;

    // No point yet and the text isn't a known listing city → try to resolve
    // it to coordinates so the search runs by expanding proximity rings.
    // If geocoding finds nothing, fall through to the classic text search.
    if (lat == null && text.isNotEmpty && !_isKnownCity(text)) {
      setState(() => _resolvingPlace = true);
      final place = await GeocodingService().geocode(text);
      if (!mounted) return;
      setState(() => _resolvingPlace = false);
      if (place != null) {
        lat = place.latitude;
        lng = place.longitude;
      }
    }

    widget.searchState.updateFilters(
      widget.searchState.filters.copyWith(
        location: widget.searchController.text.isEmpty
            ? null
            : widget.searchController.text,
        latitude: lat,
        longitude: lng,
        clearCoordinates: lat == null || lng == null,
        checkIn:
            _dateMode == SearchDateMode.dateRange ? _dateRange?.start : null,
        checkOut:
            _dateMode == SearchDateMode.dateRange ? _dateRange?.end : null,
        guestCount: _guestCount,
        propertyTypes: _selectedTypes,
        dateMode: _dateMode,
        singleDate:
            _dateMode == SearchDateMode.singleDateWithTime ? _singleDate : null,
        startTime:
            _dateMode == SearchDateMode.singleDateWithTime ? _startTime : null,
        endTime:
            _dateMode == SearchDateMode.singleDateWithTime ? _endTime : null,
        clearLocation: widget.searchController.text.isEmpty,
        clearDates: _dateMode == SearchDateMode.dateRange && _dateRange == null,
        clearTime: _dateMode == SearchDateMode.dateRange,
      ),
    );
    widget.onSearch();
  }

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);

    return Container(
      decoration: BoxDecoration(
        color: theme.colorScheme.surface,
        borderRadius: const BorderRadius.vertical(top: Radius.circular(24)),
      ),
      padding: EdgeInsets.only(
        bottom: MediaQuery.of(context).viewInsets.bottom,
      ),
      child: SingleChildScrollView(
        padding: const EdgeInsets.all(24),
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.stretch,
          mainAxisSize: MainAxisSize.min,
          children: [
            // Handle
            Center(
              child: Container(
                width: 40,
                height: 4,
                decoration: BoxDecoration(
                  color: theme.colorScheme.outlineVariant,
                  borderRadius: BorderRadius.circular(2),
                ),
              ),
            ),
            const SizedBox(height: 24),

            // Title
            Text(
              'Search',
              style: theme.textTheme.headlineSmall?.copyWith(
                fontWeight: FontWeight.bold,
              ),
            ),
            const SizedBox(height: 24),

            // Property Type Filter
            Text(
              'Property Type',
              style: theme.textTheme.titleSmall?.copyWith(
                fontWeight: FontWeight.w600,
              ),
            ),
            const SizedBox(height: 12),
            Wrap(
              spacing: 8,
              runSpacing: 8,
              children: [
                FilterChip(
                  label: const Text('All'),
                  selected: _selectedTypes.isEmpty,
                  onSelected: (_) {
                    setState(() => _selectedTypes.clear());
                  },
                ),
                ...ListingType.values.map((type) => FilterChip(
                      label: Text(type.title),
                      selected: _selectedTypes.contains(type),
                      onSelected: (_) => _togglePropertyType(type),
                    )),
              ],
            ),
            const SizedBox(height: 20),

            // Location with suggestions
            Column(
              crossAxisAlignment: CrossAxisAlignment.stretch,
              children: [
                TextField(
                  controller: widget.searchController,
                  decoration: InputDecoration(
                    labelText: 'Where',
                    hintText: 'Area, address or place — e.g. Dakshinkhan',
                    prefixIcon: const Icon(Icons.search),
                    border: OutlineInputBorder(
                      borderRadius: BorderRadius.circular(12),
                    ),
                  ),
                ),
                Align(
                  alignment: Alignment.centerLeft,
                  child: TextButton.icon(
                    onPressed: _locatingMe ? null : _useCurrentLocation,
                    icon: _locatingMe
                        ? const SizedBox(
                            width: 16,
                            height: 16,
                            child: CircularProgressIndicator(strokeWidth: 2),
                          )
                        : const Icon(Icons.my_location, size: 18),
                    label: const Text('Use my current location'),
                  ),
                ),
                // Suggestions dropdown: listing cities first (instant), then
                // Google type-ahead predictions (any area / address / POI).
                if (_showSuggestions &&
                    (_suggestions.isNotEmpty ||
                        _placeSuggestions.isNotEmpty ||
                        _searchingPlaces))
                  Container(
                    margin: const EdgeInsets.only(top: 4),
                    decoration: BoxDecoration(
                      color: theme.colorScheme.surface,
                      border: Border.all(color: theme.colorScheme.outline),
                      borderRadius: BorderRadius.circular(12),
                      boxShadow: [
                        BoxShadow(
                          color: Colors.black.withValues(alpha: 0.1),
                          blurRadius: 8,
                          offset: const Offset(0, 2),
                        ),
                      ],
                    ),
                    child: Column(
                      mainAxisSize: MainAxisSize.min,
                      children: [
                        ..._suggestions.map((suggestion) {
                          return InkWell(
                            onTap: () => _selectSuggestion(suggestion),
                            borderRadius: BorderRadius.circular(8),
                            child: Padding(
                              padding: const EdgeInsets.symmetric(
                                horizontal: 16,
                                vertical: 12,
                              ),
                              child: Row(
                                children: [
                                  Icon(
                                    Icons.location_on_outlined,
                                    color: theme.colorScheme.primary,
                                    size: 20,
                                  ),
                                  const SizedBox(width: 12),
                                  Expanded(
                                    child: Text(
                                      '${suggestion.city} (${suggestion.count} listing${suggestion.count > 1 ? 's' : ''})',
                                      style: theme.textTheme.bodyMedium,
                                    ),
                                  ),
                                ],
                              ),
                            ),
                          );
                        }),
                        if (_suggestions.isNotEmpty &&
                            (_placeSuggestions.isNotEmpty || _searchingPlaces))
                          const Divider(height: 1),
                        if (_searchingPlaces && _placeSuggestions.isEmpty)
                          const Padding(
                            padding: EdgeInsets.symmetric(vertical: 12),
                            child: SizedBox(
                              width: 16,
                              height: 16,
                              child: CircularProgressIndicator(strokeWidth: 2),
                            ),
                          ),
                        ..._placeSuggestions.map((s) {
                          final resolving = _resolvingSuggestionId == s.placeId;
                          return InkWell(
                            onTap: _resolvingSuggestionId != null
                                ? null
                                : () => _selectPlaceSuggestion(s),
                            borderRadius: BorderRadius.circular(8),
                            child: Padding(
                              padding: const EdgeInsets.symmetric(
                                horizontal: 16,
                                vertical: 12,
                              ),
                              child: Row(
                                children: [
                                  Icon(
                                    Icons.travel_explore_rounded,
                                    color: theme.colorScheme.onSurfaceVariant,
                                    size: 20,
                                  ),
                                  const SizedBox(width: 12),
                                  Expanded(
                                    child: Column(
                                      crossAxisAlignment:
                                          CrossAxisAlignment.start,
                                      children: [
                                        Text(
                                          s.name,
                                          style: theme.textTheme.bodyMedium,
                                          maxLines: 1,
                                          overflow: TextOverflow.ellipsis,
                                        ),
                                        if (s.label.isNotEmpty)
                                          Text(
                                            s.label,
                                            style: theme.textTheme.bodySmall
                                                ?.copyWith(
                                              color: theme
                                                  .colorScheme.onSurfaceVariant,
                                            ),
                                            maxLines: 1,
                                            overflow: TextOverflow.ellipsis,
                                          ),
                                      ],
                                    ),
                                  ),
                                  if (resolving)
                                    const SizedBox(
                                      width: 16,
                                      height: 16,
                                      child: CircularProgressIndicator(
                                          strokeWidth: 2),
                                    ),
                                ],
                              ),
                            ),
                          );
                        }),
                      ],
                    ),
                  ),
              ],
            ),
            const SizedBox(height: 20),

            // Date Mode Toggle
            Text(
              'When',
              style: theme.textTheme.titleSmall?.copyWith(
                fontWeight: FontWeight.w600,
              ),
            ),
            const SizedBox(height: 12),
            SegmentedButton<SearchDateMode>(
              segments: const [
                ButtonSegment(
                  value: SearchDateMode.dateRange,
                  label: Text('Date Range'),
                  icon: Icon(Icons.date_range),
                ),
                ButtonSegment(
                  value: SearchDateMode.singleDateWithTime,
                  label: Text('Single Day'),
                  icon: Icon(Icons.schedule),
                ),
              ],
              selected: {_dateMode},
              onSelectionChanged: (selected) {
                setState(() => _dateMode = selected.first);
              },
            ),
            const SizedBox(height: 16),

            // Date Range Selection (shown when dateRange mode)
            if (_dateMode == SearchDateMode.dateRange) ...[
              GestureDetector(
                onTap: _selectDateRange,
                child: Container(
                  padding: const EdgeInsets.all(16),
                  decoration: BoxDecoration(
                    border: Border.all(color: theme.colorScheme.outline),
                    borderRadius: BorderRadius.circular(12),
                  ),
                  child: Row(
                    children: [
                      const Icon(Icons.calendar_today),
                      const SizedBox(width: 12),
                      Expanded(
                        child: Column(
                          crossAxisAlignment: CrossAxisAlignment.start,
                          children: [
                            Text(
                              'Check-in - Check-out',
                              style: theme.textTheme.labelMedium?.copyWith(
                                color: theme.colorScheme.onSurfaceVariant,
                              ),
                            ),
                            Text(
                              _dateRange != null
                                  ? '${_formatDate(_dateRange!.start)} - ${_formatDate(_dateRange!.end)}'
                                  : 'Select dates',
                              style: theme.textTheme.bodyLarge,
                            ),
                          ],
                        ),
                      ),
                      if (_dateRange != null)
                        IconButton(
                          icon: const Icon(Icons.close),
                          onPressed: () => setState(() => _dateRange = null),
                        ),
                    ],
                  ),
                ),
              ),
            ],

            // Single Date with Time Selection
            if (_dateMode == SearchDateMode.singleDateWithTime) ...[
              // Date picker
              GestureDetector(
                onTap: _selectSingleDate,
                child: Container(
                  padding: const EdgeInsets.all(16),
                  decoration: BoxDecoration(
                    border: Border.all(color: theme.colorScheme.outline),
                    borderRadius: BorderRadius.circular(12),
                  ),
                  child: Row(
                    children: [
                      const Icon(Icons.calendar_today),
                      const SizedBox(width: 12),
                      Expanded(
                        child: Column(
                          crossAxisAlignment: CrossAxisAlignment.start,
                          children: [
                            Text(
                              'Date',
                              style: theme.textTheme.labelMedium?.copyWith(
                                color: theme.colorScheme.onSurfaceVariant,
                              ),
                            ),
                            Text(
                              _singleDate != null
                                  ? _formatDate(_singleDate!)
                                  : 'Select date',
                              style: theme.textTheme.bodyLarge,
                            ),
                          ],
                        ),
                      ),
                      if (_singleDate != null)
                        IconButton(
                          icon: const Icon(Icons.close),
                          onPressed: () => setState(() => _singleDate = null),
                        ),
                    ],
                  ),
                ),
              ),
              const SizedBox(height: 12),

              // Time range row
              Row(
                children: [
                  // Start time
                  Expanded(
                    child: GestureDetector(
                      onTap: _selectStartTime,
                      child: Container(
                        padding: const EdgeInsets.all(16),
                        decoration: BoxDecoration(
                          border: Border.all(color: theme.colorScheme.outline),
                          borderRadius: BorderRadius.circular(12),
                        ),
                        child: Column(
                          crossAxisAlignment: CrossAxisAlignment.start,
                          children: [
                            Text(
                              'Start Time',
                              style: theme.textTheme.labelMedium?.copyWith(
                                color: theme.colorScheme.onSurfaceVariant,
                              ),
                            ),
                            const SizedBox(height: 4),
                            Row(
                              children: [
                                const Icon(Icons.access_time, size: 20),
                                const SizedBox(width: 8),
                                Text(
                                  _startTime != null
                                      ? _formatTime(_startTime!)
                                      : 'Select',
                                  style: theme.textTheme.bodyLarge,
                                ),
                              ],
                            ),
                          ],
                        ),
                      ),
                    ),
                  ),
                  const SizedBox(width: 12),
                  // End time
                  Expanded(
                    child: GestureDetector(
                      onTap: _selectEndTime,
                      child: Container(
                        padding: const EdgeInsets.all(16),
                        decoration: BoxDecoration(
                          border: Border.all(color: theme.colorScheme.outline),
                          borderRadius: BorderRadius.circular(12),
                        ),
                        child: Column(
                          crossAxisAlignment: CrossAxisAlignment.start,
                          children: [
                            Text(
                              'End Time',
                              style: theme.textTheme.labelMedium?.copyWith(
                                color: theme.colorScheme.onSurfaceVariant,
                              ),
                            ),
                            const SizedBox(height: 4),
                            Row(
                              children: [
                                const Icon(Icons.access_time, size: 20),
                                const SizedBox(width: 8),
                                Text(
                                  _endTime != null
                                      ? _formatTime(_endTime!)
                                      : 'Select',
                                  style: theme.textTheme.bodyLarge,
                                ),
                              ],
                            ),
                          ],
                        ),
                      ),
                    ),
                  ),
                ],
              ),
            ],
            const SizedBox(height: 16),

            // Guests
            Container(
              padding: const EdgeInsets.all(16),
              decoration: BoxDecoration(
                border: Border.all(color: theme.colorScheme.outline),
                borderRadius: BorderRadius.circular(12),
              ),
              child: Row(
                children: [
                  const Icon(Icons.people),
                  const SizedBox(width: 12),
                  Expanded(
                    child: Column(
                      crossAxisAlignment: CrossAxisAlignment.start,
                      children: [
                        Text(
                          'Who',
                          style: theme.textTheme.labelMedium?.copyWith(
                            color: theme.colorScheme.onSurfaceVariant,
                          ),
                        ),
                        Text(
                          '$_guestCount guest${_guestCount > 1 ? 's' : ''}',
                          style: theme.textTheme.bodyLarge,
                        ),
                      ],
                    ),
                  ),
                  Row(
                    children: [
                      IconButton(
                        icon: const Icon(Icons.remove_circle_outline),
                        onPressed: _guestCount > 1
                            ? () => setState(() => _guestCount--)
                            : null,
                      ),
                      Text(
                        '$_guestCount',
                        style: theme.textTheme.titleMedium,
                      ),
                      IconButton(
                        icon: const Icon(Icons.add_circle_outline),
                        onPressed: _guestCount < 16
                            ? () => setState(() => _guestCount++)
                            : null,
                      ),
                    ],
                  ),
                ],
              ),
            ),
            const SizedBox(height: 24),

            // Search button
            FilledButton(
              onPressed: _resolvingPlace ? null : _applySearch,
              style: FilledButton.styleFrom(
                padding: const EdgeInsets.symmetric(vertical: 16),
              ),
              child: Row(
                mainAxisAlignment: MainAxisAlignment.center,
                children: _resolvingPlace
                    ? const [
                        SizedBox(
                          width: 18,
                          height: 18,
                          child: CircularProgressIndicator(strokeWidth: 2),
                        ),
                        SizedBox(width: 8),
                        Text('Finding place…'),
                      ]
                    : const [
                        Icon(Icons.search),
                        SizedBox(width: 8),
                        Text('Search'),
                      ],
              ),
            ),
            const SizedBox(height: 16),
          ],
        ),
      ),
    );
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
    return '${months[date.month - 1]} ${date.day}';
  }

  String _formatTime(TimeOfDay time) {
    final hour = time.hourOfPeriod == 0 ? 12 : time.hourOfPeriod;
    final minute = time.minute.toString().padLeft(2, '0');
    final period = time.period == DayPeriod.am ? 'AM' : 'PM';
    return '$hour:$minute $period';
  }
}

/// Model for city suggestion with listing count
class _CitySuggestion {
  final String city;
  final int count;

  const _CitySuggestion({required this.city, required this.count});
}

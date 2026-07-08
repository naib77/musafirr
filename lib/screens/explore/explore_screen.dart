import 'package:flutter/material.dart';

import '../../models/listing.dart';
import '../../models/listing_type.dart';
import '../../models/search_filters.dart';
import '../../repositories/musafir_repository.dart';
import '../leaderboard/host_leaderboard_screen.dart';
import '../../services/booking/booking_lifecycle_service.dart';
import '../../services/booking/booking_messaging_coordinator.dart';
import '../../state/auth_state.dart';
import '../../state/favorites_state.dart';
import '../../state/messaging_state.dart';
import '../../state/notification_state.dart';
import '../../state/search_state.dart';
import '../../widgets/animations/fade_slide_in.dart';
import '../../widgets/category_scroll.dart';
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

    return Scaffold(
      body: SafeArea(
        child: Column(
          children: [
            // Search bar with notification bell
            Padding(
              padding: const EdgeInsets.fromLTRB(16, 10, 16, 8),
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

                  return RefreshIndicator(
                    onRefresh: _onRefresh,
                    child: CustomScrollView(
                      controller: _scrollController,
                      physics: const AlwaysScrollableScrollPhysics(),
                      slivers: [
                        SliverPadding(
                          padding: const EdgeInsets.all(16),
                          sliver: SliverGrid(
                            gridDelegate:
                                const SliverGridDelegateWithFixedCrossAxisCount(
                              crossAxisCount: 2,
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

  // Location suggestions
  List<_CitySuggestion> _suggestions = [];
  bool _showSuggestions = false;

  @override
  void initState() {
    super.initState();
    final filters = widget.searchState.filters;
    _guestCount = filters.guestCount;
    _selectedTypes = List.from(filters.propertyTypes);
    _dateMode = filters.dateMode;
    widget.searchController.text = filters.location ?? '';

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
    widget.searchController.removeListener(_onLocationChanged);
    super.dispose();
  }

  void _onLocationChanged() {
    final query = widget.searchController.text.toLowerCase();
    if (query.isEmpty) {
      setState(() {
        _suggestions = [];
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

    setState(() {
      _suggestions = limited;
      _showSuggestions = limited.isNotEmpty;
    });
  }

  void _selectSuggestion(_CitySuggestion suggestion) {
    widget.searchController.text = suggestion.city;
    widget.searchController.selection = TextSelection.fromPosition(
      TextPosition(offset: suggestion.city.length),
    );
    setState(() {
      _showSuggestions = false;
    });
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

  void _applySearch() {
    widget.searchState.updateFilters(
      widget.searchState.filters.copyWith(
        location: widget.searchController.text.isEmpty
            ? null
            : widget.searchController.text,
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
                    hintText: 'Search destinations',
                    prefixIcon: const Icon(Icons.search),
                    border: OutlineInputBorder(
                      borderRadius: BorderRadius.circular(12),
                    ),
                  ),
                ),
                // Suggestions dropdown
                if (_showSuggestions && _suggestions.isNotEmpty)
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
                      children: _suggestions.map((suggestion) {
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
                      }).toList(),
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
              onPressed: _applySearch,
              style: FilledButton.styleFrom(
                padding: const EdgeInsets.symmetric(vertical: 16),
              ),
              child: const Row(
                mainAxisAlignment: MainAxisAlignment.center,
                children: [
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

import 'dart:async';

import 'package:flutter/material.dart';
import 'package:intl/intl.dart';
import 'package:supabase_flutter/supabase_flutter.dart';

import '../../core/routing/listing_path.dart';
import '../../core/utils/responsive.dart';
import '../../models/geo_bounds.dart';
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
import '../../models/landmark.dart';
import '../../widgets/animations/fade_slide_in.dart';
import '../../widgets/modern_banner.dart';
import '../../models/voice_query.dart';
import '../../services/voice/speech_service.dart';
import '../../services/voice/voice_search_runner.dart';
import '../../widgets/voice_listening_sheet.dart';
import '../../widgets/voice_search_button.dart';
import '../../widgets/landmark_picker_sheet.dart';
import '../../widgets/purpose_scroll.dart';
import '../../widgets/hover_lift.dart';
import '../../widgets/listing_card_modern.dart';
import '../../widgets/listing_card_wide.dart';
import 'show_all_listings_screen.dart';
import '../../widgets/listing_price_map.dart';
import '../../widgets/notification_bell.dart';
import '../../widgets/results_map_sheet.dart';
import '../../widgets/top_hosts_button.dart';
import '../notifications/notification_center_screen.dart';

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
    this.isActiveTab = true,
    this.searchInShell = false,
  });

  /// True when the shell's own chrome already carries the search control — the
  /// desktop header's Where/When/Who pill, the leaderboard trophy and the
  /// notification bell (see `DesktopTopNav`). This screen then renders its feed
  /// alone, because two search fields on one page is one too many and the
  /// header's is the one that survives scrolling.
  ///
  /// An explicit flag rather than this screen re-deriving `Responsive.isWide`:
  /// the shell decides when it shows a header, and a second copy of that
  /// predicate is a second thing to keep in step. The public methods below are
  /// what the header drives this screen's search with.
  final bool searchInShell;

  /// Whether Explore is the currently-shown shell tab. Explore is kept alive in
  /// the shell's IndexedStack, so its [PopScope] stays registered on the shell
  /// route even while another tab is on screen. Gating the back interception on
  /// this flag stops a back press on some OTHER tab from also clearing an active
  /// Explore search (a single back press must do one thing).
  final bool isActiveTab;

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
  final TextEditingController _searchController = TextEditingController();

  /// True while a spoken place is being geocoded — the feed shows its normal
  /// searching state, but the mic flow needs its own flag because the search
  /// notifier is not busy yet.
  bool _voiceResolving = false;
  final ScrollController _scrollController = ScrollController();

  // When a category's "See all" is tapped, its full list is shown inline (so
  // the shell's bottom nav stays) instead of pushing a route. Non-null title +
  // list means the show-all view is on screen.
  String? _showAllTitle;
  List<Listing>? _showAllItems;

  bool get _showAllActive => _showAllItems != null;

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

  /// Drops the search and returns to the browse feed. Shared by the back
  /// button, the ✕ inside the search bar, and the system/browser back gesture,
  /// so all three leave the results the same way.
  void _clearSearch() {
    widget.searchState.clearFilters();
    _searchController.clear();
    setState(() {});
  }

  /// Called by [MainShell] when the Explore tab is re-tapped while it is
  /// already selected. Search results render inline inside this tab, so a
  /// re-tap can't switch tabs to escape them — instead it drops any active
  /// search and returns to the main feed. No-op when no search is active.
  void resetFromTabTap() {
    if (_showAllActive) _closeShowAll();
    if (_searchActive) _clearSearch();
  }

  // ── Driven by the desktop header ──────────────────────────────────────────
  //
  // With [ExploreScreen.searchInShell] the search control lives in the shell's
  // header, but the search itself still lives here: the sheet, the text
  // controller, the voice flow and the results are all this screen's state.
  // So the header calls in rather than owning a second copy of any of it —
  // there is exactly one search implementation, and the header is a remote for
  // it. MainShell reaches these through its Explore GlobalKey.

  /// Re-reads the search state after the header's bar ran a search.
  ///
  /// The results themselves come from a [ListenableBuilder] on the notifier, so
  /// they need no help. This is for `_searchActive`, which the [PopScope] at
  /// the top of `build` reads directly — without it, a search started from the
  /// header would leave back-to-browse unarmed until some unrelated rebuild
  /// happened to come along.
  void onShellSearchCommitted() {
    if (mounted) setState(() {});
  }

  /// Starts voice search, including its microphone permission prompt.
  void startVoiceSearchFromShell() => _startVoiceSearch();

  /// Drops the active search and returns to the browse feed. Unlike
  /// [resetFromTabTap] this leaves a "See all" grid alone: the header's ✕ is
  /// about the search, and a guest inside a category grid has not searched.
  void clearSearchFromShell() {
    if (_searchActive) _clearSearch();
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
    // Named, so the address bar shows /listing/<id> and the visitor can send
    // it to someone. The Listing rides along as `arguments`, so the screen
    // renders from what is already in hand — app.dart's route only falls back
    // to fetching when the id arrived from a pasted link.
    Navigator.of(context)
        .pushNamed(listingRoutePath(listing.id), arguments: listing);
  }

  void _openSearch() {
    showModalBottomSheet(
      context: context,
      isScrollControlled: true,
      // Full-screen sheet: only the status bar stays visible above it. With
      // no scrim left to tap, dismissal is the ✕ button or drag-down.
      useSafeArea: true,
      backgroundColor: Colors.transparent,
      builder: (context) => SizedBox.expand(
        child: _SearchSheet(
          searchController: _searchController,
          searchState: widget.searchState,
          onSearch: () {
            Navigator.pop(context);
            setState(() {});
          },
          repository: widget.repository,
        ),
      ),
    );
  }

  /// Voice search: listen, confirm what was heard, then run it through the
  /// ordinary search stack.
  ///
  /// The sheet does the listening and the confirming; everything after it is
  /// the same geocode-then-filter path a typed search takes, so results, map
  /// framing and empty states all behave identically.
  Future<void> _startVoiceSearch() async {
    // Ask for the microphone HERE, not inside the sheet. A browser only shows
    // a permission prompt while the tap's user activation is still live, and
    // the sheet asks after a post-frame callback and an await — by then the
    // activation is spent and Chrome can decline to prompt at all, which
    // surfaced as the sheet opening and immediately saying it heard nothing.
    final granted =
        await VoiceSpeechService.current.ensureMicrophonePermission();
    if (!mounted) return;
    if (!granted) {
      ModernBanner.showError(
        context,
        'Musafir needs permission to use your microphone. Allow it for this '
        'site, then tap the mic again.',
      );
      return;
    }

    final query = await VoiceListeningSheet.show(context);
    if (query == null || !mounted) return;

    setState(() => _voiceResolving = true);
    final runner = VoiceSearchRunner(
      searchState: widget.searchState,
      isKnownCity: _isKnownCityName,
    );
    final ran = await runner.run(query);
    if (!mounted) return;
    setState(() => _voiceResolving = false);

    // Fire-and-forget: the lexicon grows from what people actually said, and
    // a logging outage must never be visible to someone mid-search.
    unawaited(_logVoiceSearch(query, ran));

    if (!ran) {
      ModernBanner.showError(
        context,
        'Could not turn that into a search. Try naming an area, like '
        '"Dhanmondi".',
      );
      return;
    }

    // The spoken words go into the search field too, so the pill shows what
    // was searched and the sheet opens pre-filled if they want to adjust it.
    _searchController.text = query.placeText ?? query.transcript;
  }

  Future<void> _logVoiceSearch(VoiceQuery query, bool ran) async {
    final logger = VoiceSearchLogger((row) async {
      // Never chain .select() here. The table has an insert policy and no
      // select policy by design (transcripts are private telemetry), and
      // .select() makes PostgREST ask for the row back — which RLS refuses
      // with a 401 that reads, misleadingly, as "new row violates row-level
      // security policy". A bare insert sends Prefer: return=minimal and
      // succeeds; verified against the live table.
      await Supabase.instance.client.from('voice_search_log').insert({
        ...row,
        'user_id': widget.authState.currentUser?.id,
      });
    });
    await logger.log(
      query: query,
      localeId: VoiceSpeechService.current.supportsBangla ? 'bn-BD' : 'en-US',
      parsed: ran,
      resultCount: widget.searchState.results.length,
    );
  }

  /// Same test the search sheet applies to typed text — a city we already
  /// stock is searched by name, not by dropping a point in the middle of it.
  bool _isKnownCityName(String name) {
    final q = name.trim().toLowerCase();
    return widget.repository.listings
        .any((l) => (l.city ?? '').trim().toLowerCase() == q);
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

    // System back / browser back leaves the results instead of leaving the app.
    // The shell's own PopScope only knows about tabs, and Explore is the first
    // tab, so without this a back press on a results page exits.
    // Back leaves the See-all grid or the search results (in that order) rather
    // than exiting, but only while Explore is the tab on screen — otherwise the
    // shell handles back (see [isActiveTab]).
    final intercept = (_showAllActive || _searchActive) && widget.isActiveTab;
    return PopScope(
      canPop: !intercept,
      onPopInvokedWithResult: (didPop, _) {
        if (didPop) return;
        if (_showAllActive) {
          _closeShowAll();
        } else if (_searchActive) {
          _clearSearch();
        }
      },
      child: _buildScaffold(context, theme, wide),
    );
  }

  Widget _buildScaffold(BuildContext context, ThemeData theme, bool wide) {
    return Scaffold(
      body: SafeArea(
        child: Column(
          children: [
            // The whole in-page header — hero, search bar, trophy, bell — is
            // the shell header's job wherever there is one, so on desktop this
            // screen is just the feed. See [ExploreScreen.searchInShell].
            if (!widget.searchInShell) ...[
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
                    // Leaving the results is a navigation, so it gets the
                    // affordance guests look for. Only shown once a search is
                    // running — while browsing there is nothing to go back to.
                    if (_searchActive) ...[
                      IconButton(
                        onPressed: _clearSearch,
                        icon: const Icon(Icons.arrow_back),
                        tooltip: 'Back to browsing',
                        visualDensity: VisualDensity.compact,
                        padding: EdgeInsets.zero,
                        constraints: const BoxConstraints(
                          minWidth: 40,
                          minHeight: 40,
                        ),
                      ),
                      const SizedBox(width: 4),
                    ],
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
                              // Balances the trailing mic so the label stays
                              // visually centered.
                              const SizedBox(width: 12),
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
                                        style: theme.textTheme.bodyMedium
                                            ?.copyWith(
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
                                  onTap: _clearSearch,
                                  child: Icon(
                                    Icons.close,
                                    size: 18,
                                    color: theme.colorScheme.onSurfaceVariant,
                                  ),
                                ),
                              // Inside the pill rather than beside it: the row
                              // already carries a trophy and a bell, and a
                              // fourth circle would squeeze the label off a
                              // 360dp phone. Hides itself where the browser has
                              // no Web Speech API.
                              VoiceSearchMicButton(onTap: _startVoiceSearch),
                              const SizedBox(width: 4),
                            ],
                          ),
                        ),
                      ),
                    ),
                    // Top Hosts leaderboard — gold chip so it reads as a reward
                    // worth tapping, not just another grey action. Shared with
                    // the desktop header's action group.
                    const SizedBox(width: 6),
                    TopHostsButton(
                      onTap: () => Navigator.of(context).push(
                        MaterialPageRoute(
                          builder: (_) => HostLeaderboardScreen(
                            repository: widget.repository,
                            currentUserId: widget.authState.currentUser?.id,
                          ),
                        ),
                      ),
                    ),
                    // Notification bell. Hidden while signed out: notifications
                    // are per-user and notificationState is only ever
                    // initialize()d on login, so for a visitor the bell can
                    // never be anything but an empty list behind a dead badge.
                    if (widget.notificationState != null &&
                        widget.authState.isLoggedIn) ...[
                      const SizedBox(width: 4),
                      AnimatedNotificationBell(
                        notificationState: widget.notificationState!,
                        onTap: _openNotificationCenter,
                      ),
                    ],
                  ],
                ),
              ),

              // Property-type and purpose filters live inside the search sheet
              // (_SearchSheet) — the page itself stays a clean browse feed.
              //
              // Inside the wrapper on purpose: where the shell header carries
              // the search row, its own bottom border already separates chrome
              // from feed, and a second hairline right beneath it reads as a
              // rendering fault.
              const Divider(height: 1),
            ],

            // Listings grid with pull-to-refresh
            Expanded(
              child: ListenableBuilder(
                listenable: Listenable.merge([
                  widget.repository,
                  widget.favoritesState,
                  widget.searchState,
                ]),
                builder: (context, _) {
                  // A category's "See all" grid takes over just the content
                  // area — the search bar, notification bell and leaderboard
                  // above it, and the shell's bottom nav below, all stay.
                  if (_showAllActive) {
                    return ShowAllListingsView(
                      title: _showAllTitle!,
                      listings: _showAllItems!,
                      favoritesState: widget.favoritesState,
                      onOpenListing: _openListingDetail,
                      onBack: _closeShowAll,
                    );
                  }

                  final listings = _filteredListings;
                  // Geocoding a spoken place happens before the search
                  // notifier is busy, so the feed would otherwise sit on stale
                  // results with no sign anything was happening.
                  final isLoading = _voiceResolving ||
                      (_searchActive
                          ? widget.searchState.isSearching
                          : widget.repository.isLoadingListings);

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
                  // search). Only an explicit search (incl. a city "See all")
                  // falls back to the grid; type/purpose filters are part of
                  // the search sheet.
                  if (!_searchActive) {
                    return RefreshIndicator(
                      onRefresh: _onRefresh,
                      child: _buildCategoryRows(listings),
                    );
                  }

                  return _buildSearchResults(listings, theme, wide);
                },
              ),
            ),
          ],
        ),
      ),
    );
  }

  /// Search results, laid out around the map.
  ///
  /// On a phone the map fills the area and the results ride over it in a
  /// draggable sheet (Airbnb's pattern): the map is the context, the sheet is
  /// the answer, and the guest chooses how much of each to see. On a wide
  /// screen a sheet over a 1400px map reads badly, so the map stays a banner
  /// above the grid. With no coordinates anywhere there is nothing to put
  /// behind a sheet, so the grid stands alone.
  Widget _buildSearchResults(
    List<Listing> listings,
    ThemeData theme,
    bool wide,
  ) {
    final hasMap = mappableListings(listings).isNotEmpty;

    if (!hasMap) {
      return RefreshIndicator(
        onRefresh: _onRefresh,
        child: CustomScrollView(
          controller: _scrollController,
          physics: const AlwaysScrollableScrollPhysics(),
          slivers: _resultSlivers(listings, theme, singleColumn: !wide),
        ),
      );
    }

    if (wide) {
      return RefreshIndicator(
        onRefresh: _onRefresh,
        child: CustomScrollView(
          controller: _scrollController,
          physics: const AlwaysScrollableScrollPhysics(),
          slivers: [
            SliverToBoxAdapter(
              child: Padding(
                padding: const EdgeInsets.fromLTRB(16, 12, 16, 4),
                child: ListingPriceMap(
                  listings: listings,
                  onListingTap: _openListingDetail,
                  height: 320,
                ),
              ),
            ),
            ..._resultSlivers(listings, theme, singleColumn: false),
          ],
        ),
      );
    }

    return ResultsMapSheet(
      // Full-bleed and fully interactive: with the sheet handling the list,
      // nothing competes with the map for drags any more. The sheet reports how
      // much of the map it covers so the camera frames results ABOVE it.
      mapBuilder: (context, bottomInset) => ListingPriceMap(
        listings: listings,
        onListingTap: _openListingDetail,
        height: null,
        interactive: true,
        bottomInset: bottomInset,
      ),
      slivers: _resultSlivers(listings, theme, singleColumn: true),
    );
  }

  /// The dates the guest searched for, for the result rows to be priced
  /// against: "21 – 23 Aug", "2 Sep – 4 Oct", or "21 Aug, 10:00 AM – 2:00 PM"
  /// for an hourly search. Null when no dates were picked, in which case the
  /// row simply doesn't claim any.
  String? _stayLabel(BuildContext context) {
    final filters = widget.searchState.filters;
    if (!filters.hasDateSelection) return null;

    if (filters.dateMode == SearchDateMode.singleDateWithTime) {
      final day = DateFormat('d MMM').format(filters.singleDate!);
      final from = filters.startTime!.format(context);
      final to = filters.endTime!.format(context);
      return '$day, $from – $to';
    }

    final checkIn = filters.checkIn!;
    final checkOut = filters.checkOut!;
    // Same month reads better without repeating it: "21 – 23 Aug".
    final sameMonth =
        checkIn.year == checkOut.year && checkIn.month == checkOut.month;
    final start = DateFormat(sameMonth ? 'd' : 'd MMM').format(checkIn);
    final end = DateFormat('d MMM').format(checkOut);
    return '$start – $end';
  }

  /// The result content itself — proximity banner, cards, footer — shared by
  /// every layout above so they can't drift apart.
  ///
  /// [singleColumn] switches between the two card shapes. Results on a phone
  /// get one listing per row with the detail to judge it by ([ListingCardWide]);
  /// a wide screen has room for a real grid, where the compact card is right.
  List<Widget> _resultSlivers(
    List<Listing> listings,
    ThemeData theme, {
    required bool singleColumn,
  }) {
    return [
      // Which radius ring the results came from, or that we fell back to the
      // nearest stays.
      if (widget.searchState.matchedRadiusMeters != null ||
          widget.searchState.usedNearestFallback)
        SliverToBoxAdapter(
          child: _ProximityBanner(
            count: listings.length,
            radiusMeters: widget.searchState.matchedRadiusMeters,
            usedNearestFallback: widget.searchState.usedNearestFallback,
            placeLabel: widget.searchState.filters.location,
          ),
        ),
      if (singleColumn)
        SliverPadding(
          padding: const EdgeInsets.fromLTRB(16, 8, 16, 0),
          sliver: SliverList.separated(
            itemCount: listings.length,
            separatorBuilder: (context, index) => const SizedBox(height: 26),
            itemBuilder: (context, index) {
              final listing = listings[index];
              return ListingCardWide(
                listing: listing,
                isFavorite: widget.favoritesState.isFavorite(listing.id),
                onTap: () => _openListingDetail(listing),
                onFavoriteTap: () {
                  widget.favoritesState.toggleFavorite(listing.id);
                },
                stayLabel: _stayLabel(context),
              );
            },
          ),
        )
      else
        SliverPadding(
          padding: const EdgeInsets.all(16),
          sliver: SliverGrid(
            // Max-extent so the column count grows with width: 3–4 across the
            // desktop content panel, with cards kept a consistent, readable
            // size.
            gridDelegate: const SliverGridDelegateWithMaxCrossAxisExtent(
              maxCrossAxisExtent: 300,
              mainAxisSpacing: 16,
              crossAxisSpacing: 12,
              // ~square photo like Airbnb (the photo takes 5/7 of the cell
              // height in ListingCardModern).
              childAspectRatio: 0.72,
            ),
            delegate: SliverChildBuilderDelegate(
              (context, index) {
                final listing = listings[index];
                // Staggered entrance; modulo keeps the delay small for items
                // revealed far down on scroll.
                return FadeSlideIn(
                  delay: Duration(milliseconds: 45 * (index % 6)),
                  child: HoverLift(
                    child: ListingCardModern(
                      listing: listing,
                      isFavorite: widget.favoritesState.isFavorite(listing.id),
                      onTap: () => _openListingDetail(listing),
                      onFavoriteTap: () {
                        widget.favoritesState.toggleFavorite(listing.id);
                      },
                    ),
                  ),
                );
              },
              childCount: listings.length,
            ),
          ),
        ),
      SliverToBoxAdapter(
        child: Padding(
          padding: const EdgeInsets.all(16),
          child: Center(
            child: widget.repository.isLoadingListings
                ? const SizedBox(
                    height: 32,
                    width: 32,
                    child: CircularProgressIndicator(strokeWidth: 2),
                  )
                : !widget.repository.hasMoreListings && listings.isNotEmpty
                    ? Text(
                        'No more listings',
                        style: theme.textTheme.bodySmall?.copyWith(
                          color: theme.colorScheme.onSurfaceVariant,
                        ),
                      )
                    : const SizedBox.shrink(),
          ),
        ),
      ),
    ];
  }

  /// The city most of these listings are in, used to name the first curated
  /// row. Null when none of them carry a city.
  String? _dominantCity(List<Listing> listings) {
    final counts = <String, int>{};
    for (final l in listings) {
      final city = l.city?.trim();
      if (city == null || city.isEmpty) continue;
      counts[city] = (counts[city] ?? 0) + 1;
    }
    if (counts.isEmpty) return null;
    return counts.entries.reduce((a, b) => b.value > a.value ? b : a).key;
  }

  /// Shows the full curated list behind a category row's "See all" arrow.
  /// Rendered inline (see [_showAllItems]) so the shell's bottom nav stays.
  void _openShowAll(String title, List<Listing> items) {
    setState(() {
      _showAllTitle = title;
      _showAllItems = items;
    });
  }

  /// Returns from the "See all" grid to the browse feed.
  void _closeShowAll() {
    setState(() {
      _showAllTitle = null;
      _showAllItems = null;
    });
  }

  /// Airbnb-style curated rows shown while browsing (no search, no single
  /// category filter): Popular stays in {city}, Featured, Top rated,
  /// Budget-friendly, and other cities — each a horizontal, scrolling list.
  Widget _buildCategoryRows(List<Listing> listings) {
    final sections = <Widget>[];

    // Every category's "See all" arrow opens the full curated list (the row
    // itself only shows the first 12) as a client-side grid.
    void add(String title, List<Listing> items) {
      if (items.isEmpty) return;
      sections.add(
        _CategorySection(
          title: title,
          listings: items.take(12).toList(),
          favoritesState: widget.favoritesState,
          onOpen: _openListingDetail,
          onSeeAll: () => _openShowAll(title, items),
        ),
      );
    }

    // Popular — most reviewed, then highest rated. Named after the city most
    // of the catalogue is in ("Popular stays in Dhaka"), which reads as a place
    // to start rather than an unexplained ranking.
    final popular = [...listings]..sort((a, b) {
        final byReviews = b.reviewCount.compareTo(a.reviewCount);
        if (byReviews != 0) return byReviews;
        return (b.rating ?? 0).compareTo(a.rating ?? 0);
      });
    final mainCity = _dominantCity(listings);
    add(
      mainCity == null ? 'Popular stays' : 'Popular stays in $mainCity',
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

    // Location-wise — the busiest cities, "Stays in {city}".
    final byCity = <String, List<Listing>>{};
    for (final l in listings) {
      final c = l.city?.trim();
      if (c == null || c.isEmpty) continue;
      (byCity[c] ??= []).add(l);
    }
    final cities = byCity.keys.toList()
      ..sort((a, b) => byCity[b]!.length.compareTo(byCity[a]!.length));
    for (final city in cities.take(4)) {
      if (byCity[city]!.length < 2) continue;
      // The first row already covers this one.
      if (city == mainCity) continue;
      add('Stays in $city', byCity[city]!);
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
                IconButton(
                  onPressed: onSeeAll,
                  visualDensity: VisualDensity.compact,
                  padding: const EdgeInsets.all(6),
                  constraints: const BoxConstraints(),
                  tooltip: 'See all',
                  icon: const Icon(Icons.arrow_forward, size: 20),
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

  // Purpose of stay (Medical, Exam, …) with its optional landmark anchor
  // (the chosen hospital / exam center / …) — applied on Search.
  ListingPurpose? _selectedPurpose;
  Landmark? _pickedLandmark;

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
  // The resolved place's extent (a geocoded/Places viewport), when the picked
  // place is an area rather than a precise point. Present → the search covers
  // exactly this box instead of a radius ring. Cleared alongside the point.
  GeoBounds? _pickedBounds;
  bool _settingTextProgrammatically = false;
  bool _locatingMe = false;
  bool _resolvingPlace = false;

  @override
  void initState() {
    super.initState();
    final filters = widget.searchState.filters;
    _guestCount = filters.guestCount;
    _selectedTypes = List.from(filters.propertyTypes);
    // General is a host default, not a guest search intent — reads as "Any".
    final activePurpose =
        filters.purposeTags.isEmpty ? null : filters.purposeTags.first;
    _selectedPurpose =
        activePurpose == ListingPurpose.general ? null : activePurpose;
    _pickedLandmark = filters.landmark;
    _dateMode = filters.dateMode;
    _settingTextProgrammatically = true;
    widget.searchController.text = filters.location ?? '';
    _settingTextProgrammatically = false;
    _pickedLat = filters.latitude;
    _pickedLng = filters.longitude;
    _pickedBounds = filters.bounds;

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
    // Manual edit: any previously resolved point (or landmark anchor) no
    // longer matches the text. The purpose itself stays selected — it still
    // applies as a tag filter without a landmark.
    _pickedLat = null;
    _pickedLng = null;
    _pickedBounds = null;
    _pickedLandmark = null;
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
    // Guard the programmatic write: without this, setting the field text fires
    // the controller listener (_onLocationChanged), which recomputes the
    // suggestions and schedules a fresh places lookup — reopening the dropdown
    // ~300ms after the tap. The Google-prediction and current-location handlers
    // guard the same way; this one was missing it.
    _settingTextProgrammatically = true;
    widget.searchController.text = suggestion.city;
    widget.searchController.selection = TextSelection.fromPosition(
      TextPosition(offset: suggestion.city.length),
    );
    _settingTextProgrammatically = false;
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
    // locate (not resolve): the search bar only needs coordinates + the place's
    // extent, and locate carries the viewport bounds that let the search cover
    // exactly this area — resolve would flatten it to a point-only Landmark.
    final place = await PlacesService().locate(s);
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
        _pickedBounds = place.bounds;
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
      // "Near me" is a point + radius search, not an area — no box.
      _pickedBounds = null;
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

  /// Picking a purpose that needs an anchor (all guest-facing ones do) opens
  /// the landmark picker on top of this sheet; the chosen place fills the
  /// Where field and becomes the proximity center. "Any purpose" clears both.
  Future<void> _onPurposeSelected(ListingPurpose? purpose) async {
    if (purpose == null) {
      setState(() {
        _selectedPurpose = null;
        _pickedLandmark = null;
      });
      return;
    }
    final type = purpose.landmarkType;
    if (type == null) {
      setState(() {
        _selectedPurpose = purpose;
        _pickedLandmark = null;
      });
      return;
    }
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
    if (!mounted || chosen == null) {
      return; // dismissed — leave the current selection untouched
    }
    setState(() {
      _selectedPurpose = purpose;
      _pickedLandmark = chosen;
      // The landmark anchors the search: show it in the Where field and use
      // its coordinates (the text is only a display label server-side).
      _settingTextProgrammatically = true;
      widget.searchController.text = chosen.name;
      _settingTextProgrammatically = false;
      _pickedLat = chosen.latitude;
      _pickedLng = chosen.longitude;
      // A landmark anchors a fixed-radius ring around the place, not a box.
      _pickedBounds = null;
      _suggestions = [];
      _placeSuggestions = [];
      _showSuggestions = false;
    });
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

  /// Compact chip for the single-line property-type row under the search field.
  Widget _buildTypeChip(String label, bool selected, VoidCallback onTap) {
    return FilterChip(
      label: Text(label, style: const TextStyle(fontSize: 12)),
      selected: selected,
      onSelected: (_) => onTap(),
      showCheckmark: false,
      visualDensity: VisualDensity.compact,
      materialTapTargetSize: MaterialTapTargetSize.shrinkWrap,
      labelPadding: const EdgeInsets.symmetric(horizontal: 4),
      padding: const EdgeInsets.symmetric(horizontal: 8, vertical: 4),
    );
  }

  Future<void> _applySearch() async {
    final text = widget.searchController.text.trim();
    double? lat = _pickedLat;
    double? lng = _pickedLng;
    GeoBounds? bounds = _pickedBounds;

    // No point picked yet → resolve the typed text. We do this even for a known
    // listing city ("Dhaka"): the resolver returns the place's box, which lets
    // the search cover — and the map frame to — the city's real extent instead
    // of sprawling north into Tongi/Gazipur. Priority:
    //   • a box came back  → search & frame within it (best; areas and cities);
    //   • no box, unknown  → center an expanding proximity ring on the point;
    //   • no box, known city (or geocoding failed) → classic city text search.
    if (lat == null && bounds == null && text.isNotEmpty) {
      setState(() => _resolvingPlace = true);
      final place = await GeocodingService().geocode(text);
      if (!mounted) return;
      setState(() => _resolvingPlace = false);
      if (place != null) {
        bounds = place.bounds;
        if (bounds == null && !_isKnownCity(text)) {
          lat = place.latitude;
          lng = place.longitude;
        }
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
        // Carry the place's extent when we have one; a landmark or a point-only
        // resolve must drop any stale box so it doesn't keep framing the map.
        bounds: _pickedLandmark == null ? bounds : null,
        clearBounds: bounds == null || _pickedLandmark != null,
        checkIn:
            _dateMode == SearchDateMode.dateRange ? _dateRange?.start : null,
        checkOut:
            _dateMode == SearchDateMode.dateRange ? _dateRange?.end : null,
        guestCount: _guestCount,
        propertyTypes: _selectedTypes,
        purposeTags: _selectedPurpose == null
            ? const <ListingPurpose>[]
            : [_selectedPurpose!],
        landmark: _pickedLandmark,
        // No radiusMeters: the landmark ring is admin-configured and resolved
        // in the repository, so the sheet never carries a second copy of it.
        clearLandmark: _pickedLandmark == null,
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
            // Drag handle + explicit close button, so the sheet is always easy
            // to dismiss on mobile (drag-to-dismiss can be swallowed by the
            // scrollable content). No title — the search field is the header.
            Stack(
              alignment: Alignment.center,
              children: [
                Container(
                  width: 40,
                  height: 4,
                  decoration: BoxDecoration(
                    color: theme.colorScheme.outlineVariant,
                    borderRadius: BorderRadius.circular(2),
                  ),
                ),
                Align(
                  alignment: Alignment.centerRight,
                  child: IconButton(
                    onPressed: () => Navigator.of(context).pop(),
                    icon: const Icon(Icons.close),
                    tooltip: 'Close',
                    visualDensity: VisualDensity.compact,
                  ),
                ),
              ],
            ),
            const SizedBox(height: 12),

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
            const SizedBox(height: 16),

            // Property type — a single compact line directly under the search
            // field (small text; scrolls horizontally if it can't all fit).
            SizedBox(
              height: 36,
              child: SingleChildScrollView(
                scrollDirection: Axis.horizontal,
                child: Row(
                  children: [
                    _buildTypeChip(
                      'All',
                      _selectedTypes.isEmpty,
                      () => setState(() => _selectedTypes.clear()),
                    ),
                    for (final type in ListingType.values) ...[
                      const SizedBox(width: 8),
                      _buildTypeChip(
                        type.title,
                        _selectedTypes.contains(type),
                        () => _togglePropertyType(type),
                      ),
                    ],
                  ],
                ),
              ),
            ),
            const SizedBox(height: 16),

            // Purpose of stay (near a hospital / exam center / …) — moved in
            // from the Explore page so every filter lives in this sheet.
            Text(
              'Purpose of stay',
              style: theme.textTheme.titleSmall?.copyWith(
                fontWeight: FontWeight.w600,
              ),
            ),
            const SizedBox(height: 8),
            PurposeScroll(
              selected: _selectedPurpose,
              onSelected: _onPurposeSelected,
              padding: const EdgeInsets.symmetric(vertical: 4),
            ),
            if (_pickedLandmark != null)
              Padding(
                padding: const EdgeInsets.only(top: 6),
                child: Row(
                  children: [
                    Icon(
                      Icons.place_outlined,
                      size: 16,
                      color: theme.colorScheme.primary,
                    ),
                    const SizedBox(width: 6),
                    Expanded(
                      child: Text(
                        'Near ${_pickedLandmark!.name}',
                        style: theme.textTheme.bodySmall?.copyWith(
                          color: theme.colorScheme.onSurfaceVariant,
                        ),
                        maxLines: 1,
                        overflow: TextOverflow.ellipsis,
                      ),
                    ),
                  ],
                ),
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

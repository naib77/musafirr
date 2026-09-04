import 'package:flutter/foundation.dart' show kIsWeb;
import 'package:flutter/material.dart';

import '../core/theme/app_colors.dart';
import '../core/utils/responsive.dart';
import '../models/booking_status.dart';
import '../repositories/musafir_repository.dart';
import '../services/auth/auth_flow.dart';
import '../services/booking/booking_messaging_coordinator.dart';
import '../repositories/supabase_musafir_repository.dart';
import '../services/booking/booking_lifecycle_service.dart';
import '../services/search/search_summary.dart';
import '../state/app_mode_state.dart';
import '../state/auth_state.dart';
import '../state/favorites_state.dart';
import '../state/messaging_state.dart';
import '../state/notification_state.dart';
import '../state/search_state.dart';
import '../state/shell_nav_state.dart';
import '../widgets/app_page_header.dart';
import '../widgets/desktop_top_nav.dart';
import '../widgets/dialogs/confirm_logout_dialog.dart';
import '../widgets/modern_banner.dart';
import '../widgets/notification_bell.dart';
import '../widgets/review_prompt_handler.dart';
import '../widgets/smart_sidebar.dart';
import '../widgets/top_hosts_button.dart';
import 'explore/explore_screen.dart';
import 'host/become_host_screen.dart';
import 'hosting/earnings_screen.dart';
import 'host/host_dashboard_screen.dart';
import 'host/host_reservations_screen.dart';
import 'leaderboard/host_leaderboard_screen.dart';
import 'inbox/inbox_screen.dart';
import 'notifications/notification_center_screen.dart';
import 'profile/profile_screen.dart';
import 'trips/trips_screen.dart';
import 'wishlists/wishlists_screen.dart';

class MainShell extends StatefulWidget {
  const MainShell({
    super.key,
    required this.repository,
    required this.authState,
    required this.favoritesState,
    required this.searchState,
    this.notificationState,
    this.messagingState,
    this.bookingLifecycleService,
    this.bookingMessagingCoordinator,
    this.appModeState,
  });

  final MusafirRepository repository;
  final AuthStateNotifier authState;
  final FavoritesStateNotifier favoritesState;
  final SearchStateNotifier searchState;
  final NotificationStateNotifier? notificationState;
  final MessagingStateNotifier? messagingState;
  final BookingLifecycleService? bookingLifecycleService;
  final BookingMessagingCoordinator? bookingMessagingCoordinator;
  final AppModeStateNotifier? appModeState;

  @override
  State<MainShell> createState() => _MainShellState();
}

class _MainShellState extends State<MainShell> {
  int _guestTabIndex = 0;
  int _hostTabIndex = 0;
  late AppModeStateNotifier _appModeState;

  // GlobalKey to access TripsScreen state for tap-to-refresh
  final GlobalKey<dynamic> _exploreScreenKey = GlobalKey();
  final GlobalKey<dynamic> _tripsScreenKey = GlobalKey();

  // GlobalKey to drive the host Reservations screen's inner tab from elsewhere.
  final GlobalKey<dynamic> _hostReservationsKey = GlobalKey();

  @override
  void initState() {
    super.initState();
    _appModeState = widget.appModeState ?? AppModeStateNotifier();
    ShellNavState.instance.addListener(_onShellNavRequest);
  }

  @override
  void dispose() {
    ShellNavState.instance.removeListener(_onShellNavRequest);
    super.dispose();
  }

  /// Applies a tab-switch requested by a deep screen (booking sheet, notification
  /// center) and clears it so it fires once.
  void _onShellNavRequest() {
    if (!mounted) return;
    final nav = ShellNavState.instance;
    final guestTab = nav.guestTab;
    final hostTab = nav.hostTab;
    final reservationsTab = nav.reservationsTab;
    nav.consumed();

    setState(() {
      if (guestTab != null) _guestTabIndex = guestTab;
      if (hostTab != null) _hostTabIndex = hostTab;
    });
    // The Reservations screen stays mounted once visited (see
    // _LazyIndexedStack), so its inner tab is switched imperatively via its
    // state. Safe with lazy mounting because openHostReservations() always
    // sets the host tab too, so the screen is built in the frame before this
    // callback runs.
    if (reservationsTab != null) {
      WidgetsBinding.instance.addPostFrameCallback((_) {
        _hostReservationsKey.currentState?.goToTab(reservationsTab);
      });
    }
  }

  bool get _isLoggedIn => widget.authState.isLoggedIn;

  bool get _hasHostNotification {
    if (!_isLoggedIn) return false;
    final user = widget.authState.currentUser;
    if (user == null) return false;

    // Check for pending booking requests
    final hostListings =
        widget.repository.listings.where((l) => l.hostId == user.id).toList();

    if (hostListings.isEmpty) return false;

    final pendingRequests = widget.repository.bookings.where((b) =>
        hostListings.any((l) => l.id == b.listingId) &&
        b.status == BookingStatus.pending);

    return pendingRequests.isNotEmpty;
  }

  /// Flips between the guest and host portals. With the top tab strip gone,
  /// this is only reachable from the Profile tab ("Switch to hosting" /
  /// "Switch to travelling"). Lands on the target portal's first tab and
  /// confirms with a toast. [AppModeStateNotifier] persists the choice
  /// per-user, so the app reopens in whichever portal was used last.
  void _switchMode(AppMode target) {
    if (_appModeState.mode == target) return;
    setState(() {
      if (target == AppMode.host) {
        _hostTabIndex = 0;
      } else {
        _guestTabIndex = 0;
      }
    });
    _appModeState.setMode(target);
    ModernBanner.showSuccess(
      context,
      target == AppMode.host
          ? 'Switched to hosting — manage your listings & bookings.'
          : 'Switched to travelling — find & book stays.',
      duration: const Duration(seconds: 2),
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
          // After a host accepts a booking, land them on the shell's live
          // Reservations tab, showing the Upcoming inner tab.
          onViewReservations: () =>
              ShellNavState.instance.openHostReservations(innerTab: 0),
        ),
      ),
    );
  }

  @override
  Widget build(BuildContext context) {
    return ListenableBuilder(
      listenable: Listenable.merge([
        _appModeState,
        widget.authState,
        widget.repository,
        if (widget.messagingState != null) widget.messagingState!,
      ]),
      builder: (context, _) {
        // The saved guest/host mode loads asynchronously. Until it resolves,
        // rendering would default to guest and then snap to host — a visible
        // flash on every reload for hosts. Hold on a neutral splash frame
        // while logged in until the mode is known. (Logged-out users are
        // always guest, so no need to wait.)
        if (_isLoggedIn && !_appModeState.isLoaded) {
          return const Scaffold(
            body: Center(child: CircularProgressIndicator()),
          );
        }

        final isGuest = _appModeState.isGuestMode || !_isLoggedIn;

        // The shell is the single top-inset consumer (the removed Guest/Host
        // tab strip used to play this role): a surface-coloured shim spans the
        // status bar, and the inset is stripped from everything below it so
        // the per-tab slim headers render flush underneath. Any descendant
        // SafeArea then sees a zero top inset and adds nothing.
        final Widget statusBarShim = Container(
          color: AppColors.surface,
          height: MediaQuery.paddingOf(context).top,
        );

        // Main content.
        final Widget content = MediaQuery.removePadding(
          context: context,
          removeTop: true,
          child: AnimatedSwitcher(
            duration: const Duration(milliseconds: 300),
            child: isGuest ? _buildGuestContent() : _buildHostContent(),
          ),
        );

        final Widget scaffold;
        if (Responsive.isWide(context)) {
          // ── Desktop framing ──────────────────────────────────────────────
          // A top header replaces the stretched bottom bar: brand, centred
          // destinations, account menu, and — on Explore — the search pill.
          // It used to be a left navigation rail; see [DesktopTopNav] for why
          // that moved. Each tab still centers its own content at a readable
          // width over the soft grey page (the per-tab ResponsiveCenter wraps
          // in _buildGuestContent / _buildHostContent), so lists and forms
          // don't stretch edge-to-edge. Phones/tablets (< 1000px) fall through
          // to the bottom-bar layout below, unchanged.
          scaffold = Scaffold(
            backgroundColor: AppColors.scaffold,
            body: Column(
              children: [
                statusBarShim,
                _buildDesktopTopNav(isGuest),
                Expanded(child: content),
              ],
            ),
          );
        } else {
          // ── Mobile / narrow framing (original) ──────────────────────────
          scaffold = Scaffold(
            body: Column(
              children: [
                statusBarShim,
                Expanded(child: content),
              ],
            ),
            bottomNavigationBar: isGuest
                ? _buildGuestNavigationBar()
                : _buildHostNavigationBar(),
          );
        }

        // Wrap with review prompt handler if repository supports it
        Widget result = scaffold;
        if (widget.repository is SupabaseMusafirRepository) {
          result = ReviewPromptHandler(
            repository: widget.repository as SupabaseMusafirRepository,
            authState: widget.authState,
            child: scaffold,
          );
        }

        // Mobile-web edge-swipe panel (install the PWA, jump between tabs).
        // Self-disabling off web and on wide layouts, so this wrap is a no-op
        // everywhere the navigation rail or a native build already applies.
        result = SmartSidebar(
          shortcuts: isGuest ? _guestShortcuts() : _hostShortcuts(),
          cta: _hostCta(isGuest),
          child: result,
        );

        // Android system back on a non-first tab returns to the first tab
        // (Explore for guests, dashboard for hosts) instead of exiting the
        // app; pressing back again on the first tab exits. Pushed routes on
        // top of the shell are unaffected — this PopScope only applies when
        // the shell itself is the top route.
        final int currentTab = isGuest ? _guestTabIndex : _hostTabIndex;
        return PopScope(
          // On native, allowing the first-tab pop lets a second back press exit
          // the app (intended). On web there is nothing beneath this sole root
          // route, so popping it empties the Navigator and shows a blank/black
          // page — never allow it there; back on the first tab is simply inert.
          canPop: currentTab == 0 && !kIsWeb,
          onPopInvokedWithResult: (didPop, _) {
            if (didPop) return;
            setState(() {
              if (isGuest) {
                _guestTabIndex = 0;
              } else {
                _hostTabIndex = 0;
              }
            });
          },
          child: result,
        );
      },
    );
  }

  /// Airbnb-style tab bar shell: hairline top border and capped text
  /// scaling so five labels always fit on one line, even with large
  /// system fonts.
  Widget _navBarShell(Widget bar) {
    return Container(
      decoration: BoxDecoration(
        color: AppColors.surface,
        border: Border(
          top: BorderSide(color: AppColors.outline, width: 0.5),
        ),
      ),
      child: MediaQuery.withClampedTextScaling(
        maxScaleFactor: 1.1,
        child: bar,
      ),
    );
  }

  // ============================================================
  // DESKTOP TOP NAVIGATION (wide screens only)
  // ============================================================

  /// The desktop header, in place of the left navigation rail this used to be.
  ///
  /// It drives the very same `_guestTabIndex` / `_hostTabIndex` the bottom bar
  /// does — no second navigation model — which is also why every destination
  /// selection goes through `_goToGuestTab`, keeping its signed-out guard.
  ///
  /// Listens to [SearchStateNotifier] here rather than in the shell's
  /// top-level merge: the pill's Where/When/Who summary is the only thing in
  /// the shell that cares about filters, and rebuilding every mounted tab on
  /// each change inside the search sheet would be a lot to pay for three
  /// labels.
  Widget _buildDesktopTopNav(bool isGuest) {
    return ListenableBuilder(
      listenable: widget.searchState,
      builder: (context, _) => isGuest ? _guestTopNav() : _hostTopNav(),
    );
  }

  Widget _guestTopNav() {
    final user = widget.authState.currentUser;
    final unreadMessageCount = widget.messagingState?.totalUnreadCount ?? 0;

    return DesktopTopNav(
      // Signed out, Explore is the only destination — same reason the
      // signed-out bottom bar has two items and not five: nothing behind
      // Wishlists, Trips, Messages or Profile can render without a user. The
      // way in is the header's primary action AND the first row of the account
      // menu, both visible without opening anything, because a login reachable
      // only from inside a hamburger is a login most visitors never find.
      destinations: [
        const DesktopNavDestination(
          icon: Icons.search_outlined,
          selectedIcon: Icons.search,
          label: 'Explore',
        ),
        if (_isLoggedIn) ...[
          const DesktopNavDestination(
            icon: Icons.favorite_outline,
            selectedIcon: Icons.favorite,
            label: 'Wishlists',
          ),
          const DesktopNavDestination(
            icon: Icons.luggage_outlined,
            selectedIcon: Icons.luggage,
            label: 'Trips',
          ),
          DesktopNavDestination(
            icon: Icons.chat_bubble_outline,
            selectedIcon: Icons.chat_bubble,
            label: 'Messages',
            badgeCount: unreadMessageCount,
          ),
        ],
      ],
      // Profile is logical tab 4 and lives in the account menu, not the strip,
      // so while it is on screen no destination is current. The account
      // button's brand ring is what says "you are here" instead.
      selectedIndex: _guestTabIndex == 4 ? -1 : _guestTabIndex,
      accountHighlighted: _guestTabIndex == 4,
      onDestinationSelected: _onDesktopGuestDestination,
      onBrandTap: () => _goToGuestTab(0),
      primaryAction: _guestHeaderAction(),
      trailing: _headerTrailing(),
      avatarUrl: user?.avatarUrl,
      displayName: user?.name,
      accountMenu: _guestAccountMenu(),
      // Explore only. A Where/When/Who pill above the Trips list would be
      // furniture — and worse, it would suggest that searching from there
      // filters what is on screen.
      search: _guestTabIndex == 0 ? _searchSummary() : null,
    );
  }

  Widget _hostTopNav() {
    final user = widget.authState.currentUser;
    final unreadMessageCount = widget.messagingState?.totalUnreadCount ?? 0;

    return DesktopTopNav(
      destinations: [
        const DesktopNavDestination(
          icon: Icons.dashboard_outlined,
          selectedIcon: Icons.dashboard,
          label: 'Dashboard',
        ),
        DesktopNavDestination(
          icon: Icons.calendar_month_outlined,
          selectedIcon: Icons.calendar_month,
          label: 'Reservations',
          showDot: _hasHostNotification,
        ),
        const DesktopNavDestination(
          icon: Icons.account_balance_wallet_outlined,
          selectedIcon: Icons.account_balance_wallet,
          label: 'Earnings',
        ),
        DesktopNavDestination(
          icon: Icons.chat_bubble_outline,
          selectedIcon: Icons.chat_bubble,
          label: 'Messages',
          badgeCount: unreadMessageCount,
        ),
      ],
      selectedIndex: _hostTabIndex == 4 ? -1 : _hostTabIndex,
      accountHighlighted: _hostTabIndex == 4,
      onDestinationSelected: _goToHostTab,
      onBrandTap: () => _goToHostTab(0),
      primaryAction: DesktopTopNavAction(
        label: 'Switch to travelling',
        tooltip: 'Find and book stays',
        onTap: () => _switchMode(AppMode.guest),
      ),
      trailing: _headerTrailing(),
      avatarUrl: user?.avatarUrl,
      displayName: user?.name,
      accountMenu: [
        DesktopAccountMenuItem(
          label: 'Profile',
          icon: Icons.person_outline,
          onTap: () => _goToHostTab(4),
        ),
        DesktopAccountMenuItem(
          label: 'Log out',
          icon: Icons.logout_rounded,
          dividerAbove: true,
          onTap: _confirmLogout,
        ),
      ],
      search: null,
    );
  }

  /// Re-selecting the destination already showing mirrors the bottom bar:
  /// Explore drops an active search, Trips refreshes. The header's indices are
  /// 1:1 with the logical guest tabs 0–3, so nothing needs remapping.
  void _onDesktopGuestDestination(int index) {
    if (index == _guestTabIndex) {
      if (index == 0) _exploreScreenKey.currentState?.resetFromTabTap();
      if (index == 2) _tripsScreenKey.currentState?.refreshFromTabTap();
      return;
    }
    _goToGuestTab(index);
  }

  /// The header's single text action.
  ///
  /// For a signed-in guest it is the hosting CTA, taken from the same
  /// three-state [_hostCta] the mobile sidebar uses, so the entry points into
  /// hosting cannot start disagreeing about what this user can do next.
  DesktopTopNavAction? _guestHeaderAction() {
    if (!_isLoggedIn) {
      return DesktopTopNavAction(
        label: 'Log in or sign up',
        onTap: _promptSignIn,
      );
    }
    final cta = _hostCta(true);
    if (cta == null) return null;
    return DesktopTopNavAction(
      label: cta.label,
      tooltip: cta.description,
      onTap: cta.onTap,
    );
  }

  /// The header's icon actions: the Top Hosts leaderboard and the notification
  /// bell.
  ///
  /// Both used to live inside the Explore tab's own search row — which is why
  /// that row is hidden on desktop (see `ExploreScreen.searchInShell`). They
  /// are app chrome, not part of the feed, and in the header they stay
  /// reachable from every tab instead of only from Explore.
  List<Widget> _headerTrailing() {
    return [
      TopHostsButton(onTap: _openLeaderboard),
      // Hidden while signed out: notifications are per-user and
      // notificationState is only ever initialize()d on login, so for a
      // visitor the bell could never be anything but an empty list behind a
      // dead badge.
      if (widget.notificationState != null && _isLoggedIn)
        AnimatedNotificationBell(
          notificationState: widget.notificationState!,
          onTap: _openNotificationCenter,
        ),
    ];
  }

  List<DesktopAccountMenuItem> _guestAccountMenu() {
    if (!_isLoggedIn) {
      return [
        DesktopAccountMenuItem(
          label: 'Log in or sign up',
          icon: Icons.login_rounded,
          emphasized: true,
          onTap: _promptSignIn,
        ),
        DesktopAccountMenuItem(
          label: 'Become a host',
          icon: Icons.home_work_outlined,
          dividerAbove: true,
          // Hosting needs an account, so this is the same login prompt rather
          // than a dead end that explains it later.
          onTap: _promptSignIn,
        ),
      ];
    }
    return [
      DesktopAccountMenuItem(
        label: 'Profile',
        icon: Icons.person_outline,
        onTap: () => _goToGuestTab(4),
      ),
      DesktopAccountMenuItem(
        label: 'Log out',
        icon: Icons.logout_rounded,
        dividerAbove: true,
        onTap: _confirmLogout,
      ),
    ];
  }

  /// What the search pill shows, and what each of its parts does.
  ///
  /// The pill is chrome owned by the shell, but the search itself belongs to
  /// the Explore tab — it holds the sheet, the text controller and the voice
  /// flow. So the three callbacks reach into that state through
  /// [_exploreScreenKey] rather than duplicating any of it here. A null state
  /// (Explore not yet mounted) makes them inert, which is correct: the pill
  /// only renders while Explore is the current tab.
  DesktopSearchSummary _searchSummary() {
    final filters = widget.searchState.filters;
    final summary = searchPillSummaryFor(filters);
    return DesktopSearchSummary(
      where: summary.where,
      when: summary.when,
      who: summary.who,
      onTap: () => _exploreScreenKey.currentState?.openSearchFromShell(),
      onVoice: () =>
          _exploreScreenKey.currentState?.startVoiceSearchFromShell(),
      // hasActiveFilters, not the summary: a property type or an amenity is an
      // active search the pill has no segment for, and leaving it with no ✕
      // would strand the guest in results they cannot clear from the header.
      onClear: filters.hasActiveFilters
          ? () => _exploreScreenKey.currentState?.clearSearchFromShell()
          : null,
    );
  }

  /// Shares its dialog with the Profile tab's log-out row, so the two cannot
  /// drift into asking differently (or one of them into not asking at all).
  Future<void> _confirmLogout() async {
    if (await confirmLogout(context)) widget.authState.logout();
  }

  // ============================================================
  // GUEST MODE
  // ============================================================

  /// Asks a signed-out visitor to log in, for anything account-shaped.
  ///
  /// Nothing behind Wishlists, Trips, Messages or Profile can render without a
  /// user, so a signed-out visitor gets Explore plus this instead of four tabs
  /// that each explain they are empty.
  Future<void> _promptSignIn() async {
    await AuthFlow.ensureSignedIn(
      context,
      widget.authState,
      reason: 'to see your trips, saved places and messages',
    );
  }

  Widget _buildGuestNavigationBar() {
    final unreadMessageCount = widget.messagingState?.totalUnreadCount ?? 0;

    // Signed out: Explore and a way in, nothing else.
    //
    // Deliberately a SEPARATE bar rather than a filter over the five-item
    // list. `_guestTabIndex` is a logical tab id that `_buildGuestContent`,
    // `_goToGuestTab(0..4)` and `ShellNavState.openGuestTrips()` all index
    // with; renumbering the destinations would silently repoint every one of
    // those. Here the index never leaves 0.
    if (!_isLoggedIn) {
      return _navBarShell(NavigationBar(
        selectedIndex: 0,
        onDestinationSelected: (index) {
          if (index == 0) {
            _exploreScreenKey.currentState?.resetFromTabTap();
            return;
          }
          _promptSignIn();
        },
        destinations: const [
          NavigationDestination(
            icon: Icon(Icons.search_outlined),
            selectedIcon: Icon(Icons.search),
            label: 'Explore',
          ),
          NavigationDestination(
            icon: Icon(Icons.login_outlined),
            selectedIcon: Icon(Icons.login),
            label: 'Log in',
          ),
        ],
      ));
    }

    return _navBarShell(NavigationBar(
      selectedIndex: _guestTabIndex,
      onDestinationSelected: (index) {
        // Re-tapping the already-selected tab: Explore (0) drops any active
        // search back to the feed — its results render inline, so switching
        // tabs can't escape them; Trips (2) refreshes.
        if (index == _guestTabIndex) {
          if (index == 0) _exploreScreenKey.currentState?.resetFromTabTap();
          if (index == 2) _tripsScreenKey.currentState?.refreshFromTabTap();
        }
        setState(() => _guestTabIndex = index);
      },
      destinations: [
        const NavigationDestination(
          icon: Icon(Icons.search_outlined),
          selectedIcon: Icon(Icons.search),
          label: 'Explore',
        ),
        const NavigationDestination(
          icon: Icon(Icons.favorite_outline),
          selectedIcon: Icon(Icons.favorite),
          label: 'Wishlists',
        ),
        const NavigationDestination(
          icon: Icon(Icons.luggage_outlined),
          selectedIcon: Icon(Icons.luggage),
          label: 'Trips',
        ),
        NavigationDestination(
          icon: _MessagesNavIcon(count: unreadMessageCount, selected: false),
          selectedIcon:
              _MessagesNavIcon(count: unreadMessageCount, selected: true),
          label: 'Messages',
        ),
        const NavigationDestination(
          icon: Icon(Icons.person_outline),
          selectedIcon: Icon(Icons.person),
          label: 'Profile',
        ),
      ],
    ));
  }

  Widget _buildGuestContent() {
    // Per-tab desktop content widths. ResponsiveCenter only caps when the
    // screen is wider than the value, so these are no-ops on mobile.
    const widths = <double>[
      Responsive.contentMaxWidth, // Explore (needs room for the grid)
      980, // Wishlists
      820, // Trips
      820, // Messages
      760, // Profile
    ];
    final tabs = <Widget>[
      // Explore
      ExploreScreen(
        key: _exploreScreenKey,
        isActiveTab: _guestTabIndex == 0,
        // On desktop the header carries the search pill, the leaderboard and
        // the bell, so Explore renders the feed alone. Same predicate the
        // build method framed the layout with — told to the screen rather than
        // re-derived inside it.
        searchInShell: Responsive.isWide(context),
        repository: widget.repository,
        authState: widget.authState,
        favoritesState: widget.favoritesState,
        searchState: widget.searchState,
        notificationState: widget.notificationState,
        bookingLifecycleService: widget.bookingLifecycleService,
        bookingMessagingCoordinator: widget.bookingMessagingCoordinator,
        messagingState: widget.messagingState,
      ),
      // Wishlists - slim header instead of full AppBar
      Column(
        children: [
          _buildSlimHeader('Wishlists', subtitle: 'Your saved places'),
          Expanded(
            child: WishlistsScreen(
              repository: widget.repository,
              favoritesState: widget.favoritesState,
              authState: widget.authState,
              messagingState: widget.messagingState,
              onNavigateToExplore: () => setState(() => _guestTabIndex = 0),
            ),
          ),
        ],
      ),
      // Trips - has its own AppBar with TabBar
      TripsScreen(
        key: _tripsScreenKey,
        repository: widget.repository,
        authState: widget.authState,
        messagingState: widget.messagingState,
        notificationState: widget.notificationState,
        bookingMessagingCoordinator: widget.bookingMessagingCoordinator,
        onOpenNotifications: _openNotificationCenter,
        onNavigateToExplore: () => setState(() => _guestTabIndex = 0),
      ),
      // Messages - slim header instead of full AppBar
      Column(
        children: [
          _buildSlimHeader('Messages', subtitle: 'Chats with your hosts'),
          Expanded(
            child: InboxScreen(
              messagingState: widget.messagingState,
              repository: widget.repository,
              embedded: true,
            ),
          ),
        ],
      ),
      // Profile - slim header instead of full AppBar
      Column(
        children: [
          _buildSlimHeader('Profile', subtitle: 'Account and settings'),
          Expanded(
            child: ProfileScreen(
              authState: widget.authState,
              repository: widget.repository,
              notificationState: widget.notificationState,
              isHostContext: false,
              onSwitchToHosting: () => _switchMode(AppMode.host),
              hostHasPendingRequests: _hasHostNotification,
            ),
          ),
        ],
      ),
    ];
    return _LazyIndexedStack(
      key: const ValueKey('guest'),
      index: _guestTabIndex,
      children: [
        for (var i = 0; i < tabs.length; i++)
          ResponsiveCenter(maxWidth: widths[i], child: tabs[i]),
      ],
    );
  }

  // ============================================================
  // HOST MODE
  // ============================================================

  Widget _buildHostNavigationBar() {
    final unreadMessageCount = widget.messagingState?.totalUnreadCount ?? 0;

    return _navBarShell(NavigationBar(
      selectedIndex: _hostTabIndex,
      onDestinationSelected: (index) {
        setState(() => _hostTabIndex = index);
      },
      destinations: [
        const NavigationDestination(
          icon: Icon(Icons.dashboard_outlined),
          selectedIcon: Icon(Icons.dashboard),
          label: 'Dashboard',
        ),
        NavigationDestination(
          icon: Badge(
            isLabelVisible: _hasHostNotification,
            child: const Icon(Icons.calendar_month_outlined),
          ),
          selectedIcon: Badge(
            isLabelVisible: _hasHostNotification,
            child: const Icon(Icons.calendar_month),
          ),
          label: 'Reservations',
        ),
        const NavigationDestination(
          icon: Icon(Icons.account_balance_wallet_outlined),
          selectedIcon: Icon(Icons.account_balance_wallet),
          label: 'Earnings',
        ),
        NavigationDestination(
          icon: _MessagesNavIcon(count: unreadMessageCount, selected: false),
          selectedIcon:
              _MessagesNavIcon(count: unreadMessageCount, selected: true),
          label: 'Messages',
        ),
        const NavigationDestination(
          icon: Icon(Icons.person_outline),
          selectedIcon: Icon(Icons.person),
          label: 'Profile',
        ),
      ],
    ));
  }

  Widget _buildHostContent() {
    // Per-tab desktop content widths (no-ops on mobile).
    const widths = <double>[
      1000, // Dashboard
      900, // Reservations
      860, // Earnings
      820, // Messages
      760, // Profile
    ];
    final tabs = <Widget>[
      // Dashboard - slim header instead of full AppBar
      Column(
        children: [
          _buildSlimHeader('Dashboard',
              subtitle: 'Your hosting at a glance', showLeaderboard: true),
          Expanded(
            child: HostDashboardScreen(
              repository: widget.repository,
              authState: widget.authState,
              messagingState: widget.messagingState,
              onOpenReservations: () => setState(() => _hostTabIndex = 1),
            ),
          ),
        ],
      ),
      // Reservations — the tabbed Upcoming / Active Stays / Completed view.
      HostReservationsScreen(
        key: _hostReservationsKey,
        repository: widget.repository,
        authState: widget.authState,
        messagingState: widget.messagingState,
        bookingMessagingCoordinator: widget.bookingMessagingCoordinator,
        notificationState: widget.notificationState,
        onOpenNotifications: _openNotificationCenter,
      ),
      // Earnings - slim header instead of full AppBar
      Column(
        children: [
          _buildSlimHeader('Earnings', subtitle: 'Track your income'),
          Expanded(
            child: EarningsScreen(
              repository: widget.repository,
              authState: widget.authState,
            ),
          ),
        ],
      ),
      // Messages - slim header instead of full AppBar
      Column(
        children: [
          _buildSlimHeader('Messages', subtitle: 'Chats with your guests'),
          Expanded(
            child: InboxScreen(
              messagingState: widget.messagingState,
              repository: widget.repository,
              embedded: true,
            ),
          ),
        ],
      ),
      // Profile (shared) - slim header instead of full AppBar
      Column(
        children: [
          _buildSlimHeader('Profile', subtitle: 'Account and settings'),
          Expanded(
            child: ProfileScreen(
              authState: widget.authState,
              repository: widget.repository,
              notificationState: widget.notificationState,
              isHostContext: true,
              onSwitchToTravelling: () => _switchMode(AppMode.guest),
            ),
          ),
        ],
      ),
    ];
    return _LazyIndexedStack(
      key: const ValueKey('host'),
      index: _hostTabIndex,
      children: [
        for (var i = 0; i < tabs.length; i++)
          ResponsiveCenter(maxWidth: widths[i], child: tabs[i]),
      ],
    );
  }

  // ============================================================
  // SMART SIDEBAR SHORTCUTS
  // ============================================================

  /// The quick-access tiles behind the mobile-web edge swipe. They mirror the
  /// bottom bar's destinations (so the panel is a shortcut, never a second,
  /// divergent navigation model) plus Notifications, which has no tab of its
  /// own and is otherwise only reachable from a per-tab header button.
  List<SmartSidebarShortcut> _guestShortcuts() {
    final unreadMessages = (widget.messagingState?.totalUnreadCount ?? 0) > 0;
    return [
      SmartSidebarShortcut(
        icon: Icons.search_rounded,
        label: 'Explore',
        accent: AppColors.brand,
        onTap: () => _goToGuestTab(0),
      ),
      SmartSidebarShortcut(
        icon: Icons.favorite_rounded,
        label: 'Wishlists',
        accent: AppColors.pink,
        onTap: () => _goToGuestTab(1),
      ),
      SmartSidebarShortcut(
        icon: Icons.luggage_rounded,
        label: 'Trips',
        accent: AppColors.violet,
        onTap: () => _goToGuestTab(2),
      ),
      SmartSidebarShortcut(
        icon: Icons.chat_bubble_rounded,
        label: 'Messages',
        accent: AppColors.blue,
        badge: unreadMessages,
        onTap: () => _goToGuestTab(3),
      ),
      SmartSidebarShortcut(
        icon: Icons.notifications_rounded,
        label: 'Alerts',
        accent: AppColors.amber,
        badge: widget.notificationState?.hasUnread ?? false,
        onTap: _openNotificationCenter,
      ),
      SmartSidebarShortcut(
        icon: Icons.person_rounded,
        label: 'Profile',
        accent: AppColors.indigo,
        onTap: () => _goToGuestTab(4),
      ),
    ];
  }

  List<SmartSidebarShortcut> _hostShortcuts() {
    final unreadMessages = (widget.messagingState?.totalUnreadCount ?? 0) > 0;
    return [
      SmartSidebarShortcut(
        icon: Icons.dashboard_rounded,
        label: 'Dashboard',
        accent: AppColors.brand,
        onTap: () => _goToHostTab(0),
      ),
      SmartSidebarShortcut(
        icon: Icons.calendar_month_rounded,
        label: 'Bookings',
        accent: AppColors.coral,
        badge: _hasHostNotification,
        onTap: () => _goToHostTab(1),
      ),
      SmartSidebarShortcut(
        icon: Icons.account_balance_wallet_rounded,
        label: 'Earnings',
        accent: AppColors.green,
        onTap: () => _goToHostTab(2),
      ),
      SmartSidebarShortcut(
        icon: Icons.chat_bubble_rounded,
        label: 'Messages',
        accent: AppColors.blue,
        badge: unreadMessages,
        onTap: () => _goToHostTab(3),
      ),
      SmartSidebarShortcut(
        icon: Icons.notifications_rounded,
        label: 'Alerts',
        accent: AppColors.amber,
        badge: widget.notificationState?.hasUnread ?? false,
        onTap: _openNotificationCenter,
      ),
      SmartSidebarShortcut(
        icon: Icons.person_rounded,
        label: 'Profile',
        accent: AppColors.indigo,
        onTap: () => _goToHostTab(4),
      ),
    ];
  }

  /// The panel's headline action: the way into hosting. Only the guest panel
  /// carries it — the host portal is already where it leads. Which of the
  /// three states applies mirrors the Profile tab's hosting section, so the
  /// two entry points never disagree about what the user can do next.
  SmartSidebarCta? _hostCta(bool isGuest) {
    if (!isGuest) return null;

    final user = widget.authState.currentUser;
    if (user == null) {
      // Hosting needs an account. This used to send them to the Profile tab
      // because that is where the login prompt lived — a tab a signed-out
      // visitor no longer has. Ask for the login directly instead.
      return SmartSidebarCta(
        icon: Icons.home_work_rounded,
        label: 'Become a host',
        description: 'Sign in to start earning',
        onTap: _promptSignIn,
      );
    }

    if (user.isHost) {
      return SmartSidebarCta(
        icon: Icons.swap_horiz_rounded,
        label: 'Switch to hosting',
        description: _hasHostNotification
            ? 'New booking request waiting'
            : 'Go to your host dashboard',
        onTap: () => _switchMode(AppMode.host),
      );
    }

    return SmartSidebarCta(
      icon: Icons.home_work_rounded,
      label: 'Become a host',
      description: 'Start earning by sharing your space',
      onTap: _openBecomeHost,
    );
  }

  /// Signs the user up as a host and lands them in the host portal, the same
  /// way the Profile tab's "Become a Host" row does.
  void _openBecomeHost() {
    Navigator.push(
      context,
      MaterialPageRoute(
        builder: (_) => BecomeHostScreen(
          authState: widget.authState,
          onBecomeHost: () {
            Navigator.pop(context);
            _switchMode(AppMode.host);
          },
        ),
      ),
    );
  }

  void _goToGuestTab(int index) {
    if (!mounted) return;
    // Every guest tab but Explore needs a user, and a signed-out visitor has
    // no way to navigate to one — so any request to switch to one arrived from
    // a shortcut or a deep screen (the smart sidebar, ShellNavState) that did
    // not check. Guarding centrally here rather than at each caller means a
    // new caller cannot reintroduce the hole.
    if (!_isLoggedIn && index != 0) {
      _promptSignIn();
      return;
    }
    setState(() => _guestTabIndex = index);
  }

  void _goToHostTab(int index) {
    if (!mounted) return;
    setState(() => _hostTabIndex = index);
  }

  // ============================================================
  // SHARED COMPONENTS
  // ============================================================

  /// The unified page header shown at the top of every primary tab. Sits
  /// directly below the shell's status-bar shim (which is the single
  /// top-inset consumer, so this adds no SafeArea of its own).
  ///
  /// Messages has its own bottom-navigation tab (with unread badge), so the
  /// header carries no chat shortcut.
  Widget _buildSlimHeader(
    String title, {
    String? subtitle,
    bool showLeaderboard = false,
  }) {
    return AppPageHeader(
      title: title,
      subtitle: subtitle,
      actions: [
        if (showLeaderboard) _LeaderboardHeaderButton(onTap: _openLeaderboard),
        if (widget.notificationState != null)
          AnimatedNotificationBell(
            notificationState: widget.notificationState!,
            onTap: _openNotificationCenter,
            iconSize: 22,
            decorated: true,
          ),
      ],
    );
  }

  void _openLeaderboard() {
    Navigator.of(context).push(
      MaterialPageRoute(
        builder: (_) => HostLeaderboardScreen(
          repository: widget.repository,
          currentUserId: widget.authState.currentUser?.id,
        ),
      ),
    );
  }
}

/// Messages destination icon with an unread-count badge, Airbnb-style.
class _MessagesNavIcon extends StatelessWidget {
  const _MessagesNavIcon({required this.count, required this.selected});

  final int count;
  final bool selected;

  @override
  Widget build(BuildContext context) {
    // Airbnb-style unread indicator: a small red dot, no count.
    return Badge(
      isLabelVisible: count > 0,
      smallSize: 8,
      backgroundColor: AppColors.error,
      child: Icon(
        selected ? Icons.chat_bubble : Icons.chat_bubble_outline,
      ),
    );
  }
}

/// Eye-catching gold trophy chip used in the host header so the leaderboard
/// reads as a reward worth chasing — deliberately *not* the muted grey of the
/// other header chips. A soft glow + amber gradient draws the eye to it.
class _LeaderboardHeaderButton extends StatelessWidget {
  const _LeaderboardHeaderButton({required this.onTap});

  final VoidCallback onTap;

  @override
  Widget build(BuildContext context) {
    return Tooltip(
      message: 'Top Hosts',
      child: Material(
        shape: const CircleBorder(),
        clipBehavior: Clip.antiAlias,
        color: Colors.transparent,
        child: InkWell(
          onTap: onTap,
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
                  color: const Color(0xFFFFB300).withValues(alpha: 0.45),
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
    );
  }
}

/// An [IndexedStack] that only builds a tab once it has actually been visited.
///
/// A plain IndexedStack mounts every child immediately: all five tabs ran their
/// initState and fired their startup fetches before the user had chosen
/// anything, and the map tab kept a live GL surface rendering behind whatever
/// was on screen — GPU work and radio traffic for screens nobody was looking
/// at. Visited tabs stay mounted, so switching back is still instant and their
/// scroll position and state survive, which is the reason IndexedStack was
/// chosen in the first place.
class _LazyIndexedStack extends StatefulWidget {
  const _LazyIndexedStack({
    super.key,
    required this.index,
    required this.children,
  });

  final int index;
  final List<Widget> children;

  @override
  State<_LazyIndexedStack> createState() => _LazyIndexedStackState();
}

class _LazyIndexedStackState extends State<_LazyIndexedStack> {
  final Set<int> _visited = {};

  @override
  void initState() {
    super.initState();
    _visited.add(widget.index);
  }

  @override
  void didUpdateWidget(covariant _LazyIndexedStack oldWidget) {
    super.didUpdateWidget(oldWidget);
    _visited.add(widget.index);
  }

  @override
  Widget build(BuildContext context) {
    return IndexedStack(
      index: widget.index,
      children: [
        for (var i = 0; i < widget.children.length; i++)
          // A zero-size box holds the slot so the stack's indices still line up
          // with the navigation bar's.
          if (_visited.contains(i))
            widget.children[i]
          else
            const SizedBox.shrink(),
      ],
    );
  }
}

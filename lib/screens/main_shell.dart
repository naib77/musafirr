import 'package:flutter/material.dart';

import '../core/theme/app_colors.dart';
import '../core/utils/responsive.dart';
import '../models/booking_status.dart';
import '../repositories/musafir_repository.dart';
import '../services/booking/booking_messaging_coordinator.dart';
import '../repositories/supabase_musafir_repository.dart';
import '../services/booking/booking_lifecycle_service.dart';
import '../state/app_mode_state.dart';
import '../state/auth_state.dart';
import '../state/favorites_state.dart';
import '../state/messaging_state.dart';
import '../state/notification_state.dart';
import '../state/search_state.dart';
import '../state/shell_nav_state.dart';
import '../widgets/app_page_header.dart';
import '../widgets/guest_host_switcher.dart';
import '../widgets/notification_bell.dart';
import '../widgets/review_prompt_handler.dart';
import 'explore/explore_screen.dart';
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
    // The Reservations screen is kept alive in an IndexedStack, so its inner
    // tab is switched imperatively via its state.
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

        // Guest/Host switcher (only when logged in). Shared by both the mobile
        // (bottom-bar) and desktop (side-rail) framings below.
        final Widget? switcher = _isLoggedIn
            ? GuestHostSwitcher(
                mode: _appModeState.mode,
                onModeChanged: (mode) => _appModeState.setMode(mode),
                hasHostNotification: _hasHostNotification,
              )
            : null;

        // Main content.
        //
        // When the GuestHostSwitcher is shown it already consumes the top
        // safe-area inset (status bar). Content below it must NOT consume that
        // inset again — a sibling lower in the Column still sees the full
        // MediaQuery.padding.top, so any descendant SafeArea/AppBar would inject
        // the status-bar height a second time (invisible on web where the inset
        // is 0, a large gap on Android). Strip the top inset here so descendants
        // match the slim-header tabs that render directly below the switcher.
        // When logged out there is no switcher, so the inset is left intact for
        // the child's own SafeArea to handle.
        final Widget content = MediaQuery.removePadding(
          context: context,
          removeTop: _isLoggedIn,
          child: AnimatedSwitcher(
            duration: const Duration(milliseconds: 300),
            child: isGuest ? _buildGuestContent() : _buildHostContent(),
          ),
        );

        final Widget scaffold;
        if (Responsive.isWide(context)) {
          // ── Desktop framing ──────────────────────────────────────────────
          // A left navigation rail replaces the stretched bottom bar. Each tab
          // centers its own content at a readable width over the soft grey page
          // (see the per-tab ResponsiveCenter wraps in _buildGuestContent /
          // _buildHostContent), so lists and forms don't stretch edge-to-edge.
          // Phones/tablets (< 1000px) fall through to the bottom-bar layout
          // below, unchanged.
          scaffold = Scaffold(
            backgroundColor: AppColors.scaffold,
            body: Row(
              crossAxisAlignment: CrossAxisAlignment.stretch,
              children: [
                isGuest
                    ? _buildGuestNavigationRail()
                    : _buildHostNavigationRail(),
                Expanded(
                  child: Column(
                    children: [
                      if (switcher != null)
                        ResponsiveCenter(
                          maxWidth: Responsive.contentMaxWidth,
                          child: switcher,
                        ),
                      Expanded(child: content),
                    ],
                  ),
                ),
              ],
            ),
          );
        } else {
          // ── Mobile / narrow framing (original) ──────────────────────────
          scaffold = Scaffold(
            body: Column(
              children: [
                if (switcher != null) switcher,
                Expanded(child: content),
              ],
            ),
            bottomNavigationBar: isGuest
                ? _buildGuestNavigationBar()
                : _buildHostNavigationBar(),
          );
        }

        // Wrap with review prompt handler if repository supports it
        if (widget.repository is SupabaseMusafirRepository) {
          return ReviewPromptHandler(
            repository: widget.repository as SupabaseMusafirRepository,
            authState: widget.authState,
            child: scaffold,
          );
        }

        return scaffold;
      },
    );
  }

  /// Airbnb-style tab bar shell: hairline top border and capped text
  /// scaling so five labels always fit on one line, even with large
  /// system fonts.
  Widget _navBarShell(Widget bar) {
    return Container(
      decoration: const BoxDecoration(
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
  // DESKTOP NAVIGATION RAIL (wide screens only)
  // ============================================================

  /// White rail column with a hairline right border and clamped text scaling —
  /// the vertical counterpart of [_navBarShell].
  Widget _navRailShell(Widget rail) {
    return Container(
      decoration: const BoxDecoration(
        color: AppColors.surface,
        border: Border(
          right: BorderSide(color: AppColors.outline, width: 0.5),
        ),
      ),
      child: MediaQuery.withClampedTextScaling(
        maxScaleFactor: 1.1,
        child: rail,
      ),
    );
  }

  /// Brand wordmark shown at the top of the rail — gives the desktop layout a
  /// proper app identity instead of a floating icon strip.
  Widget _railBrandHeader() {
    return Padding(
      padding: const EdgeInsets.fromLTRB(20, 22, 20, 14),
      child: Row(
        mainAxisSize: MainAxisSize.min,
        children: [
          const Icon(Icons.travel_explore_rounded,
              color: AppColors.brand, size: 26),
          const SizedBox(width: 8),
          Text(
            'Musaafir',
            style: TextStyle(
              fontSize: 20,
              fontWeight: FontWeight.w700,
              color: AppColors.ink,
              letterSpacing: -0.5,
            ),
          ),
        ],
      ),
    );
  }

  /// Brand-tinted selection styling so the active destination pops.
  NavigationRailThemeData get _railTheme => NavigationRailThemeData(
        backgroundColor: AppColors.surface,
        indicatorColor: AppColors.brand.withValues(alpha: 0.12),
        selectedIconTheme: const IconThemeData(color: AppColors.brand),
        unselectedIconTheme: const IconThemeData(color: AppColors.inkMuted),
        selectedLabelTextStyle: const TextStyle(
          color: AppColors.brand,
          fontWeight: FontWeight.w600,
        ),
        unselectedLabelTextStyle: const TextStyle(color: AppColors.inkMuted),
      );

  Widget _buildGuestNavigationRail() {
    final unreadMessageCount = widget.messagingState?.totalUnreadCount ?? 0;

    return _navRailShell(NavigationRailTheme(
      data: _railTheme,
      child: NavigationRail(
        extended: true,
        minExtendedWidth: 220,
        leading: _railBrandHeader(),
        selectedIndex: _guestTabIndex,
        onDestinationSelected: (index) {
          // Re-tapping Trips (index 2) refreshes it, matching the bottom bar.
          if (index == _guestTabIndex && index == 2) {
            _tripsScreenKey.currentState?.refreshFromTabTap();
          }
          setState(() => _guestTabIndex = index);
        },
        destinations: [
          const NavigationRailDestination(
            icon: Icon(Icons.search_outlined),
            selectedIcon: Icon(Icons.search),
            label: Text('Explore'),
          ),
          const NavigationRailDestination(
            icon: Icon(Icons.favorite_outline),
            selectedIcon: Icon(Icons.favorite),
            label: Text('Wishlists'),
          ),
          const NavigationRailDestination(
            icon: Icon(Icons.luggage_outlined),
            selectedIcon: Icon(Icons.luggage),
            label: Text('Trips'),
          ),
          NavigationRailDestination(
            icon: _MessagesNavIcon(count: unreadMessageCount, selected: false),
            selectedIcon:
                _MessagesNavIcon(count: unreadMessageCount, selected: true),
            label: const Text('Messages'),
          ),
          const NavigationRailDestination(
            icon: Icon(Icons.person_outline),
            selectedIcon: Icon(Icons.person),
            label: Text('Profile'),
          ),
        ],
      ),
    ));
  }

  Widget _buildHostNavigationRail() {
    final unreadMessageCount = widget.messagingState?.totalUnreadCount ?? 0;

    return _navRailShell(NavigationRailTheme(
      data: _railTheme,
      child: NavigationRail(
        extended: true,
        minExtendedWidth: 220,
        leading: _railBrandHeader(),
        selectedIndex: _hostTabIndex,
        onDestinationSelected: (index) {
          setState(() => _hostTabIndex = index);
        },
        destinations: [
          const NavigationRailDestination(
            icon: Icon(Icons.dashboard_outlined),
            selectedIcon: Icon(Icons.dashboard),
            label: Text('Dashboard'),
          ),
          NavigationRailDestination(
            icon: Badge(
              isLabelVisible: _hasHostNotification,
              child: const Icon(Icons.calendar_month_outlined),
            ),
            selectedIcon: Badge(
              isLabelVisible: _hasHostNotification,
              child: const Icon(Icons.calendar_month),
            ),
            label: const Text('Reservations'),
          ),
          const NavigationRailDestination(
            icon: Icon(Icons.account_balance_wallet_outlined),
            selectedIcon: Icon(Icons.account_balance_wallet),
            label: Text('Earnings'),
          ),
          NavigationRailDestination(
            icon: _MessagesNavIcon(count: unreadMessageCount, selected: false),
            selectedIcon:
                _MessagesNavIcon(count: unreadMessageCount, selected: true),
            label: const Text('Messages'),
          ),
          const NavigationRailDestination(
            icon: Icon(Icons.person_outline),
            selectedIcon: Icon(Icons.person),
            label: Text('Profile'),
          ),
        ],
      ),
    ));
  }

  // ============================================================
  // GUEST MODE
  // ============================================================

  Widget _buildGuestNavigationBar() {
    final unreadMessageCount = widget.messagingState?.totalUnreadCount ?? 0;

    return _navBarShell(NavigationBar(
      selectedIndex: _guestTabIndex,
      onDestinationSelected: (index) {
        // If tapping the same tab (Trips = 2), trigger refresh
        if (index == _guestTabIndex && index == 2) {
          _tripsScreenKey.currentState?.refreshFromTabTap();
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
              onSwitchToHosting: () => _appModeState.setMode(AppMode.host),
            ),
          ),
        ],
      ),
    ];
    return IndexedStack(
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
            ),
          ),
        ],
      ),
    ];
    return IndexedStack(
      key: const ValueKey('host'),
      index: _hostTabIndex,
      children: [
        for (var i = 0; i < tabs.length; i++)
          ResponsiveCenter(maxWidth: widths[i], child: tabs[i]),
      ],
    );
  }

  // ============================================================
  // SHARED COMPONENTS
  // ============================================================

  /// The unified page header shown at the top of every primary tab. Sits
  /// directly below the Guest/Host switcher (which is the single top-inset
  /// consumer, so this adds no SafeArea of its own).
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

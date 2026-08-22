import 'package:flutter/foundation.dart' show kIsWeb;
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
import '../widgets/modern_banner.dart';
import '../widgets/notification_bell.dart';
import '../widgets/review_prompt_handler.dart';
import '../widgets/smart_sidebar.dart';
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
                      statusBarShim,
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
          // Re-tapping the active tab, matching the bottom bar: Explore (0)
          // drops any active search back to the feed; Trips (2) refreshes.
          if (index == _guestTabIndex) {
            if (index == 0) _exploreScreenKey.currentState?.resetFromTabTap();
            if (index == 2) _tripsScreenKey.currentState?.refreshFromTabTap();
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
      // Hosting needs an account; the Profile tab is where the login prompt
      // lives, so send them there rather than to a screen that would fail.
      return SmartSidebarCta(
        icon: Icons.home_work_rounded,
        label: 'Become a host',
        description: 'Sign in to start earning',
        onTap: () => _goToGuestTab(4),
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

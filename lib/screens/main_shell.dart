import 'package:flutter/material.dart';

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
import '../widgets/app_page_header.dart';
import '../widgets/guest_host_switcher.dart';
import '../widgets/notification_bell.dart';
import '../widgets/review_prompt_handler.dart';
import 'explore/explore_screen.dart';
import 'hosting/earnings_screen.dart';
import 'host/host_dashboard_screen.dart';
import 'host/host_reservations_screen.dart';
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

  @override
  void initState() {
    super.initState();
    _appModeState = widget.appModeState ?? AppModeStateNotifier();
  }

  bool get _isLoggedIn => widget.authState.isLoggedIn;

  bool get _hasHostNotification {
    if (!_isLoggedIn) return false;
    final user = widget.authState.currentUser;
    if (user == null) return false;

    // Check for pending booking requests
    final hostListings = widget.repository.listings
        .where((l) => l.hostId == user.id || l.ownerName == user.name)
        .toList();

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
        ),
      ),
    );
  }

  void _openInbox() {
    Navigator.push(
      context,
      MaterialPageRoute(
        builder: (context) => InboxScreen(messagingState: widget.messagingState),
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
        final scaffold = Scaffold(
          body: Column(
            children: [
              // Guest/Host switcher (only when logged in)
              if (_isLoggedIn)
                GuestHostSwitcher(
                  mode: _appModeState.mode,
                  onModeChanged: (mode) {
                    _appModeState.setMode(mode);
                  },
                  hasHostNotification: _hasHostNotification,
                ),
              // Main content.
              //
              // When the GuestHostSwitcher is shown it already consumes the top
              // safe-area inset (status bar). Content below it must NOT consume
              // that inset again — a sibling lower in the Column still sees the
              // full MediaQuery.padding.top, so any descendant SafeArea/AppBar
              // would inject the status-bar height a second time (invisible on
              // web where the inset is 0, a large gap on Android). Strip the top
              // inset here so descendants match the slim-header tabs that
              // already render directly below the switcher. When logged out
              // there is no switcher, so the inset is left intact for the
              // child's own SafeArea to handle.
              Expanded(
                child: MediaQuery.removePadding(
                  context: context,
                  removeTop: _isLoggedIn,
                  child: AnimatedSwitcher(
                    duration: const Duration(milliseconds: 300),
                    child: _appModeState.isGuestMode || !_isLoggedIn
                        ? _buildGuestContent()
                        : _buildHostContent(),
                  ),
                ),
              ),
            ],
          ),
          bottomNavigationBar: _appModeState.isGuestMode || !_isLoggedIn
              ? _buildGuestNavigationBar()
              : _buildHostNavigationBar(),
        );

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

  // ============================================================
  // GUEST MODE
  // ============================================================

  Widget _buildGuestNavigationBar() {
    return NavigationBar(
      selectedIndex: _guestTabIndex,
      onDestinationSelected: (index) {
        // If tapping the same tab (Trips = 2), trigger refresh
        if (index == _guestTabIndex && index == 2) {
          _tripsScreenKey.currentState?.refreshFromTabTap();
        }
        setState(() => _guestTabIndex = index);
      },
      destinations: const [
        NavigationDestination(
          icon: Icon(Icons.search_outlined),
          selectedIcon: Icon(Icons.search),
          label: 'Explore',
        ),
        NavigationDestination(
          icon: Icon(Icons.favorite_outline),
          selectedIcon: Icon(Icons.favorite),
          label: 'Wishlists',
        ),
        NavigationDestination(
          icon: Icon(Icons.luggage_outlined),
          selectedIcon: Icon(Icons.luggage),
          label: 'Trips',
        ),
        NavigationDestination(
          icon: Icon(Icons.person_outline),
          selectedIcon: Icon(Icons.person),
          label: 'Profile',
        ),
      ],
    );
  }

  Widget _buildGuestContent() {
    final unreadMessageCount = widget.messagingState?.totalUnreadCount ?? 0;

    return IndexedStack(
      key: const ValueKey('guest'),
      index: _guestTabIndex,
      children: [
        // Explore
        ExploreScreen(
          repository: widget.repository,
          authState: widget.authState,
          favoritesState: widget.favoritesState,
          searchState: widget.searchState,
          notificationState: widget.notificationState,
          bookingLifecycleService: widget.bookingLifecycleService,
          messagingState: widget.messagingState,
          onOpenInbox: _openInbox,
        ),
        // Wishlists - slim header instead of full AppBar
        Column(
          children: [
            _buildSlimHeader('Wishlists', unreadMessageCount,
                subtitle: 'Your saved places'),
            Expanded(
              child: WishlistsScreen(
                repository: widget.repository,
                favoritesState: widget.favoritesState,
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
          onOpenInbox: _openInbox,
          onOpenNotifications: _openNotificationCenter,
          onNavigateToExplore: () => setState(() => _guestTabIndex = 0),
        ),
        // Profile - slim header instead of full AppBar
        Column(
          children: [
            _buildSlimHeader('Profile', unreadMessageCount,
                subtitle: 'Account and settings'),
            Expanded(
              child: ProfileScreen(
                authState: widget.authState,
                repository: widget.repository,
                notificationState: widget.notificationState,
              ),
            ),
          ],
        ),
      ],
    );
  }

  // ============================================================
  // HOST MODE
  // ============================================================

  Widget _buildHostNavigationBar() {
    return NavigationBar(
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
        const NavigationDestination(
          icon: Icon(Icons.person_outline),
          selectedIcon: Icon(Icons.person),
          label: 'Profile',
        ),
      ],
    );
  }

  Widget _buildHostContent() {
    final unreadMessageCount = widget.messagingState?.totalUnreadCount ?? 0;

    return IndexedStack(
      key: const ValueKey('host'),
      index: _hostTabIndex,
      children: [
        // Dashboard - slim header instead of full AppBar
        Column(
          children: [
            _buildSlimHeader('Dashboard', unreadMessageCount,
                subtitle: 'Your hosting at a glance'),
            Expanded(
              child: HostDashboardScreen(
                repository: widget.repository,
                authState: widget.authState,
                messagingState: widget.messagingState,
                onOpenReservations: () =>
                    setState(() => _hostTabIndex = 1),
              ),
            ),
          ],
        ),
        // Reservations — the tabbed Upcoming / Active Stays / Completed view.
        HostReservationsScreen(
          repository: widget.repository,
          authState: widget.authState,
          messagingState: widget.messagingState,
          bookingMessagingCoordinator: widget.bookingMessagingCoordinator,
          notificationState: widget.notificationState,
          onOpenInbox: _openInbox,
          onOpenNotifications: _openNotificationCenter,
        ),
        // Earnings - slim header instead of full AppBar
        Column(
          children: [
            _buildSlimHeader('Earnings', unreadMessageCount,
                subtitle: 'Track your income'),
            Expanded(
              child: EarningsScreen(
                repository: widget.repository,
                authState: widget.authState,
              ),
            ),
          ],
        ),
        // Profile (shared) - slim header instead of full AppBar
        Column(
          children: [
            _buildSlimHeader('Profile', unreadMessageCount,
                subtitle: 'Account and settings'),
            Expanded(
              child: ProfileScreen(
                authState: widget.authState,
                repository: widget.repository,
                notificationState: widget.notificationState,
              ),
            ),
          ],
        ),
      ],
    );
  }

  // ============================================================
  // SHARED COMPONENTS
  // ============================================================

  /// The unified page header shown at the top of every primary tab. Sits
  /// directly below the Guest/Host switcher (which is the single top-inset
  /// consumer, so this adds no SafeArea of its own).
  Widget _buildSlimHeader(
    String title,
    int unreadMessageCount, {
    String? subtitle,
  }) {
    return AppPageHeader(
      title: title,
      subtitle: subtitle,
      actions: [
        if (widget.messagingState != null)
          HeaderActionButton(
            icon: Icons.chat_bubble_outline,
            badgeCount: unreadMessageCount,
            onTap: _openInbox,
            tooltip: 'Messages',
          ),
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
}

import 'package:flutter/material.dart';

import '../models/booking_status.dart';
import '../repositories/musafir_repository.dart';
import '../repositories/supabase_musafir_repository.dart';
import '../services/booking/booking_lifecycle_service.dart';
import '../state/app_mode_state.dart';
import '../state/auth_state.dart';
import '../state/favorites_state.dart';
import '../state/messaging_state.dart';
import '../state/notification_state.dart';
import '../state/search_state.dart';
import '../widgets/guest_host_switcher.dart';
import '../widgets/notification_bell.dart';
import '../widgets/review_prompt_handler.dart';
import 'explore/explore_screen.dart';
import 'hosting/earnings_screen.dart';
import 'host/host_dashboard_screen.dart';
import 'hosting/host_listings_screen.dart';
import 'hosting/hosting_screen.dart';
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
    this.appModeState,
  });

  final MusafirRepository repository;
  final AuthStateNotifier authState;
  final FavoritesStateNotifier favoritesState;
  final SearchStateNotifier searchState;
  final NotificationStateNotifier? notificationState;
  final MessagingStateNotifier? messagingState;
  final BookingLifecycleService? bookingLifecycleService;
  final AppModeStateNotifier? appModeState;

  @override
  State<MainShell> createState() => _MainShellState();
}

class _MainShellState extends State<MainShell> {
  int _guestTabIndex = 0;
  int _hostTabIndex = 0;
  late AppModeStateNotifier _appModeState;

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
      listenable: Listenable.merge([_appModeState, widget.authState, widget.repository]),
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
              // Main content
              Expanded(
                child: AnimatedSwitcher(
                  duration: const Duration(milliseconds: 300),
                  child: _appModeState.isGuestMode || !_isLoggedIn
                      ? _buildGuestContent()
                      : _buildHostContent(),
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
        ),
        // Wishlists
        Scaffold(
          appBar: _buildAppBar('Wishlists', unreadMessageCount),
          body: WishlistsScreen(
            repository: widget.repository,
            favoritesState: widget.favoritesState,
          ),
        ),
        // Trips
        Scaffold(
          appBar: _buildAppBar('Trips', unreadMessageCount),
          body: TripsScreen(
            repository: widget.repository,
            authState: widget.authState,
          ),
        ),
        // Profile
        Scaffold(
          appBar: _buildAppBar('Profile', unreadMessageCount),
          body: ProfileScreen(
            authState: widget.authState,
            repository: widget.repository,
            notificationState: widget.notificationState,
          ),
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
        // Dashboard
        Scaffold(
          appBar: _buildAppBar('Dashboard', unreadMessageCount),
          body: HostDashboardScreen(
            repository: widget.repository,
            authState: widget.authState,
          ),
        ),
        // Reservations (existing HostingScreen content)
        widget.bookingLifecycleService != null
            ? HostingScreen(
                repository: widget.repository,
                authState: widget.authState,
                bookingLifecycleService: widget.bookingLifecycleService!,
              )
            : const Center(child: Text('Reservations unavailable')),
        // Earnings
        Scaffold(
          appBar: _buildAppBar('Earnings', unreadMessageCount),
          body: EarningsScreen(
            repository: widget.repository,
            authState: widget.authState,
          ),
        ),
        // Profile (shared)
        Scaffold(
          appBar: _buildAppBar('Profile', unreadMessageCount),
          body: ProfileScreen(
            authState: widget.authState,
            repository: widget.repository,
            notificationState: widget.notificationState,
          ),
        ),
      ],
    );
  }

  // ============================================================
  // SHARED COMPONENTS
  // ============================================================

  AppBar _buildAppBar(String title, int unreadMessageCount) {
    return AppBar(
      title: Text(title),
      centerTitle: false,
      actions: [
        // Messages icon with badge
        if (widget.messagingState != null)
          IconButton(
            icon: Badge(
              isLabelVisible: unreadMessageCount > 0,
              label: Text(
                unreadMessageCount > 99 ? '99+' : '$unreadMessageCount',
              ),
              child: const Icon(Icons.chat_bubble_outline),
            ),
            onPressed: _openInbox,
            tooltip: 'Messages',
          ),
        // Notification bell
        if (widget.notificationState != null)
          AnimatedNotificationBell(
            notificationState: widget.notificationState!,
            onTap: _openNotificationCenter,
          ),
      ],
    );
  }
}

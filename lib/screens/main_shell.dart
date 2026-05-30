import 'package:flutter/material.dart';

import '../repositories/musafir_repository.dart';
import '../services/booking/booking_lifecycle_service.dart';
import '../state/auth_state.dart';
import '../state/favorites_state.dart';
import '../state/messaging_state.dart';
import '../state/notification_state.dart';
import '../state/search_state.dart';
import '../widgets/notification_bell.dart';
import 'explore/explore_screen.dart';
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
  });

  final MusafirRepository repository;
  final AuthStateNotifier authState;
  final FavoritesStateNotifier favoritesState;
  final SearchStateNotifier searchState;
  final NotificationStateNotifier? notificationState;
  final MessagingStateNotifier? messagingState;
  final BookingLifecycleService? bookingLifecycleService;

  @override
  State<MainShell> createState() => _MainShellState();
}

class _MainShellState extends State<MainShell> {
  int _currentIndex = 0;

  String get _currentTitle {
    switch (_currentIndex) {
      case 0:
        return 'Explore';
      case 1:
        return 'Wishlists';
      case 2:
        return 'Trips';
      case 3:
        return 'Inbox';
      case 4:
        return 'Profile';
      default:
        return 'Musafir';
    }
  }

  Widget _buildNavigationBar() {
    final unreadCount = widget.messagingState?.totalUnreadCount ?? 0;

    return NavigationBar(
      selectedIndex: _currentIndex,
      onDestinationSelected: (index) {
        setState(() => _currentIndex = index);
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
          icon: Badge(
            isLabelVisible: unreadCount > 0,
            label: Text(unreadCount > 99 ? '99+' : '$unreadCount'),
            child: const Icon(Icons.chat_bubble_outline),
          ),
          selectedIcon: Badge(
            isLabelVisible: unreadCount > 0,
            label: Text(unreadCount > 99 ? '99+' : '$unreadCount'),
            child: const Icon(Icons.chat_bubble),
          ),
          label: 'Inbox',
        ),
        const NavigationDestination(
          icon: Icon(Icons.person_outline),
          selectedIcon: Icon(Icons.person),
          label: 'Profile',
        ),
      ],
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
        ),
      ),
    );
  }

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      appBar: _currentIndex == 0
          ? null // Explore has its own app bar
          : AppBar(
              title: Text(_currentTitle),
              centerTitle: false,
              actions: [
                if (widget.notificationState != null)
                  AnimatedNotificationBell(
                    notificationState: widget.notificationState!,
                    onTap: _openNotificationCenter,
                  ),
              ],
            ),
      body: IndexedStack(
        index: _currentIndex,
        children: [
          ExploreScreen(
            repository: widget.repository,
            authState: widget.authState,
            favoritesState: widget.favoritesState,
            searchState: widget.searchState,
            notificationState: widget.notificationState,
            bookingLifecycleService: widget.bookingLifecycleService,
          ),
          WishlistsScreen(
            repository: widget.repository,
            favoritesState: widget.favoritesState,
          ),
          TripsScreen(
            repository: widget.repository,
            authState: widget.authState,
          ),
          InboxScreen(messagingState: widget.messagingState),
          ProfileScreen(
            authState: widget.authState,
            repository: widget.repository,
            notificationState: widget.notificationState,
          ),
        ],
      ),
      bottomNavigationBar: widget.messagingState != null
          ? ListenableBuilder(
              listenable: widget.messagingState!,
              builder: (context, _) => _buildNavigationBar(),
            )
          : _buildNavigationBar(),
    );
  }
}

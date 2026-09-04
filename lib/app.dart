import 'package:flutter/material.dart';
import 'package:supabase_flutter/supabase_flutter.dart';

import 'core/routing/listing_path.dart';
import 'core/theme/app_palette.dart';
import 'core/theme/app_theme.dart';
import 'core/theme/theme_controller.dart';
import 'models/listing.dart';
import 'models/notification.dart';
import 'repositories/supabase_musafir_repository.dart';
import 'screens/explore/listing_route.dart';
import 'screens/main_shell.dart';
import 'screens/splash/splash_screen.dart';
import 'services/auth/auth_flow.dart';
import 'services/booking/booking_lifecycle_service.dart';
import 'services/booking/booking_messaging_coordinator.dart';
import 'services/booking/booking_rules.dart';
import 'repositories/supabase_conversation_repository.dart';
import 'repositories/supabase_message_template_repository.dart';
import 'services/messaging/booking_conversation_service.dart';
import 'services/messaging/supabase_messaging_service.dart';
import 'services/notifications/fcm_token_service.dart';
import 'services/pwa/pwa_install_service.dart';
import 'services/web_update_service.dart';
import 'services/notifications/notification_service_factory.dart';
import 'state/auth_state.dart';
import 'state/favorites_state.dart';
import 'state/messaging_state.dart';
import 'state/notification_state.dart';
import 'state/search_state.dart';
import 'widgets/modern_banner.dart';

class MusafirApp extends StatefulWidget {
  const MusafirApp({super.key});

  @override
  State<MusafirApp> createState() => _MusafirAppState();
}

class _MusafirAppState extends State<MusafirApp> {
  /// App-wide navigator so background state (e.g. the realtime notification
  /// handler) can surface an in-app toast without a widget context.
  final GlobalKey<NavigatorState> _navigatorKey = GlobalKey<NavigatorState>();

  /// App-wide messenger so the web update check can show its banner from
  /// outside any screen's context.
  final GlobalKey<ScaffoldMessengerState> _scaffoldMessengerKey =
      GlobalKey<ScaffoldMessengerState>();

  /// The id of the user we last (re)initialised per-user state for. Guards
  /// [_onAuthStateChanged] so a routine token refresh (which re-notifies
  /// authState with the SAME user, e.g. on every app resume) does not wipe and
  /// refetch the whole repository cache — which flashed a blank feed each time.
  String? _lastAuthedUserId;

  late final SupabaseMusafirRepository repository;
  final AuthStateNotifier authState = AuthStateNotifier();
  final FavoritesStateNotifier favoritesState = FavoritesStateNotifier();
  final SearchStateNotifier searchState = SearchStateNotifier();
  late final NotificationStateNotifier notificationState;
  late final MessagingStateNotifier messagingState;
  late final BookingLifecycleService bookingLifecycleService;
  late final BookingConversationService bookingConversationService;
  late final BookingMessagingCoordinator bookingMessagingCoordinator;

  @override
  void initState() {
    super.initState();

    // Web only: offer a refresh when a newer build is deployed while this
    // tab stays open (reloads always get the newest build; idle tabs don't).
    WebUpdateService.instance.start(onUpdateAvailable: _showUpdateBanner);

    // Web only: track whether the browser can add Musaafir to the home screen,
    // so the smart sidebar can offer it. Must start early — Chrome fires
    // `beforeinstallprompt` shortly after load.
    PwaInstallService.instance.start();

    // Initialize Supabase repository
    repository = SupabaseMusafirRepository();

    // Initialize booking lifecycle service
    bookingLifecycleService = BookingLifecycleService(
      store: repository,
      rules: BookingRules(),
    );

    // Initialize booking conversation service
    bookingConversationService = BookingConversationService(
      conversationRepository: SupabaseConversationRepository.instance,
      messagingService: SupabaseMessagingService.instance,
      templateProvider: SupabaseMessageTemplateRepository.instance,
    );

    // Initialize booking-messaging coordinator. On accept, ask the server to
    // send the map now (and check-in details for imminent/hourly bookings).
    bookingMessagingCoordinator = BookingMessagingCoordinator(
      lifecycleService: bookingLifecycleService,
      conversationService: bookingConversationService,
      onBookingAccepted: (bookingId) async {
        await Supabase.instance.client.rpc(
          'send_booking_accept_messages',
          params: {'p_booking_id': bookingId},
        );
      },
    );

    // Initialize notification state with appropriate service
    notificationState = NotificationStateNotifier(
      service: NotificationServiceFactory.instance,
    );

    // Initialize messaging state with repository and service
    messagingState = MessagingStateNotifier(
      conversationRepository: SupabaseConversationRepository.instance,
      messagingService: SupabaseMessagingService.instance,
    );

    // The notifications realtime channel is the most reliable delivery path
    // (simple RLS), so let a new_message notification also refresh the
    // Messages tab unread badge.
    notificationState.onNewNotification = (notification) {
      if (notification.type == NotificationType.newMessage) {
        messagingState.refreshConversations();
      }
      // A booking-status change (host accepts/declines, check-in, etc.) isn't
      // reliably delivered by the bookings realtime channel, so refresh the
      // booking list off the reliable notification channel — this is what makes
      // the guest's Trips update the moment the host accepts, no manual pull.
      if (_isBookingNotification(notification.type)) {
        final user = authState.currentUser;
        if (user != null) {
          repository.resetBookingsPagination(user.id);
        }
      }
      // Surface an in-app toast for every live notification. This is the only
      // "popup" on web (OS push is stubbed there) and also shows in the
      // foreground on mobile. Fires only on realtime inserts, so no startup spam.
      _showNotificationToast(notification);
    };

    // A signed-out visitor tapping the wishlist heart gets a login instead of
    // silence. Wired here, through the app-wide navigator, because the heart
    // lives in stateless card widgets with no context of their own — the same
    // reason _showNotificationToast uses this key.
    favoritesState.onSignInRequired = () async {
      final context = _navigatorKey.currentContext;
      if (context == null) return;
      await AuthFlow.ensureSignedIn(
        context,
        authState,
        reason: 'to save places you like',
      );
    };

    // Initialize search state with listings
    _initializeSearchState();

    // Listen for repository changes to update search
    repository.addListener(_onRepositoryChange);

    // Listen for auth changes to initialize/clear notifications
    authState.addListener(_onAuthStateChanged);
  }

  void _onAuthStateChanged() {
    if (authState.isLoggedIn && authState.currentUser != null) {
      final userId = authState.currentUser!.id;

      // Only (re)initialise per-user state when the signed-in USER actually
      // changes — a first login or a switch to a different account. authState
      // notifies on EVERY auth event, including the routine token refresh that
      // fires on app resume and the userUpdated event after a profile/avatar
      // edit. Without this guard each of those would call
      // repository.resetForAuthChange(), which clears the listings/bookings
      // cache and notifies BEFORE the refetch completes — flashing a blank
      // feed (worse after idle, when the refetch is a cold network call).
      if (userId == _lastAuthedUserId) return;
      _lastAuthedUserId = userId;

      // User logged in (or switched) - initialize notifications, favorites,
      // and messaging.
      notificationState.initialize(userId);
      favoritesState.initializeForUser(userId);
      messagingState.initialize(userId);

      // Re-fetch data and (re-)subscribe to booking realtime for this user.
      // The subscription is created once in the repository constructor, so a
      // login after a logged-out start or a re-login needs this to get live
      // updates and to drop any previous user's cached data.
      repository.resetForAuthChange();

      // Save FCM token to Supabase for push notifications
      FcmTokenService.instance.initializeForUser();
    } else {
      // Ignore repeat logged-out notifications; only tear down on the actual
      // authenticated -> logged-out transition.
      if (_lastAuthedUserId == null) return;
      _lastAuthedUserId = null;

      // User logged out - clear all per-user state and deactivate FCM token.
      notificationState.clear();
      favoritesState.clearAll();
      messagingState.clear();
      repository.clearSession();
      FcmTokenService.instance.cleanupOnLogout();
    }
  }

  /// Whether a notification reflects a booking-lifecycle change that should
  /// refresh the cached bookings (so Trips/Reservations update without a manual
  /// pull-to-refresh).
  bool _isBookingNotification(NotificationType type) {
    switch (type) {
      case NotificationType.bookingRequest:
      case NotificationType.bookingConfirmed:
      case NotificationType.bookingCancelled:
      case NotificationType.bookingReminder:
      case NotificationType.checkInReminder:
      case NotificationType.checkOutReminder:
      // A settled payment flips booking.payment_status; refresh so the guest's
      // Trips shows "paid" and the host's Reservations unlocks "mark complete".
      case NotificationType.paymentReceived:
      case NotificationType.paymentFailed:
        return true;
      default:
        return false;
    }
  }

  /// Shows a transient in-app toast for a freshly-arrived realtime
  /// notification, using the root navigator's overlay so it works from any
  /// screen (and on web, where OS push is unavailable).
  void _showNotificationToast(AppNotification notification) {
    final context = _navigatorKey.currentContext;
    if (context == null) return;
    final body = notification.body.trim();
    final message =
        body.isEmpty ? notification.title : '${notification.title} · $body';
    ModernBanner.showInfo(context, message);
  }

  Future<void> _initializeSearchState() async {
    // Explore search runs server-side over the full catalog.
    searchState.attachSearcher(repository.searchListingsFromDb);
  }

  void _onRepositoryChange() {
    // Search results are a server-side snapshot; the default feed updates
    // itself via the repository's own listeners, so nothing to sync here.
  }

  /// A newer build was deployed while this tab was open — offer a refresh.
  void _showUpdateBanner() {
    final messenger = _scaffoldMessengerKey.currentState;
    if (messenger == null) return;
    messenger.showMaterialBanner(
      MaterialBanner(
        leading: const Icon(Icons.system_update_alt_rounded),
        content: const Text('A new version of Musafir is available.'),
        actions: [
          TextButton(
            onPressed: () => WebUpdateService.instance.reloadForUpdate(),
            child: const Text('Refresh'),
          ),
          TextButton(
            onPressed: messenger.hideCurrentMaterialBanner,
            child: const Text('Later'),
          ),
        ],
      ),
    );
  }

  @override
  void dispose() {
    WebUpdateService.instance.stop();
    authState.removeListener(_onAuthStateChanged);
    repository.removeListener(_onRepositoryChange);
    authState.dispose();
    favoritesState.dispose();
    searchState.dispose();
    notificationState.dispose();
    messagingState.dispose();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    // Which palette the app wears is an admin setting, not a compile-time fact,
    // and it can land mid-session: boot paints the locally cached theme and the
    // background app_settings load confirms or corrects it a moment later. So
    // MaterialApp is rebuilt from the controller rather than given a fixed theme.
    //
    // The whole subtree rebuilds with it, which matters beyond ThemeData: most
    // screens read `AppColors.brand` and friends directly rather than going
    // through Theme.of(context), and those getters answer from the active
    // palette. ThemeController updates AppColors before notifying, so a rebuild
    // triggered here always sees consistent values.
    return ValueListenableBuilder<AppPalette>(
      valueListenable: ThemeController.instance,
      builder: (context, palette, _) => _buildApp(AppTheme.forPalette(palette)),
    );
  }

  Widget _buildApp(ThemeData theme) {
    return MaterialApp(
      title: 'Musaafir',
      navigatorKey: _navigatorKey,
      scaffoldMessengerKey: _scaffoldMessengerKey,
      debugShowCheckedModeBanner: false,
      // The design system is light-only; pinning themeMode (plus
      // forceDarkAllowed=false in the Android styles) stops OEM "force dark"
      // from auto-inverting the UI into an unreadable mix.
      theme: theme,
      darkTheme: theme,
      themeMode: ThemeMode.light,
      // No crossfade on a theme swap. MaterialApp lerps theme changes over
      // 200ms by default, and during that lerp Theme.of(context) is still
      // part-way to the new palette while the AppColors getters — which most
      // screens read directly — have already snapped. That renders frames with
      // two different brand colours on them. A palette arriving from
      // app_settings is a correction, not a gesture the user made, so it has
      // nothing to animate; swapping instantly keeps every frame internally
      // consistent. Guarded by theme_controller_test's live-swap test.
      themeAnimationDuration: Duration.zero,
      // Named routes exist for one reason: a listing needs a URL somebody can
      // send to a friend. Everything else still navigates by pushing a
      // constructed screen, which is fine — those have no shareable identity.
      //
      // There is deliberately NO `home:` here. MaterialApp asserts
      // `home == null || onGenerateInitialRoutes == null` ("the home argument
      // will be redundant"), so the shell is produced by both callbacks below
      // instead — _onGenerateRoute answers '/' with it.
      onGenerateRoute: _onGenerateRoute,
      // A cold `/listing/<id>` must open with the shell UNDERNEATH it, so Back
      // (and the browser's back button) lands on Explore instead of exiting to
      // a blank page. Flutter's default would split the path into a route per
      // segment, which for '/listing/abc' means asking for '/listing' too —
      // a route that does not exist.
      onGenerateInitialRoutes: (initialRoute) => [
        _rootRoute(),
        if (listingIdFromRoute(initialRoute) case final id?)
          MaterialPageRoute(
            settings: RouteSettings(name: initialRoute),
            builder: (_) => _listingRoute(id),
          ),
      ],
    );
  }

  MaterialPageRoute<dynamic> _rootRoute() => MaterialPageRoute(
        settings: const RouteSettings(name: '/'),
        builder: (_) => _root(),
      );

  /// The app itself: shell once auth has resolved, splash until then.
  Widget _root() {
    return ListenableBuilder(
      listenable: authState,
      builder: (context, _) {
        // Browsing is public: the shell is the app for a signed-out visitor
        // too, and login is reached from whatever they tried to do
        // (AuthFlow.ensureSignedIn) rather than being the front door.
        //
        // Returning the SAME widget type from both post-initializing states
        // is load-bearing, not tidiness. Flutter updates an element in place
        // when the type and key match, so signing in mid-session keeps
        // MainShell's State — the selected tab, each tab's scroll offset,
        // the _LazyIndexedStack's already-built children. Branching to a
        // different widget here would rebuild all of it, which is exactly
        // what the old `unauthenticated → AuthNavigator` arm did on every
        // login.
        //
        // MainShell already tolerates a null user throughout: host mode is
        // unreachable while signed out, and the repository's refresh,
        // own-listings load and bookings realtime subscription all
        // early-return without a session.
        if (authState.status == AuthStatus.initializing) {
          // Still deciding whether a stored session is valid. Not "signed
          // out" — showing the shell here would flash a guest feed at a
          // returning user before their session resolves.
          return const SplashScreen();
        }
        return MainShell(
          repository: repository,
          authState: authState,
          favoritesState: favoritesState,
          searchState: searchState,
          notificationState: notificationState,
          messagingState: messagingState,
          bookingLifecycleService: bookingLifecycleService,
          bookingMessagingCoordinator: bookingMessagingCoordinator,
        );
      },
    );
  }

  Widget _listingRoute(String id, {Listing? listing}) => ListingRoute(
        listingId: id,
        listing: listing,
        repository: repository,
        authState: authState,
        favoritesState: favoritesState,
        messagingState: messagingState,
      );

  Route<dynamic>? _onGenerateRoute(RouteSettings settings) {
    final name = settings.name ?? '';

    final id = listingIdFromRoute(name);
    if (id == null) {
      // With no `home:`, this is the only thing that can answer '/'. Any other
      // name gets the shell too rather than null: returning null here leaves
      // the app with no route at all, and every in-app path ('/trips' as a
      // cold URL, since the SPA rule serves index.html for it) is a tab inside
      // the shell, not a route.
      return _rootRoute();
    }

    return MaterialPageRoute(
      settings: settings,
      // A tap on a card passes the Listing through `arguments`, so the screen
      // renders immediately and the URL still changes; a pasted link has no
      // arguments and ListingRoute fetches by id.
      builder: (_) => _listingRoute(
        id,
        listing: settings.arguments is Listing
            ? settings.arguments as Listing
            : null,
      ),
    );
  }
}

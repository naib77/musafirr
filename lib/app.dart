import 'package:flutter/material.dart';
import 'package:supabase_flutter/supabase_flutter.dart';

import 'core/theme/app_theme.dart';
import 'models/notification.dart';
import 'repositories/supabase_musafir_repository.dart';
import 'screens/auth/otp_verification_screen.dart';
import 'screens/auth/phone_entry_screen.dart';
import 'screens/auth/profile_completion_screen.dart';
import 'screens/main_shell.dart';
import 'screens/splash/splash_screen.dart';
import 'services/booking/booking_lifecycle_service.dart';
import 'services/booking/booking_messaging_coordinator.dart';
import 'services/booking/booking_rules.dart';
import 'repositories/supabase_conversation_repository.dart';
import 'repositories/supabase_message_template_repository.dart';
import 'services/messaging/booking_conversation_service.dart';
import 'services/messaging/supabase_messaging_service.dart';
import 'services/notifications/fcm_token_service.dart';
import 'services/web_update_service.dart';
import 'services/notifications/notification_service_factory.dart';
import 'state/auth_state.dart';
import 'state/favorites_state.dart';
import 'state/messaging_state.dart';
import 'state/notification_state.dart';
import 'state/otp_state.dart';
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

    // Initialize search state with listings
    _initializeSearchState();

    // Listen for repository changes to update search
    repository.addListener(_onRepositoryChange);

    // Listen for auth changes to initialize/clear notifications
    authState.addListener(_onAuthStateChanged);
  }

  void _onAuthStateChanged() {
    if (authState.isLoggedIn && authState.currentUser != null) {
      // User logged in - initialize notifications, favorites, and messaging
      notificationState.initialize(authState.currentUser!.id);
      favoritesState.initializeForUser(authState.currentUser!.id);
      messagingState.initialize(authState.currentUser!.id);

      // Re-fetch data and (re-)subscribe to booking realtime for this user.
      // The subscription is created once in the repository constructor, so a
      // login after a logged-out start or a re-login needs this to get live
      // updates and to drop any previous user's cached data.
      repository.resetForAuthChange();

      // Save FCM token to Supabase for push notifications
      FcmTokenService.instance.initializeForUser();
    } else {
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
    return MaterialApp(
      title: 'Musaafir',
      navigatorKey: _navigatorKey,
      scaffoldMessengerKey: _scaffoldMessengerKey,
      debugShowCheckedModeBanner: false,
      // The design system is light-only; pinning themeMode (plus
      // forceDarkAllowed=false in the Android styles) stops OEM "force dark"
      // from auto-inverting the UI into an unreadable mix.
      theme: AppTheme.light,
      darkTheme: AppTheme.light,
      themeMode: ThemeMode.light,
      home: ListenableBuilder(
        listenable: authState,
        builder: (context, _) {
          // Three-state auth flow: initializing → authenticated | unauthenticated
          switch (authState.status) {
            case AuthStatus.initializing:
              // Show splash screen while determining auth state
              return const SplashScreen();

            case AuthStatus.authenticated:
              // User is logged in - show main app
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

            case AuthStatus.unauthenticated:
              // No user - show login flow
              return AuthNavigator(authState: authState);
          }
        },
      ),
    );
  }
}

/// Auth screen type for navigation
enum AuthScreen {
  phoneEntry,
  otpVerification,
  profileCompletion,
}

/// Handles navigation between login and signup screens
class AuthNavigator extends StatefulWidget {
  const AuthNavigator({super.key, required this.authState});

  final AuthStateNotifier authState;

  @override
  State<AuthNavigator> createState() => _AuthNavigatorState();
}

class _AuthNavigatorState extends State<AuthNavigator> {
  AuthScreen _currentScreen = AuthScreen.phoneEntry;
  final OtpStateNotifier _otpState = OtpStateNotifier();

  @override
  void initState() {
    super.initState();
    // Listen to OTP state changes to handle navigation
    _otpState.addListener(_onOtpStateChanged);
  }

  @override
  void dispose() {
    _otpState.removeListener(_onOtpStateChanged);
    _otpState.dispose();
    super.dispose();
  }

  void _onOtpStateChanged() {
    setState(() {
      switch (_otpState.currentStep) {
        case OtpFlowStep.phoneEntry:
          _currentScreen = AuthScreen.phoneEntry;
          break;
        case OtpFlowStep.otpVerification:
          _currentScreen = AuthScreen.otpVerification;
          break;
        case OtpFlowStep.profileCompletion:
          _currentScreen = AuthScreen.profileCompletion;
          break;
        case OtpFlowStep.complete:
          // Auth state will handle navigation to main shell
          break;
      }
    });
  }

  @override
  Widget build(BuildContext context) {
    switch (_currentScreen) {
      case AuthScreen.phoneEntry:
        return PhoneEntryScreen(
          otpState: _otpState,
        );

      case AuthScreen.otpVerification:
        return OtpVerificationScreen(otpState: _otpState);

      case AuthScreen.profileCompletion:
        return ProfileCompletionScreen(
          otpState: _otpState,
          authState: widget.authState,
        );
    }
  }
}

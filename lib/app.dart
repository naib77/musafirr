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

  @override
  void dispose() {
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
      title: 'Musafir',
      navigatorKey: _navigatorKey,
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

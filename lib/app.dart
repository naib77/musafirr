import 'package:flutter/material.dart';

import 'repositories/in_memory_musafir_repository.dart';
import 'repositories/musafir_repository.dart';
import 'repositories/supabase_musafir_repository.dart';
import 'screens/auth/login_screen.dart';
import 'screens/auth/otp_verification_screen.dart';
import 'screens/auth/phone_entry_screen.dart';
import 'screens/auth/profile_completion_screen.dart';
import 'screens/auth/signup_screen.dart';
import 'screens/main_shell.dart';
import 'state/auth_state.dart';
import 'state/favorites_state.dart';
import 'state/otp_state.dart';
import 'state/search_state.dart';

class MusafirApp extends StatefulWidget {
  const MusafirApp({super.key, this.useSupabase = false});

  final bool useSupabase;

  @override
  State<MusafirApp> createState() => _MusafirAppState();
}

class _MusafirAppState extends State<MusafirApp> {
  late final MusafirRepository repository;
  late final InMemoryMusafirRepository? _inMemoryRepo;
  final AuthStateNotifier authState = AuthStateNotifier();
  final FavoritesStateNotifier favoritesState = FavoritesStateNotifier();
  final SearchStateNotifier searchState = SearchStateNotifier();

  @override
  void initState() {
    super.initState();

    // Initialize repository based on configuration
    if (widget.useSupabase) {
      repository = SupabaseMusafirRepository();
      _inMemoryRepo = null;
    } else {
      final inMemory = InMemoryMusafirRepository();
      repository = inMemory;
      _inMemoryRepo = inMemory;
    }

    // Initialize search state with listings
    _initializeSearchState();

    // Listen for repository changes (only for in-memory repo)
    _inMemoryRepo?.addListener(_onRepositoryChange);
  }

  Future<void> _initializeSearchState() async {
    searchState.setListings(repository.listings);
  }

  void _onRepositoryChange() {
    searchState.setListings(repository.listings);
  }

  @override
  void dispose() {
    _inMemoryRepo?.removeListener(_onRepositoryChange);
    _inMemoryRepo?.dispose();
    authState.dispose();
    favoritesState.dispose();
    searchState.dispose();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    return MaterialApp(
      title: 'Musafir',
      debugShowCheckedModeBanner: false,
      theme: ThemeData(
        colorScheme: ColorScheme.fromSeed(
          seedColor: const Color(0xFF0B7285),
          brightness: Brightness.light,
        ),
        scaffoldBackgroundColor: const Color(0xFFF6F8F7),
        useMaterial3: true,
      ),
      home: ListenableBuilder(
        listenable: authState,
        builder: (context, _) {
          if (authState.isLoggedIn) {
            return MainShell(
              repository: repository,
              authState: authState,
              favoritesState: favoritesState,
              searchState: searchState,
            );
          }
          return AuthNavigator(authState: authState);
        },
      ),
    );
  }
}

/// Auth screen type for navigation
enum AuthScreen {
  login,
  emailSignup,
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
  AuthScreen _currentScreen = AuthScreen.login;
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

  void _navigateTo(AuthScreen screen) {
    setState(() => _currentScreen = screen);
    if (screen == AuthScreen.login) {
      _otpState.reset();
    }
  }

  @override
  Widget build(BuildContext context) {
    switch (_currentScreen) {
      case AuthScreen.login:
        return LoginScreen(
          authState: widget.authState,
          onSignupTap: () => _navigateTo(AuthScreen.emailSignup),
          onPhoneSignupTap: () => _navigateTo(AuthScreen.phoneEntry),
        );

      case AuthScreen.emailSignup:
        return SignupScreen(
          authState: widget.authState,
          onLoginTap: () => _navigateTo(AuthScreen.login),
        );

      case AuthScreen.phoneEntry:
        return PhoneEntryScreen(
          otpState: _otpState,
          onEmailSignupTap: () => _navigateTo(AuthScreen.emailSignup),
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

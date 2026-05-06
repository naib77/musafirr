import 'package:flutter/material.dart';

import 'repositories/in_memory_musafir_repository.dart';
import 'screens/auth/login_screen.dart';
import 'screens/auth/signup_screen.dart';
import 'screens/main_shell.dart';
import 'state/auth_state.dart';
import 'state/favorites_state.dart';
import 'state/search_state.dart';

class MusafirApp extends StatefulWidget {
  const MusafirApp({super.key});

  @override
  State<MusafirApp> createState() => _MusafirAppState();
}

class _MusafirAppState extends State<MusafirApp> {
  final InMemoryMusafirRepository repository = InMemoryMusafirRepository();
  final AuthStateNotifier authState = AuthStateNotifier();
  final FavoritesStateNotifier favoritesState = FavoritesStateNotifier();
  final SearchStateNotifier searchState = SearchStateNotifier();

  @override
  void initState() {
    super.initState();
    // Initialize search state with listings
    searchState.setListings(repository.listings);
    // Listen for repository changes
    repository.addListener(_onRepositoryChange);
  }

  void _onRepositoryChange() {
    searchState.setListings(repository.listings);
  }

  @override
  void dispose() {
    repository.removeListener(_onRepositoryChange);
    repository.dispose();
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

/// Handles navigation between login and signup screens
class AuthNavigator extends StatefulWidget {
  const AuthNavigator({super.key, required this.authState});

  final AuthStateNotifier authState;

  @override
  State<AuthNavigator> createState() => _AuthNavigatorState();
}

class _AuthNavigatorState extends State<AuthNavigator> {
  bool _showSignup = false;

  @override
  Widget build(BuildContext context) {
    if (_showSignup) {
      return SignupScreen(
        authState: widget.authState,
        onLoginTap: () => setState(() => _showSignup = false),
      );
    }
    return LoginScreen(
      authState: widget.authState,
      onSignupTap: () => setState(() => _showSignup = true),
    );
  }
}

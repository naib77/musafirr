import 'dart:async';

import 'package:flutter/foundation.dart';
import '../core/state/safe_notifier.dart';

import '../models/user.dart';
import '../services/auth/auth_service.dart';
import '../services/auth/auth_service_factory.dart';

/// Authentication status for the app startup flow.
///
/// - [initializing]: Auth state is being determined (show splash screen)
/// - [authenticated]: User is logged in (show main app)
/// - [unauthenticated]: No user logged in (show login screen)
enum AuthStatus {
  initializing,
  authenticated,
  unauthenticated,
}

/// Authentication state notifier for the application.
///
/// Delegates to [AuthService] (either Mock or Supabase implementation).
/// Maintains the same public interface for all 17+ consumer files.
class AuthStateNotifier extends ChangeNotifier with SafeNotifier {
  AuthStateNotifier() {
    _service = AuthServiceFactory.instance;
    _subscription = _service.authStateChanges.listen(_onAuthChange);
    _currentUser = _service.currentUser;

    // Start initialization - will complete when auth state is determined
    _initializeAuthState();
  }

  late final AuthService _service;
  StreamSubscription<User?>? _subscription;

  User? _currentUser;
  bool _isLoading = false;
  String? _error;
  AuthStatus _status = AuthStatus.initializing;
  bool _hasReceivedFirstAuthEvent = false;

  User? get currentUser => _currentUser;
  bool get isLoggedIn => _currentUser != null;
  bool get isLoading => _isLoading;
  String? get error => _error;
  bool get isHost => _currentUser?.isHost ?? false;

  /// Current authentication status (initializing, authenticated, unauthenticated)
  AuthStatus get status => _status;

  /// Initialize auth state from the persisted session.
  ///
  /// A restored session is available synchronously (before the user profile
  /// finishes loading over the network). So we decide the startup status from
  /// the session, NOT from whether the profile has loaded yet:
  ///
  /// - Session present -> the user IS authenticated. We stay on the splash
  ///   screen (status = initializing) until the profile arrives via
  ///   [_onAuthChange], so the login screen never flashes. A safety timeout
  ///   marks the user authenticated even if the profile fetch stalls.
  /// - No session -> mark unauthenticated after a brief grace period that
  ///   lets the auth service emit its first event.
  Future<void> _initializeAuthState() async {
    final hasSession = _service.hasActiveSession;

    // A session that exists means a logged-in user; give the profile fetch a
    // generous window. Without a session, only a short grace period is needed.
    await Future.delayed(
      hasSession
          ? const Duration(seconds: 8)
          : const Duration(milliseconds: 400),
    );

    // If the profile already loaded, _onAuthChange has set the status.
    if (_hasReceivedFirstAuthEvent) return;

    _hasReceivedFirstAuthEvent = true;
    // Trust the session: if one exists, the user is authenticated even if the
    // profile fetch hasn't completed yet.
    _status = (hasSession || _currentUser != null)
        ? AuthStatus.authenticated
        : AuthStatus.unauthenticated;
    notifyListeners();
  }

  void _onAuthChange(User? user) {
    _currentUser = user;

    // Update status on auth change
    if (!_hasReceivedFirstAuthEvent || _status == AuthStatus.initializing) {
      _hasReceivedFirstAuthEvent = true;
      _status = user != null
          ? AuthStatus.authenticated
          : AuthStatus.unauthenticated;
    } else {
      // Subsequent auth changes (login/logout during app use)
      _status = user != null
          ? AuthStatus.authenticated
          : AuthStatus.unauthenticated;
    }

    notifyListeners();
  }

  /// Upgrade current user to host status
  Future<bool> becomeHost() async {
    if (_currentUser == null) return false;

    _isLoading = true;
    notifyListeners();

    final result = await _service.becomeHost();

    _isLoading = false;
    if (result.success) {
      _currentUser = result.user;
      notifyListeners();
      return true;
    }

    _error = result.error;
    notifyListeners();
    return false;
  }

  /// Update user profile
  void updateUser(User updatedUser) {
    _service.updateProfile(updatedUser);
    if (_currentUser?.id == updatedUser.id) {
      _currentUser = updatedUser;
    }
    notifyListeners();
  }

  /// Update user avatar
  void updateAvatar(String? avatarUrl) {
    if (_currentUser == null) return;

    final updatedUser = _currentUser!.copyWith(avatarUrl: avatarUrl);
    updateUser(updatedUser);
  }

  void logout() {
    _service.logout();
    _currentUser = null;
    _error = null;
    _status = AuthStatus.unauthenticated;
    notifyListeners();
  }

  void clearError() {
    _error = null;
    notifyListeners();
  }

  // Get user by ID (for repository use)
  User? getUserById(String id) {
    return _service.getUserById(id);
  }

  // Get user by email (for repository use)
  User? getUserByEmail(String email) {
    return _service.getUserByEmail(email);
  }

  // Get user by phone number
  User? getUserByPhone(String phone) {
    return _service.getUserByPhone(phone);
  }

  /// Sign up with phone number (after OTP verification)
  Future<bool> signupWithPhone({
    required String phone,
    required String name,
    required String nid,
    String? email,
  }) async {
    _isLoading = true;
    _error = null;
    notifyListeners();

    final result = await _service.completePhoneSignup(
      phone: phone,
      name: name,
      nid: nid,
      email: email,
    );

    _isLoading = false;
    if (result.success) {
      _currentUser = result.user;
      notifyListeners();
      return true;
    }

    _error = result.error ?? 'Signup failed';
    notifyListeners();
    return false;
  }

  /// Login with phone number (for returning phone-registered users)
  Future<bool> loginWithPhone(String phone) async {
    _isLoading = true;
    _error = null;
    notifyListeners();

    final result = await _service.loginWithPhone(phone);

    _isLoading = false;
    if (result.success) {
      _currentUser = result.user;
      notifyListeners();
      return true;
    }

    _error = result.error ?? 'No account found with this phone number';
    notifyListeners();
    return false;
  }

  @override
  void dispose() {
    _subscription?.cancel();
    super.dispose();
  }
}

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

  /// Initialize auth state - waits for first auth event or timeout
  Future<void> _initializeAuthState() async {
    // Give the auth service time to check existing session and load profile
    // This covers the async gap between session check and profile load
    await Future.delayed(const Duration(milliseconds: 1500));

    // If we still haven't received an auth event, determine status from current state
    if (!_hasReceivedFirstAuthEvent) {
      _hasReceivedFirstAuthEvent = true;
      _status = _currentUser != null
          ? AuthStatus.authenticated
          : AuthStatus.unauthenticated;
      notifyListeners();
    }
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

  Future<bool> login(String email, String password) async {
    _isLoading = true;
    _error = null;
    notifyListeners();

    final result = await _service.loginWithEmail(email, password);

    _isLoading = false;
    if (result.success) {
      _currentUser = result.user;
      notifyListeners();
      return true;
    }

    _error = result.error ?? 'Invalid email or password';
    notifyListeners();
    return false;
  }

  Future<bool> signup({
    required String name,
    required String email,
    required String password,
  }) async {
    _isLoading = true;
    _error = null;
    notifyListeners();

    final result = await _service.signupWithEmail(
      name: name,
      email: email,
      password: password,
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

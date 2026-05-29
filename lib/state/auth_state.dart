import 'dart:async';

import 'package:flutter/foundation.dart';

import '../models/user.dart';
import '../services/auth/auth_service.dart';
import '../services/auth/auth_service_factory.dart';

/// Authentication state notifier for the application.
///
/// Delegates to [AuthService] (either Mock or Supabase implementation).
/// Maintains the same public interface for all 17+ consumer files.
class AuthStateNotifier extends ChangeNotifier {
  AuthStateNotifier() {
    _service = AuthServiceFactory.instance;
    _subscription = _service.authStateChanges.listen(_onAuthChange);
    _currentUser = _service.currentUser;
  }

  late final AuthService _service;
  StreamSubscription<User?>? _subscription;

  User? _currentUser;
  bool _isLoading = false;
  String? _error;

  User? get currentUser => _currentUser;
  bool get isLoggedIn => _currentUser != null;
  bool get isLoading => _isLoading;
  String? get error => _error;
  bool get isHost => _currentUser?.isHost ?? false;

  void _onAuthChange(User? user) {
    _currentUser = user;
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

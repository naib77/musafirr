import 'package:flutter/foundation.dart';

import '../models/user.dart';
import '../models/user_role.dart';

class AuthStateNotifier extends ChangeNotifier {
  User? _currentUser;
  bool _isLoading = false;
  String? _error;

  User? get currentUser => _currentUser;
  bool get isLoggedIn => _currentUser != null;
  bool get isLoading => _isLoading;
  String? get error => _error;
  bool get isHost => _currentUser?.isHost ?? false;

  // Mock users database (keyed by email)
  final Map<String, User> _users = {
    'demo@musafir.com': const User(
      id: 'user_1',
      name: 'Demo User',
      email: 'demo@musafir.com',
      avatarUrl: 'https://ui-avatars.com/api/?name=Demo+User&background=0B7285&color=fff&size=150',
      role: UserRole.tenant,
      phone: '+880 1712345678',
      registrationMethod: RegistrationMethod.email,
    ),
    'owner@musafir.com': User(
      id: 'user_2',
      name: 'Property Owner',
      email: 'owner@musafir.com',
      avatarUrl: 'https://ui-avatars.com/api/?name=Property+Owner&background=1098AD&color=fff&size=150',
      role: UserRole.owner,
      phone: '+880 1812345678',
      isHost: true,
      hostSince: DateTime(2023, 6, 15),
      bio: 'Experienced host with multiple properties in Dhaka.',
      responseRate: 98,
      responseTime: 'within an hour',
      registrationMethod: RegistrationMethod.email,
    ),
    'admin@musafir.com': const User(
      id: 'user_3',
      name: 'Admin User',
      email: 'admin@musafir.com',
      avatarUrl: 'https://ui-avatars.com/api/?name=Admin+User&background=7048E8&color=fff&size=150',
      role: UserRole.admin,
      phone: '+880 1912345678',
      registrationMethod: RegistrationMethod.email,
    ),
  };

  // Phone to user ID mapping for phone-based users
  final Map<String, String> _phoneToUserId = {};

  Future<bool> login(String email, String password) async {
    _isLoading = true;
    _error = null;
    notifyListeners();

    // Simulate network delay
    await Future.delayed(const Duration(milliseconds: 800));

    // Mock authentication: any email with password "password123"
    if (password == 'password123') {
      // Check if user exists, otherwise create a new tenant user
      if (_users.containsKey(email.toLowerCase())) {
        _currentUser = _users[email.toLowerCase()];
      } else {
        // Create new user on the fly for any email with correct password
        final newUser = User(
          id: 'user_${DateTime.now().millisecondsSinceEpoch}',
          name: email
              .split('@')
              .first
              .replaceAll('.', ' ')
              .split(' ')
              .map(
                (word) => word.isNotEmpty
                    ? '${word[0].toUpperCase()}${word.substring(1)}'
                    : '',
              )
              .join(' '),
          email: email.toLowerCase(),
          role: UserRole.tenant,
          createdAt: DateTime.now(),
        );
        _users[email.toLowerCase()] = newUser;
        _currentUser = newUser;
      }
      _isLoading = false;
      notifyListeners();
      return true;
    }

    _error = 'Invalid email or password';
    _isLoading = false;
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

    // Simulate network delay
    await Future.delayed(const Duration(milliseconds: 800));

    // Check if email already exists
    if (_users.containsKey(email.toLowerCase())) {
      _error = 'An account with this email already exists';
      _isLoading = false;
      notifyListeners();
      return false;
    }

    // Validate password
    if (password.length < 6) {
      _error = 'Password must be at least 6 characters';
      _isLoading = false;
      notifyListeners();
      return false;
    }

    // Create new user
    final newUser = User(
      id: 'user_${DateTime.now().millisecondsSinceEpoch}',
      name: name,
      email: email.toLowerCase(),
      role: UserRole.tenant,
      createdAt: DateTime.now(),
    );
    _users[email.toLowerCase()] = newUser;
    _currentUser = newUser;

    _isLoading = false;
    notifyListeners();
    return true;
  }

  /// Upgrade current user to host status
  Future<bool> becomeHost() async {
    if (_currentUser == null) return false;

    _isLoading = true;
    notifyListeners();

    // Simulate network delay
    await Future.delayed(const Duration(milliseconds: 500));

    final updatedUser = _currentUser!.copyWith(
      isHost: true,
      hostSince: DateTime.now(),
      role: UserRole.owner,
    );

    if (_currentUser!.email != null) {
      _users[_currentUser!.email!.toLowerCase()] = updatedUser;
    }
    _currentUser = updatedUser;

    _isLoading = false;
    notifyListeners();
    return true;
  }

  /// Update user profile
  void updateUser(User updatedUser) {
    if (updatedUser.email != null) {
      _users[updatedUser.email!.toLowerCase()] = updatedUser;
    }
    if (_currentUser?.id == updatedUser.id) {
      _currentUser = updatedUser;
    }
    notifyListeners();
  }

  void logout() {
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
    return _users.values.where((u) => u.id == id).firstOrNull;
  }

  // Get user by email (for repository use)
  User? getUserByEmail(String email) {
    return _users[email.toLowerCase()];
  }

  // Get user by phone number
  User? getUserByPhone(String phone) {
    final normalized = _normalizePhone(phone);
    final userId = _phoneToUserId[normalized];
    if (userId == null) return null;
    return _users.values.where((u) => u.id == userId).firstOrNull;
  }

  /// Normalize phone number for storage
  String _normalizePhone(String phone) {
    var normalized = phone.replaceAll(RegExp(r'[\s\-\(\)\+]'), '');
    if (normalized.startsWith('880')) {
      normalized = '0${normalized.substring(3)}';
    }
    return normalized;
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

    // Simulate network delay
    await Future.delayed(const Duration(milliseconds: 800));

    final normalizedPhone = _normalizePhone(phone);

    // Check if phone already exists
    if (_phoneToUserId.containsKey(normalizedPhone)) {
      _error = 'An account with this phone number already exists';
      _isLoading = false;
      notifyListeners();
      return false;
    }

    // Check if email already exists (if provided)
    if (email != null && email.isNotEmpty && _users.containsKey(email.toLowerCase())) {
      _error = 'An account with this email already exists';
      _isLoading = false;
      notifyListeners();
      return false;
    }

    // Create new user
    final userId = 'user_${DateTime.now().millisecondsSinceEpoch}';
    final newUser = User(
      id: userId,
      name: name,
      email: email,
      phone: '+880 $normalizedPhone',
      role: UserRole.tenant,
      createdAt: DateTime.now(),
      nid: nid,
      nidVerified: true,
      phoneVerified: true,
      registrationMethod: RegistrationMethod.phone,
    );

    // Store user
    if (email != null && email.isNotEmpty) {
      _users[email.toLowerCase()] = newUser;
    }
    _phoneToUserId[normalizedPhone] = userId;
    // Also store in _users with a phone-based key
    _users['phone:$normalizedPhone'] = newUser;

    _currentUser = newUser;
    _isLoading = false;
    notifyListeners();
    return true;
  }

  /// Login with phone number (for returning phone-registered users)
  Future<bool> loginWithPhone(String phone) async {
    _isLoading = true;
    _error = null;
    notifyListeners();

    // Simulate network delay
    await Future.delayed(const Duration(milliseconds: 800));

    final user = getUserByPhone(phone);
    if (user != null) {
      _currentUser = user;
      _isLoading = false;
      notifyListeners();
      return true;
    }

    _error = 'No account found with this phone number';
    _isLoading = false;
    notifyListeners();
    return false;
  }
}

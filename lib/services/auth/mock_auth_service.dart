import 'dart:async';

import 'package:flutter/foundation.dart';

import '../../models/user.dart';
import '../../models/user_role.dart';
import '../otp_service.dart';
import 'auth_service.dart';

/// Mock implementation of [AuthService] for development and demo mode.
///
/// Uses in-memory storage with predefined demo users.
/// Password "password123" works for any email login.
class MockAuthService implements AuthService {
  MockAuthService._();

  static MockAuthService? _instance;
  static MockAuthService get instance {
    _instance ??= MockAuthService._();
    return _instance!;
  }

  final OtpService _otpService = OtpService.instance;

  User? _currentUser;
  final _authStateController = StreamController<User?>.broadcast();

  // Mock users database (keyed by email)
  final Map<String, User> _users = {
    'demo@musafir.com': const User(
      id: 'user_1',
      name: 'Demo User',
      email: 'demo@musafir.com',
      avatarUrl:
          'https://ui-avatars.com/api/?name=Demo+User&background=0B7285&color=fff&size=150',
      role: UserRole.tenant,
      phone: '+880 1712345678',
      registrationMethod: RegistrationMethod.email,
    ),
    'owner@musafir.com': User(
      id: 'user_2',
      name: 'Property Owner',
      email: 'owner@musafir.com',
      avatarUrl:
          'https://ui-avatars.com/api/?name=Property+Owner&background=1098AD&color=fff&size=150',
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
      avatarUrl:
          'https://ui-avatars.com/api/?name=Admin+User&background=7048E8&color=fff&size=150',
      role: UserRole.admin,
      phone: '+880 1912345678',
      registrationMethod: RegistrationMethod.email,
    ),
  };

  // Phone to user ID mapping for phone-based users
  final Map<String, String> _phoneToUserId = {};

  @override
  User? get currentUser => _currentUser;

  @override
  bool get hasActiveSession => _currentUser != null;

  @override
  Stream<User?> get authStateChanges => _authStateController.stream;

  void _setCurrentUser(User? user) {
    _currentUser = user;
    _authStateController.add(user);
  }

  /// Normalize phone number for storage
  String _normalizePhone(String phone) {
    var normalized = phone.replaceAll(RegExp(r'[\s\-\(\)\+]'), '');
    if (normalized.startsWith('880')) {
      normalized = '0${normalized.substring(3)}';
    }
    return normalized;
  }

  @override
  Future<AuthResult> loginWithEmail(String email, String password) async {
    debugPrint('[MockAuthService] loginWithEmail: $email');

    // Simulate network delay
    await Future.delayed(const Duration(milliseconds: 800));

    // Mock authentication: any email with password "password123"
    if (password == 'password123') {
      // Check if user exists, otherwise create a new tenant user
      if (_users.containsKey(email.toLowerCase())) {
        final user = _users[email.toLowerCase()]!;
        _setCurrentUser(user);
        return AuthResult.success(user);
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
        _setCurrentUser(newUser);
        return AuthResult.success(newUser, isNewUser: true);
      }
    }

    return AuthResult.failure('Invalid email or password');
  }

  @override
  Future<AuthResult> signupWithEmail({
    required String name,
    required String email,
    required String password,
  }) async {
    debugPrint('[MockAuthService] signupWithEmail: $email');

    // Simulate network delay
    await Future.delayed(const Duration(milliseconds: 800));

    // Check if email already exists
    if (_users.containsKey(email.toLowerCase())) {
      return AuthResult.failure('An account with this email already exists');
    }

    // Validate password
    if (password.length < 6) {
      return AuthResult.failure('Password must be at least 6 characters');
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
    _setCurrentUser(newUser);

    return AuthResult.success(newUser, isNewUser: true);
  }

  @override
  Future<OtpResult> sendOtp(String phoneNumber) async {
    debugPrint('[MockAuthService] sendOtp: $phoneNumber');

    final result = await _otpService.sendOtp(phoneNumber);

    if (result.success) {
      return OtpResult.success();
    }
    return OtpResult.failure(result.errorMessage ?? 'Failed to send OTP');
  }

  @override
  Future<OtpResult> verifyOtp(String phoneNumber, String otp) async {
    debugPrint('[MockAuthService] verifyOtp: $phoneNumber');

    // Simulate slight delay for UX
    await Future.delayed(const Duration(milliseconds: 300));

    final result = await _otpService.verifyOtp(phoneNumber, otp);

    if (result.success) {
      // Check if user already exists
      final existingUser = getUserByPhone(phoneNumber);
      final isExistingUser = existingUser != null;
      debugPrint('[MockAuthService] isExistingUser: $isExistingUser');
      return OtpResult.success(isExistingUser: isExistingUser);
    }
    return OtpResult.failure(
      result.errorMessage ?? 'Invalid OTP',
      attemptsRemaining: result.attemptsRemaining,
    );
  }

  @override
  Future<AuthResult> completePhoneSignup({
    required String phone,
    required String name,
    required String nid,
    String? email,
  }) async {
    debugPrint('[MockAuthService] completePhoneSignup: $phone');

    // Simulate network delay
    await Future.delayed(const Duration(milliseconds: 800));

    final normalizedPhone = _normalizePhone(phone);

    // Check if phone already exists
    if (_phoneToUserId.containsKey(normalizedPhone)) {
      return AuthResult.failure(
          'An account with this phone number already exists');
    }

    // Check if email already exists (if provided)
    if (email != null &&
        email.isNotEmpty &&
        _users.containsKey(email.toLowerCase())) {
      return AuthResult.failure('An account with this email already exists');
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

    _setCurrentUser(newUser);
    return AuthResult.success(newUser, isNewUser: true);
  }

  @override
  Future<AuthResult> loginWithPhone(String phone) async {
    debugPrint('[MockAuthService] loginWithPhone: $phone');

    // Simulate network delay
    await Future.delayed(const Duration(milliseconds: 800));

    final user = getUserByPhone(phone);
    if (user != null) {
      _setCurrentUser(user);
      return AuthResult.success(user);
    }

    return AuthResult.failure('No account found with this phone number');
  }

  @override
  Future<AuthResult> updateProfile(User updatedUser) async {
    debugPrint('[MockAuthService] updateProfile: ${updatedUser.id}');

    if (updatedUser.email != null) {
      _users[updatedUser.email!.toLowerCase()] = updatedUser;
    }
    if (_currentUser?.id == updatedUser.id) {
      _setCurrentUser(updatedUser);
    }

    return AuthResult.success(updatedUser);
  }

  @override
  Future<AuthResult> becomeHost() async {
    debugPrint('[MockAuthService] becomeHost');

    if (_currentUser == null) {
      return AuthResult.failure('No user logged in');
    }

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
    _setCurrentUser(updatedUser);

    return AuthResult.success(updatedUser);
  }

  @override
  Future<void> logout() async {
    debugPrint('[MockAuthService] logout');
    _setCurrentUser(null);
  }

  @override
  User? getUserById(String id) {
    return _users.values.where((u) => u.id == id).firstOrNull;
  }

  @override
  User? getUserByEmail(String email) {
    return _users[email.toLowerCase()];
  }

  @override
  User? getUserByPhone(String phone) {
    final normalized = _normalizePhone(phone);
    final userId = _phoneToUserId[normalized];
    if (userId == null) return null;
    return _users.values.where((u) => u.id == userId).firstOrNull;
  }

  @override
  void dispose() {
    _authStateController.close();
  }
}

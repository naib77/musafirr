import 'dart:async';

import '../../models/user.dart';

/// Result of an authentication operation
class AuthResult {
  const AuthResult({
    required this.success,
    this.user,
    this.error,
    this.isNewUser,
  });

  final bool success;
  final User? user;
  final String? error;
  final bool? isNewUser;

  factory AuthResult.success(User user, {bool isNewUser = false}) {
    return AuthResult(success: true, user: user, isNewUser: isNewUser);
  }

  factory AuthResult.failure(String error) {
    return AuthResult(success: false, error: error);
  }
}

/// Result of an OTP operation
class OtpResult {
  const OtpResult({
    required this.success,
    this.error,
    this.attemptsRemaining,
    this.isExistingUser = false,
  });

  final bool success;
  final String? error;
  final int? attemptsRemaining;
  /// Whether an existing user profile was found (for verifyOtp)
  final bool isExistingUser;

  factory OtpResult.success({bool isExistingUser = false}) {
    return OtpResult(success: true, isExistingUser: isExistingUser);
  }

  factory OtpResult.failure(String error, {int? attemptsRemaining}) {
    return OtpResult(
      success: false,
      error: error,
      attemptsRemaining: attemptsRemaining,
    );
  }
}

/// Abstract authentication service interface.
///
/// Implementations:
/// - [MockAuthService] for development/demo mode
/// - [SupabaseAuthService] for production with real Supabase backend
abstract class AuthService {
  /// Get the currently authenticated user (if any)
  User? get currentUser;

  /// Stream of authentication state changes
  Stream<User?> get authStateChanges;

  /// Login with email and password
  Future<AuthResult> loginWithEmail(String email, String password);

  /// Sign up with email and password
  Future<AuthResult> signupWithEmail({
    required String name,
    required String email,
    required String password,
  });

  /// Send OTP to phone number
  Future<OtpResult> sendOtp(String phoneNumber);

  /// Verify OTP code
  Future<OtpResult> verifyOtp(String phoneNumber, String otp);

  /// Complete phone signup after OTP verification
  Future<AuthResult> completePhoneSignup({
    required String phone,
    required String name,
    required String nid,
    String? email,
  });

  /// Login with phone (for returning users after OTP verification)
  Future<AuthResult> loginWithPhone(String phone);

  /// Update user profile
  Future<AuthResult> updateProfile(User updatedUser);

  /// Upgrade current user to host status
  Future<AuthResult> becomeHost();

  /// Logout the current user
  Future<void> logout();

  /// Get user by ID
  User? getUserById(String id);

  /// Get user by email
  User? getUserByEmail(String email);

  /// Get user by phone number
  User? getUserByPhone(String phone);

  /// Dispose of resources
  void dispose();
}

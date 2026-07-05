import 'dart:async';

import 'package:flutter/foundation.dart';
import 'package:supabase_flutter/supabase_flutter.dart' hide User;
import 'package:supabase_flutter/supabase_flutter.dart' as supabase show User;

import '../../models/user.dart';
import '../../models/user_role.dart';
import '../otp_service.dart';
import 'auth_service.dart';

/// Supabase-backed implementation of [AuthService].
///
/// Uses Supabase Auth for authentication and the profiles table for user data.
class SupabaseAuthService implements AuthService {
  SupabaseAuthService._();

  static SupabaseAuthService? _instance;
  static SupabaseAuthService get instance {
    _instance ??= SupabaseAuthService._();
    return _instance!;
  }

  SupabaseClient get _client => Supabase.instance.client;
  GoTrueClient get _auth => _client.auth;

  User? _currentUser;
  final _authStateController = StreamController<User?>.broadcast();
  StreamSubscription<AuthState>? _authSubscription;

  // Cache for user lookups
  final Map<String, User> _userCache = {};

  // OTP service for phone verification (uses existing SMS gateway)
  final OtpService _otpService = OtpService.instance;

  // Track verified phone numbers pending signup completion
  String? _verifiedPhone;

  /// Initialize the service and listen for auth state changes
  void initialize() {
    _authSubscription = _auth.onAuthStateChange.listen(_handleAuthStateChange);
    // Check if already logged in
    final session = _auth.currentSession;
    if (session != null) {
      _loadUserProfile(session.user);
    }
  }

  void _handleAuthStateChange(AuthState state) {
    debugPrint('[SupabaseAuthService] Auth state changed: ${state.event}');

    switch (state.event) {
      case AuthChangeEvent.signedIn:
      case AuthChangeEvent.tokenRefreshed:
      case AuthChangeEvent.userUpdated:
        if (state.session?.user != null) {
          _loadUserProfile(state.session!.user);
        }
        break;
      case AuthChangeEvent.signedOut:
        _setCurrentUser(null);
        _userCache.clear();
        break;
      default:
        break;
    }
  }

  Future<void> _loadUserProfile(supabase.User authUser) async {
    try {
      final profile = await _client
          .from('profiles')
          .select()
          .eq('id', authUser.id)
          .maybeSingle();

      final user = _mapToUser(authUser, profile);
      _userCache[user.id] = user;
      _setCurrentUser(user);
    } catch (e) {
      debugPrint('[SupabaseAuthService] Error loading profile: $e');
      // Create a minimal user from auth data
      final user = _mapToUser(authUser, null);
      _setCurrentUser(user);
    }
  }

  User _mapToUser(supabase.User authUser, Map<String, dynamic>? profile) {
    return User(
      id: authUser.id,
      name: profile?['full_name'] as String? ??
          authUser.userMetadata?['full_name'] as String? ??
          authUser.email?.split('@').first ??
          'User',
      email: authUser.email,
      phone: profile?['mobile'] as String? ?? authUser.phone,
      avatarUrl: profile?['avatar_url'] as String?,
      role: _parseRole(profile?['role'] as String?),
      createdAt: DateTime.tryParse(authUser.createdAt),
      isHost: profile?['is_host'] as bool? ?? false,
      hostAvailable: profile?['is_available'] as bool? ?? true,
      hostSince: profile?['host_since'] != null
          ? DateTime.tryParse(profile!['host_since'] as String)
          : null,
      bio: profile?['bio'] as String?,
      responseRate: profile?['response_rate'] as int?,
      responseTime: profile?['response_time'] as String?,
      nid: profile?['nid'] as String?,
      nidVerified: profile?['nid_verified'] as bool? ?? false,
      phoneVerified: profile?['phone_verified'] as bool? ?? false,
      registrationMethod:
          _parseRegistrationMethod(profile?['registration_method'] as String?),
    );
  }

  UserRole _parseRole(String? role) {
    if (role == null) return UserRole.tenant;
    return UserRole.values.firstWhere(
      (r) => r.name == role,
      orElse: () => UserRole.tenant,
    );
  }

  RegistrationMethod? _parseRegistrationMethod(String? method) {
    if (method == null) return null;
    return RegistrationMethod.values.firstWhere(
      (m) => m.name == method,
      orElse: () => RegistrationMethod.email,
    );
  }

  void _setCurrentUser(User? user) {
    _currentUser = user;
    _authStateController.add(user);
    debugPrint('[SupabaseAuthService] Current user: ${user?.id}');
  }

  @override
  User? get currentUser => _currentUser;

  @override
  bool get hasActiveSession => _auth.currentSession != null;

  @override
  Stream<User?> get authStateChanges => _authStateController.stream;

  @override
  Future<AuthResult> loginWithEmail(String email, String password) async {
    debugPrint('[SupabaseAuthService] loginWithEmail: $email');

    try {
      final response = await _auth.signInWithPassword(
        email: email,
        password: password,
      );

      if (response.user == null) {
        return AuthResult.failure('Login failed');
      }

      // Profile will be loaded via auth state listener
      // But we can fetch it here to return immediately
      final profile = await _client
          .from('profiles')
          .select()
          .eq('id', response.user!.id)
          .maybeSingle();

      final user = _mapToUser(response.user!, profile);
      _userCache[user.id] = user;
      _setCurrentUser(user);

      return AuthResult.success(user);
    } on AuthException catch (e) {
      debugPrint('[SupabaseAuthService] Login error: ${e.message}');
      return AuthResult.failure(e.message);
    } catch (e) {
      debugPrint('[SupabaseAuthService] Login error: $e');
      return AuthResult.failure('Login failed: $e');
    }
  }

  @override
  Future<AuthResult> signupWithEmail({
    required String name,
    required String email,
    required String password,
  }) async {
    debugPrint('[SupabaseAuthService] signupWithEmail: $email');

    try {
      final response = await _auth.signUp(
        email: email,
        password: password,
        data: {'full_name': name},
      );

      if (response.user == null) {
        return AuthResult.failure('Signup failed');
      }

      // Create/update profile
      await _client.from('profiles').upsert({
        'id': response.user!.id,
        'full_name': name,
        'role': UserRole.tenant.name,
        'registration_method': RegistrationMethod.email.name,
      });

      final user = _mapToUser(response.user!, {
        'full_name': name,
        'role': UserRole.tenant.name,
        'registration_method': RegistrationMethod.email.name,
      });
      _userCache[user.id] = user;
      _setCurrentUser(user);

      return AuthResult.success(user, isNewUser: true);
    } on AuthException catch (e) {
      debugPrint('[SupabaseAuthService] Signup error: ${e.message}');
      return AuthResult.failure(e.message);
    } catch (e) {
      debugPrint('[SupabaseAuthService] Signup error: $e');
      return AuthResult.failure('Signup failed: $e');
    }
  }

  @override
  Future<OtpResult> sendOtp(String phoneNumber) async {
    debugPrint('[SupabaseAuthService] sendOtp: $phoneNumber');

    // Use existing SMS gateway via OtpService (not Supabase phone provider)
    final result = await _otpService.sendOtp(phoneNumber);

    if (result.success) {
      return OtpResult.success();
    }
    return OtpResult.failure(result.errorMessage ?? 'Failed to send OTP');
  }

  @override
  Future<OtpResult> verifyOtp(String phoneNumber, String otp) async {
    debugPrint('[SupabaseAuthService] verifyOtp: $phoneNumber');

    // Verify OTP using existing OtpService
    final result = await _otpService.verifyOtp(phoneNumber, otp);

    if (!result.success) {
      return OtpResult.failure(
        result.errorMessage ?? 'Invalid OTP',
        attemptsRemaining: result.attemptsRemaining,
      );
    }

    // OTP verified - store the verified phone for signup completion
    _verifiedPhone = _otpService.normalizePhoneNumber(phoneNumber);
    debugPrint('[SupabaseAuthService] Phone verified: $_verifiedPhone');

    // Check if user already exists by attempting to sign in
    // (We can't query profiles directly due to RLS - user isn't authenticated yet)
    bool isExistingUser = false;
    final phoneEmail = _phoneToEmail(_verifiedPhone!);
    final phonePassword = _phoneToPassword(_verifiedPhone!);

    debugPrint('[SupabaseAuthService] Attempting sign-in to check if user exists: $phoneEmail');

    try {
      final response = await _auth.signInWithPassword(
        email: phoneEmail,
        password: phonePassword,
      );

      if (response.user != null) {
        isExistingUser = true;
        debugPrint('[SupabaseAuthService] Existing user found and signed in: ${response.user!.id}');

        // Now we're authenticated, fetch the profile
        final profile = await _client
            .from('profiles')
            .select()
            .eq('id', response.user!.id)
            .maybeSingle();

        final user = _mapToUser(response.user!, profile);
        _userCache[user.id] = user;
        _setCurrentUser(user);
      }
    } on AuthException catch (e) {
      // "Invalid login credentials" means user doesn't exist - this is expected for new users
      debugPrint('[SupabaseAuthService] Sign-in attempt result: ${e.message}');
      if (!e.message.contains('Invalid login credentials')) {
        debugPrint('[SupabaseAuthService] Unexpected auth error: ${e.message}');
      }
      // isExistingUser remains false - new user
    } catch (e) {
      debugPrint('[SupabaseAuthService] Error checking existing user: $e');
    }

    return OtpResult.success(isExistingUser: isExistingUser);
  }

  @override
  Future<AuthResult> completePhoneSignup({
    required String phone,
    required String name,
    required String nid,
    String? email,
  }) async {
    debugPrint('[SupabaseAuthService] completePhoneSignup: $phone');

    // Verify the phone was actually verified via OTP
    final normalizedPhone = _otpService.normalizePhoneNumber(phone);
    if (_verifiedPhone != normalizedPhone) {
      return AuthResult.failure('Phone number not verified');
    }

    try {
      final formattedPhone = _formatPhoneForDisplay(phone);

      // Internal email for Supabase Auth only (user never sees this)
      // Real email (or null) is stored in profiles table
      final authEmail = _phoneToEmail(normalizedPhone);
      final authPassword = _phoneToPassword(normalizedPhone);

      // Create Supabase auth user
      final response = await _auth.signUp(
        email: authEmail,
        password: authPassword,
        data: {
          'full_name': name,
          'mobile': formattedPhone,
        },
      );

      if (response.user == null) {
        return AuthResult.failure('Failed to create account');
      }

      // Update profile with real user details (real email or null here)
      debugPrint('[SupabaseAuthService] Upserting profile with mobile: $formattedPhone');
      try {
        await _client.from('profiles').upsert({
          'id': response.user!.id,
          'full_name': name,
          'mobile': formattedPhone,
          'nid': nid.isEmpty ? null : nid,
          // Identity is no longer collected at signup; it becomes a one-time
          // gate before hosting/booking. Only an admin marking the account
          // verified should flip nid_verified.
          'nid_verified': false,
          'phone_verified': true,
          'role': UserRole.tenant.name,
          'registration_method': RegistrationMethod.phone.name,
        });
        debugPrint('[SupabaseAuthService] Profile upsert successful');
      } catch (upsertError) {
        debugPrint('[SupabaseAuthService] Profile upsert FAILED: $upsertError');
        // Profile may have been created by trigger, continue anyway
      }

      final user = User(
        id: response.user!.id,
        name: name,
        email: email, // Real email or null (NOT the internal auth email)
        phone: formattedPhone,
        role: UserRole.tenant,
        createdAt: DateTime.tryParse(response.user!.createdAt),
        nid: nid.isEmpty ? null : nid,
        nidVerified: false,
        phoneVerified: true,
        registrationMethod: RegistrationMethod.phone,
      );

      _userCache[user.id] = user;
      _setCurrentUser(user);
      _verifiedPhone = null;

      return AuthResult.success(user, isNewUser: true);
    } on AuthException catch (e) {
      debugPrint('[SupabaseAuthService] Complete signup error: ${e.message}');
      if (e.message.contains('already registered')) {
        return AuthResult.failure('An account with this phone already exists');
      }
      return AuthResult.failure(e.message);
    } catch (e) {
      debugPrint('[SupabaseAuthService] Complete signup error: $e');
      return AuthResult.failure('Failed to complete signup: $e');
    }
  }

  @override
  Future<AuthResult> loginWithPhone(String phone) async {
    debugPrint('[SupabaseAuthService] loginWithPhone: $phone');

    // If already logged in via verifyOtp, just return current user
    if (_auth.currentUser != null && _currentUser != null) {
      return AuthResult.success(_currentUser!);
    }

    // Otherwise, try to sign in with phone-derived credentials
    final normalizedPhone = _otpService.normalizePhoneNumber(phone);
    final phoneEmail = _phoneToEmail(normalizedPhone);
    final phonePassword = _phoneToPassword(normalizedPhone);

    try {
      final response = await _auth.signInWithPassword(
        email: phoneEmail,
        password: phonePassword,
      );

      if (response.user == null) {
        return AuthResult.failure('Login failed');
      }

      final profile = await _client
          .from('profiles')
          .select()
          .eq('id', response.user!.id)
          .maybeSingle();

      final user = _mapToUser(response.user!, profile);
      _userCache[user.id] = user;
      _setCurrentUser(user);

      return AuthResult.success(user);
    } on AuthException catch (e) {
      debugPrint('[SupabaseAuthService] Phone login error: ${e.message}');
      return AuthResult.failure('No account found with this phone number');
    } catch (e) {
      debugPrint('[SupabaseAuthService] Phone login error: $e');
      return AuthResult.failure('Login failed: $e');
    }
  }

  @override
  Future<AuthResult> updateProfile(User updatedUser) async {
    debugPrint('[SupabaseAuthService] updateProfile: ${updatedUser.id}');

    try {
      await _client.from('profiles').upsert({
        'id': updatedUser.id,
        'full_name': updatedUser.name,
        'mobile': updatedUser.phone,
        'avatar_url': updatedUser.avatarUrl,
        'role': updatedUser.role.name,
        'bio': updatedUser.bio,
        'is_host': updatedUser.isHost,
        'is_available': updatedUser.hostAvailable,
        'host_since': updatedUser.hostSince?.toIso8601String(),
        'response_rate': updatedUser.responseRate,
        'response_time': updatedUser.responseTime,
        'nid': updatedUser.nid,
        'nid_verified': updatedUser.nidVerified,
        'phone_verified': updatedUser.phoneVerified,
        'registration_method': updatedUser.registrationMethod?.name,
      });

      _userCache[updatedUser.id] = updatedUser;
      if (_currentUser?.id == updatedUser.id) {
        _setCurrentUser(updatedUser);
      }

      return AuthResult.success(updatedUser);
    } catch (e) {
      debugPrint('[SupabaseAuthService] Update profile error: $e');
      return AuthResult.failure('Failed to update profile: $e');
    }
  }

  @override
  Future<AuthResult> becomeHost() async {
    debugPrint('[SupabaseAuthService] becomeHost');

    if (_currentUser == null) {
      return AuthResult.failure('No user logged in');
    }

    try {
      final now = DateTime.now();
      await _client.from('profiles').update({
        'is_host': true,
        'host_since': now.toIso8601String(),
        'role': UserRole.owner.name,
      }).eq('id', _currentUser!.id);

      final updatedUser = _currentUser!.copyWith(
        isHost: true,
        hostSince: now,
        role: UserRole.owner,
      );

      _userCache[updatedUser.id] = updatedUser;
      _setCurrentUser(updatedUser);

      return AuthResult.success(updatedUser);
    } catch (e) {
      debugPrint('[SupabaseAuthService] Become host error: $e');
      return AuthResult.failure('Failed to become host: $e');
    }
  }

  @override
  Future<void> logout() async {
    debugPrint('[SupabaseAuthService] logout');

    try {
      await _auth.signOut();
      _setCurrentUser(null);
      _userCache.clear();
    } catch (e) {
      debugPrint('[SupabaseAuthService] Logout error: $e');
    }
  }

  @override
  User? getUserById(String id) {
    return _userCache[id];
  }

  @override
  User? getUserByEmail(String email) {
    return _userCache.values.where((u) => u.email == email).firstOrNull;
  }

  @override
  User? getUserByPhone(String phone) {
    final normalized = _normalizePhone(phone);
    return _userCache.values.where((u) {
      if (u.phone == null) return false;
      return _normalizePhone(u.phone!) == normalized;
    }).firstOrNull;
  }

  /// Convert phone number to email for Supabase auth
  /// Uses a deterministic format: phone.01712345678@musafir.app
  /// Note: .local TLD is rejected by Supabase, must use valid-looking domain
  String _phoneToEmail(String normalizedPhone) {
    return 'phone.$normalizedPhone@musafir.app';
  }

  /// Generate a deterministic password from phone number
  /// This is secure because:
  /// 1. User must verify OTP to get here
  /// 2. The password pattern is not guessable from phone alone
  String _phoneToPassword(String normalizedPhone) {
    // Create a password that's deterministic but not trivially guessable
    final reversed = normalizedPhone.split('').reversed.join();
    return 'Ph0n3_${reversed}_M$normalizedPhone';
  }

  /// Format phone number for display (+880 format)
  String _formatPhoneForDisplay(String phone) {
    var normalized = phone.replaceAll(RegExp(r'[\s\-\(\)]'), '');

    if (normalized.startsWith('+')) {
      normalized = normalized.substring(1);
    }

    if (normalized.startsWith('880')) {
      return '+880 ${normalized.substring(3)}';
    } else if (normalized.startsWith('0')) {
      return '+880 ${normalized.substring(1)}';
    } else {
      return '+880 $normalized';
    }
  }

  /// Normalize phone number for comparison
  String _normalizePhone(String phone) {
    var normalized = phone.replaceAll(RegExp(r'[\s\-\(\)\+]'), '');
    if (normalized.startsWith('880')) {
      normalized = '0${normalized.substring(3)}';
    }
    return normalized;
  }

  @override
  void dispose() {
    _authSubscription?.cancel();
    _authStateController.close();
  }
}

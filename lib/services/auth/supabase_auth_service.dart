import 'dart:async';

import 'package:flutter/foundation.dart';
import 'package:sms_autofill/sms_autofill.dart';
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
  Future<OtpResult> sendOtp(String phoneNumber) async {
    final normalized = _otpService.normalizePhoneNumber(phoneNumber);
    debugPrint('[SupabaseAuthService] sendOtp -> send-otp fn: $normalized');

    // On Android, fetch the app's SMS-Retriever signature so the server can
    // append it and the OTP screen can auto-read the code. Best-effort only.
    String? appSignature;
    if (!kIsWeb && defaultTargetPlatform == TargetPlatform.android) {
      try {
        appSignature = await SmsAutoFill().getAppSignature;
      } catch (e) {
        debugPrint('[SupabaseAuthService] getAppSignature failed: $e');
      }
    }

    // OTP generation + delivery happen entirely server-side (send-otp Edge
    // Function). The client never sees or stores the code.
    try {
      final response = await _client.functions.invoke(
        'send-otp',
        body: {
          'phone': normalized,
          if (appSignature != null && appSignature.isNotEmpty)
            'appSignature': appSignature,
        },
      );
      final data = response.data;
      if (data is Map && data['success'] == true) {
        return OtpResult.success();
      }
      final error = (data is Map ? data['error']?.toString() : null) ??
          'Failed to send OTP';
      return OtpResult.failure(error);
    } on FunctionException catch (e) {
      return OtpResult.failure(_functionError(e, 'Failed to send OTP'));
    } catch (e) {
      debugPrint('[SupabaseAuthService] sendOtp error: $e');
      return OtpResult.failure('Failed to send OTP: $e');
    }
  }

  @override
  Future<OtpResult> verifyOtp(String phoneNumber, String otp) async {
    final normalized = _otpService.normalizePhoneNumber(phoneNumber);
    debugPrint('[SupabaseAuthService] verifyOtp -> verify-otp fn: $normalized');

    // Verification is authoritative on the server (verify-otp Edge Function).
    // On success it returns a single-use magic-link token_hash, which we
    // exchange for a real session — no phone-derived password is ever used.
    try {
      final response = await _client.functions.invoke(
        'verify-otp',
        body: {'phone': normalized, 'otp': otp},
      );
      final data = response.data;
      if (data is! Map || data['success'] != true) {
        return OtpResult.failure(
          (data is Map ? data['error']?.toString() : null) ?? 'Invalid code',
          attemptsRemaining:
              data is Map ? (data['attemptsRemaining'] as num?)?.toInt() : null,
        );
      }

      final tokenHash = data['tokenHash']?.toString();
      if (tokenHash == null || tokenHash.isEmpty) {
        return OtpResult.failure('Could not establish session');
      }

      final authResponse = await _auth.verifyOTP(
        type: OtpType.magiclink,
        tokenHash: tokenHash,
      );
      if (authResponse.user == null) {
        return OtpResult.failure('Could not establish session');
      }

      _verifiedPhone = normalized;
      await _loadUserProfile(authResponse.user!);

      final isExistingUser = data['isExistingUser'] == true;
      debugPrint(
          '[SupabaseAuthService] verified; isExistingUser=$isExistingUser');
      return OtpResult.success(isExistingUser: isExistingUser);
    } on FunctionException catch (e) {
      final details = e.details;
      return OtpResult.failure(
        _functionError(e, 'Verification failed'),
        attemptsRemaining: details is Map
            ? (details['attemptsRemaining'] as num?)?.toInt()
            : null,
      );
    } on AuthException catch (e) {
      debugPrint('[SupabaseAuthService] verifyOtp auth error: ${e.message}');
      return OtpResult.failure(e.message);
    } catch (e) {
      debugPrint('[SupabaseAuthService] verifyOtp error: $e');
      return OtpResult.failure('Verification failed: $e');
    }
  }

  /// Pull a human-readable error out of a FunctionException's JSON body.
  String _functionError(FunctionException e, String fallback) {
    final details = e.details;
    final msg = details is Map ? details['error']?.toString() : null;
    return (msg != null && msg.isNotEmpty) ? msg : '$fallback (${e.status})';
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

    // verify-otp already created the auth user and minted our session, so we
    // just fill in the profile — no signUp (and no phone-derived password).
    final authUser = _auth.currentUser;
    if (authUser == null) {
      return AuthResult.failure(
          'Session not established. Please verify again.');
    }

    try {
      final formattedPhone = _formatPhoneForDisplay(phone);

      debugPrint(
          '[SupabaseAuthService] Upserting profile with mobile: $formattedPhone');
      await _client.from('profiles').upsert({
        'id': authUser.id,
        'full_name': name,
        'mobile': formattedPhone,
        'nid': nid.isEmpty ? null : nid,
        // Identity is no longer collected at signup; it becomes a one-time
        // gate before hosting/booking. Only an admin marking the account
        // verified should flip nid_verified.
        'nid_verified': false,
        'phone_verified': true,
        'signup_completed': true,
        'role': UserRole.tenant.name,
        'registration_method': RegistrationMethod.phone.name,
      });
      debugPrint('[SupabaseAuthService] Profile upsert successful');

      final user = User(
        id: authUser.id,
        name: name,
        email: email, // Real email or null (NOT the internal auth email)
        phone: formattedPhone,
        role: UserRole.tenant,
        createdAt: DateTime.tryParse(authUser.createdAt),
        nid: nid.isEmpty ? null : nid,
        nidVerified: false,
        phoneVerified: true,
        registrationMethod: RegistrationMethod.phone,
      );

      _userCache[user.id] = user;
      _setCurrentUser(user);
      _verifiedPhone = null;

      return AuthResult.success(user, isNewUser: true);
    } catch (e) {
      debugPrint('[SupabaseAuthService] Complete signup error: $e');
      return AuthResult.failure('Failed to complete signup: $e');
    }
  }

  @override
  Future<AuthResult> loginWithPhone(String phone) async {
    debugPrint('[SupabaseAuthService] loginWithPhone: $phone');

    // Sessions are established by verifyOtp (server-minted, single-use token).
    // There is deliberately no password-based phone login — that was the
    // deterministic-credential bypass this refactor removed.
    if (_auth.currentUser != null && _currentUser != null) {
      return AuthResult.success(_currentUser!);
    }
    return AuthResult.failure('Please sign in with a verification code');
  }

  @override
  Future<AuthResult> updateProfile(User updatedUser) async {
    debugPrint('[SupabaseAuthService] updateProfile: ${updatedUser.id}');

    try {
      // Only the fields users edit through profile flows (Personal information +
      // the host availability toggle). Deliberately NOT role / is_host /
      // host_since / nid / nid_verified / phone_verified / registration_method:
      // those are owned by signup, becomeHost and verification. Letting a
      // (possibly stale) client User overwrite them risks failing the entire
      // write on one bad value AND is a privilege-escalation smell. The profile
      // row always exists for a signed-in user, so UPDATE (not upsert) is right.
      await _client.from('profiles').update({
        'full_name': updatedUser.name,
        'avatar_url': updatedUser.avatarUrl,
        'bio': updatedUser.bio,
        'is_available': updatedUser.hostAvailable,
      }).eq('id', updatedUser.id);

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

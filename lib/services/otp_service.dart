import 'dart:convert';
import 'dart:math';

import 'package:crypto/crypto.dart';
import 'package:flutter/foundation.dart';
import 'package:supabase_flutter/supabase_flutter.dart';

import '../config/otp_config.dart';
import '../config/sms_config.dart';
import 'sms/sms_gateway_factory.dart';
import 'sms/sms_send_result.dart';

/// Stored OTP entry with expiry and attempt tracking
class OtpEntry {
  OtpEntry({
    required this.otp,
    required this.phoneNumber,
    required this.expiresAt,
    this.dbId,
  });

  final String otp;
  final String phoneNumber;
  final DateTime expiresAt;
  final String? dbId; // Database record ID for updates
  int attempts = 0;

  bool get isExpired => DateTime.now().isAfter(expiresAt);
}

/// Result of OTP verification
class OtpVerificationResult {
  const OtpVerificationResult({
    required this.success,
    this.errorMessage,
    this.attemptsRemaining,
  });

  final bool success;
  final String? errorMessage;
  final int? attemptsRemaining;

  factory OtpVerificationResult.success() {
    return const OtpVerificationResult(success: true);
  }

  factory OtpVerificationResult.failure(String message,
      {int? attemptsRemaining}) {
    return OtpVerificationResult(
      success: false,
      errorMessage: message,
      attemptsRemaining: attemptsRemaining,
    );
  }
}

/// Singleton service for OTP generation, sending, and verification
///
/// Features:
/// - In-memory OTP storage for fast verification
/// - Optional persistence to Supabase for audit trail
/// - Master OTP support for development/testing
/// - Automatic cleanup of old database records
class OtpService {
  OtpService._();

  static OtpService? _instance;

  static OtpService get instance {
    _instance ??= OtpService._();
    return _instance!;
  }

  /// Configuration from OtpConfig
  static int get otpLength => OtpConfig.otpLength;
  static int get validityMinutes => OtpConfig.validityMinutes;
  static int get maxAttempts => OtpConfig.maxAttempts;
  static int get resendCooldownSeconds => OtpConfig.resendCooldownSeconds;

  /// In-memory OTP storage (phone -> OtpEntry)
  final Map<String, OtpEntry> _otpStore = {};

  /// Resend timestamps (phone -> last sent time)
  final Map<String, DateTime> _resendTimestamps = {};

  final Random _random = Random.secure();

  /// Counter for periodic cleanup (every 10 operations)
  int _operationCount = 0;

  /// Get Supabase client
  SupabaseClient get _client => Supabase.instance.client;

  /// Generate a random OTP of specified length
  String _generateOtp() {
    final otp = StringBuffer();
    for (var i = 0; i < otpLength; i++) {
      otp.write(_random.nextInt(10));
    }
    return otp.toString();
  }

  /// Hash OTP using SHA-256 (for production) or return plaintext (for development)
  String _processOtpForStorage(String otp) {
    if (OtpConfig.hashOtpInDatabase) {
      // Production: hash the OTP
      final bytes = utf8.encode(otp);
      final digest = sha256.convert(bytes);
      return digest.toString();
    } else {
      // Development: store plaintext for easy debugging
      return otp;
    }
  }

  /// Normalize phone number to standard format
  String normalizePhoneNumber(String phone) {
    // Remove spaces, dashes, and other formatting
    var normalized = phone.replaceAll(RegExp(r'[\s\-\(\)]'), '');

    // Handle +880 prefix
    if (normalized.startsWith('+880')) {
      normalized = '0${normalized.substring(4)}';
    } else if (normalized.startsWith('880')) {
      normalized = '0${normalized.substring(3)}';
    }

    return normalized;
  }

  /// Check if resend cooldown is active
  bool isResendCooldownActive(String phoneNumber) {
    final normalized = normalizePhoneNumber(phoneNumber);
    final lastSent = _resendTimestamps[normalized];
    if (lastSent == null) return false;

    final elapsed = DateTime.now().difference(lastSent);
    return elapsed.inSeconds < resendCooldownSeconds;
  }

  /// Get remaining cooldown seconds
  int getResendCooldownRemaining(String phoneNumber) {
    final normalized = normalizePhoneNumber(phoneNumber);
    final lastSent = _resendTimestamps[normalized];
    if (lastSent == null) return 0;

    final elapsed = DateTime.now().difference(lastSent);
    final remaining = resendCooldownSeconds - elapsed.inSeconds;
    return remaining > 0 ? remaining : 0;
  }

  /// Trigger periodic cleanup of old OTP records
  Future<void> _maybeCleanupOldRecords() async {
    _operationCount++;

    // Run cleanup every 10 operations
    if (_operationCount >= 10 && OtpConfig.persistToDatabase) {
      _operationCount = 0;
      try {
        await _client.rpc('cleanup_old_otps');
        debugPrint('[OTP Service] Cleanup triggered');
      } catch (e) {
        debugPrint('[OTP Service] Cleanup failed (non-critical): $e');
      }
    }
  }

  /// Persist OTP to database (hashed)
  Future<String?> _persistOtpToDatabase({
    required String phoneNumber,
    required String otp,
    required DateTime expiresAt,
  }) async {
    if (!OtpConfig.persistToDatabase) return null;

    try {
      // Written via a SECURITY DEFINER RPC: the otp_attempts table is not
      // client-accessible (the OTP hash must never be readable — see migration
      // 060). The RPC inserts and returns the new row id.
      final id = await _client.rpc('otp_log_send', params: {
        'p_phone': phoneNumber,
        'p_otp_hash': _processOtpForStorage(otp),
        'p_expires_at': expiresAt.toUtc().toIso8601String(),
      });

      return id as String?;
    } catch (e) {
      debugPrint('[OTP Service] Failed to persist OTP to database: $e');
      return null;
    }
  }

  /// Update OTP attempt count in database
  Future<void> _updateDbAttempts(String? dbId, int attempts) async {
    if (dbId == null || !OtpConfig.persistToDatabase) return;

    try {
      await _client.rpc('otp_log_attempts', params: {
        'p_id': dbId,
        'p_attempts': attempts,
      });
    } catch (e) {
      debugPrint('[OTP Service] Failed to update attempts in database: $e');
    }
  }

  /// Mark OTP as verified in database
  Future<void> _markDbVerified(String? dbId) async {
    if (dbId == null || !OtpConfig.persistToDatabase) return;

    try {
      await _client.rpc('otp_log_verified', params: {'p_id': dbId});
    } catch (e) {
      debugPrint('[OTP Service] Failed to mark OTP as verified: $e');
    }
  }

  /// Send OTP to phone number
  Future<SmsSendResult> sendOtp(String phoneNumber) async {
    final normalized = normalizePhoneNumber(phoneNumber);

    debugPrint('[OTP Service] sendOtp called for: $normalized');
    debugPrint('[OTP Service] Current resend timestamps: $_resendTimestamps');

    // Check resend cooldown
    if (isResendCooldownActive(normalized)) {
      final remaining = getResendCooldownRemaining(normalized);
      debugPrint(
          '[OTP Service] Cooldown active! Remaining: $remaining seconds');
      return SmsSendResult.failure(
        'Please wait $remaining seconds before requesting a new code',
      );
    }

    debugPrint('[OTP Service] No cooldown, proceeding to send OTP...');

    // Trigger periodic cleanup
    await _maybeCleanupOldRecords();

    // Generate OTP
    final otp = _generateOtp();
    final expiresAt = DateTime.now().add(Duration(minutes: validityMinutes));

    // Persist to database first (if enabled)
    final dbId = await _persistOtpToDatabase(
      phoneNumber: normalized,
      otp: otp,
      expiresAt: expiresAt,
    );

    // Store OTP in memory
    _otpStore[normalized] = OtpEntry(
      otp: otp,
      phoneNumber: normalized,
      expiresAt: expiresAt,
      dbId: dbId,
    );

    // Update resend timestamp
    _resendTimestamps[normalized] = DateTime.now();

    // Send SMS
    final gateway = SmsGatewayFactory.getGateway();
    final message = SmsConfig.getOtpMessage(otp);

    debugPrint(
        '[OTP Service] Sending OTP to $normalized via ${gateway.gatewayName}');

    // Print OTP to console in development mode for easy testing
    if (OtpConfig.printOtpToConsole) {
      debugPrint('');
      debugPrint('╔════════════════════════════════════════╗');
      debugPrint('║  [DEV MODE] OTP for $normalized: $otp  ');
      debugPrint('╚════════════════════════════════════════╝');
      debugPrint('');
    }

    // Log master OTP info if configured
    if (OtpConfig.isMasterOtpConfigured) {
      debugPrint(
          '[OTP Service] Master OTP is enabled. Use "${OtpConfig.masterOtp}" to bypass.');
    }

    return gateway.sendSms(
      phoneNumber: normalized,
      message: message,
    );
  }

  /// Verify OTP
  Future<OtpVerificationResult> verifyOtp(
      String phoneNumber, String otp) async {
    final normalized = normalizePhoneNumber(phoneNumber);

    // Check master OTP first (if enabled)
    if (OtpConfig.isMasterOtpMatch(otp)) {
      debugPrint('[OTP Service] Master OTP used for $normalized');
      // Clear any pending OTP for this number
      final entry = _otpStore.remove(normalized);
      if (entry?.dbId != null) {
        await _markDbVerified(entry!.dbId);
      }
      return OtpVerificationResult.success();
    }

    final entry = _otpStore[normalized];

    // Check if OTP exists
    if (entry == null) {
      return OtpVerificationResult.failure('No OTP found for this number');
    }

    // Check if OTP is expired
    if (entry.isExpired) {
      _otpStore.remove(normalized);
      return OtpVerificationResult.failure(
          'OTP has expired. Please request a new one.');
    }

    // Check attempts
    if (entry.attempts >= maxAttempts) {
      _otpStore.remove(normalized);
      return OtpVerificationResult.failure(
        'Too many failed attempts. Please request a new code.',
      );
    }

    // Verify OTP
    if (entry.otp == otp) {
      _otpStore.remove(normalized);
      await _markDbVerified(entry.dbId);
      debugPrint('[OTP Service] OTP verified successfully for $normalized');
      return OtpVerificationResult.success();
    }

    // Increment attempts
    entry.attempts++;
    await _updateDbAttempts(entry.dbId, entry.attempts);
    final remaining = maxAttempts - entry.attempts;

    debugPrint('[OTP Service] Invalid OTP. Attempts remaining: $remaining');
    return OtpVerificationResult.failure(
      'Invalid OTP',
      attemptsRemaining: remaining,
    );
  }

  /// Clear OTP for phone number
  void clearOtp(String phoneNumber) {
    final normalized = normalizePhoneNumber(phoneNumber);
    _otpStore.remove(normalized);
  }

  /// Get OTP expiry time remaining (in seconds)
  int getExpiryRemaining(String phoneNumber) {
    final normalized = normalizePhoneNumber(phoneNumber);
    final entry = _otpStore[normalized];
    if (entry == null || entry.isExpired) return 0;

    final remaining = entry.expiresAt.difference(DateTime.now());
    return remaining.inSeconds > 0 ? remaining.inSeconds : 0;
  }

  /// Reset service (for testing)
  void reset() {
    _otpStore.clear();
    _resendTimestamps.clear();
  }
}

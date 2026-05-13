import 'dart:math';

import 'package:flutter/foundation.dart';

import '../config/sms_config.dart';
import 'sms/sms_gateway_factory.dart';
import 'sms/sms_send_result.dart';

/// Stored OTP entry with expiry and attempt tracking
class OtpEntry {
  OtpEntry({
    required this.otp,
    required this.phoneNumber,
    required this.expiresAt,
  });

  final String otp;
  final String phoneNumber;
  final DateTime expiresAt;
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

  factory OtpVerificationResult.failure(String message, {int? attemptsRemaining}) {
    return OtpVerificationResult(
      success: false,
      errorMessage: message,
      attemptsRemaining: attemptsRemaining,
    );
  }
}

/// Singleton service for OTP generation, sending, and verification
class OtpService {
  OtpService._();

  static OtpService? _instance;

  static OtpService get instance {
    _instance ??= OtpService._();
    return _instance!;
  }

  /// Configuration
  static const int otpLength = 4;
  static const int validityMinutes = 5;
  static const int maxAttempts = 3;
  static const int resendCooldownSeconds = 60;

  /// In-memory OTP storage (phone -> OtpEntry)
  final Map<String, OtpEntry> _otpStore = {};

  /// Resend timestamps (phone -> last sent time)
  final Map<String, DateTime> _resendTimestamps = {};

  final Random _random = Random.secure();

  /// Generate a random OTP of specified length
  String _generateOtp() {
    final otp = StringBuffer();
    for (var i = 0; i < otpLength; i++) {
      otp.write(_random.nextInt(10));
    }
    return otp.toString();
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

  /// Send OTP to phone number
  Future<SmsSendResult> sendOtp(String phoneNumber) async {
    final normalized = normalizePhoneNumber(phoneNumber);

    // Check resend cooldown
    if (isResendCooldownActive(normalized)) {
      final remaining = getResendCooldownRemaining(normalized);
      return SmsSendResult.failure(
        'Please wait $remaining seconds before requesting a new code',
      );
    }

    // Generate OTP
    final otp = _generateOtp();
    final expiresAt = DateTime.now().add(const Duration(minutes: validityMinutes));

    // Store OTP
    _otpStore[normalized] = OtpEntry(
      otp: otp,
      phoneNumber: normalized,
      expiresAt: expiresAt,
    );

    // Update resend timestamp
    _resendTimestamps[normalized] = DateTime.now();

    // Send SMS
    final gateway = SmsGatewayFactory.getGateway();
    final message = SmsConfig.getOtpMessage(otp);

    debugPrint('[OTP Service] Sending OTP to $normalized via ${gateway.gatewayName}');

    return gateway.sendSms(
      phoneNumber: normalized,
      message: message,
    );
  }

  /// Verify OTP
  OtpVerificationResult verifyOtp(String phoneNumber, String otp) {
    final normalized = normalizePhoneNumber(phoneNumber);
    final entry = _otpStore[normalized];

    // Check if OTP exists
    if (entry == null) {
      return OtpVerificationResult.failure('No OTP found for this number');
    }

    // Check if OTP is expired
    if (entry.isExpired) {
      _otpStore.remove(normalized);
      return OtpVerificationResult.failure('OTP has expired. Please request a new one.');
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
      debugPrint('[OTP Service] OTP verified successfully for $normalized');
      return OtpVerificationResult.success();
    }

    // Increment attempts
    entry.attempts++;
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

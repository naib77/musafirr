import 'package:flutter/foundation.dart';

/// OTP Configuration
///
/// ## Development Mode (debug builds)
/// - OTPs are printed to console for easy testing
/// - OTPs are stored as plaintext in database (not hashed)
/// - No real SMS sent (uses console provider)
///
/// ## Release Mode (APK/IPA builds)
/// - OTPs are hashed (SHA-256) before storing in database
/// - Real SMS provider should be configured
/// - Use master OTP for testing without real SMS:
///   ```
///   flutter build apk --dart-define=MASTER_OTP_ENABLED=true --dart-define=MASTER_OTP=1234
///   ```
///
/// SECURITY WARNING: Never enable master OTP in production builds!

class OtpConfig {
  OtpConfig._();

  /// Whether app is running in development/debug mode
  /// Uses Flutter's kDebugMode - true for debug builds, false for release
  static bool get isDevMode => kDebugMode;

  /// Whether master OTP bypass is enabled
  /// Set via: --dart-define=MASTER_OTP_ENABLED=true
  static const bool masterOtpEnabled = bool.fromEnvironment(
    'MASTER_OTP_ENABLED',
    defaultValue: false,
  );

  /// Master OTP code that always works (when enabled)
  /// Set via: --dart-define=MASTER_OTP=1234
  static const String masterOtp = String.fromEnvironment(
    'MASTER_OTP',
    defaultValue: '',
  );

  /// Whether to persist OTPs to Supabase database
  /// Enables audit trail and cross-device verification
  static const bool persistToDatabase = bool.fromEnvironment(
    'OTP_PERSIST_TO_DB',
    defaultValue: true,
  );

  /// Whether to hash OTPs before storing in database
  /// - Development mode: false (plaintext for easy debugging)
  /// - Release mode: true (hashed for security)
  static bool get hashOtpInDatabase => !isDevMode;

  /// Whether to print OTPs to console (development mode only)
  static bool get printOtpToConsole => isDevMode;

  /// OTP length (number of digits)
  static const int otpLength = 4;

  /// OTP validity duration in minutes
  static const int validityMinutes = 5;

  /// Maximum verification attempts before OTP is invalidated
  static const int maxAttempts = 3;

  /// Cooldown between OTP resend requests in seconds
  static const int resendCooldownSeconds = 60;

  /// Check if master OTP is properly configured
  static bool get isMasterOtpConfigured =>
      masterOtpEnabled && masterOtp.isNotEmpty;

  /// Validate if provided OTP matches the master OTP
  static bool isMasterOtpMatch(String otp) =>
      isMasterOtpConfigured && otp == masterOtp;
}

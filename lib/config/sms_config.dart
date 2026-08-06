/// SMS Provider options
enum SmsProvider {
  /// Development mode - prints OTP to console
  console,

  /// BulkSMS BD provider
  bulkSmsBd,

  /// Alpha SMS provider
  alphaSms,

  /// Zaman IT SMS provider
  zamanIt,

  /// GenNet iSMS provider (direct from client — token ships in the APK)
  gennet,
}

/// SMS configuration for the application
class SmsConfig {
  SmsConfig._();

  /// Active SMS provider for the OtpService path.
  ///
  /// NOTE: When Supabase is configured, phone auth goes fully server-side via
  /// the send-otp / verify-otp Edge Functions and this gateway is NOT used.
  /// This setting only applies to the no-Supabase / mock fallback, where
  /// `console` just prints the OTP for local dev. `gennet` would send directly
  /// from the client (token ships in the APK — not recommended).
  static const SmsProvider activeProvider = SmsProvider.console;

  /// BulkSMS BD credentials (placeholder values)
  static const String bulkSmsBdApiKey = 'YOUR_BULKSMSBD_API_KEY';
  static const String bulkSmsBdSenderId = 'YOUR_SENDER_ID';
  static const String bulkSmsBdBaseUrl = 'https://bulksmsbd.net/api/smsapi';

  /// Alpha SMS credentials (placeholder values)
  static const String alphaSmsApiKey = 'YOUR_ALPHA_SMS_API_KEY';
  static const String alphaSmsSenderId = 'YOUR_SENDER_ID';
  static const String alphaSmsBaseUrl = 'https://api.alpha.net.bd/api/v1/sms';

  /// Zaman IT SMS credentials (placeholder values)
  static const String zamanItApiKey = 'YOUR_ZAMAN_IT_API_KEY';
  static const String zamanItSenderId = 'YOUR_SENDER_ID';
  static const String zamanItBaseUrl = 'https://sms.zamanit.com/api/send';

  /// GenNet iSMS credentials.
  ///
  /// Supplied at build time so the secret is not committed to git:
  ///   --dart-define=GENNET_API_TOKEN=... --dart-define=GENNET_SID=...
  /// (The token is still embedded in the compiled APK — for true secrecy,
  /// proxy the send through a Supabase Edge Function.)
  static const String gennetApiToken =
      String.fromEnvironment('GENNET_API_TOKEN', defaultValue: '');
  static const String gennetSid =
      String.fromEnvironment('GENNET_SID', defaultValue: '');
  static const String gennetBaseUrl = String.fromEnvironment(
    'GENNET_BASE_URL',
    defaultValue: 'https://isms.gennet.com.bd/api/v3/send-sms',
  );

  /// OTP message template
  static String getOtpMessage(String otp) {
    return 'Your Musaafir verification code is: $otp. Valid for 5 minutes.';
  }
}

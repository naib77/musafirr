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
}

/// SMS configuration for the application
class SmsConfig {
  SmsConfig._();

  /// Active SMS provider (change this to switch providers)
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

  /// OTP message template
  static String getOtpMessage(String otp) {
    return 'Your Musafir verification code is: $otp. Valid for 5 minutes.';
  }
}

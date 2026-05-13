import 'sms_send_result.dart';

/// Abstract interface for SMS gateways
abstract class SmsGateway {
  /// Send an SMS message
  Future<SmsSendResult> sendSms({
    required String phoneNumber,
    required String message,
  });

  /// Name of the SMS gateway
  String get gatewayName;

  /// Whether the gateway is properly configured
  bool get isConfigured;
}

import 'package:flutter/foundation.dart';

import 'sms_gateway.dart';
import 'sms_send_result.dart';

/// Development SMS gateway that prints OTP to console
class ConsoleSmsGateway implements SmsGateway {
  @override
  String get gatewayName => 'Console (Development)';

  @override
  bool get isConfigured => true;

  @override
  Future<SmsSendResult> sendSms({
    required String phoneNumber,
    required String message,
  }) async {
    // Simulate network delay
    await Future.delayed(const Duration(milliseconds: 500));

    // Print OTP to console with clear formatting
    debugPrint('');
    debugPrint('╔══════════════════════════════════════════════════════════╗');
    debugPrint('║                    SMS GATEWAY (DEV)                      ║');
    debugPrint('╠══════════════════════════════════════════════════════════╣');
    debugPrint('║ To: $phoneNumber');
    debugPrint('║ Message: $message');
    debugPrint('╚══════════════════════════════════════════════════════════╝');
    debugPrint('');

    return SmsSendResult.success(
      messageId: 'console_${DateTime.now().millisecondsSinceEpoch}',
    );
  }
}

import 'dart:convert';

import 'package:http/http.dart' as http;

import '../../config/sms_config.dart';
import 'sms_gateway.dart';
import 'sms_send_result.dart';

/// Alpha SMS gateway implementation
class AlphaSmsGateway implements SmsGateway {
  @override
  String get gatewayName => 'Alpha SMS';

  @override
  bool get isConfigured => SmsConfig.alphaSmsApiKey != 'YOUR_ALPHA_SMS_API_KEY';

  @override
  Future<SmsSendResult> sendSms({
    required String phoneNumber,
    required String message,
  }) async {
    if (!isConfigured) {
      return SmsSendResult.failure('Alpha SMS is not configured');
    }

    try {
      final response = await http.post(
        Uri.parse(SmsConfig.alphaSmsBaseUrl),
        headers: {
          'Content-Type': 'application/json',
          'Authorization': 'Bearer ${SmsConfig.alphaSmsApiKey}',
        },
        body: jsonEncode({
          'sender_id': SmsConfig.alphaSmsSenderId,
          'phone': phoneNumber,
          'message': message,
        }),
      );

      if (response.statusCode == 200) {
        final data = jsonDecode(response.body);
        return SmsSendResult.success(messageId: data['message_id']?.toString());
      } else {
        return SmsSendResult.failure(
          'Failed to send SMS: ${response.statusCode}',
        );
      }
    } catch (e) {
      return SmsSendResult.failure('SMS gateway error: $e');
    }
  }
}

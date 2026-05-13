import 'package:http/http.dart' as http;

import '../../config/sms_config.dart';
import 'sms_gateway.dart';
import 'sms_send_result.dart';

/// Zaman IT SMS gateway implementation
class ZamanItSmsGateway implements SmsGateway {
  @override
  String get gatewayName => 'Zaman IT SMS';

  @override
  bool get isConfigured => SmsConfig.zamanItApiKey != 'YOUR_ZAMAN_IT_API_KEY';

  @override
  Future<SmsSendResult> sendSms({
    required String phoneNumber,
    required String message,
  }) async {
    if (!isConfigured) {
      return SmsSendResult.failure('Zaman IT SMS is not configured');
    }

    try {
      final uri = Uri.parse(SmsConfig.zamanItBaseUrl).replace(
        queryParameters: {
          'api_key': SmsConfig.zamanItApiKey,
          'sender_id': SmsConfig.zamanItSenderId,
          'phone': phoneNumber,
          'message': message,
        },
      );

      final response = await http.get(uri);

      if (response.statusCode == 200) {
        return SmsSendResult.success(messageId: response.body);
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

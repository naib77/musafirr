import 'package:http/http.dart' as http;

import '../../config/sms_config.dart';
import 'sms_gateway.dart';
import 'sms_send_result.dart';

/// BulkSMS BD gateway implementation
class BulkSmsBdGateway implements SmsGateway {
  @override
  String get gatewayName => 'BulkSMS BD';

  @override
  bool get isConfigured =>
      SmsConfig.bulkSmsBdApiKey != 'YOUR_BULKSMSBD_API_KEY';

  @override
  Future<SmsSendResult> sendSms({
    required String phoneNumber,
    required String message,
  }) async {
    if (!isConfigured) {
      return SmsSendResult.failure('BulkSMS BD is not configured');
    }

    try {
      final uri = Uri.parse(SmsConfig.bulkSmsBdBaseUrl).replace(
        queryParameters: {
          'api_key': SmsConfig.bulkSmsBdApiKey,
          'senderid': SmsConfig.bulkSmsBdSenderId,
          'number': phoneNumber,
          'message': message,
          'type': 'text',
        },
      );

      final response = await http.get(uri);

      if (response.statusCode == 200) {
        // Parse response to check if successful
        // BulkSMS BD returns JSON with response_code
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

import 'dart:convert';
import 'dart:math';

import 'package:flutter/foundation.dart';
import 'package:http/http.dart' as http;

import '../../config/sms_config.dart';
import 'sms_gateway.dart';
import 'sms_send_result.dart';

/// GenNet (iSMS) Push SMS gateway — Single SMS API (v3).
///
/// Docs: `POST {base}/api/v3/send-sms` with a JSON body of
/// `{api_token, sid, msisdn, sms, csms_id}`. A `status`/`status_code` of
/// SUCCESS/200 means accepted; `smsinfo[0].reference_id` is the provider id.
///
/// SECURITY: `api_token` and `sid` are read from `--dart-define` so they are
/// not committed to git, but they are still compiled into the shipped APK and
/// can be recovered by decompiling it. For production, move the actual send
/// behind a Supabase Edge Function that holds the token server-side and have
/// the app call that instead.
class GennetSmsGateway implements SmsGateway {
  final Random _random = Random.secure();

  @override
  String get gatewayName => 'GenNet iSMS';

  @override
  bool get isConfigured =>
      SmsConfig.gennetApiToken.isNotEmpty && SmsConfig.gennetSid.isNotEmpty;

  /// Convert an app-normalized BD number (e.g. `01673293542`) to the msisdn
  /// format GenNet expects (`8801673293542`).
  String _toMsisdn(String phoneNumber) {
    var digits = phoneNumber.replaceAll(RegExp(r'[^0-9]'), '');
    if (digits.startsWith('880')) return digits;
    if (digits.startsWith('0')) digits = digits.substring(1);
    return '880$digits';
  }

  /// A per-request reference id: alphanumeric, unique within a day, <= 20 chars.
  String _generateCsmsId() {
    final ts = DateTime.now().microsecondsSinceEpoch.toRadixString(36);
    const chars = 'ABCDEFGHIJKLMNOPQRSTUVWXYZ0123456789';
    final rand =
        List.generate(5, (_) => chars[_random.nextInt(chars.length)]).join();
    final id = '$ts$rand'.toUpperCase();
    return id.length > 20 ? id.substring(id.length - 20) : id;
  }

  @override
  Future<SmsSendResult> sendSms({
    required String phoneNumber,
    required String message,
  }) async {
    if (!isConfigured) {
      return SmsSendResult.failure('GenNet SMS is not configured');
    }

    try {
      final response = await http.post(
        Uri.parse(SmsConfig.gennetBaseUrl),
        headers: {
          'accept': '*/*',
          'Content-Type': 'application/json',
        },
        body: jsonEncode({
          'api_token': SmsConfig.gennetApiToken,
          'sid': SmsConfig.gennetSid,
          'msisdn': _toMsisdn(phoneNumber),
          'sms': message,
          'csms_id': _generateCsmsId(),
        }),
      );

      Map<String, dynamic>? data;
      try {
        final decoded = jsonDecode(response.body);
        if (decoded is Map<String, dynamic>) data = decoded;
      } catch (_) {
        // Non-JSON body; fall through to status-code handling below.
      }

      final apiStatus = (data?['status'] as String?)?.toUpperCase();
      final apiStatusCode = data?['status_code'];
      final accepted = response.statusCode == 200 &&
          (apiStatus == 'SUCCESS' || apiStatusCode == 200);

      if (accepted) {
        String? referenceId;
        final smsInfo = data?['smsinfo'];
        if (smsInfo is List && smsInfo.isNotEmpty && smsInfo.first is Map) {
          referenceId = (smsInfo.first as Map)['reference_id']?.toString();
        }
        return SmsSendResult.success(messageId: referenceId);
      }

      final errorMessage = (data?['error_message'] as String?);
      final reason = (errorMessage != null && errorMessage.isNotEmpty)
          ? errorMessage
          : 'HTTP ${response.statusCode}';
      debugPrint('[GenNet SMS] send failed: $reason (body: ${response.body})');
      return SmsSendResult.failure('Failed to send SMS: $reason');
    } catch (e) {
      return SmsSendResult.failure('SMS gateway error: $e');
    }
  }
}

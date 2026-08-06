import 'package:flutter/foundation.dart';
import 'package:supabase_flutter/supabase_flutter.dart';

/// Result of starting a payment session.
class PaymentInitResult {
  const PaymentInitResult({
    required this.success,
    this.gatewayUrl,
    this.tranId,
    this.error,
  });

  final bool success;
  final String? gatewayUrl;
  final String? tranId;
  final String? error;

  factory PaymentInitResult.failure(String error) =>
      PaymentInitResult(success: false, error: error);
}

/// Outcome of the hosted payment page (from the WebView redirect).
enum PaymentOutcome { success, failed, cancelled }

/// Final settled state of a payment attempt, resolved from the server.
enum PaymentSettlement { paid, failed, pending }

/// Guest-facing SSLCommerz payment operations. The amount and settlement are
/// authoritative on the server (sslcommerz-init / sslcommerz-ipn Edge
/// Functions); the app only starts the session and opens the gateway page.
class SslcommerzService {
  SslcommerzService._();
  static final SslcommerzService instance = SslcommerzService._();

  SupabaseClient get _client => Supabase.instance.client;

  /// Starts a payment session for a confirmed booking. Returns the hosted
  /// gateway URL to open in a WebView. Never throws.
  Future<PaymentInitResult> initiate(String bookingId) async {
    try {
      final response = await _client.functions.invoke(
        'sslcommerz-init',
        body: {'booking_id': bookingId},
      );
      final data = response.data;
      if (data is Map && data['success'] == true) {
        return PaymentInitResult(
          success: true,
          gatewayUrl: data['gateway_url'] as String?,
          tranId: data['tran_id'] as String?,
        );
      }
      final error = (data is Map ? data['error']?.toString() : null) ??
          'Could not start payment';
      return PaymentInitResult.failure(error);
    } on FunctionException catch (e) {
      final details = e.details;
      final msg = (details is Map ? details['error']?.toString() : null) ??
          'Could not start payment';
      return PaymentInitResult.failure(msg);
    } catch (e) {
      debugPrint('[SslcommerzService] initiate failed: $e');
      return PaymentInitResult.failure('Could not start payment. Try again.');
    }
  }

  /// Host-only: confirms a booking was paid in cash. The server RPC verifies the
  /// caller owns the listing, records an auditable cash payment, flips the
  /// booking to paid, and notifies the guest. Returns true on success.
  Future<bool> markCashReceived(String bookingId) async {
    try {
      await _client.rpc('mark_cash_payment', params: {
        'p_booking_id': bookingId,
      });
      return true;
    } catch (e) {
      debugPrint('[SslcommerzService] markCashReceived failed: $e');
      return false;
    }
  }

  /// Polls the payment attempt (by [tranId]) until it settles, covering the lag
  /// between the gateway closing and the server settling the payment. Returns
  /// [PaymentSettlement.paid] / [PaymentSettlement.failed] once known, or
  /// [PaymentSettlement.pending] if it hasn't settled within the budget.
  Future<PaymentSettlement> awaitSettlement(
    String tranId, {
    int attempts = 8,
    Duration interval = const Duration(seconds: 2),
  }) async {
    for (var i = 0; i < attempts; i++) {
      try {
        final row = await _client
            .from('payments')
            .select('status')
            .eq('tran_id', tranId)
            .maybeSingle();
        final status = row?['status'] as String?;
        if (status == 'paid') return PaymentSettlement.paid;
        if (status == 'failed' || status == 'cancelled') {
          return PaymentSettlement.failed;
        }
      } catch (e) {
        debugPrint('[SslcommerzService] awaitSettlement poll failed: $e');
      }
      if (i < attempts - 1) await Future.delayed(interval);
    }
    return PaymentSettlement.pending;
  }
}

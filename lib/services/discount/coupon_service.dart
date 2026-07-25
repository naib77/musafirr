import 'package:flutter/foundation.dart';
import 'package:supabase_flutter/supabase_flutter.dart';

/// Result of validating a coupon code against a booking amount. The discount
/// math is authoritative from the server (`validate_coupon` RPC), so the client
/// never computes its own discount.
class CouponValidation {
  const CouponValidation({
    required this.valid,
    required this.message,
    this.couponId,
    this.code,
    this.discountType,
    this.discountAmount = 0,
    this.finalAmount = 0,
  });

  final bool valid;
  final String message;
  final String? couponId;
  final String? code;

  /// 'percentage' or 'flat'.
  final String? discountType;
  final double discountAmount;
  final double finalAmount;

  factory CouponValidation.error(String message) =>
      CouponValidation(valid: false, message: message);

  factory CouponValidation.fromMap(Map<String, dynamic> m) {
    final valid = m['valid'] == true;
    return CouponValidation(
      valid: valid,
      message: (m['message'] as String?) ?? (valid ? 'Coupon applied' : 'Invalid coupon'),
      couponId: m['coupon_id'] as String?,
      code: m['code'] as String?,
      discountType: m['discount_type'] as String?,
      discountAmount: (m['discount_amount'] as num?)?.toDouble() ?? 0,
      finalAmount: (m['final_amount'] as num?)?.toDouble() ?? 0,
    );
  }
}

/// Guest-facing coupon operations, backed by the server-side SECURITY DEFINER
/// functions so codes can't be enumerated and limits can't be bypassed.
class CouponService {
  CouponService._();
  static final CouponService instance = CouponService._();

  SupabaseClient get _client => Supabase.instance.client;

  /// Validate [code] for a pre-discount [amount]. Returns a verdict with the
  /// server-computed discount; never throws.
  Future<CouponValidation> validate(String code, double amount) async {
    final trimmed = code.trim();
    if (trimmed.isEmpty) {
      return CouponValidation.error('Enter a coupon code');
    }
    try {
      final res = await _client.rpc('validate_coupon', params: {
        'p_code': trimmed,
        'p_amount': amount,
      });
      if (res is Map) {
        return CouponValidation.fromMap(res.cast<String, dynamic>());
      }
      return CouponValidation.error('Could not check coupon. Please try again.');
    } catch (e) {
      debugPrint('[CouponService] validate failed: $e');
      return CouponValidation.error('Could not check coupon. Please try again.');
    }
  }

  /// Records a redemption and increments usage after a booking is created.
  /// Best-effort: the booking already exists, so a failure here is logged, not
  /// surfaced. Returns true on success.
  Future<bool> redeem({
    required String couponId,
    required String bookingId,
    required double discountAmount,
  }) async {
    try {
      await _client.rpc('redeem_coupon', params: {
        'p_coupon_id': couponId,
        'p_booking_id': bookingId,
        'p_discount_amount': discountAmount,
      });
      return true;
    } catch (e) {
      debugPrint('[CouponService] redeem failed: $e');
      return false;
    }
  }
}

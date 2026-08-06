/// A single payment row (from the `payments` table), as shown in the
/// Payments & payouts history. Only the display-relevant fields are kept.
class PaymentRecord {
  const PaymentRecord({
    required this.id,
    required this.bookingId,
    required this.amount,
    required this.currency,
    required this.status,
    this.method,
    this.createdAt,
    this.paidAt,
  });

  final String id;
  final String bookingId;
  final double amount;
  final String currency;

  /// 'initiated' | 'paid' | 'failed' | 'cancelled' | 'refunded' | …
  final String status;

  /// Gateway card_type, e.g. 'BKASH-BKash', 'VISA-…', or 'cash'.
  final String? method;
  final DateTime? createdAt;
  final DateTime? paidAt;

  bool get isPaid => status == 'paid';
  bool get isCash => (method ?? '').toLowerCase() == 'cash';

  /// The moment to display/sort by: when it settled, else when it was created.
  DateTime? get effectiveDate => paidAt ?? createdAt;

  factory PaymentRecord.fromJson(Map<String, dynamic> json) {
    DateTime? parse(dynamic v) =>
        v == null ? null : DateTime.tryParse(v as String)?.toLocal();
    return PaymentRecord(
      id: json['id'] as String,
      bookingId: json['booking_id'] as String? ?? '',
      amount: (json['amount'] as num?)?.toDouble() ?? 0,
      currency: json['currency'] as String? ?? 'BDT',
      status: json['status'] as String? ?? 'initiated',
      method: json['card_type'] as String?,
      createdAt: parse(json['created_at']),
      paidAt: parse(json['validated_at']),
    );
  }
}

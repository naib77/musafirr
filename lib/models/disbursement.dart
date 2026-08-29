import 'payout_method.dart';

/// Which direction money went. A payout and a refund are the same mechanical
/// act — an admin sends money to a saved account — but they answer different
/// questions on screen, so the ledger records which one it was rather than
/// leaving the reader to infer it from who the recipient happens to be.
enum DisbursementKind { hostPayout, guestRefund }

extension DisbursementKindX on DisbursementKind {
  String get wireName => switch (this) {
        DisbursementKind.hostPayout => 'host_payout',
        DisbursementKind.guestRefund => 'guest_refund',
      };

  String get label => switch (this) {
        DisbursementKind.hostPayout => 'Payout',
        DisbursementKind.guestRefund => 'Refund',
      };
}

DisbursementKind disbursementKindFromWire(String? value) =>
    value == 'guest_refund'
        ? DisbursementKind.guestRefund
        : DisbursementKind.hostPayout;

/// `pending` — queued but not yet sent. `sent` — the money has left.
/// `failed` — the transfer bounced and may be retried.
enum DisbursementStatus { pending, sent, failed }

extension DisbursementStatusX on DisbursementStatus {
  String get wireName => name;

  String get label => switch (this) {
        DisbursementStatus.pending => 'Processing',
        DisbursementStatus.sent => 'Paid',
        DisbursementStatus.failed => 'Failed',
      };
}

DisbursementStatus disbursementStatusFromWire(String? value) => switch (value) {
      'sent' => DisbursementStatus.sent,
      'failed' => DisbursementStatus.failed,
      // Unknown values read as pending: claiming money has arrived when the
      // app cannot tell is the one wrong answer here.
      _ => DisbursementStatus.pending,
    };

/// A record that money was actually paid out to a host or refunded to a guest.
///
/// Written only by an admin, through `record_disbursement()`, after they send
/// the money from the bKash app or a bank transfer. Its purpose is to answer
/// two questions that were previously answered from memory: "have we paid this
/// host yet?" and "what reference can I quote when they say they never got
/// it?".
class Disbursement {
  const Disbursement({
    required this.id,
    required this.userId,
    required this.payoutMethodId,
    required this.kind,
    required this.status,
    required this.amount,
    required this.currency,
    this.bookingId,
    this.reference,
    this.note,
    this.failureReason,
    this.createdAt,
    this.sentAt,
    this.method,
  });

  final String id;
  final String userId;
  final String payoutMethodId;

  /// The stay this settles, when it settles exactly one. Null for a lump
  /// settlement covering several bookings, or a goodwill refund.
  final String? bookingId;

  final DisbursementKind kind;
  final DisbursementStatus status;
  final double amount;
  final String currency;

  /// The bKash TrxID or bank transfer reference — the thing worth quoting.
  final String? reference;
  final String? note;
  final String? failureReason;

  final DateTime? createdAt;
  final DateTime? sentAt;

  /// The destination account, when the query joined it in. Because payout
  /// methods are immutable and never hard-deleted, this is a faithful record
  /// of where the money actually went, not a best guess at today's account.
  final PayoutMethod? method;

  /// When to display this by: when it settled, else when it was recorded.
  DateTime? get effectiveDate => sentAt ?? createdAt;

  factory Disbursement.fromJson(Map<String, dynamic> json) {
    DateTime? parse(dynamic v) =>
        v == null ? null : DateTime.tryParse(v as String)?.toLocal();

    // The embedded method arrives as a nested object when the select asked for
    // one; absent otherwise. Both are normal, so neither is an error.
    final rawMethod = json['payout_methods'];

    return Disbursement(
      id: json['id'] as String,
      userId: json['user_id'] as String? ?? '',
      payoutMethodId: json['payout_method_id'] as String? ?? '',
      bookingId: json['booking_id'] as String?,
      kind: disbursementKindFromWire(json['kind'] as String?),
      status: disbursementStatusFromWire(json['status'] as String?),
      amount: (json['amount'] as num?)?.toDouble() ?? 0,
      currency: json['currency'] as String? ?? 'BDT',
      reference: json['reference'] as String?,
      note: json['note'] as String?,
      failureReason: json['failure_reason'] as String?,
      createdAt: parse(json['created_at']),
      sentAt: parse(json['sent_at']),
      method: rawMethod is Map
          ? PayoutMethod.fromJson(rawMethod.cast<String, dynamic>())
          : null,
    );
  }
}

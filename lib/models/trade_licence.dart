/// Where a hotel listing's optional trade licence stands (migration 152).
///
/// Optional by the owner's decision: nothing is gated on it. A listing is
/// live with or without one; an admin-verified licence only adds the
/// "Licensed hotel" badge. The verdict is admin-only — the table has no write
/// policy, and the submit RPC can only ever set 'pending'.
enum TradeLicenceStatus {
  /// Nothing submitted (no row).
  none,
  pending,
  verified,
  rejected;

  static TradeLicenceStatus fromName(String? value) =>
      TradeLicenceStatus.values.firstWhere(
        (s) => s.name == value,
        // An unknown value from a newer database must not read as verified.
        orElse: () => TradeLicenceStatus.none,
      );
}

class TradeLicence {
  const TradeLicence({
    this.status = TradeLicenceStatus.none,
    this.licenceNumber,
    this.reason,
  });

  static const TradeLicence none = TradeLicence();

  factory TradeLicence.fromJson(Map<String, dynamic> json) => TradeLicence(
        status: TradeLicenceStatus.fromName(json['status'] as String?),
        licenceNumber: json['licence_number'] as String?,
        reason: json['rejection_reason'] as String?,
      );

  final TradeLicenceStatus status;
  final String? licenceNumber;

  /// Why an admin turned it down; for the host only, never guests.
  final String? reason;

  /// The one line the host card shows for this state.
  String get summary => switch (status) {
        TradeLicenceStatus.none =>
          'Optional. Add your trade licence to earn a "Licensed hotel" badge. '
              'Your listing is live either way.',
        TradeLicenceStatus.pending =>
          'Submitted. A Musafir admin will review it.',
        TradeLicenceStatus.verified =>
          'Verified. Guests see the "Licensed hotel" badge.',
        TradeLicenceStatus.rejected => (reason == null || reason!.isEmpty)
            ? 'Not accepted. Upload a clearer copy.'
            : 'Not accepted: $reason',
      };
}

/// What to tell the host when `submit_trade_licence` refuses, by hint.
String tradeLicenceRefusalMessage(String? hint) => switch (hint) {
      'not_a_hotel' => 'Save this listing as a hotel first.',
      'document_invalid' =>
        'Upload a JPG, PNG or PDF of the licence, under 5 MB.',
      'licence_number_invalid' => 'The licence number is too long.',
      'not_listing_owner' => 'Only the host can add a licence.',
      _ => 'Could not submit the licence. Please try again.',
    };

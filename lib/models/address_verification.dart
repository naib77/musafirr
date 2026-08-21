/// Where a host's own address verification stands.
///
/// Distinct from [HostVerifications], which is the guest-facing view: that one
/// carries a single boolean per credential and nothing else. This is the host's
/// own record, so it also carries the state that only they should see — the
/// address they declared and why an admin turned it down.
///
/// The verdict belongs to an admin who physically visited the address
/// (migration 095). Nothing the app does can grant it; the database rejects the
/// attempt outright.
enum AddressVerificationStatus {
  /// Nothing submitted yet.
  none,

  /// Bill and address are in, awaiting a Musafir admin's visit.
  pending,

  /// An admin visited and confirmed the address.
  verified,

  /// An admin visited and could not confirm it. [AddressVerification.reason]
  /// says why; the host can fix it and resubmit.
  rejected;

  static AddressVerificationStatus fromName(String? value) {
    return AddressVerificationStatus.values.firstWhere(
      (s) => s.name == value,
      // An unknown value from a newer database must not read as verified.
      orElse: () => AddressVerificationStatus.none,
    );
  }
}

class AddressVerification {
  const AddressVerification({
    this.status = AddressVerificationStatus.none,
    this.addressLine,
    this.reason,
    this.hasProofDocument = false,
  });

  /// Nothing submitted — also the fail-safe result of a failed lookup.
  static const AddressVerification none = AddressVerification();

  final AddressVerificationStatus status;

  /// The full address the host declared, so a resubmission starts from what
  /// they last typed rather than a blank field.
  final String? addressLine;

  /// Why an admin rejected the address. Only set when [status] is
  /// [AddressVerificationStatus.rejected].
  final String? reason;

  /// Whether the billed copy is already on file. The address and the document
  /// are two halves of one submission — the server refuses a declaration with
  /// no document behind it.
  final bool hasProofDocument;

  bool get isVerified => status == AddressVerificationStatus.verified;
  bool get isPending => status == AddressVerificationStatus.pending;
  bool get isRejected => status == AddressVerificationStatus.rejected;

  /// Whether the host has submitted at all. This — not [isVerified] — is what
  /// unlocks publishing a listing: a physical visit takes days, and onboarding
  /// must not wait on one.
  bool get isSubmitted =>
      hasProofDocument && status != AddressVerificationStatus.none;

  factory AddressVerification.fromJson(Map<String, dynamic> json) {
    final path = json['address_proof_path'] as String?;
    return AddressVerification(
      status: AddressVerificationStatus.fromName(
        json['address_verification_status'] as String?,
      ),
      addressLine: json['address_line'] as String?,
      reason: json['address_rejection_reason'] as String?,
      hasProofDocument: path != null && path.isNotEmpty,
    );
  }
}

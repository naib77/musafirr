/// What a host has actually had verified, as the database records it.
///
/// Read from the `public_profiles` view (migrations 094, 095), which exposes
/// these three booleans and nothing else about the underlying documents.
/// Guests see only the outcome, never the NID number, the uploaded files, or
/// what an admin wrote down at the door.
///
/// Every flag defaults to false: an absent or unreadable profile must not read
/// as a verified one. A badge is a trust claim, so the fail-safe direction is
/// to claim nothing.
class HostVerifications {
  const HostVerifications({
    this.phoneVerified = false,
    this.identityVerified = false,
    this.addressVerified = false,
  });

  /// Nothing verified — also what a failed lookup yields.
  static const HostVerifications none = HostVerifications();

  /// Phone confirmed by OTP at sign-up (`profiles.phone_verified`).
  final bool phoneVerified;

  /// Identity document + selfie approved by an admin
  /// (`profiles.verification_status = 'verified'`). A pending or rejected
  /// submission is not verified.
  final bool identityVerified;

  /// A Musafir admin physically visited the host's declared address and
  /// approved it (`profiles.address_verification_status = 'verified'`).
  /// A submitted bill alone does not earn this — see [AddressVerification].
  final bool addressVerified;

  /// Whether there is anything at all to show. The badge strip hides itself
  /// entirely for an unverified host rather than displaying an empty row.
  bool get hasAny => phoneVerified || identityVerified || addressVerified;

  factory HostVerifications.fromJson(Map<String, dynamic> json) {
    return HostVerifications(
      phoneVerified: json['phone_verified'] as bool? ?? false,
      identityVerified: json['identity_verified'] as bool? ?? false,
      addressVerified: json['address_verified'] as bool? ?? false,
    );
  }

  @override
  bool operator ==(Object other) =>
      other is HostVerifications &&
      other.phoneVerified == phoneVerified &&
      other.identityVerified == identityVerified &&
      other.addressVerified == addressVerified;

  @override
  int get hashCode =>
      Object.hash(phoneVerified, identityVerified, addressVerified);
}

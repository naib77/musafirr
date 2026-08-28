/// A date range the host has declared unavailable on one listing.
///
/// Distinct from the three availability flags that already existed — the
/// host-wide Away switch, the per-listing Hide/Show, and the per-plan rate
/// toggles — because all three of those are all-or-nothing across every future
/// date. A block is the only way to say "I'm away 2–9 September" without hiding
/// the listing and having to remember to un-hide it.
///
/// Rows live in `public.listing_availability_blocks` (migration 110) and are
/// enforced at booking time by `create_marketplace_booking` and surfaced to
/// guests through `is_booking_available` (migration 111).
class AvailabilityBlock {
  const AvailabilityBlock({
    required this.id,
    required this.listingId,
    required this.startsAt,
    required this.endsAt,
    this.note,
  });

  factory AvailabilityBlock.fromJson(Map<String, dynamic> json) {
    return AvailabilityBlock(
      id: json['id'] as String,
      listingId: json['listing_id'] as String,
      startsAt: DateTime.parse(json['starts_at'] as String).toLocal(),
      endsAt: DateTime.parse(json['ends_at'] as String).toLocal(),
      note: json['note'] as String?,
    );
  }

  final String id;
  final String listingId;
  final DateTime startsAt;
  final DateTime endsAt;

  /// The host's private reason. Never leaves the owner's own client — the
  /// guest-facing `listing_blocked_ranges` RPC returns the two timestamps only,
  /// which is also why the table's SELECT policy is owner-scoped.
  final String? note;

  /// Whether this block collides with [start]–[end].
  ///
  /// Half-open on both sides, matching the `'[)'` bounds every range in the
  /// schema uses (`bookings_no_overlap`, `listing_blocks_no_overlap`). The
  /// consequence worth stating: a block that *ends* at the instant a stay
  /// begins does not collide, so blocking a checkout day doesn't silently eat
  /// the next check-in.
  bool overlaps(DateTime start, DateTime end) =>
      start.isBefore(endsAt) && startsAt.isBefore(end);
}

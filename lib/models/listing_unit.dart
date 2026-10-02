/// One bookable room of a listing (`public.listing_units`, migration 147).
///
/// Every listing has at least one; a hotel has as many as the host set with
/// `set_listing_unit_count`. Guests never see these: the database assigns a
/// booking its room, and only the host can move it (151's
/// `reassign_booking_unit`) or block one room on its own.
class ListingUnit {
  const ListingUnit({
    required this.id,
    required this.listingId,
    required this.isActive,
    this.label,
  });

  factory ListingUnit.fromJson(Map<String, dynamic> json) {
    return ListingUnit(
      id: json['id'] as String,
      listingId: json['listing_id'] as String,
      label: json['label'] as String?,
      isActive: json['is_active'] as bool? ?? true,
    );
  }

  final String id;
  final String listingId;

  /// The host's own name for the room ("201", "Garden room"). Nullable in the
  /// table and never set by `set_listing_unit_count`, so most rooms have none.
  final String? label;

  /// A shrink deactivates rather than deletes (bookings keep their unit_id).
  final bool isActive;
}

/// What the host sees for a room: its label, or its 1-based place in
/// [rooms] when it has none. Positional names are only stable while the room
/// set is — fine for a host's own screen, never stored.
String listingUnitName(ListingUnit unit, List<ListingUnit> rooms) {
  final label = unit.label?.trim();
  if (label != null && label.isNotEmpty) return label;
  final i = rooms.indexWhere((u) => u.id == unit.id);
  return i < 0 ? 'Room' : 'Room ${i + 1}';
}

/// What to tell the host when `reassign_booking_unit` refuses, keyed by the
/// hint (never the message text — see database-booking-and-search.md).
String roomMoveRefusalMessage(String? hint) => switch (hint) {
      'unit_taken' => 'That room already has a booking at these times.',
      'unit_blocked' => 'That room is blocked for these dates.',
      'unit_mismatch' => 'That room is no longer part of this listing.',
      'booking_not_live' => 'This booking can no longer be moved.',
      'not_listing_owner' => 'Only the host can move a booking.',
      _ => 'Could not move the booking. Please try again.',
    };

/// The label to store for what the host typed: trimmed, and null when blank
/// so the room falls back to "Room N" rather than storing ''. `label` is
/// unique per listing (147) and '' would collide with the next blank rename.
String? normalizeRoomLabel(String raw) {
  final trimmed = raw.trim();
  return trimmed.isEmpty ? null : trimmed;
}

/// The longest label `listing_units_label_len` accepts.
const kRoomLabelMaxLength = 40;

/// What to tell the host when a rename is refused, keyed by SQLSTATE: the
/// write is a plain UPDATE, so there is no hint, only the constraint's code.
String roomRenameRefusalMessage(String? code) => switch (code) {
      '23505' => 'Another room already has that name.',
      '23514' => 'Keep the name to $kRoomLabelMaxLength characters.',
      _ => 'Could not rename the room. Please try again.',
    };

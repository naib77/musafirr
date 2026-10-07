/// The contact phone a host attaches to a listing or hotel (160).
///
/// Who sees it is decided by the database, not here: it lives in
/// `listing_addresses` / `property_addresses`, so it is disclosed exactly
/// when the exact address is — owner, admin, and a guest the host has
/// accepted (093/103). It is never a public column.
///
/// `canonicalBdPhone` (auth/phone_number.dart) is the login normaliser and is
/// parity-checked against its TypeScript twin, so it is reused rather than
/// edited. What this adds is the shape the row stores: E.164-style, the way
/// `profiles.mobile` already is on live (`+880…`), so `get_booking_contacts`
/// can hand back either without the card telling them apart.
library;

import 'auth/phone_number.dart';

final RegExp _bdNational = RegExp(r'^01[3-9][0-9]{8}$');
final RegExp _digits = RegExp(r'^[0-9]{8,15}$');

/// Blank → null (no contact number). A BD mobile in any spelling → `+8801…`.
/// Any other `+`-prefixed international number is kept as digits with its
/// plus. Anything else → [FormatException], so the form can say so instead
/// of the row's check constraint refusing the whole address save.
String? normalizeContactPhone(String? input) {
  final raw = input?.trim();
  if (raw == null || raw.isEmpty) return null;
  final n = canonicalBdPhone(raw);
  if (_bdNational.hasMatch(n)) return '+880${n.substring(1)}';
  // canonicalBdPhone strips a foreign "+" and leaves the digits; a number
  // that was typed with one is international, one without is a typo.
  if (raw.startsWith('+') && _digits.hasMatch(n)) return '+$n';
  throw const FormatException(
      'Enter a Bangladeshi mobile (e.g. 017…) or an international number '
      'starting with +.');
}

/// `AppTextField.validator` form of [normalizeContactPhone]: null when the
/// field is acceptable (blank included), the message otherwise.
String? contactPhoneValidator(String? value) {
  try {
    normalizeContactPhone(value);
    return null;
  } on FormatException catch (e) {
    return e.message;
  }
}

/// What the form shows for a stored `+8801…`: the national spelling hosts
/// recognise. Other countries are shown as stored.
String displayContactPhone(String stored) =>
    stored.startsWith('+880') ? '0${stored.substring(4)}' : stored;

/// The most numbers one listing or hotel may carry -- the cap 162's check
/// constraint enforces, mirrored so the form stops offering "Add number"
/// instead of the save being refused.
const int maxContactPhones = 5;

/// `contact_phones` as PostgREST returns it (a JSON array, or null) → a
/// list. Anything that is not a string is dropped rather than throwing, so a
/// malformed row cannot break the screen that reads it.
List<String> contactPhonesFromJson(Object? raw) =>
    raw is List ? List.unmodifiable(raw.whereType<String>()) : const <String>[];

/// The host's list as typed → what `contact_phones` stores: each entry
/// through [normalizeContactPhone], blanks dropped, duplicates dropped (017…
/// and +88017… are the same phone), order kept. More than
/// [maxContactPhones], or any entry that is not a phone number, is a
/// [FormatException] carrying the message to show.
List<String> normalizeContactPhones(Iterable<String> typed) {
  final out = <String>[];
  for (final t in typed) {
    final n = normalizeContactPhone(t);
    if (n != null && !out.contains(n)) out.add(n);
  }
  if (out.length > maxContactPhones) {
    throw const FormatException(
        'Add at most $maxContactPhones contact numbers.');
  }
  return out;
}

/// [normalizeContactPhones] as a form check: null when the list can be
/// saved, the message otherwise.
String? contactPhonesError(Iterable<String> typed) {
  try {
    normalizeContactPhones(typed);
    return null;
  } on FormatException catch (e) {
    return e.message;
  }
}

import '../../models/search_filters.dart';

/// The interval a dated search must be filtered by, ready for the wire.
///
/// Exists as its own value because deciding *whether* a search has usable
/// dates is a real rule with three ways to get it wrong (a half-filled range,
/// an hourly selection missing its times, a reversed window), and none of them
/// is reachable from a widget test once it is buried in the repository's RPC
/// parameter map.
class SearchDateWindow {
  const SearchDateWindow({required this.startsAt, required this.endsAt});

  final DateTime startsAt;
  final DateTime endsAt;

  /// Serialized as UTC. A naive local (UTC+6) string is read by a timestamptz
  /// parameter as UTC, which would shift the window six hours and quietly
  /// filter on the wrong day — the same trap createMarketplaceBooking documents.
  String get startsAtIso => startsAt.toUtc().toIso8601String();
  String get endsAtIso => endsAt.toUtc().toIso8601String();
}

/// The window [filters] should search within, or null to search every date.
///
/// Null means "do not filter", not "no results": an undated search has no
/// window to test a listing against, so every listing still qualifies.
SearchDateWindow? searchDateWindowFor(SearchFilters filters) {
  // effectiveCheckIn/Out already fold the two date modes together — a
  // check-in/check-out range, or an hourly singleDate plus start/end times —
  // and return null when either half of the selection is still missing.
  final start = filters.effectiveCheckIn;
  final end = filters.effectiveCheckOut;
  if (start == null || end == null) return null;

  // A zero-length or reversed window is not a search constraint. Reversed is
  // reachable in hourly mode (an end time before the start time), and the rest
  // of the app already refuses to price it — numberOfHours clamps to at least
  // one hour rather than crossing midnight. Sending it would make the RPC
  // build tstzrange(lower > upper) and abort the whole search.
  if (!end.isAfter(start)) return null;

  return SearchDateWindow(startsAt: start, endsAt: end);
}

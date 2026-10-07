import '../../models/listing.dart';

/// One curated Explore row: its heading and every listing behind its
/// "See all" (the row itself shows only the first few).
typedef CuratedRow = ({String title, List<Listing> items});

/// The hotel-only rows on the Explore feed: newest, cheapest, best rated.
///
/// A hotel reaches the feed as one card -- its cheapest matching room type
/// (154) -- so a row entry *is* a hotel, and [Listing.isHotelRoomType] is
/// what tells it apart from a flat or a room. Ordering uses that room type's
/// own fields: its price is the hotel's "from" price, which is what the card
/// shows, and its created_at is close enough to when the hotel went live
/// (a host creates the first room type with the hotel).
///
/// A row with nothing in it is left out, so a catalogue with no hotels shows
/// no hotel rows at all rather than empty headings.
List<CuratedRow> hotelRows(List<Listing> listings) {
  final hotels = listings.where((l) => l.isHotelRoomType).toList();
  if (hotels.isEmpty) return const [];

  final newest = hotels.where((l) => l.createdAt != null).toList()
    ..sort((a, b) => b.createdAt!.compareTo(a.createdAt!));

  final budget = hotels.where((l) => l.displayPrice > 0).toList()
    ..sort((a, b) => a.displayPrice.compareTo(b.displayPrice));

  final topRated = hotels.where((l) => (l.rating ?? 0) > 0).toList()
    ..sort((a, b) => (b.rating ?? 0).compareTo(a.rating ?? 0));

  return [
    (title: 'Newly available hotels', items: newest),
    (title: 'Budget-friendly hotels', items: budget),
    (title: 'Top rated hotels', items: topRated),
  ].where((row) => row.items.isNotEmpty).toList();
}

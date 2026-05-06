import 'booking_status.dart';
import 'listing.dart';

class Booking {
  Booking({
    required this.id,
    required this.listingId,
    required this.tenantName,
    required this.startAt,
    required this.endAt,
    required this.totalPrice,
    required this.unitLabel,
    // New marketplace fields
    this.userId,
    this.status = BookingStatus.pending,
    this.guestCount = 1,
    this.checkIn,
    this.checkOut,
    this.listing,
    this.createdAt,
    this.listingTitle,
    this.listingImageUrl,
    this.listingCity,
  });

  final String id;
  final String listingId;
  final String tenantName;
  final DateTime startAt;
  final DateTime endAt;
  final double totalPrice;
  final String unitLabel;

  // New marketplace fields
  final String? userId;
  final BookingStatus status;
  final int guestCount;
  final DateTime? checkIn;
  final DateTime? checkOut;
  final Listing? listing;
  final DateTime? createdAt;
  final String? listingTitle;
  final String? listingImageUrl;
  final String? listingCity;

  // Computed properties
  DateTime get effectiveCheckIn => checkIn ?? startAt;
  DateTime get effectiveCheckOut => checkOut ?? endAt;

  int get numberOfNights => effectiveCheckOut.difference(effectiveCheckIn).inDays;

  bool get isUpcoming =>
      status.isActive && effectiveCheckIn.isAfter(DateTime.now());

  bool get isPast =>
      status.isPast || effectiveCheckOut.isBefore(DateTime.now());

  bool get isOngoing =>
      status.isActive &&
      effectiveCheckIn.isBefore(DateTime.now()) &&
      effectiveCheckOut.isAfter(DateTime.now());

  Booking copyWith({
    String? id,
    String? listingId,
    String? tenantName,
    DateTime? startAt,
    DateTime? endAt,
    double? totalPrice,
    String? unitLabel,
    String? userId,
    BookingStatus? status,
    int? guestCount,
    DateTime? checkIn,
    DateTime? checkOut,
    Listing? listing,
    DateTime? createdAt,
    String? listingTitle,
    String? listingImageUrl,
    String? listingCity,
  }) {
    return Booking(
      id: id ?? this.id,
      listingId: listingId ?? this.listingId,
      tenantName: tenantName ?? this.tenantName,
      startAt: startAt ?? this.startAt,
      endAt: endAt ?? this.endAt,
      totalPrice: totalPrice ?? this.totalPrice,
      unitLabel: unitLabel ?? this.unitLabel,
      userId: userId ?? this.userId,
      status: status ?? this.status,
      guestCount: guestCount ?? this.guestCount,
      checkIn: checkIn ?? this.checkIn,
      checkOut: checkOut ?? this.checkOut,
      listing: listing ?? this.listing,
      createdAt: createdAt ?? this.createdAt,
      listingTitle: listingTitle ?? this.listingTitle,
      listingImageUrl: listingImageUrl ?? this.listingImageUrl,
      listingCity: listingCity ?? this.listingCity,
    );
  }
}

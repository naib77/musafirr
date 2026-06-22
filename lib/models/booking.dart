import '../core/currency/currency.dart';
import '../core/currency/money.dart';
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
    this.listingType,
    // Currency and pricing
    this.currency = Currency.BDT,
    this.serviceFee,
    this.discount,
    // Lifecycle fields
    this.hostMessage,
    this.rejectionReason,
    this.confirmedAt,
    this.actualCheckIn,
    this.completedAt,
    this.cancelledBy,
    this.cancelledAt,
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
  final String? listingType;

  // Currency and pricing
  final Currency currency;
  final double? serviceFee;
  final double? discount;

  // Lifecycle fields
  /// Optional message from host when accepting the booking
  final String? hostMessage;

  /// Optional reason from host when rejecting the booking
  final String? rejectionReason;

  /// Timestamp when host confirmed the booking
  final DateTime? confirmedAt;

  /// Timestamp when host marked guest as arrived (check-in)
  final DateTime? actualCheckIn;

  /// Timestamp when host marked service as complete
  final DateTime? completedAt;

  /// User ID of who cancelled the booking (guest or host)
  final String? cancelledBy;

  /// Timestamp when booking was cancelled
  final DateTime? cancelledAt;

  // Money-typed getters for type-safe currency handling
  Money get totalPriceMoney => Money(totalPrice, currency);
  Money? get serviceFeeMoney =>
      serviceFee != null ? Money(serviceFee!, currency) : null;
  Money? get discountMoney =>
      discount != null ? Money(discount!, currency) : null;

  // Subtotal before fees and discounts
  Money get subtotalMoney {
    var subtotal = totalPriceMoney;
    if (serviceFeeMoney != null) {
      subtotal = subtotal.subtract(serviceFeeMoney!);
    }
    if (discountMoney != null) {
      subtotal = subtotal.add(discountMoney!);
    }
    return subtotal;
  }

  // Computed properties
  DateTime get effectiveCheckIn => checkIn ?? startAt;
  DateTime get effectiveCheckOut => checkOut ?? endAt;

  int get numberOfNights =>
      effectiveCheckOut.difference(effectiveCheckIn).inDays;

  // Single source of truth for booking categorization, consumed everywhere via
  // [BookingCategorizer] — the guest "My Trips" screen, the host "Reservations"
  // tab (HostReservationsScreen, the tabbed Upcoming/Active/Completed view), and
  // the host dashboard. Do NOT re-derive "upcoming/ongoing/past" anywhere else,
  // or two screens will disagree (that exact split caused the dashboard to show
  // no upcoming reservations while the Reservations tab listed them).
  //
  // The rules are driven purely by lifecycle STATUS, NOT by dates. This is
  // deliberate:
  //   - pending + confirmed -> Upcoming. A booking the host has accepted (or
  //     not yet responded to) is a live reservation; it must never vanish just
  //     because its requested date slipped (test data, late check-in, a host
  //     who hasn't checked the guest in yet). The host resolves it explicitly.
  //   - active (the host tapped "Guest arrived") -> Current/Ongoing. Stays here
  //     until the host marks it complete, even past the scheduled checkout.
  //   - completed / cancelled / rejected -> Past.
  //
  // Date-independence is what guarantees all the reservation views agree — the
  // `now` argument is kept for API stability and any future date-aware refinement.
  // The three are mutually exclusive and exhaustive for every status.

  bool isOngoingAt(DateTime now) => status == BookingStatus.active;

  bool isPastAt(DateTime now) => status.isPast;

  bool isUpcomingAt(DateTime now) =>
      status == BookingStatus.pending || status == BookingStatus.confirmed;

  bool get isUpcoming => isUpcomingAt(DateTime.now());

  bool get isPast => isPastAt(DateTime.now());

  bool get isOngoing => isOngoingAt(DateTime.now());

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
    String? listingType,
    Currency? currency,
    double? serviceFee,
    double? discount,
    String? hostMessage,
    String? rejectionReason,
    DateTime? confirmedAt,
    DateTime? actualCheckIn,
    DateTime? completedAt,
    String? cancelledBy,
    DateTime? cancelledAt,
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
      listingType: listingType ?? this.listingType,
      currency: currency ?? this.currency,
      serviceFee: serviceFee ?? this.serviceFee,
      discount: discount ?? this.discount,
      hostMessage: hostMessage ?? this.hostMessage,
      rejectionReason: rejectionReason ?? this.rejectionReason,
      confirmedAt: confirmedAt ?? this.confirmedAt,
      actualCheckIn: actualCheckIn ?? this.actualCheckIn,
      completedAt: completedAt ?? this.completedAt,
      cancelledBy: cancelledBy ?? this.cancelledBy,
      cancelledAt: cancelledAt ?? this.cancelledAt,
    );
  }
}

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
    this.currency = Currency.bdt,
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
    // Payment
    this.paymentStatus = 'unpaid',
    this.paidAt,
    this.paymentMethod,
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

  /// Payment state mirrored from the `payments` table: 'unpaid' | 'paid' |
  /// 'refunded'. Guests pay after the host accepts; hosts can only complete a
  /// booking once this is 'paid'.
  final String paymentStatus;

  /// When the guest's payment was collected (payment_status → 'paid'). Null while
  /// unpaid. Used to attribute realized earnings to the month payment landed.
  final DateTime? paidAt;

  /// The payment method the guest chose at the pay step: 'online' | 'cash'.
  /// Null until chosen (treated as online-by-default). 'cash' means the guest
  /// will pay the host directly and the host confirms receipt.
  final String? paymentMethod;

  /// Whether the guest chose to pay in hand cash (host confirms receipt).
  bool get isCashChosen => paymentMethod == 'cash';

  /// Whether the guest has paid for this booking.
  bool get isPaid => paymentStatus == 'paid';

  /// Whether this booking's money counts as **realized host earnings**.
  ///
  /// Payment-driven: a stay counts the moment the guest has paid (guests pay
  /// upfront once the host accepts, so `paid` means the money is collected) OR
  /// once the stay is marked completed — whichever comes first. Cancelled,
  /// rejected, and still-pending requests never count. Single source of truth
  /// shared by the host dashboard and the Earnings tab so the two can't drift.
  bool get isEarnedRevenue =>
      status != BookingStatus.cancelled &&
      status != BookingStatus.rejected &&
      status != BookingStatus.pending &&
      (status == BookingStatus.completed || isPaid);

  /// Money committed but not yet collected: an accepted stay (confirmed/active)
  /// still awaiting the guest's payment (or a host's cash confirmation). Mutually
  /// exclusive with [isEarnedRevenue].
  bool get isPendingPayout =>
      (status == BookingStatus.confirmed || status == BookingStatus.active) &&
      !isEarnedRevenue;

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

  /// Human-readable duration that respects the booking's unit:
  /// hourly → "N hours", monthly → "N months", otherwise → "N nights".
  ///
  /// [unitLabel] is the persisted pricing unit ('hour' / 'day' / 'month').
  /// Use this everywhere a booking's length is shown so hourly/monthly
  /// bookings don't render as "0 nights".
  String get durationLabel {
    final span = effectiveCheckOut.difference(effectiveCheckIn);
    switch (unitLabel) {
      case 'hour':
        final hours = span.inHours;
        return '$hours hour${hours == 1 ? '' : 's'}';
      case 'month':
        final months = (span.inDays / 30).round();
        return '$months month${months == 1 ? '' : 's'}';
      default:
        final nights = span.inDays;
        return '$nights night${nights == 1 ? '' : 's'}';
    }
  }

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
    String? paymentStatus,
    DateTime? paidAt,
    String? paymentMethod,
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
      paymentStatus: paymentStatus ?? this.paymentStatus,
      paidAt: paidAt ?? this.paidAt,
      paymentMethod: paymentMethod ?? this.paymentMethod,
    );
  }
}

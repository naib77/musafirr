class Booking {
  Booking({
    required this.id,
    required this.listingId,
    required this.tenantName,
    required this.startAt,
    required this.endAt,
    required this.totalPrice,
    required this.unitLabel,
  });

  final String id;
  final String listingId;
  final String tenantName;
  final DateTime startAt;
  final DateTime endAt;
  final double totalPrice;
  final String unitLabel;
}

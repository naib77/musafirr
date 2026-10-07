/// Contact details for the two parties of a confirmed booking, returned by the
/// `get_booking_contacts` RPC. The guest's phone is the login number; the
/// host's is the number they put on the listing when there is one (160, so a
/// hotel's card dials the front desk), else their login number. Only
/// populated for participants of a confirmed/active/completed booking.
class BookingContacts {
  const BookingContacts({
    this.guestName,
    this.guestPhone,
    this.hostName,
    this.hostPhone,
  });

  final String? guestName;
  final String? guestPhone;
  final String? hostName;
  final String? hostPhone;
}

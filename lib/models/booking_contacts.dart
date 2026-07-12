/// Contact details for the two parties of a confirmed booking, returned by the
/// `get_booking_contacts` RPC. Phones are the login numbers (profiles.mobile)
/// and are only populated for participants of a confirmed/active/completed
/// booking.
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

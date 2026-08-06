import '../../models/message_template.dart';

/// Built-in, non-editable automated messages the app sends on booking events,
/// localized to the host's [MessageLanguage]. The editable milestone messages
/// live in [MessageTemplate]; these are the system notices around them.
class BookingSystemMessages {
  const BookingSystemMessages._();

  /// Label on the reservation card sent when a host accepts a booking.
  static String reservationConfirmed(
    String listingTitle,
    MessageLanguage language,
  ) {
    return switch (language) {
      MessageLanguage.en => 'Reservation confirmed · $listingTitle',
      MessageLanguage.bn => 'রিজার্ভেশন নিশ্চিত হয়েছে · $listingTitle',
    };
  }

  /// Notice sent when the host marks the guest as checked in.
  static String checkedIn(MessageLanguage language) {
    return switch (language) {
      MessageLanguage.en => 'Guest has checked in. Enjoy your stay! 🏠',
      MessageLanguage.bn =>
        'অতিথি চেক-ইন করেছেন। আপনার অবস্থান আনন্দময় হোক! 🏠',
    };
  }

  /// Notice sent when a booking is cancelled by the host or the guest.
  static String cancelled({
    required bool cancelledByHost,
    required MessageLanguage language,
  }) {
    return switch (language) {
      MessageLanguage.en => cancelledByHost
          ? 'I (host) have cancelled this booking. '
              'If you have any questions, feel free to message.'
          : 'I have cancelled this booking. '
              'If you have any questions, feel free to message.',
      MessageLanguage.bn => cancelledByHost
          ? 'আমি (হোস্ট) এই বুকিংটি বাতিল করেছি। '
              'কোনো প্রশ্ন থাকলে নির্দ্বিধায় মেসেজ করুন।'
          : 'আমি এই বুকিংটি বাতিল করেছি। '
              'কোনো প্রশ্ন থাকলে নির্দ্বিধায় মেসেজ করুন।',
    };
  }
}

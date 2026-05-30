import '../../core/currency/money.dart';
import '../../models/booking.dart';
import '../../models/listing.dart';
import '../../models/notification.dart';

/// Template for creating notifications with consistent formatting
class NotificationTemplates {
  NotificationTemplates._();

  // ============================================================
  // BOOKING NOTIFICATIONS
  // ============================================================

  /// Create a notification for a new booking request (for host)
  static AppNotification bookingRequest({
    required String notificationId,
    required String hostId,
    required String guestName,
    required String listingTitle,
    required String bookingId,
    required DateTime checkIn,
    required DateTime checkOut,
    required Money totalAmount,
    String? guestAvatarUrl,
    double? guestRating,
    int? guestReviewCount,
    int guestCount = 1,
  }) {
    return AppNotification(
      id: notificationId,
      userId: hostId,
      type: NotificationType.bookingRequest,
      title: 'New Booking Request',
      body:
          '$guestName wants to book "$listingTitle" from ${_formatDate(checkIn)} to ${_formatDate(checkOut)}',
      createdAt: DateTime.now(),
      priority: NotificationPriority.high,
      data: {
        'booking_id': bookingId,
        'guest_name': guestName,
        'listing_title': listingTitle,
        'check_in': checkIn.toIso8601String(),
        'check_out': checkOut.toIso8601String(),
        'total_amount': totalAmount.amount,
        'guest_avatar_url': guestAvatarUrl,
        'guest_rating': guestRating,
        'guest_review_count': guestReviewCount,
        'guest_count': guestCount,
      },
      actionUrl: '/host/reservations/$bookingId',
      groupKey: 'booking_$bookingId',
    );
  }

  /// Create a notification for booking confirmation (for guest)
  static AppNotification bookingConfirmed({
    required String notificationId,
    required String guestId,
    required String hostName,
    required String listingTitle,
    required String bookingId,
    required DateTime checkIn,
    required DateTime checkOut,
  }) {
    return AppNotification(
      id: notificationId,
      userId: guestId,
      type: NotificationType.bookingConfirmed,
      title: 'Booking Confirmed!',
      body:
          'Your booking at "$listingTitle" has been confirmed. Check-in: ${_formatDate(checkIn)}',
      createdAt: DateTime.now(),
      priority: NotificationPriority.high,
      data: {
        'booking_id': bookingId,
        'host_name': hostName,
        'listing_title': listingTitle,
        'check_in': checkIn.toIso8601String(),
        'check_out': checkOut.toIso8601String(),
      },
      actionUrl: '/trips/$bookingId',
      groupKey: 'booking_$bookingId',
    );
  }

  /// Create a notification for booking cancellation
  static AppNotification bookingCancelled({
    required String notificationId,
    required String userId,
    required String listingTitle,
    required String bookingId,
    required String cancelledBy,
    String? reason,
  }) {
    return AppNotification(
      id: notificationId,
      userId: userId,
      type: NotificationType.bookingCancelled,
      title: 'Booking Cancelled',
      body: reason != null
          ? 'Your booking at "$listingTitle" has been cancelled: $reason'
          : 'Your booking at "$listingTitle" has been cancelled by $cancelledBy',
      createdAt: DateTime.now(),
      priority: NotificationPriority.high,
      data: {
        'booking_id': bookingId,
        'listing_title': listingTitle,
        'cancelled_by': cancelledBy,
        if (reason != null) 'reason': reason,
      },
      actionUrl: '/trips/$bookingId',
      groupKey: 'booking_$bookingId',
    );
  }

  /// Create a check-in reminder notification
  static AppNotification checkInReminder({
    required String notificationId,
    required String guestId,
    required String listingTitle,
    required String bookingId,
    required DateTime checkIn,
    required String hostName,
    String? address,
  }) {
    return AppNotification(
      id: notificationId,
      userId: guestId,
      type: NotificationType.checkInReminder,
      title: 'Check-in Tomorrow',
      body:
          'Your check-in at "$listingTitle" is tomorrow at ${_formatTime(checkIn)}. Contact $hostName if you have questions.',
      createdAt: DateTime.now(),
      priority: NotificationPriority.high,
      data: {
        'booking_id': bookingId,
        'listing_title': listingTitle,
        'check_in': checkIn.toIso8601String(),
        'host_name': hostName,
        if (address != null) 'address': address,
      },
      actionUrl: '/trips/$bookingId',
      groupKey: 'booking_$bookingId',
    );
  }

  /// Create a check-out reminder notification
  static AppNotification checkOutReminder({
    required String notificationId,
    required String guestId,
    required String listingTitle,
    required String bookingId,
    required DateTime checkOut,
  }) {
    return AppNotification(
      id: notificationId,
      userId: guestId,
      type: NotificationType.checkOutReminder,
      title: 'Check-out Tomorrow',
      body:
          'Reminder: Your check-out from "$listingTitle" is tomorrow at ${_formatTime(checkOut)}',
      createdAt: DateTime.now(),
      priority: NotificationPriority.normal,
      data: {
        'booking_id': bookingId,
        'listing_title': listingTitle,
        'check_out': checkOut.toIso8601String(),
      },
      actionUrl: '/trips/$bookingId',
      groupKey: 'booking_$bookingId',
    );
  }

  // ============================================================
  // PAYMENT NOTIFICATIONS
  // ============================================================

  /// Create a notification for payment received (for host)
  static AppNotification paymentReceived({
    required String notificationId,
    required String hostId,
    required Money amount,
    required String bookingId,
    required String guestName,
  }) {
    return AppNotification(
      id: notificationId,
      userId: hostId,
      type: NotificationType.paymentReceived,
      title: 'Payment Received',
      body: 'You received ${amount.format()} from $guestName',
      createdAt: DateTime.now(),
      priority: NotificationPriority.normal,
      data: {
        'booking_id': bookingId,
        'amount': amount.amount,
        'currency': amount.currency.code,
        'guest_name': guestName,
      },
      actionUrl: '/host/earnings',
      groupKey: 'payment_$bookingId',
    );
  }

  /// Create a notification for payment failed
  static AppNotification paymentFailed({
    required String notificationId,
    required String userId,
    required String bookingId,
    required Money amount,
    String? reason,
  }) {
    return AppNotification(
      id: notificationId,
      userId: userId,
      type: NotificationType.paymentFailed,
      title: 'Payment Failed',
      body: reason != null
          ? 'Your payment of ${amount.format()} failed: $reason'
          : 'Your payment of ${amount.format()} could not be processed',
      createdAt: DateTime.now(),
      priority: NotificationPriority.urgent,
      data: {
        'booking_id': bookingId,
        'amount': amount.amount,
        if (reason != null) 'reason': reason,
      },
      actionUrl: '/payments/$bookingId',
      groupKey: 'payment_$bookingId',
    );
  }

  /// Create a notification for refund processed
  static AppNotification refundProcessed({
    required String notificationId,
    required String userId,
    required Money amount,
    required String bookingId,
  }) {
    return AppNotification(
      id: notificationId,
      userId: userId,
      type: NotificationType.refundProcessed,
      title: 'Refund Processed',
      body:
          'Your refund of ${amount.format()} has been processed and will arrive in 5-7 business days',
      createdAt: DateTime.now(),
      priority: NotificationPriority.normal,
      data: {
        'booking_id': bookingId,
        'amount': amount.amount,
      },
      actionUrl: '/payments/$bookingId',
      groupKey: 'payment_$bookingId',
    );
  }

  // ============================================================
  // REVIEW NOTIFICATIONS
  // ============================================================

  /// Create a notification for new review received (for host)
  static AppNotification reviewReceived({
    required String notificationId,
    required String hostId,
    required String reviewerName,
    required String listingTitle,
    required int rating,
    String? reviewId,
    String? snippet,
  }) {
    final stars = '⭐' * rating;
    return AppNotification(
      id: notificationId,
      userId: hostId,
      type: NotificationType.reviewReceived,
      title: 'New $rating-Star Review',
      body: snippet != null
          ? '$reviewerName left a review: "$snippet"'
          : '$reviewerName left a $stars review for "$listingTitle"',
      createdAt: DateTime.now(),
      priority: NotificationPriority.normal,
      data: {
        'listing_title': listingTitle,
        'reviewer_name': reviewerName,
        'rating': rating,
        if (reviewId != null) 'review_id': reviewId,
      },
      actionUrl: reviewId != null ? '/reviews/$reviewId' : '/host/reviews',
    );
  }

  /// Create a reminder to leave a review
  static AppNotification reviewReminder({
    required String notificationId,
    required String guestId,
    required String listingTitle,
    required String bookingId,
    required String hostName,
  }) {
    return AppNotification(
      id: notificationId,
      userId: guestId,
      type: NotificationType.reviewReminder,
      title: 'How was your stay?',
      body:
          'Share your experience at "$listingTitle". Your review helps $hostName and future guests!',
      createdAt: DateTime.now(),
      priority: NotificationPriority.low,
      data: {
        'booking_id': bookingId,
        'listing_title': listingTitle,
        'host_name': hostName,
      },
      actionUrl: '/review/$bookingId',
      expiresAt: DateTime.now().add(const Duration(days: 14)),
    );
  }

  // ============================================================
  // PROMOTION NOTIFICATIONS
  // ============================================================

  /// Create a notification for a new promotion
  static AppNotification promotionAvailable({
    required String notificationId,
    required String userId,
    required String title,
    required String description,
    required String promoCode,
    required int discountPercent,
    DateTime? expiresAt,
  }) {
    return AppNotification(
      id: notificationId,
      userId: userId,
      type: NotificationType.promotionAvailable,
      title: title,
      body: description,
      createdAt: DateTime.now(),
      priority: NotificationPriority.low,
      data: {
        'promo_code': promoCode,
        'discount_percent': discountPercent,
        if (expiresAt != null) 'expires_at': expiresAt.toIso8601String(),
      },
      actionUrl: '/promotions',
      expiresAt: expiresAt,
      groupKey: 'promotions',
    );
  }

  /// Create a notification for expiring discount
  static AppNotification discountExpiring({
    required String notificationId,
    required String userId,
    required String promoCode,
    required int discountPercent,
    required DateTime expiresAt,
  }) {
    final hoursLeft = expiresAt.difference(DateTime.now()).inHours;
    return AppNotification(
      id: notificationId,
      userId: userId,
      type: NotificationType.discountExpiring,
      title: 'Your Discount is Expiring!',
      body: hoursLeft <= 24
          ? 'Your $discountPercent% discount (code: $promoCode) expires in $hoursLeft hours!'
          : 'Your $discountPercent% discount (code: $promoCode) expires soon',
      createdAt: DateTime.now(),
      priority: NotificationPriority.normal,
      data: {
        'promo_code': promoCode,
        'discount_percent': discountPercent,
        'expires_at': expiresAt.toIso8601String(),
      },
      actionUrl: '/explore',
      expiresAt: expiresAt,
    );
  }

  /// Create a notification for referral reward
  static AppNotification referralReward({
    required String notificationId,
    required String userId,
    required String referredUserName,
    required Money rewardAmount,
  }) {
    return AppNotification(
      id: notificationId,
      userId: userId,
      type: NotificationType.referralReward,
      title: 'Referral Reward Earned!',
      body:
          '$referredUserName completed their first booking! You earned ${rewardAmount.format()}',
      createdAt: DateTime.now(),
      priority: NotificationPriority.normal,
      data: {
        'referred_user': referredUserName,
        'reward_amount': rewardAmount.amount,
      },
      actionUrl: '/profile/referrals',
    );
  }

  // ============================================================
  // MESSAGE NOTIFICATIONS
  // ============================================================

  /// Create a notification for new message
  static AppNotification newMessage({
    required String notificationId,
    required String userId,
    required String senderName,
    required String conversationId,
    required String messagePreview,
    String? senderAvatarUrl,
  }) {
    return AppNotification(
      id: notificationId,
      userId: userId,
      type: NotificationType.newMessage,
      title: senderName,
      body: messagePreview,
      createdAt: DateTime.now(),
      priority: NotificationPriority.normal,
      imageUrl: senderAvatarUrl,
      data: {
        'conversation_id': conversationId,
        'sender_name': senderName,
      },
      actionUrl: '/messages/$conversationId',
      groupKey: 'messages_$conversationId',
    );
  }

  // ============================================================
  // SYSTEM NOTIFICATIONS
  // ============================================================

  /// Create a system alert notification
  static AppNotification systemAlert({
    required String notificationId,
    required String userId,
    required String title,
    required String body,
    NotificationPriority priority = NotificationPriority.normal,
    String? actionUrl,
  }) {
    return AppNotification(
      id: notificationId,
      userId: userId,
      type: NotificationType.systemAlert,
      title: title,
      body: body,
      createdAt: DateTime.now(),
      priority: priority,
      actionUrl: actionUrl,
    );
  }

  /// Create a security alert notification
  static AppNotification securityAlert({
    required String notificationId,
    required String userId,
    required String title,
    required String body,
    Map<String, dynamic>? data,
  }) {
    return AppNotification(
      id: notificationId,
      userId: userId,
      type: NotificationType.securityAlert,
      title: title,
      body: body,
      createdAt: DateTime.now(),
      priority: NotificationPriority.urgent,
      data: data,
      actionUrl: '/profile/security',
    );
  }

  // ============================================================
  // HELPER FUNCTIONS
  // ============================================================

  /// Helper to create notification from booking
  static AppNotification fromBooking({
    required String notificationId,
    required Booking booking,
    required Listing listing,
    required NotificationType type,
    required String recipientId,
    String? guestAvatarUrl,
    double? guestRating,
    int? guestReviewCount,
  }) {
    switch (type) {
      case NotificationType.bookingRequest:
        return bookingRequest(
          notificationId: notificationId,
          hostId: recipientId,
          guestName: booking.tenantName,
          listingTitle: listing.title,
          bookingId: booking.id,
          checkIn: booking.effectiveCheckIn,
          checkOut: booking.effectiveCheckOut,
          totalAmount: booking.totalPriceMoney,
          guestAvatarUrl: guestAvatarUrl,
          guestRating: guestRating,
          guestReviewCount: guestReviewCount,
          guestCount: booking.guestCount,
        );
      case NotificationType.bookingConfirmed:
        return bookingConfirmed(
          notificationId: notificationId,
          guestId: recipientId,
          hostName: listing.ownerName,
          listingTitle: listing.title,
          bookingId: booking.id,
          checkIn: booking.effectiveCheckIn,
          checkOut: booking.effectiveCheckOut,
        );
      default:
        throw ArgumentError('Unsupported notification type: $type');
    }
  }

  static String _formatDate(DateTime date) {
    final months = [
      'Jan',
      'Feb',
      'Mar',
      'Apr',
      'May',
      'Jun',
      'Jul',
      'Aug',
      'Sep',
      'Oct',
      'Nov',
      'Dec'
    ];
    return '${months[date.month - 1]} ${date.day}';
  }

  static String _formatTime(DateTime time) {
    final hour = time.hour % 12 == 0 ? 12 : time.hour % 12;
    final minute = time.minute.toString().padLeft(2, '0');
    final period = time.hour >= 12 ? 'PM' : 'AM';
    return '$hour:$minute $period';
  }
}

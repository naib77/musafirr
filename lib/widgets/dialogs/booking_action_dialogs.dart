import 'package:flutter/material.dart';

/// Result from a booking action dialog (accept/decline).
class BookingActionResult {
  const BookingActionResult({
    required this.confirmed,
    this.message,
  });

  /// Whether the user confirmed the action.
  final bool confirmed;

  /// Optional message (welcome message for accept, reason for decline).
  final String? message;
}

/// Shows a dialog to accept a booking request.
///
/// Returns a [BookingActionResult] with confirmed=true if accepted,
/// or null if cancelled.
Future<BookingActionResult?> showAcceptBookingDialog(
  BuildContext context, {
  required String guestName,
}) async {
  final messageController = TextEditingController();
  var isLoading = false;

  return showDialog<BookingActionResult>(
    context: context,
    barrierDismissible: false,
    builder: (dialogContext) => StatefulBuilder(
      builder: (context, setState) => AlertDialog(
        title: const Text('Accept Booking'),
        content: Column(
          mainAxisSize: MainAxisSize.min,
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            Text('Accept booking from $guestName?'),
            const SizedBox(height: 16),
            TextField(
              controller: messageController,
              enabled: !isLoading,
              decoration: const InputDecoration(
                labelText: 'Welcome message (optional)',
                hintText: 'e.g., Looking forward to hosting you!',
                border: OutlineInputBorder(),
              ),
              maxLines: 3,
            ),
          ],
        ),
        actions: [
          TextButton(
            onPressed: isLoading ? null : () => Navigator.pop(dialogContext),
            child: const Text('Cancel'),
          ),
          FilledButton(
            onPressed: isLoading
                ? null
                : () {
                    Navigator.pop(
                      dialogContext,
                      BookingActionResult(
                        confirmed: true,
                        message: messageController.text.isNotEmpty
                            ? messageController.text
                            : null,
                      ),
                    );
                  },
            child: isLoading
                ? const SizedBox(
                    width: 20,
                    height: 20,
                    child: CircularProgressIndicator(
                      strokeWidth: 2,
                      valueColor: AlwaysStoppedAnimation<Color>(Colors.white),
                    ),
                  )
                : const Text('Accept'),
          ),
        ],
      ),
    ),
  );
}

/// Shows a dialog to decline a booking request.
///
/// Returns a [BookingActionResult] with confirmed=true if declined,
/// or null if cancelled.
Future<BookingActionResult?> showDeclineBookingDialog(
  BuildContext context, {
  required String guestName,
}) async {
  final reasonController = TextEditingController();
  var isLoading = false;

  return showDialog<BookingActionResult>(
    context: context,
    barrierDismissible: false,
    builder: (dialogContext) => StatefulBuilder(
      builder: (context, setState) => AlertDialog(
        title: const Text('Decline Booking'),
        content: Column(
          mainAxisSize: MainAxisSize.min,
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            Text('Decline booking from $guestName?'),
            const SizedBox(height: 16),
            TextField(
              controller: reasonController,
              enabled: !isLoading,
              decoration: const InputDecoration(
                labelText: 'Reason (optional)',
                hintText: 'e.g., Dates not available',
                border: OutlineInputBorder(),
              ),
              maxLines: 2,
            ),
          ],
        ),
        actions: [
          TextButton(
            onPressed: isLoading ? null : () => Navigator.pop(dialogContext),
            child: const Text('Cancel'),
          ),
          FilledButton(
            onPressed: isLoading
                ? null
                : () {
                    Navigator.pop(
                      dialogContext,
                      BookingActionResult(
                        confirmed: true,
                        message: reasonController.text.isNotEmpty
                            ? reasonController.text
                            : null,
                      ),
                    );
                  },
            style: FilledButton.styleFrom(
              backgroundColor: Colors.red,
            ),
            child: isLoading
                ? const SizedBox(
                    width: 20,
                    height: 20,
                    child: CircularProgressIndicator(
                      strokeWidth: 2,
                      valueColor: AlwaysStoppedAnimation<Color>(Colors.white),
                    ),
                  )
                : const Text('Decline'),
          ),
        ],
      ),
    ),
  );
}

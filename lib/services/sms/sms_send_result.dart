/// Result of an SMS send operation
class SmsSendResult {
  const SmsSendResult({
    required this.success,
    this.messageId,
    this.errorMessage,
  });

  /// Whether the SMS was sent successfully
  final bool success;

  /// Message ID from the provider (if successful)
  final String? messageId;

  /// Error message (if failed)
  final String? errorMessage;

  /// Factory for successful result
  factory SmsSendResult.success({String? messageId}) {
    return SmsSendResult(success: true, messageId: messageId);
  }

  /// Factory for failed result
  factory SmsSendResult.failure(String errorMessage) {
    return SmsSendResult(success: false, errorMessage: errorMessage);
  }

  @override
  String toString() {
    if (success) {
      return 'SmsSendResult(success: true, messageId: $messageId)';
    }
    return 'SmsSendResult(success: false, error: $errorMessage)';
  }
}
